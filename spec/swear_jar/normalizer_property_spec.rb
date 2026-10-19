# frozen_string_literal: true

require 'spec_helper'

# Seeded random strings from an alphabet of characters that stress folding, masking and
# spaced-letter joining. The fast (whole-string) skeleton path must agree with the
# character-by-character path, and the index map must stay consistent.
RSpec.describe SwearJar::Normalizer do
  describe 'properties' do
    let(:alphabet) do
      %w[a k u r w A K ą Ł ó _ # % * . - ~ ! | @ $ 1 4 0 ﬁ İ ß Ｋ 😀 中 ǅ ½ ² Ⓚ Ⅰ] +
        ["\u0020", "\u00A0", "\u0301", "\u0332", "\u200B", "\u00AD", "\uFEFF", "\t", "\n"]
    end

    let(:samples) do
      random = Random.new(20_261_019)
      Array.new(3_000) { Array.new(random.rand(1..14)) { alphabet[random.rand(alphabet.size)] }.join }
    end

    it 'gives the same skeleton on the fast and the general path, with a consistent map' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      samples.each do |text|
        skeleton, map = described_class.call(text)
        fast, joins = described_class.skeleton_with_joins(text)
        expect(described_class.skeleton(text)).to eq(skeleton), text.inspect
        expect(fast).to eq(skeleton), text.inspect
        expect(map.size).to eq(skeleton.length), text.inspect
        expect(map).to eq(map.sort).and(all(be < text.length)), text.inspect
        expect(joins).to eq(joins.sort).and(all(be < skeleton.length)), text.inspect
      end
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.0
    end
  end
end
