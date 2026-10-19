# frozen_string_literal: true

module SwearJar
  # Per-character folds (NFKC, downcase, diacritics, `#` and `%` masks, invisible characters
  # dropped), cached in blocks of 256 code points. The Latin and fullwidth blocks are built at
  # load time. Any other block is built the first time a message contains one of its characters,
  # up to MAX_BLOCKS, so text in another script or full of emoji pays for Unicode normalization
  # once per process instead of on every call. A table is immutable: adding blocks publishes a
  # new table under a mutex, and readers never lock.
  #
  # @api private
  class FoldTable
    BLOCK_BITS = 8
    BLOCK_SIZE = 1 << BLOCK_BITS
    INITIAL_BLOCKS = [0x00, 0x01, 0x02, 0xFF].freeze
    MAX_BLOCKS = 64
    SURROGATES = 0xD800..0xDFFF
    POLISH = {
      'ą' => 'a', 'ć' => 'c', 'ę' => 'e', 'ł' => 'l', 'ń' => 'n', 'ó' => 'o', 'ś' => 's', 'ź' => 'z', 'ż' => 'z'
    }.freeze
    POLISH_RE = /[ąćęłńóśźż]/
    MARKS_RE = /\p{Mn}/
    # Format characters (zero-width space and joiners, soft hyphen, BOM...) and other default
    # ignorables (Hangul fillers...) render as nothing, so they must not split a word.
    INVISIBLE_RE = /\A[\p{Cf}\p{Default_Ignorable_Code_Point}]\z/

    # +slow+: matches a character the whole-string fast path does not fold: an uncovered one,
    # or one whose fold contains `_` (a mask only between letters, which needs the context).
    attr_reader :blocks, :folds, :changing, :uncovered, :slow

    class << self
      def compute(char)
        return '' if INVISIBLE_RE.match?(char)

        folded = char.unicode_normalize(:nfkc).downcase.gsub(POLISH_RE, POLISH)
        folded = folded.unicode_normalize(:nfd).gsub(MARKS_RE, '')
        folded.tr('#%', '**')
      end

      attr_reader :current

      # The current table, first extended with the blocks of +text+'s characters when needed.
      def for(text)
        table = @current
        return table if table.full? || !text.match?(table.uncovered)

        @mutex.synchronize { @current = @current.with_blocks_of(text) }
      end

      def block_folds(block)
        first = block << BLOCK_BITS
        (first...first + BLOCK_SIZE).each_with_object({}) do |codepoint, folds|
          next if SURROGATES.cover?(codepoint)

          char = codepoint.chr(Encoding::UTF_8)
          folds[-char] = -compute(char)
        end
      end

      def initial
        new(INITIAL_BLOCKS, INITIAL_BLOCKS.reduce({}) { |folds, block| folds.merge(block_folds(block)) })
      end
    end

    def initialize(blocks, folds)
      @blocks = blocks.sort.freeze
      @folds = folds.freeze
      build_patterns
      freeze
    end

    def full?
      blocks.size >= MAX_BLOCKS
    end

    def inspect
      "#<#{self.class.name} blocks=#{blocks.size}>"
    end

    # A table that also holds the blocks of +text+'s uncovered characters, or self when none fit.
    def with_blocks_of(text)
      return self if full?

      added = text.scan(uncovered).map { |char| char.ord >> BLOCK_BITS }.uniq.first(MAX_BLOCKS - blocks.size)
      return self if added.empty?

      self.class.new(blocks + added, added.reduce(folds) { |all, block| all.merge(self.class.block_folds(block)) })
    end

    private

    def build_patterns
      changing = folds.filter_map { |char, fold| char.ord if char != fold }
      underscores = folds.filter_map { |char, fold| char.ord if fold.include?('_') }
      @changing = Regexp.new("[#{char_class(ranges(changing))}]")
      @uncovered = Regexp.new("[^#{char_class(block_ranges)}]")
      @slow = Regexp.new("#{@uncovered.source}|[#{char_class(ranges(underscores))}]")
    end

    def block_ranges
      ranges(blocks).map { |range| (range.begin << BLOCK_BITS)..((range.end << BLOCK_BITS) + BLOCK_SIZE - 1) }
    end

    def ranges(values)
      values.sort.uniq.slice_when { |a, b| b != a + 1 }.map { |run| run.first..run.last }
    end

    def char_class(ranges)
      ranges.map { |r| r.size == 1 ? format('\u{%X}', r.begin) : format('\u{%X}-\u{%X}', r.begin, r.end) }.join
    end

    @mutex = Mutex.new
    @current = initial
  end
end
