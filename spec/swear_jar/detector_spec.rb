# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::Detector do
  subject(:detector) { described_class.new }

  let(:embedded) { described_class.new(mode: :embedded) }

  describe '#matches' do
    it 'reports a spaced-out word with its original text and range' do
      matches = detector.matches('ty k u r r w o!')
      expect(matches.size).to eq(1)
      expect(matches.first).to have_attributes(
        text: 'k u r r w o', range: (3...14), stem: 'kurw', locale: :pl, severity: :strong, categories: [:vulgar]
      )
    end

    it 'returns several sorted, non-overlapping matches' do
      matches = detector.matches('kurwa, dupa')
      expect(matches.map(&:text)).to eq(%w[kurwa dupa])
      expect(matches.map(&:stem)).to eq(%w[kurw dup])
      expect(matches.each_cons(2).all? { |a, b| a.range.end <= b.range.begin }).to be(true)
    end

    it 'covers the whole word around a prefixed stem' do
      expect(detector.matches('jestem wkurwiony').map(&:text)).to eq(['wkurwiony'])
    end

    it 'returns frozen Match objects' do
      expect(detector.matches('kurwa').first).to be_a(SwearJar::Match).and be_frozen
    end
  end

  describe '#profane?' do
    it 'is false for an allowlisted word' do
      expect(detector.profane?('assassin')).to be(false)
    end

    it 'is true for an exact word' do
      expect(detector.profane?('you ass')).to be(true)
    end

    it 'is false for a clean message' do
      expect(detector.profane?('dzień dobry, miłego dnia')).to be(false)
    end
  end

  describe 'options' do
    it 'ignores entries below min_severity' do
      strong = described_class.new(min_severity: :strong)
      expect(strong.profane?('dupa')).to be(false)
      expect(strong.profane?('kurwa')).to be(true)
    end

    it 'finds stems inside words in :embedded mode' do
      expect(embedded.matches('KurwiMistrz').map(&:text)).to eq(['KurwiMistrz'])
      expect(detector.profane?('KurwiMistrz')).to be(true)
      expect(detector.profane?('xKurwiMistrz')).to be(false)
    end

    it 'still ignores a non-embeddable exact word inside a longer one in :embedded mode' do
      expect(embedded.profane?('Assassin')).to be(false)
    end

    it 'picks the most severe stem when one word hits several entries' do
      matches = embedded.matches('dupokurwa')
      expect(matches.size).to eq(1)
      expect(matches.first).to have_attributes(text: 'dupokurwa', stem: 'kurw', severity: :strong)
    end

    it 'keeps the word boundary of a non-embeddable entry hit inside a word in :embedded mode' do
      detector = described_class.new(mode: :embedded, extra_words: [{ stem: 'as', locale: :en, severity: :mild,
                                                                      categories: [:vulgar] }])
      expect(detector.matches('xass').map(&:stem)).to eq(['as'])
    end

    it 'finds spaced letters after a one-letter word that the run swallowed' do
      { 'a k u r w a' => 'k u r w a', 'i k u r w a' => 'k u r w a', 'x k u r w a' => 'k u r w a',
        'a w k u r w a' => 'w k u r w a', 'I f u c k you' => 'f u c k', 'i a s s' => 'a s s',
        'ok, a k.u.r.w.a' => 'k.u.r.w.a' }.each do |text, found|
        matches = detector.matches(text)
        expect(matches.map(&:text)).to eq([found]), text
        expect(text[matches.first.range]).to eq(found)
      end
    end

    it 'finds a non-exact stem in spaced letters after any character in :embedded mode' do
      ['a k u r w a', 'x k u r w a', 'I f u c k you'].each do |text|
        expect(embedded.profane?(text)).to be(true), text
      end
    end

    it 'does not split an exact word off a spaced word after a letter that is no one-letter word' do
      ['p a s s', 'b a s s', 'm a s s', 'l a s s', 'g a s s', 'x a s s'].each do |text|
        expect(detector.profane?(text)).to be(false), text
        expect(embedded.profane?(text)).to be(false), text
      end
    end

    it 'keeps a spaced word that starts with a one-letter stem letter whole' do
      expect(detector.matches('a s s h o l e').map(&:text)).to eq(['a s s h o l e'])
      expect(detector.profane?('a d u p l i k a t')).to be(false)
      expect(detector.profane?('a b c d')).to be(false)
    end

    it 'picks the longest stem among entries of the same severity' do
      detector = described_class.new(extra_words: [{ stem: 'kurwisz', locale: :pl, severity: :strong,
                                                     categories: [:insult] }])
      expect(detector.matches('kurwiszon').first.stem).to eq('kurwisz')
    end

    it 'suppresses words from the allow option' do
      expect(described_class.new(allow: ['kurwiszon']).profane?('kurwiszon')).to be(false)
    end

    it 'restricts detection to the given locales' do
      english = described_class.new(locales: [:en])
      expect(english.profane?('kurwa')).to be(false)
      expect(english.profane?('fuck')).to be(true)
    end

    {
      'digit_variant.yml' => /entry "smok": "sm0k" contains a digit/,
      'no_letters.yml' => /entry "--": "--" has no letters/,
      'digit_allow.yml' => /allow word: "sm0czek" contains a digit/
    }.each do |name, message|
      it "names the file and the entry of a bad spelling in #{name}" do
        path = File.join(__dir__, '..', 'fixtures', 'word_lists', name)
        expect { described_class.new(extra_paths: [path]) }
          .to raise_error(SwearJar::InvalidWordListError, a_string_including("#{path}: ").and(match(message)))
      end
    end

    it 'names the source of a bad spelling given as an option' do
      expect { described_class.new(allow: ['dup1ikat']) }.to raise_error(SwearJar::InvalidWordListError, /allow option/)
      words = [{ stem: 'x1', locale: :pl, severity: :mild, categories: [:insult] }]
      expect { described_class.new(extra_words: words) }.to raise_error(SwearJar::InvalidWordListError, /extra_words/)
    end

    it 'raises ArgumentError for an unknown mode' do
      expect { described_class.new(mode: :fast) }.to raise_error(ArgumentError, /mode/)
    end

    it 'raises ArgumentError for an unknown locale' do
      expect { described_class.new(locales: [:de]) }.to raise_error(ArgumentError)
    end
  end

  it 'is frozen' do
    expect(detector).to be_frozen
  end

  it 'has a compact inspect' do
    entries = SwearJar::WordList.load.entries.size
    expect(detector.inspect).to eq("#<SwearJar::Detector locales=[:pl, :en] mode=:words entries=#{entries}>")
    expect(described_class.new(locales: :en, mode: :embedded).inspect).to include('locales=[:en] mode=:embedded')
  end

  it 'keeps the inspect of its internals compact' do
    internals = [detector.instance_variable_get(:@matcher), SwearJar::FoldTable.current, SwearJar::WordList.load,
                 SwearJar::PatternBuilder.new(SwearJar::WordList.load, mode: :words)]
    internals.each { |object| expect(object.inspect.length).to be < 100 }
  end

  describe 'markers around a word' do
    {
      '**kurwa** mac' => [['kurwa', 2...7]], '*kurwa*' => [['kurwa', 1...6]], '**fuck**' => [['fuck', 2...6]],
      '~~chuj~~' => [['chuj', 2...6]], '#kurwa' => [['kurwa', 1...6]], '%dupa%' => [['dupa', 1...5]],
      '_kurwa_' => [['kurwa', 1...6]], 'ty k*rwo *tak*' => [['k*rwo', 3...8]], '***' => []
    }.each do |text, expected|
      it "reports #{expected.map(&:first).inspect} without the markers in #{text.inspect}" do
        expect(detector.matches(text).map { |match| [match.text, match.range] }).to eq(expected)
      end
    end

    it 'still treats masks between letters as letters' do
      %w[k*rwa a**hole pu**y k#rwa].each do |text|
        expect(detector.matches(text).map(&:text)).to eq([text]), text
      end
    end

    it 'finds marked words in :embedded mode too' do
      expect(embedded.matches('**KurwiMistrz**').map(&:text)).to eq(['KurwiMistrz'])
    end

    it 'keeps the markers when censoring' do
      expect(detector.censor('**kurwa** mac', with: 'X')).to eq('**X** mac')
      expect(detector.censor('~~chuj~~ i *dupa*')).to eq('~~****~~ i ******')
    end
  end

  describe '#censor' do
    let(:text) { 'Ty k u r r w o! Co za wkurwiony dzień.' }

    it 'masks each match with as many asterisks as it has characters by default' do
      expect(detector.censor(text)).to eq('Ty ***********! Co za ********* dzień.')
    end

    it 'replaces each match with the with: string' do
      expect(detector.censor(text, with: '[bełkot]')).to eq('Ty [bełkot]! Co za [bełkot] dzień.')
    end

    it 'replaces each match with what the block returns for it' do
      result = detector.censor('dupa i kurwa') { |match| match.severity == :mild ? match.text : "<#{match.stem}>" }
      expect(result).to eq('dupa i <kurw>')
    end

    it 'counts characters, not bytes, for the default mask' do
      expect(detector.censor('ｋｕｒｗａ!')).to eq('*****!')
    end

    it 'returns an unchanged copy of a clean text' do
      clean = 'Witaj w tawernie'
      result = detector.censor(clean)
      expect(result).to eq(clean)
      expect(result).not_to be(clean)
    end

    it 'does not mutate the input' do
      input = +'ty kurwo'
      detector.censor(input)
      expect(input).to eq('ty kurwo')
    end

    it 'returns nil for nil' do
      expect(detector.censor(nil)).to be_nil
    end

    it 'returns a plain String for other inputs' do
      expect(detector.censor(:kurwa)).to eq('*****')
      expect(detector.censor(:kurwa)).to be_an_instance_of(String)
    end

    it 'rejects with: together with a block' do
      expect { detector.censor(text, with: 'x') { 'y' } }.to raise_error(ArgumentError, /with: or a block/)
    end
  end
end
