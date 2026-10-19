# frozen_string_literal: true

require 'spec_helper'

# Generated from the bundled lists: every spelling of every entry is detected as that entry.
RSpec.describe 'Bundled word lists' do # rubocop:disable RSpec/DescribeClass
  SwearJar::LOCALES.each do |locale|
    describe "locale #{locale}" do
      let(:list) { SwearJar::WordList.load(locales: [locale]) }
      let(:detector) { SwearJar::Detector.new(locales: [locale]) }

      it 'loads without InvalidWordListError' do
        expect { SwearJar::WordList.load(locales: [locale]) }.not_to raise_error
      end

      it 'has between 40 and 60 stems' do
        expect(list.entries.size).to be_between(40, 60)
      end

      it 'has unique stems' do
        stems = list.entries.map(&:stem)
        expect(stems.uniq).to eq(stems)
      end

      SwearJar::WordList.load(locales: [locale]).entries.each do |entry|
        entry.spellings.each do |spelling|
          it "detects #{spelling.inspect} as #{entry.stem.inspect}" do
            expect(detector.matches(spelling).first&.stem).to eq(entry.stem)
          end
        end
      end
    end
  end

  it 'loads every bundled locale together' do
    expect { SwearJar::Detector.new(locales: SwearJar::LOCALES) }.not_to raise_error
  end
end
