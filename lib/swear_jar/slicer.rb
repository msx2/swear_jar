# frozen_string_literal: true

module SwearJar
  # Cuts match texts out of the original string. Indexing a long non-ASCII string by
  # characters, or slicing a long piece of it, scans it from the start, so slicing each of many
  # matches in a long message would cost O(length) per match. Matches come in order, so a
  # cursor (character and byte offset) moves forward instead, and each slice works on a short
  # byte window, costing only the distance from the previous match.
  #
  # @api private
  class Slicer
    # Combining marks right after a match belong to its last character.
    TRAILING_MARKS = /\G\p{M}+/
    # A UTF-8 character takes at most 4 bytes; extra room for the marks after a match.
    CHAR_BYTES = 4
    MARKS_ROOM = 64

    def initialize(string)
      @string = string
      @char = 0
      @byte = 0
    end

    # [range, text] for the characters from +first+ to +last+ (exclusive), extended over the
    # combining marks that follow. +first+ must not be before the previous call's +first+.
    def slice(first, last)
      skip_to(first)
      length = last - first
      room = (CHAR_BYTES * length) + MARKS_ROOM
      loop do
        window = window(room)
        marks = TRAILING_MARKS.match(window, length)
        if marks.nil? || marks.end(0) < window.length || @byte + room >= @string.bytesize
          length = marks.end(0) if marks
          return [first...(first + length), window[0, length]]
        end
        room *= 2
      end
    end

    def inspect
      "#<#{self.class.name} at=#{@char}>"
    end

    private

    def skip_to(first)
      distance = first - @char
      @byte += window(CHAR_BYTES * distance)[0, distance].bytesize
      @char = first
    end

    # Up to +bytes+ bytes from the cursor, without a character cut off at the end.
    def window(bytes)
      @string.byteslice(@byte, bytes).scrub('')
    end
  end
end
