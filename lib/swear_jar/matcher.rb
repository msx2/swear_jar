# frozen_string_literal: true

module SwearJar
  # The detection loop. A clean message costs one scanner pass over the skeleton; entry
  # identification and allowlist checks run only on the words around scanner hits.
  #
  # @api private
  class Matcher
    # Leet symbols that are trimmed from word edges, so `kurwa!!!` reports `kurwa`.
    EDGE_SYMBOLS = ['!', '|'].freeze
    NO_SPANS = [].freeze
    NO_CANDIDATES = [].freeze
    NO_RETRIES = [].freeze
    # One-letter words of the bundled languages. A spaced run that starts with one of them may
    # have swallowed it (`a k u r w a`, `i a s s`); after any other character (`p a s s`) the
    # retry skips exact entries, which would otherwise match the tail of an innocent word.
    ONE_LETTER_WORDS = %w[a i o u w z].freeze
    # Invisible characters (zero-width space, word joiner, BOM...) between two letters. They are
    # dropped from the skeleton, so `ku\u200Brwa` is one word; :words mode also retries the
    # letter after them as a word start, so `you\u200Bidiot` still finds `idiot`.
    INVISIBLE_GAP = /(?<=\p{L})[\p{Cf}\p{Default_Ignorable_Code_Point}]+(?=\p{L})/
    # The word being examined: its bounds for the allowlist, the allowlisted spans in it
    # (computed on first use) and the best [entry, from, to] so far.
    Word = Struct.new(:first, :last, :spans, :best)
    # A character before a position that makes it no word start (see PatternBuilder::LEFT).
    LEFT_WORD_CHAR = /[\p{L}\p{N}*]/

    def initialize(pattern_builder)
      @scanner = pattern_builder.scanner
      @words_mode = pattern_builder.mode == :words
      @buckets = build_buckets(pattern_builder)
      @prefixes = build_prefix_index(pattern_builder.prefixes)
      @entry_count = pattern_builder.entry_patterns.map(&:first).uniq.size
      allow = pattern_builder.allow_pattern
      @allow_scanner = allow && Regexp.new(allow.source.delete_prefix('\G'))
      freeze
    end

    def inspect
      "#<#{self.class.name} entries=#{@entry_count}>"
    end

    # nil stays nil; anything else becomes a valid UTF-8 String of class String (so a Rails
    # SafeBuffer gives plain String texts). The caller's string is never mutated.
    def self.coerce(text)
      return if text.nil?

      string = text.to_s
      string = String.new(string) unless string.instance_of?(String)
      unless string.encoding == Encoding::UTF_8
        string = string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
      end
      string.valid_encoding? ? string : string.scrub('')
    end

    # Yields each Match in order of position. Returns an Enumerator without a block, which
    # is lazy: `each_match(text).any?` stops at the first verified match.
    def each_match(text)
      return enum_for(:each_match, text) unless block_given?

      original = Matcher.coerce(text)
      return if original.nil?

      skeleton, index_map, retries = prepare(original)
      hit = @scanner.match(skeleton, 0)
      return if hit.nil? && retries.empty?

      slicer = nil
      each_found(Skeleton.new(skeleton), retries, hit && hit.offset(0)) do |found|
        # The index map is only needed to report a match, so a clean message never builds it.
        index_map ||= Normalizer.call(original).last
        slicer ||= Slicer.new(original)
        yield build_match(slicer, index_map, *found)
      end
      nil
    end

    private

    # [skeleton, index map or nil, retries]. Retries are extra word starts that :words mode
    # tries when the scanner cannot see them: [start, start of the word for the allowlist,
    # whether exact entries may match]. The index map is built here only when invisible
    # characters need it; otherwise it waits for the first match.
    def prepare(original)
      skeleton, joins = Normalizer.skeleton_with_joins(original)
      return [skeleton, nil, NO_RETRIES] unless @words_mode

      # Dropped characters shorten the skeleton, so equal lengths without joins rule out
      # invisible ones without scanning the text.
      if (skeleton.length != original.length || !joins.empty?) && INVISIBLE_GAP.match?(original)
        skeleton, index_map, joins = Normalizer.analyze(original)
        gaps = gap_starts(original, index_map)
      end
      [skeleton, index_map, retries(skeleton, joins, gaps)]
    end

    def gap_starts(original, index_map)
      starts = []
      original.scan(INVISIBLE_GAP) do
        letter = Regexp.last_match.end(0)
        start = index_map.bsearch_index { |index| index >= letter }
        starts << start if start
      end
      starts
    end

    def retries(skeleton, joins, gaps)
      return NO_RETRIES if joins.empty? && gaps.nil?

      list = joins.map { |join| [join + 1, join, ONE_LETTER_WORDS.include?(skeleton[join])].freeze }
      gaps&.each { |start| list << [start, start, true].freeze }
      list.sort_by!(&:first)
      list.uniq!(&:first)
      list
    end

    # Candidates [entry, stem pattern, bounded, prefixed] grouped by the character their stem
    # can start with, in word-list order, so a stem start tries only the entries that fit.
    # bounded: in :embedded mode the scanner hits inside words, so an entry that needs a word
    # boundary checks it at the hit. In :words mode every hit already has one.
    # prefixed: the entry may follow a prefix of its locale.
    def build_buckets(builder)
      buckets = Hash.new { |hash, char| hash[char] = [] }
      builder.entry_patterns.each do |entry, pattern, first_chars|
        bounded = builder.mode == :embedded && (!entry.embeddable || entry.exact)
        prefixed = !entry.exact && !builder.prefixes[entry.locale].empty?
        candidate = [entry, Regexp.new(pattern.source.delete_prefix('\G')), bounded, prefixed].freeze
        first_chars.each { |char| buckets[char] << candidate }
      end
      buckets.to_h { |char, list| [char, list.freeze] }.freeze
    end

    # locale => first character => the locale's prefixes starting with it, longest first.
    def build_prefix_index(prefixes)
      prefixes.reject { |_, list| list.empty? }.transform_values do |list|
        list.group_by { |prefix| prefix[0] }.transform_values(&:freeze).freeze
      end.freeze
    end

    # Yields [first, last, entry] of each match, in order. Words come from scanner hits ([begin,
    # end] pairs) and from +retries+ (see +prepare+), which may have no hit: `a k u r w a` is
    # joined into `akurwa`, where :words mode finds nothing at the word start. A retry inside a
    # word whose hits had no match still runs (`duplikat\u200Bidiot`).
    def each_found(skeleton, retries, hit)
      matched_end = 0
      queue = 0
      loop do
        queue += 1 while queue < retries.size && retries[queue][0] < matched_end
        retry_at = retries[queue]
        if retry_at && (hit.nil? || retry_at[0] <= hit[0])
          queue += 1
          pos, found = examine_retry(skeleton, *retry_at)
        elsif hit
          pos, found, hit = examine_word(skeleton, hit)
        else
          break
        end
        if found
          matched_end = pos
          yield found
        end
        hit = skeleton.search(@scanner, pos) if hit && hit[0] < pos
      end
    end

    # Handles the word around +hit+. Returns [position to continue from, [first, last, entry] of
    # the match or nil, the first scanner hit after the word's hits (or nil when there is none)].
    def examine_word(skeleton, hit)
      first = skeleton.word_start(hit[0])
      scan_end = skeleton.word_end(hit[1])
      winner, next_hit = best_candidate(skeleton, hit, first, scan_end)
      return [scan_end, nil, next_hit] unless winner

      [*finish(skeleton, winner, first, scan_end), next_hit]
    end

    # Tries the entries at +start+ as a word start. In :words mode the scanner only hits at word
    # starts, so no hit can begin later inside this word. Returns [position to continue from,
    # [first, last, entry] or nil].
    def examine_retry(skeleton, start, word_start, exact)
      word_end = skeleton.word_end(start)
      word = Word.new(word_start, word_end)
      best_at(skeleton, start, word, left: true, exact: exact) if start < word_end
      return [word_end, nil] unless word.best

      finish(skeleton, word.best, start, word_end)
    end

    # [position to continue from, [first, last, entry]] for the +winner+ of the word that starts
    # at +first+ and whose hits end at +scan_end+.
    def finish(skeleton, winner, first, scan_end)
      entry, from, to = winner
      last = to > scan_end ? skeleton.word_end(to) : scan_end
      first, last = trim(skeleton, first, last, from, to)
      [last, [first, last, entry]]
    end

    # Tries the entries at every hit inside the word and keeps the best one that no allowlisted
    # word covers: the highest severity, then the longest stem. Returns [[entry, from, to], next_hit].
    def best_candidate(skeleton, hit, word_start, scan_end)
      word = Word.new(word_start, scan_end)
      while hit && hit[0] < scan_end
        best_at(skeleton, hit[0], word)
        hit = skeleton.search(@scanner, hit[0] + 1)
      end
      [word.best, hit]
    end

    # Updates +word.best+ with the entries that match at +at+. +left+ is true when +at+ is
    # known to be a word start. +exact+ false skips exact entries.
    def best_at(skeleton, at, word, left: nil, exact: true)
      each_candidate(skeleton, at, left) do |entry, stem_begin, to|
        next if !exact && entry.exact
        next if word.best && !better?(entry, word.best[0])

        word.spans ||= allow_spans(skeleton, word.first, word.last)
        word.best = [entry, at, to] unless covered?(word.spans, stem_begin, to)
      end
    end

    # Yields entry, stem begin and match end for each entry that matches at +at+. A prefixed
    # entry tries the prefixes found at +at+ (longest first) and then none, and yields only
    # its first match, which is what an optional prefix group in a regexp would match.
    def each_candidate(skeleton, at, left)
      matched = nil
      stem_starts(skeleton, at).each do |start, locale|
        @buckets.fetch(skeleton[start], NO_CANDIDATES).each do |candidate|
          entry, pattern, bounded, prefixed = candidate
          next if locale && !(prefixed && entry.locale == locale)
          next if matched&.include?(candidate)
          next if bounded && !(left = left.nil? ? boundary?(skeleton, at) : left)
          next unless (to = skeleton.match(pattern, start))

          (matched ||= []) << candidate if locale
          yield entry, start, to
        end
      end
    end

    # [stem start, locale of the prefix before it] pairs: each prefix found at +at+, then +at+
    # itself (locale nil, open to every entry).
    def stem_starts(skeleton, at)
      starts = []
      @prefixes.each do |locale, by_char|
        by_char[skeleton[at]]&.each do |prefix|
          starts << [at + prefix.length, locale] if skeleton.literal?(prefix, at)
        end
      end
      starts << [at, nil]
    end

    def boundary?(skeleton, at)
      at.zero? || !LEFT_WORD_CHAR.match?(skeleton[at - 1])
    end

    def better?(entry, current)
      entry.rank > current.rank || (entry.rank == current.rank && entry.stem.length > current.stem.length)
    end

    def allow_spans(skeleton, word_start, word_end)
      return NO_SPANS unless @allow_scanner

      word = Skeleton.new(skeleton.slice(word_start, word_end))
      spans = []
      offset = 0
      while (found = word.search(@allow_scanner, offset))
        spans << [found[0] + word_start, found[1] + word_start]
        offset = found[0] + 1
      end
      spans
    end

    def covered?(spans, stem_begin, stem_end)
      spans.any? { |from, to| from <= stem_begin && to >= stem_end }
    end

    def trim(skeleton, first, last, from, to)
      first += 1 while first < from && EDGE_SYMBOLS.include?(skeleton[first])
      last -= 1 while last > to && EDGE_SYMBOLS.include?(skeleton[last - 1])
      [first, last]
    end

    def build_match(slicer, index_map, first, last, entry)
      range, text = slicer.slice(index_map[first], index_map[last - 1] + 1)
      Match.new(text: text.freeze, range: range, stem: entry.stem, locale: entry.locale,
                severity: entry.severity, categories: entry.categories)
    end
  end
end
