# frozen_string_literal: true

require 'strscan'

module SwearJar
  # Read access to one skeleton by character index, in constant time per call. Ruby indexes a
  # non-ASCII string by scanning it from the start, so a message with many hits would cost
  # O(length) per hit; here a non-ASCII skeleton gets a character <=> byte offset table once
  # and all matching goes through a StringScanner at byte positions. Anchored matching also
  # needs StringScanner: Regexp#match(string, pos) with `\G` is not reliably anchored, since for
  # a pattern with a required substring (`{2,}` runs) Onigmo first searches the rest of the
  # string for it. fixed_anchor lets lookbehinds see before the position.
  #
  # @api private
  class Skeleton
    NON_WORD = /[^\p{L}\p{N}*@$!|]/

    attr_reader :string, :length

    def initialize(string)
      @string = string
      @length = string.length
      @scanner = StringScanner.new(string, fixed_anchor: true)
      build_offsets unless string.ascii_only?
    end

    def [](index)
      return @string[index] unless @offsets
      return if index >= @length

      @string.byteslice(@offsets[index], @offsets[index + 1] - @offsets[index])
    end

    def slice(first, last)
      return @string[first...last] unless @offsets

      @string.byteslice(@offsets[first], @offsets[last] - @offsets[first])
    end

    # The end of a +pattern+ match starting exactly at +at+, or nil.
    def match(pattern, at)
      @scanner.pos = byte(at)
      @scanner.skip(pattern) && char(@scanner.pos)
    end

    def literal?(string, at)
      @scanner.pos = byte(at)
      !@scanner.skip(string).nil?
    end

    # [begin, end] of the first +pattern+ match at or after +from+, or nil.
    def search(pattern, from)
      @scanner.pos = byte(from)
      return unless @scanner.skip_until(pattern)

      [char(@scanner.pos - @scanner.matched_size), char(@scanner.pos)]
    end

    def word_start(pos)
      return 0 if pos.zero?

      unless @offsets
        boundary = @string.rindex(NON_WORD, pos - 1)
        return boundary ? boundary + 1 : 0
      end
      index = breaks.bsearch_index { |at| at >= pos } || breaks.size
      index.zero? ? 0 : breaks[index - 1] + 1
    end

    # The end of the word that contains +pos+ (or +pos+ itself when it is not in a word).
    def word_end(pos)
      return @string.index(NON_WORD, pos) || @length unless @offsets

      breaks.bsearch { |at| at >= pos } || @length
    end

    def inspect
      "#<#{self.class.name} length=#{@length}>"
    end

    private

    def byte(char)
      @offsets ? @offsets[char] : char
    end

    def char(byte)
      @chars ? @chars[byte] : byte
    end

    # @offsets: character index => byte offset (plus the total size at the end);
    # @chars: byte offset of a character => its index.
    def build_offsets
      @offsets = []
      @chars = []
      offset = 0
      @string.each_char.with_index do |character, index|
        @offsets << offset
        @chars[offset] = index
        offset += character.bytesize
      end
      @offsets << offset
      @chars[offset] = @length
    end

    # Sorted indexes of the non-word characters, built on first use.
    def breaks
      @breaks ||= begin
        list = []
        @scanner.pos = 0
        list << char(@scanner.pos - @scanner.matched_size) while @scanner.skip_until(NON_WORD)
        list
      end
    end
  end
end
