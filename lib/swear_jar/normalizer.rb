# frozen_string_literal: true

module SwearJar
  # Turns text into a lowercase, diacritic-free skeleton plus a map from skeleton
  # character index to original character index.
  #
  # @api private
  module Normalizer
    LETTER_RE = /\p{L}/
    ASCII_UNDERSCORE_RE = /(?<=[A-Za-z])_(?=[A-Za-z])/
    ASCII_MASK_RE = /[#%_]/

    # Cheap screen: three single characters in a row with separators between them.
    SPACED_GATE = /(?:\A|[ .-])[[:alnum:]@$!|][ .-][[:alnum:]@$!|][ .-][[:alnum:]@$!|]/
    SEPARATORS = ' .-'
    # A run of three or more tokens (maximal runs of non-separators) split by one repeated
    # separator: single characters, and the last one may carry trailing punctuation (`o!`).
    SINGLE = '[[:alnum:]@$!|]'
    SPACED_RUN = Regexp.new(
      "(?<![^ .-])#{SINGLE}(?<sep>[ .-])(?:#{SINGLE}\\k<sep>)+(?:#{SINGLE}|[[:alnum:]][!|,?;:]+)(?![^ .-])"
    )
    NO_JOINS = [].freeze
    # A run of masks with no word character on one side is a marker around a word (`**kurwa**`,
    # `#tag`), not a masked letter: it becomes `_`, which is no word character, keeping lengths.
    EDGE_MASKS = /(?<![\p{L}\p{N}@$!|*])\*+|\*+(?![\p{L}\p{N}@$!|*])/

    class << self
      # [skeleton, index map].
      def call(text)
        normalize(text).first(2)
      end

      # The skeleton alone (equal to +call(text).first+), without the index map.
      def skeleton(text)
        skeleton_with_joins(text).first
      end

      # [skeleton, joins]: +joins+ lists the skeleton index where each joined spaced-letter run
      # starts (empty when there is none). Like +skeleton+, it folds the whole string with one
      # gsub instead of character by character, unless the text has a character the fold table
      # cannot handle that way (see FoldTable#slow).
      def skeleton_with_joins(text)
        return join_spaced(fold_ascii(text), nil).values_at(0, 2) if text.ascii_only?

        table = FoldTable.current
        if text.match?(table.slow)
          table = FoldTable.for(text)
          return normalize(text).values_at(0, 2) if text.match?(table.slow)
        end
        join_spaced(text.gsub(table.changing, table.folds), nil).values_at(0, 2)
      end

      # [skeleton, index map, joins] in one pass, for callers that need all three.
      def analyze(text)
        normalize(text)
      end

      def fold(string)
        string.ascii_only? ? fold_ascii(string) : scan_general(string).first
      end

      private

      # [skeleton, index map, joins].
      def normalize(text)
        text.ascii_only? ? join_spaced(*scan_ascii(text)) : join_spaced(*scan_general(text))
      end

      # The general (character by character) path of +call+, also for ASCII text.
      def call_general(text)
        join_spaced(*scan_general(text)).first(2)
      end

      # Leaves `_` alone: whether it is a mask depends on its neighbours.
      def compute_fold(char)
        FoldTable.compute(char)
      end

      def scan_ascii(text)
        skeleton = fold_ascii(text)
        [skeleton, (0...skeleton.length).to_a]
      end

      def fold_ascii(text)
        skeleton = text.downcase
        if skeleton.match?(ASCII_MASK_RE)
          skeleton.tr!('#%', '**')
          skeleton.gsub!(ASCII_UNDERSCORE_RE, '*')
        end
        skeleton
      end

      def scan_general(text)
        folds = FoldTable.for(text).folds
        chars = text.chars
        out = +''
        map = []
        chars.each_with_index do |char, index|
          folded = folds[char] || compute_fold(char)
          if folded.length == 1
            folded = mask_underscore(chars, index) if folded == '_'
            out << folded
            map << index
          else
            folded.each_char do |piece|
              piece = mask_underscore(chars, index) if piece == '_'
              out << piece
              map << index
            end
          end
        end
        [out, map]
      end

      def mask_underscore(chars, index)
        return '_' if index.zero? || index == chars.length - 1

        LETTER_RE.match?(chars[index - 1]) && LETTER_RE.match?(chars[index + 1]) ? '*' : '_'
      end

      # Second pass: turn edge masks into `_` (see EDGE_MASKS), then join runs of >= 3
      # single-character tokens split by one repeated separator, dropping the separators.
      # +map+ may be nil when only the skeleton is needed.
      # Returns [skeleton, map, joins] (see +skeleton_with_joins+).
      def join_spaced(skeleton, map)
        skeleton = skeleton.gsub(EDGE_MASKS) { |run| '_' * run.length } if skeleton.include?('*')
        return [skeleton, map, NO_JOINS] unless skeleton.match?(SPACED_GATE)
        return join_spaced_skeleton(skeleton) unless map

        out = +''
        new_map = []
        joins = []
        pos = 0
        skeleton.scan(SPACED_RUN) do
          from, to = Regexp.last_match.offset(0)
          out << skeleton[pos...from]
          new_map.concat(map[pos...from])
          joins << out.length
          (from...to).each do |index|
            next if SEPARATORS.include?(skeleton[index])

            out << skeleton[index]
            new_map << map[index]
          end
          pos = to
        end
        [out << skeleton[pos..], new_map.concat(map[pos..]), joins]
      end

      def join_spaced_skeleton(skeleton)
        joins = []
        removed = 0
        out = skeleton.gsub(SPACED_RUN) do |run|
          joined = run.delete(SEPARATORS)
          joins << (Regexp.last_match.begin(0) - removed)
          removed += run.length - joined.length
          joined
        end
        [out, nil, joins]
      end
    end
  end
end
