# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::Match do
  subject(:match) do
    described_class.new(text: 'chuj', range: 0...4, stem: 'chuj', locale: :pl, severity: :strong,
                        categories: [:vulgar])
  end

  it 'is frozen' do
    expect(match).to be_frozen
  end

  it 'exposes all six fields' do
    expect(match.text).to eq('chuj')
    expect(match.range).to eq(0...4)
    expect(match.stem).to eq('chuj')
    expect(match.locale).to eq(:pl)
    expect(match.severity).to eq(:strong)
    expect(match.categories).to eq([:vulgar])
  end
end
