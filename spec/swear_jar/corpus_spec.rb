# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

# Generated from spec/fixtures/<locale>.yml. Every case runs against a detector for its own
# locale and against one for all locales, because the default detector mixes both lists and
# a stem from one language must not flag a common word of the other.
RSpec.describe 'Fixture corpus' do # rubocop:disable RSpec/DescribeClass
  def self.detectors
    @detectors ||= Hash.new do |cache, (locales, mode)|
      cache[[locales, mode]] = SwearJar::Detector.new(locales: locales, mode: mode)
    end
  end

  def self.fixture(locale)
    YAML.safe_load(File.read(File.join(__dir__, '..', 'fixtures', "#{locale}.yml"))) # rubocop:disable Style/YAMLFileRead
  end

  def self.clean_case(item)
    item.is_a?(String) ? { 'input' => item, 'mode' => 'words' } : { 'mode' => 'words' }.merge(item)
  end

  def expect_consistent(input, matches)
    matches.each { |m| expect(input[m.range]).to eq(m.text) }
    matches.each_cons(2) { |a, b| expect(a.range.end).to be <= b.range.begin }
  end

  def self.clean_cases(locale)
    fixture(locale).fetch('clean').map { |item| clean_case(item) }
  end

  SwearJar::LOCALES.each do |locale|
    describe "#{locale} corpus" do
      it 'has enough clean cases' do
        expect(self.class.clean_cases(locale).size).to be >= (locale == :pl ? 60 : 40)
      end

      it 'contains every bundled allowlist word in a clean case' do
        folded = self.class.clean_cases(locale).map { |c| SwearJar::Normalizer.fold(c['input']) }
        SwearJar::WordList.load(locales: [locale]).allow.each do |word|
          expect(folded).to include(a_string_including(SwearJar::Normalizer.fold(word)))
        end
      end

      [[locale], SwearJar::LOCALES].each do |locales|
        fixture(locale).fetch('profane').map { |item| [item, (item['mode'] || 'words').to_sym] }.each do |item, mode|
          it "finds #{item['text'].inspect} (#{item['stem']}) in #{item['input'].inspect}, #{mode}, #{locales}" do
            matches = self.class.detectors[[locales, mode]].matches(item['input'])
            expect_consistent(item['input'], matches)
            expect(matches.map { |m| [m.text, m.stem] }).to eq([[item['text'], item['stem']]])
          end
        end

        clean_cases(locale).map { |item| [item['input'], item['mode'].to_sym] }.each do |input, mode|
          it "accepts #{input.inspect}, #{mode}, #{locales}" do
            detector = self.class.detectors[[locales, mode]]
            expect_consistent(input, detector.matches(input))
            expect(detector.profane?(input)).to be(false)
          end
        end
      end
    end
  end
end
