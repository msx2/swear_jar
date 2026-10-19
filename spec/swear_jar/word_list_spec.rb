# frozen_string_literal: true

require 'spec_helper'

RSpec::Matchers.define_negated_matcher :exclude, :include

RSpec.describe SwearJar::WordList do
  let(:fixtures) { File.join(__dir__, '..', 'fixtures', 'word_lists') }
  let(:stems) { ->(list) { list.entries.map(&:stem) } }

  def fixture(name)
    File.join(fixtures, name)
  end

  describe '.load' do
    it 'loads every bundled locale with default options' do
      list = described_class.load
      expect(stems.call(list)).to include('kurw', 'dup', 'fuck', 'ass')
      expect(list).to be_frozen
    end

    it 'excludes other locales' do
      list = described_class.load(locales: [:en])
      expect(stems.call(list)).to include('fuck', 'ass').and(exclude('kurw', 'dup'))
      expect(list.entries.map(&:locale).uniq).to eq([:en])
      expect(list.prefixes.keys).not_to include(:pl)
      expect(list.allow).to include('assassin').and(exclude(*described_class.load(locales: [:pl]).allow))
    end

    it 'filters by minimum severity' do
      list = described_class.load(min_severity: :strong)
      expect(stems.call(list)).to include('kurw', 'fuck').and(exclude('dup', 'ass'))
      expect(list.entries.map(&:severity).uniq).to contain_exactly(:strong, :severe)
    end

    it 'filters by categories' do
      list = described_class.load(categories: [:sexual])
      expect(stems.call(list)).to include('fuck').and(exclude('kurw', 'ass'))
      expect(list.entries).to all(have_attributes(categories: include(:sexual)))
    end

    it 'sorts prefixes longest first per locale' do
      prefixes = described_class.load.prefixes[:pl]
      expect(prefixes.first.length).to be >= prefixes.last.length
      expect(prefixes).to eq(prefixes.sort_by { |p| -p.length })
    end

    it 'collects bundled and option allow words without duplicates' do
      bundled = described_class.load.allow
      list = described_class.load(allow: %w[duplikat skurwiel])
      expect(list.allow).to contain_exactly(*bundled, 'skurwiel')
    end

    it 'adds entries, prefixes and allow words from extra path globs' do
      list = described_class.load(extra_paths: [fixture('extra*.yml')])
      expect(stems.call(list)).to include('smoczyslow')
      expect(list.allow).to include('smoczyslowianin')
      expect(list.prefixes[:pl]).to include('bez')
    end

    it 'applies filters to extra files too' do
      list = described_class.load(locales: [:en], extra_paths: [fixture('extra.yml')])
      expect(stems.call(list)).not_to include('smoczyslow')
      expect(list.allow).not_to include('smoczyslowianin')
    end

    it 'adds extra_words entries' do
      words = [{ stem: 'smoczydup', locale: :pl, severity: :strong, categories: [:insult] }]
      entry = described_class.load(extra_words: words).entries.find { |e| e.stem == 'smoczydup' }
      expect(entry.locale).to eq(:pl)
      expect(entry.severity).to eq(:strong)
    end

    it 'requires a locale in extra_words' do
      words = [{ stem: 'x', severity: :mild, categories: [:vulgar] }]
      expect { described_class.load(extra_words: words) }
        .to raise_error(SwearJar::InvalidWordListError, /extra_words.*locale/)
    end

    it 'reports invalid extra_words entries with the extra_words source' do
      words = [{ stem: 'x', locale: :pl, severity: :loud, categories: [:vulgar] }]
      expect { described_class.load(extra_words: words) }
        .to raise_error(SwearJar::InvalidWordListError, /extra_words/)
    end

    ['huj', [' '], [nil], false].each do |variants|
      it "rejects extra_words variants #{variants.inspect}" do
        words = [{ stem: 'x', locale: :pl, severity: :mild, categories: [:vulgar], variants: variants }]
        expect { described_class.load(extra_words: words) }
          .to raise_error(SwearJar::InvalidWordListError, /extra_words.*variants/)
      end
    end

    it 'rejects empty locales and categories with ArgumentError' do
      expect { described_class.load(locales: []) }.to raise_error(ArgumentError, /locales/)
      expect { described_class.load(categories: []) }.to raise_error(ArgumentError, /categories/)
    end

    it 'accepts a single allow word given as a String' do
      expect(described_class.load(allow: 'smoczek').allow).to include('smoczek')
    end

    it 'raises InvalidWordListError naming an extra path without wildcards that does not exist' do
      path = fixture('nothing_here.yml')
      expect { described_class.load(extra_paths: [path]) }
        .to raise_error(SwearJar::InvalidWordListError, a_string_including(path))
    end

    it 'accepts an extra path glob that matches nothing' do
      expect { described_class.load(extra_paths: [fixture('nothing_here*.yml')]) }.not_to raise_error
    end

    it 'records where each allow word comes from' do
      list = described_class.load(extra_paths: [fixture('extra.yml')], allow: ['abc'])
      expect(list.allow_sources).to include('smoczyslowianin' => fixture('extra.yml'), 'abc' => 'allow option')
    end

    it 'rejects a nil min_severity with ArgumentError' do
      expect { described_class.load(min_severity: nil) }.to raise_error(ArgumentError, /min_severity/)
    end

    it 'keeps prefix order stable among equal lengths and freezes allow words' do
      list = described_class.load(extra_paths: [fixture('extra.yml')], allow: ['abc'])
      expect(list.prefixes[:pl].select { |p| p.length == 3 }).to eq(%w[roz pod nad bez])
      expect(list.allow).to all(be_frozen)
    end

    it 'rejects unknown options with ArgumentError listing them' do
      expect { described_class.load(locales: %i[pl de]) }.to raise_error(ArgumentError, /de/)
      expect { described_class.load(min_severity: :loud) }.to raise_error(ArgumentError, /loud/)
      expect { described_class.load(categories: %i[vulgar rude]) }.to raise_error(ArgumentError, /rude/)
    end

    {
      'root_not_hash.yml' => /Hash/,
      'words_not_array.yml' => /words/,
      'entry_not_hash.yml' => /entry/,
      'variants_not_array.yml' => /variants/,
      'variants_blank.yml' => /variants/,
      'variants_false.yml' => /variants/,
      'prefixes_not_array.yml' => /prefixes/,
      'allow_not_strings.yml' => /allow/,
      'unknown_key.yml' => /wrods/,
      'missing_locale.yml' => /locale/,
      'bad_locale.yml' => /de/,
      'bad_severity.yml' => /severity/,
      'integer_key.yml' => /unknown keys \[1\]/
    }.each do |name, message|
      it "raises InvalidWordListError naming the file for #{name}" do
        path = fixture(name)
        expect { described_class.load(extra_paths: [path]) }
          .to raise_error(SwearJar::InvalidWordListError, a_string_including(path).and(match(message)))
      end
    end
  end
end
