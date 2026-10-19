# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::Configuration do
  after { SwearJar.reset_configuration! }

  it 'defaults match the detector defaults' do
    expect(described_class.new.to_h).to eq(
      locales: SwearJar::LOCALES, mode: :words, min_severity: :mild, categories: nil,
      extra_paths: [], extra_words: [], allow: []
    )
  end

  it 'does not share default arrays between instances' do
    described_class.new.extra_words << 'x'
    expect(described_class.new.extra_words).to eq([])
  end

  describe 'SwearJar.detector' do
    it 'is a memoized Detector' do
      expect(SwearJar.detector).to be_a(SwearJar::Detector)
      expect(SwearJar.detector).to equal(SwearJar.detector)
    end

    it 'builds a single detector when first used from many threads' do
      detectors = Array.new(8) { Thread.new { SwearJar.detector } }.map(&:value)
      expect(detectors.uniq(&:object_id).size).to eq(1)
    end
  end

  describe 'SwearJar.configure' do
    it 'swaps in a detector built from the new configuration' do
      expect(SwearJar.profane?('dupa')).to be true
      returned = SwearJar.configure { |c| c.min_severity = :strong }
      expect(returned).to equal(SwearJar.detector)
      expect(SwearJar.profane?('dupa')).to be false
    end

    it 'raises ArgumentError for invalid options and keeps the previous detector' do
      previous = SwearJar.detector
      expect { SwearJar.configure { |c| c.locales = [:de] } }.to raise_error(ArgumentError)
      expect(SwearJar.detector).to equal(previous)
    end

    it 'starts from fresh defaults on every call' do
      SwearJar.configure { |c| c.min_severity = :strong }
      SwearJar.configure { |c| c.allow = ['kurw'] }
      expect(SwearJar.profane?('dupa')).to be true
    end
  end

  describe 'delegation' do
    it 'censor delegates to the detector' do
      expect(SwearJar.censor('o kurwa', with: '[bełkot]')).to eq('o [bełkot]')
    end

    it 'matches delegates to the detector' do
      expect(SwearJar.matches('kurwa').size).to eq(1)
    end
  end
end
