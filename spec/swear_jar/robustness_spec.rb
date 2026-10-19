# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::Detector, '#matches robustness' do
  subject(:detector) { described_class.new }

  modes = %i[words embedded].freeze

  let(:embedded) { described_class.new(mode: :embedded) }

  def elapsed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  describe 'punctuation around a word' do
    ['kurwa!!!', '(kurwa)', '„kurwa”', 'kurwa,', 'kurwa|', '!kurwa'].each do |text|
      it "reports only the word in #{text.inspect}" do
        expect(detector.matches(text).map(&:text)).to eq(['kurwa'])
      end
    end

    it 'keeps a leet symbol that belongs to the stem' do
      detector = described_class.new(extra_words: [{ stem: 'idiot', locale: :en, severity: :mild,
                                                     categories: [:insult] }])
      expect(detector.matches('you !d!ot!!').map(&:text)).to eq(['!d!ot'])
    end
  end

  describe 'pathological input' do
    {
      '10 000 letters' => 'a' * 10_000,
      'a letter and 5 000 masks' => "k#{'*' * 5_000}",
      'spaced stems repeated 2 000 times' => 'k u r w ' * 2_000,
      'stems glued 3 000 times' => 'dupa' * 3_000,
      'allowlisted words glued 1 000 times' => 'duplikat' * 1_000
    }.each do |name, text|
      modes.each do |mode|
        it "handles #{name} within 1 second in #{mode.inspect} mode" do
          detector = described_class.new(mode: mode)
          expect(elapsed { detector.matches(text) }).to be < 1.0
        end
      end
    end
  end

  describe 'linear time' do
    def best_of_three(detector, text)
      Array.new(3) { elapsed { detector.matches(text) } }.min
    end

    # Doubling the input must not much more than double the time. A quadratic path would take
    # 4x; 3.5x plus a fixed allowance leaves room for GC and scheduler noise on slow CI runners.
    {
      'many hits' => [:words, 'kurwa ', 2_000],
      'many hits next to a non-ASCII letter' => [:words, 'żkurwa kurwa ', 1_000],
      'many hits in text that keeps non-ASCII characters' => [:words, '😀 kurwa ', 2_000],
      'one long embedded word with non-ASCII letters' => [:embedded, 'żkurw', 4_000],
      'many hits of a stem whose longer form has a doubled letter' => [:words, 'cum ', 2_000],
      'many allowlisted words' => [:words, 'duplikat ', 1_000],
      'one long embedded word' => [:embedded, 'kurw', 4_000],
      'a long run of leet symbols' => [:words, '!|', 10_000],
      'a long run of one leet symbol' => [:embedded, '|', 10_000],
      'a long run of the first letter of an allowlisted word' => [:words, 'd', 10_000, 'uplikat'],
      'a long run of the first letter of an allowlisted word, embedded' => [:embedded, 'd', 10_000, 'uplikat']
    }.each do |name, (mode, unit, count, tail)|
      it "scales linearly on #{name} in #{mode.inspect} mode" do
        detector = described_class.new(mode: mode)
        single = best_of_three(detector, "#{unit * count}#{tail}")
        double = best_of_three(detector, "#{unit * count * 2}#{tail}")
        expect(double).to be < (3.5 * single) + 0.05
        expect(double).to be < 0.5
      end
    end
  end

  describe 'invisible format characters between two words' do
    %W[\u200B \u2060 \uFEFF].each do |char|
      it "finds a word after U+#{char.ord.to_s(16).upcase.rjust(4, '0')} in :words mode" do
        { "you#{char}idiot" => ['idiot'], "what#{char}the#{char}fuck" => ['fuck'], "ty#{char}kurwo" => ['kurwo'],
          "to#{char}jest#{char}chuj" => ['chuj'] }.each do |text, found|
          matches = detector.matches(text)
          expect(matches.map(&:text)).to eq(found), text
          matches.each { |match| expect(text[match.range]).to eq(match.text) }
        end
      end
    end

    it 'reports a word with an invisible character inside once' do
      expect(detector.matches("ku\u200Brwa\u200Bmać").map(&:text)).to eq(["ku\u200Brwa\u200Bmać"])
    end

    it 'finds a word after an allowlisted word joined by an invisible character' do
      expect(detector.matches("duplikat\u200Bidiot").map(&:text)).to eq(['idiot'])
    end

    it 'keeps clean words joined by an invisible character clean' do
      expect(detector.profane?("pass\u200Bword")).to be(false)
      expect(detector.profane?("klasa\u200Bassassin")).to be(false)
    end
  end

  describe 'invisible format characters inside a word' do
    %W[\u200B \u200C \u200D \u2060 \uFEFF \u00AD \u180E].each do |char|
      it "ignores U+#{char.ord.to_s(16).upcase.rjust(4, '0')}" do
        ["ku#{char}rwa", "f#{char}u#{char}c#{char}k"].each do |text|
          expect(detector.matches("o #{text}!").map(&:text)).to eq([text])
        end
      end
    end
  end

  describe 'multi-codepoint characters before a match' do
    [
      "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} kurwa",
      "cafe\u{301} kurwa",
      "caf\u{E9} kurwa",
      "hej\r\nkurwa\r\ndupa",
      'ｋｕｒｗａ ｄｕｐａ',
      "\u{1F600} k u r w a \u{1F600}"
    ].each do |text|
      it "keeps original[range] == text for #{text.inspect}" do
        matches = detector.matches(text)
        expect(matches).not_to be_empty
        matches.each { |match| expect(text[match.range]).to eq(match.text) }
      end
    end
  end

  describe 'combining marks after a match' do
    it 'covers the marks of the last character' do
      text = "K\u0332u\u0332r\u0332w\u0332a\u0332"
      expect(detector.matches("#{text} x").map { |m| [m.text, m.range] }).to eq([[text, 0...10]])
    end

    it 'covers an accent written after the last letter' do
      expect(detector.matches("kurwa\u0301 jest").map(&:text)).to eq(["kurwa\u0301"])
    end
  end

  describe 'unusual input types' do
    it 'returns no matches for nil' do
      expect(detector.matches(nil)).to eq([])
      expect(detector.profane?(nil)).to be(false)
    end

    it 'returns no matches for an empty string' do
      expect(detector.matches('')).to eq([])
      expect(detector.profane?('')).to be(false)
    end

    it 'converts a Symbol with to_s' do
      expect(detector.matches(:kurwa).map(&:text)).to eq(['kurwa'])
    end

    it 'drops invalid bytes of a binary string without raising' do
      expect(detector.matches("kurwa\xFF".b).map(&:text)).to eq(['kurwa'])
    end

    it 'scrubs invalid bytes of a UTF-8 string' do
      expect(detector.matches((+"dupa \xFF").force_encoding(Encoding::UTF_8)).map(&:text)).to eq(['dupa'])
    end

    it 'transcodes a string in another encoding' do
      expect(detector.matches('wkurwiłem się'.encode(Encoding::ISO_8859_2)).map(&:text)).to eq(['wkurwiłem'])
    end

    it 'returns plain String texts for a String subclass that keeps its class (like SafeBuffer)' do
      buffer = Class.new(String) do
        def to_s = self

        def [](*) = self.class.new(super)
      end
      text = buffer.new('to kurwa')
      expect(text[3...8]).to be_a(buffer)
      expect(detector.matches(text).map { |m| m.text.class }).to eq([String])
    end

    it 'does not mutate a frozen input' do
      text = 'Kurwa #%_ DUPA'
      expect { detector.matches(text) }.not_to raise_error
      expect(text).to eq('Kurwa #%_ DUPA')
    end

    it 'does not mutate an unfrozen input' do
      text = +'Kurwa ŁÓDŹ k u r w a'
      detector.matches(text)
      expect(text).to eq('Kurwa ŁÓDŹ k u r w a')
    end
  end

  describe 'allowlisted words' do
    it 'reports only the profane word next to an allowlisted one' do
      expect(detector.matches('duplikat i dupa').map(&:text)).to eq(['dupa'])
    end

    it 'reports only the exact word after an allowlisted one' do
      matches = detector.matches('assassin ass')
      expect(matches.map(&:text)).to eq(['ass'])
      expect(matches.first.range).to eq(9...12)
    end

    it 'reports a second stem inside an allowlisted word in :embedded mode' do
      matches = embedded.matches('duplikatkurwa')
      expect(matches.map(&:stem)).to eq(['kurw'])
      expect(matches.first.text).to eq('duplikatkurwa')
    end

    it 'ignores an allowlisted word alone in :embedded mode' do
      expect(embedded.profane?('Duplikat')).to be(false)
    end
  end
end
