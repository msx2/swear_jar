# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::PatternBuilder do
  let(:list_class) { Struct.new(:entries, :prefixes, :allow, :allow_sources, keyword_init: true) }
  let(:pl_prefixes) { %w[prze wpie wy za s w z] }

  def entry(stem, locale: :pl, **attrs)
    SwearJar::Entry.build({ stem: stem, severity: :strong, categories: [:vulgar], **attrs },
                          locale: locale, source: 'spec')
  end

  def word_list(entries, prefixes: { pl: pl_prefixes, en: [] }, allow: [])
    list_class.new(entries: entries, prefixes: prefixes, allow: allow, allow_sources: {})
  end

  def skeleton(text)
    SwearJar::Normalizer.call(text).first
  end

  def builder(entries, mode: :words, **options)
    described_class.new(word_list(entries, **options), mode: mode)
  end

  def scan(scanner, text)
    scanner.match(skeleton(text), 0)
  end

  describe '#scanner' do
    context 'with a Polish stem in :words mode' do
      subject(:scanner) { builder([entry('kurw')]).scanner }

      %w[kurwa KURWA kurrrwa k*rwa kur.wa kurw@ wkurwiony skurwysyn].each do |text|
        it "matches #{text.inspect}" do
          expect(scan(scanner, text)).not_to be_nil
        end
      end

      it 'does not match a stem glued to a preceding letter' do
        expect(scan(scanner, 'xkurwa')).to be_nil
      end
    end

    context 'with a Polish stem in :embedded mode' do
      it 'matches a stem inside a longer word' do
        scanner = builder([entry('kurw')], mode: :embedded).scanner
        expect(scan(scanner, 'xkurwa')).not_to be_nil
      end
    end

    context 'with an exact non-embeddable English stem' do
      let(:ass) { entry('ass', locale: :en, embeddable: false, exact: true) }

      %i[words embedded].product(%w[ass a$$ @ss]).each do |mode, text|
        it "matches #{text.inspect} in #{mode.inspect} mode" do
          expect(scan(builder([ass], mode: mode).scanner, text)).not_to be_nil
        end
      end

      %i[words embedded].product(%w[assassin class as]).each do |mode, text|
        it "does not match #{text.inspect} in #{mode.inspect} mode" do
          expect(scan(builder([ass], mode: mode).scanner, text)).to be_nil
        end
      end
    end

    it 'factors shared stem prefixes through the trie' do
      source = builder([entry('kurw'), entry('kutas')]).scanner.source
      expect(source.scan('(?>[k][k]*)').size).to eq(1)
    end

    it 'matches variants' do
      scanner = builder([entry('fuck', locale: :en, variants: %w[fck])]).scanner
      expect(scan(scanner, 'fck')).not_to be_nil
    end

    it 'treats a space inside a stem as an optional separator' do
      scanner = builder([entry('son of', locale: :en)]).scanner
      expect(scan(scanner, 'sonof')).not_to be_nil
      expect(scan(scanner, 'son-of')).not_to be_nil
    end

    it 'rejects a stem without letters' do
      expect { builder([entry('---')]) }.to raise_error(SwearJar::InvalidWordListError, /---/)
    end

    it 'rejects digits in stems, variants and allow words' do
      expect { builder([entry('kurw4')]) }.to raise_error(SwearJar::InvalidWordListError, /kurw4/)
      expect { builder([entry('fuck', locale: :en, variants: %w[f0ck])]) }
        .to raise_error(SwearJar::InvalidWordListError, /f0ck/)
      expect { builder([entry('dup')], allow: %w[dup1ikat]) }
        .to raise_error(SwearJar::InvalidWordListError, /dup1ikat/)
    end

    it 'lets a mask replace only interior runs' do
      ass = entry('ass', locale: :en, exact: true, embeddable: false)
      scanner = builder([entry('kurw'), entry('dup'), ass]).scanner
      expect(scan(scanner, 'k*rwa')).not_to be_nil
      expect(scan(scanner, 'd*pa')).not_to be_nil
      expect(scan(scanner, 'a*')).to be_nil
      expect(scan(scanner, 'd**')).to be_nil
      expect(scan(scanner, 'A* search')).to be_nil
    end

    it 'lets a run of masks stand for a run of the same letter, up to its length' do
      scanner = builder([entry('asshole', locale: :en), entry('pussy', locale: :en)]).scanner
      expect(scan(scanner, 'a**hole')).not_to be_nil
      expect(scan(scanner, 'a*hole')).not_to be_nil
      expect(scan(scanner, 'pu**y')).not_to be_nil
      expect(scan(scanner, 'pu***y')).to be_nil
      expect(scan(scanner, '**hole')).to be_nil
    end

    it 'starts an :embedded hit at the stem, not at a prefix' do
      scanner = builder([entry('kurw')], mode: :embedded).scanner
      expect(scan(scanner, 'wkurwiony').begin(0)).to eq(1)
    end

    it 'escapes regexp metacharacters in prefixes' do
      scanner = builder([entry('kurw')], prefixes: { pl: ['a.'], en: [] }).scanner
      expect(scan(scanner, 'a.kurwa')).not_to be_nil
      expect(scan(scanner, 'abkurwa')).to be_nil
    end

    it 'never matches with an empty word list' do
      scanner = builder([]).scanner
      expect(scan(scanner, 'kurwa ass')).to be_nil
    end

    it 'rejects an unknown mode' do
      expect { builder([entry('kurw')], mode: :loose) }.to raise_error(ArgumentError, /loose/)
    end

    it 'scans pathological input quickly' do
      entries = %w[kurw kutas chuj pierdol jeb dup ass arse anus fuck shit].map { |stem| entry(stem) }
      scanner = builder(entries, mode: :embedded).scanner
      ["k#{'*' * 5000}", 'a' * 10_000].each do |text|
        input = skeleton(text)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        pos = 0
        while (m = scanner.match(input, pos))
          pos = m.end(0)
        end
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.0
      end
    end

    it 'scans long same-letter runs in linear time without regexp memoization' do
      entries = %w[kurw kutas dup ass arse anus].map { |stem| entry(stem) }
      # Ruby 3.0/3.1 have no regexp memoization. A back-reference disables it on newer
      # Rubies too, so this guards against quadratic rescans of a run in the free branch.
      scanner = Regexp.new("#{builder(entries, mode: :embedded).scanner.source}|(q)\\1")
      ['a' * 20_000, 'k.' * 10_000].each do |text|
        input = skeleton(text)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        pos = 0
        while (m = scanner.match(input, pos))
          pos = m.end(0)
        end
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.2
      end
    end
  end

  describe '#entry_patterns' do
    it 'matches the stem without prefixes, which are exposed separately' do
      kurw = entry('kurw')
      built = builder([entry('kutas'), kurw])
      text = skeleton('wkurwiony')
      expect(built.entry_patterns.filter_map { |e, re| e if re.match?(text, 0) }).to be_empty
      expect(built.entry_patterns.filter_map { |e, re| (m = re.match(text, 1)) && [e, m[0]] }).to eq([[kurw, 'kurw']])
      expect(built.prefixes).to eq(pl: %w[prze wpie wy za s w z], en: [])
    end

    it 'matches the stem after the prefix at the scanner hit position' do
      built = builder([entry('kurw')])
      text = skeleton('o wkurwiony')
      hit = built.scanner.match(text, 0).begin(0)
      _, regexp = built.entry_patterns.first
      expect(text[hit]).to eq('w')
      expect(regexp.match(text, hit + 1)[0]).to eq('kurw')
    end

    it 'has one anchored pattern per folded spelling' do
      fuck = entry('fuck', locale: :en, variants: %w[fck FUCK])
      patterns = builder([fuck]).entry_patterns
      expect(patterns.size).to eq(2)
      expect(patterns.map(&:first)).to all(equal(fuck))
      expect(patterns.last[1].match(skeleton('x fck'), 0)).to be_nil
      expect(patterns.last[1].match(skeleton('x fck'), 2)[0]).to eq('fck')
    end

    it 'lists the characters a stem can start with' do
      patterns = builder([entry('idiot', locale: :en), entry('kurw')]).entry_patterns
      expect(patterns.map(&:last)).to eq([%w[i 1 ! |], %w[k]])
    end

    it 'requires the right boundary for exact entries' do
      ass = entry('ass', locale: :en, exact: true, embeddable: false)
      _, regexp = builder([ass]).entry_patterns.first
      expect(regexp.match(skeleton('assassin'), 0)).to be_nil
      expect(regexp.match(skeleton('a$$!'), 0)[0]).to eq('a$$')
    end
  end

  describe '#allow_pattern' do
    it 'matches an allowlisted word at the given offset' do
      pattern = builder([entry('dup')], allow: %w[Duplikat]).allow_pattern
      expect(pattern.match(skeleton('duplikat'), 0)).not_to be_nil
      expect(pattern.match(skeleton('a duplikat'), 0)).to be_nil
      expect(pattern.match(skeleton('a duplikat'), 2)).not_to be_nil
    end

    it 'does not use prefixes' do
      pattern = builder([entry('dup')], allow: %w[duplikat]).allow_pattern
      expect(pattern.match(skeleton('wduplikat'), 0)).to be_nil
    end

    it 'is nil without allow words' do
      expect(builder([entry('dup')]).allow_pattern).to be_nil
    end
  end
end
