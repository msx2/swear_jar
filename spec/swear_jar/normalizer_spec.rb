# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SwearJar::Normalizer do
  def skeleton(text)
    described_class.call(text).first
  end

  it 'keeps the per-character fold private' do
    expect(described_class).not_to respond_to(:compute_fold)
  end

  describe '.call' do
    it 'lowercases ASCII and returns an identity map' do
      expect(described_class.call('Kurwa')).to eq(['kurwa', [0, 1, 2, 3, 4]])
    end

    it 'returns an empty skeleton and map for an empty string' do
      expect(described_class.call('')).to eq(['', []])
    end

    it 'folds Polish diacritics' do
      expect(skeleton('ŻÓŁĆ')).to eq('zolc')
      expect(skeleton('ąćęłńóśźż')).to eq('acelnoszz')
    end

    it 'folds fullwidth letters' do
      expect(skeleton('ｋｕｒｗａ')).to eq('kurwa')
    end

    it 'removes combining marks of other scripts and keeps the map' do
      expect(described_class.call('é')).to eq(['e', [0]])
      expect(described_class.call("e\u0301x")).to eq(['ex', [0, 2]])
    end

    it 'drops invisible format characters and keeps the map' do
      expect(described_class.call("ku\u200Brwa")).to eq(['kurwa', [0, 1, 3, 4, 5]])
      expect(described_class.skeleton("f\u00ADu\uFEFFck")).to eq('fuck')
    end

    it 'maps expanded characters to the same original index' do
      expect(described_class.call('ﬁx')).to eq(['fix', [0, 0, 1]])
    end

    it 'keeps 100 zl as is (no leet rewriting)' do
      expect(skeleton('100 zł')).to eq('100 zl')
    end

    it 'keeps the skeleton as UTF-8' do
      expect(skeleton('Żółć').encoding).to eq(Encoding::UTF_8)
      expect(skeleton('abc').encoding).to eq(Encoding::UTF_8)
    end

    it 'does not mutate or require an unfrozen input' do
      text = 'ŻÓŁĆ Kurwa'
      expect { described_class.call(text) }.not_to raise_error
      expect(text).to eq('ŻÓŁĆ Kurwa')
    end

    it 'keeps map size equal to skeleton length' do
      sk, map = described_class.call('Zażółć gęślą jaźń ﬁ ｋ é')
      expect(map.size).to eq(sk.length)
    end

    it 'keeps ranges valid after a ZWJ emoji' do
      text = "\u{1F468}‍\u{1F469} kurwa"
      sk, map = described_class.call(text)
      s = sk.index('kurwa')
      e = s + 4
      expect(text[map[s]..map[e]]).to eq('kurwa')
    end
  end

  describe 'masking' do
    it 'turns * # % into *' do
      expect(skeleton('k*rwa')).to eq('k*rwa')
      expect(skeleton('k#rwa')).to eq('k*rwa')
      expect(skeleton('k%rwa')).to eq('k*rwa')
      expect(skeleton('k＃rwa')).to eq('k*rwa')
    end

    it 'turns _ into * only between letters' do
      expect(skeleton('kurwa_mac')).to eq('kurwa*mac')
      expect(skeleton('_x')).to eq('_x')
      expect(skeleton('x_')).to eq('x_')
      expect(skeleton('a_1')).to eq('a_1')
      expect(skeleton('a__b')).to eq('a__b')
      expect(skeleton('ż_ó')).to eq('z*o')
    end
  end

  describe 'spaced letters' do
    it 'joins letters separated by spaces' do
      expect(described_class.call('ty k u r w a')).to eq(['ty kurwa', [0, 1, 2, 3, 5, 7, 9, 11]])
    end

    it 'joins letters separated by dots and dashes' do
      expect(skeleton('k.u.r.w.a')).to eq('kurwa')
      expect(skeleton('k-u-r-w-a')).to eq('kurwa')
    end

    it 'joins exactly three single characters' do
      expect(skeleton('i w z')).to eq('iwz')
      expect(skeleton('a i b')).to eq('aib')
    end

    it 'does not join fewer than three' do
      expect(skeleton('a i')).to eq('a i')
      expect(skeleton('i w ogóle')).to eq('i w ogole')
    end

    it 'requires the same separator throughout the run' do
      expect(skeleton('k u.r w')).to eq('k u.r w')
      expect(skeleton('k u r.w.a')).to eq('kur.w.a')
    end

    it 'does not join across double separators' do
      expect(skeleton('k  u  r')).to eq('k  u  r')
    end

    it 'joins digits and leet symbols as single characters' do
      expect(skeleton('k u r w @')).to eq('kurw@')
      expect(skeleton('1 2 3')).to eq('123')
    end

    it 'turns masks at the edge of a word into non-word characters' do
      expect(described_class.call('**kurwa** k*rwa #tag')).to eq(
        ['__kurwa__ k*rwa _tag', (0...20).to_a]
      )
      expect(described_class.skeleton('ｋ＊ｒｗａ ＊ｘ')).to eq('k*rwa _x')
    end

    it 'reports where joined runs start in the skeleton' do
      expect(described_class.skeleton_with_joins('a k u r w a, x y z')).to eq(['akurwa, xyz', [0, 8]])
      expect(described_class.skeleton_with_joins('Zażółć k.u.r.w.a')).to eq(['zazolc kurwa', [7]])
      expect(described_class.skeleton_with_joins('ty kurwa')).to eq(['ty kurwa', []])
    end

    it 'allows the last token to carry trailing punctuation' do
      sk, map = described_class.call('ty k u r r w o!')
      expect(sk).to eq('ty kurrwo!')
      expect(map[sk.index('k')]).to eq(3)
      expect(map[sk.index('o')]).to eq(13)
      expect(map.last).to eq(14)
    end

    it 'allows other trailing characters on the last token' do
      expect(skeleton('k u r w a?')).to eq('kurwa?')
      expect(skeleton('k u r w a,')).to eq('kurwa,')
      expect(skeleton('k u r w a.')).to eq('kurwa.')
    end

    it 'does not allow trailing punctuation on a middle token' do
      expect(skeleton('k u! r w')).to eq('k u! r w')
    end

    it 'keeps original indices of joined letters' do
      expect(described_class.call('k.u.r')).to eq(['kur', [0, 2, 4]])
    end

    it 'keeps ordinary sentences untouched' do
      expect(skeleton('to jest zwykle zdanie')).to eq('to jest zwykle zdanie')
    end
  end

  describe 'ASCII fast path' do
    [
      'Kurwa', 'k_u_r', 'a_b #x% _', 'ty k u r r w o!', 'k.u.r.w.a', 'i w z', 'A-B-C d', '',
      'hello world, how are you? a b c', '100 zl! @ $ | x y z', "tab\there\nnew_line"
    ].each do |text|
      it "matches the general path for #{text.inspect}" do
        expect(described_class.call(text)).to eq(described_class.send(:call_general, text))
      end
    end
  end

  describe '.skeleton' do
    [
      'Kurwa', 'k_u_r', 'a_b #x% _', 'ty k u r r w o!', 'k.u.r.w.a', '', 'ŻÓŁĆ Kurwa', 'Zażółć gęślą jaźń',
      'ｋｕｒｗａ', 'k＃rwa', 'ż_ó', 'ż＿ó', 'ﬁx ﬂ', "e\u0301x", 'ty k u r r w ó!', 'k. u. r', 'ł u k',
      'Ελληνικά ΚΕΙΜΕΝΟ', 'Dzięki 🙏 ❤️ 👨‍👩‍👧 ✨ 💯', 'ẞ İstanbul ǅ ℡ ™ ①',
      "\u{10FFFF} \u{E000} \u{1F130} \u{FE4D}x\u{FE4D}y", 'ﬀ_ﬀ', "tab\there\nnew_line ąę"
    ].each do |text|
      it "equals the skeleton from .call for #{text.inspect}" do
        expect(described_class.skeleton(text)).to eq(described_class.call(text).first)
      end
    end
  end

  describe '.fold' do
    it 'folds and masks without joining spaced letters' do
      expect(described_class.fold('ŻÓŁĆ k#r')).to eq('zolc k*r')
      expect(described_class.fold('k u r w a')).to eq('k u r w a')
      expect(described_class.fold('Kurwa')).to eq('kurwa')
      expect(described_class.fold('')).to eq('')
    end
  end
end
