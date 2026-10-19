# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::Entry do
  def build(hash, source: 'words.yml')
    described_class.build(hash, locale: :pl, source: source)
  end

  let(:base) { { 'stem' => 'chuj', 'severity' => 'strong', 'categories' => ['vulgar'] } }

  it 'applies defaults' do
    entry = build(base)
    expect(entry.embeddable).to be(true)
    expect(entry.exact).to be(false)
    expect(entry.variants).to eq([])
    expect(entry.locale).to eq(:pl)
    expect(entry.severity).to eq(:strong)
    expect(entry.categories).to eq([:vulgar])
  end

  it 'treats nil variants as empty' do
    expect(build(base.merge('variants' => nil)).variants).to eq([])
  end

  it 'accepts symbol keys' do
    entry = build({ stem: 'chuj', variants: ['huj'], severity: :mild, categories: [:vulgar], exact: true,
                    embeddable: false })
    expect(entry.severity).to eq(:mild)
    expect(entry.exact).to be(true)
    expect(entry.embeddable).to be(false)
  end

  it 'lists spellings with the stem first' do
    entry = build({ stem: 'chuj', variants: ['huj'], severity: :strong, categories: [:vulgar] })
    expect(entry.spellings).to eq(%w[chuj huj])
  end

  it 'ranks severity by index' do
    expect(build(base).rank).to eq(1)
  end

  it 'is frozen with frozen strings' do
    entry = build(base.merge('variants' => ['huj']))
    expect(entry).to be_frozen
    expect(entry.stem).to be_frozen
    expect(entry.variants).to be_frozen
    expect(entry.variants.first).to be_frozen
    expect(entry.categories).to be_frozen
  end

  {
    'unknown key' => { 'bogus' => 1 },
    'missing stem' => { 'stem' => nil },
    'blank stem' => { 'stem' => '  ' },
    'unknown severity' => { 'severity' => 'nuclear' },
    'unknown category' => { 'categories' => ['nope'] },
    'empty categories' => { 'categories' => [] },
    'non-boolean embeddable' => { 'embeddable' => 'yes' },
    'non-boolean exact' => { 'exact' => 1 }
  }.each do |name, override|
    it "raises for #{name}" do
      expect { build(base.merge(override)) }.to raise_error(SwearJar::InvalidWordListError, /words\.yml/)
    end
  end

  it 'names the stem in the error' do
    expect { build(base.merge('severity' => 'nuclear')) }.to raise_error(SwearJar::InvalidWordListError, /chuj/)
  end

  it 'raises when the stem key is absent' do
    expect { build(base.except('stem')) }.to raise_error(SwearJar::InvalidWordListError, /words\.yml/)
  end
end
