# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::FoldTable do
  describe '.compute' do
    it 'folds one character' do
      expect(described_class.compute('Ż')).to eq('z')
      expect(described_class.compute('ｋ')).to eq('k')
      expect(described_class.compute('ﬁ')).to eq('fi')
      expect(described_class.compute('#')).to eq('*')
      expect(described_class.compute("\u{FE0F}")).to eq('')
    end

    it 'drops invisible format and default-ignorable characters' do
      %W[\u200B \u200C \u200D \u2060 \uFEFF \u00AD \u180E \u3164].each do |char|
        expect(described_class.compute(char)).to eq('')
      end
    end
  end

  describe '.for' do
    it 'loads the block of a character outside the table and keeps it' do
      text = 'ᚠᚢᚦ' # Runic, a block nothing else in the suite uses
      expect(described_class.current.folds).not_to have_key('ᚠ')

      table = described_class.for(text)
      expect(table.folds['ᚠ']).to eq('ᚠ')
      expect(text).not_to match(table.uncovered)
      expect(described_class.current).to equal(table)
    end
  end

  describe '#with_blocks_of' do
    it 'stops adding blocks at MAX_BLOCKS' do
      full = described_class.new((0...described_class::MAX_BLOCKS).to_a, described_class.block_folds(0x00))
      expect(full).to be_full
      expect(full.with_blocks_of("\u{10400}")).to equal(full)
    end
  end

  describe '#slow' do
    it 'matches characters outside the table and characters that fold to an underscore' do
      table = described_class.new([0x00], described_class.block_folds(0x00))
      expect(table.slow.match?('ąb')).to be(true)
      expect(table.slow.match?('a_b')).to be(true)
      expect(table.slow.match?('a b')).to be(false)
    end
  end
end
