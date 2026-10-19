# frozen_string_literal: true

module SwearJar
  # Compiles a word list into one detection regexp (generated from a trie of stem runs),
  # per-spelling anchored regexps for entry identification, and an allowlist regexp.
  #
  # @api private
  class PatternBuilder
    LEET = {
      'a' => 'a4@', 'o' => 'o0', 'i' => 'i1!|', 'e' => 'e3', 's' => 's$5',
      't' => 't7', 'l' => 'l1|', 'b' => 'b8', 'g' => 'g9'
    }.freeze
    CLASS_SPECIALS = ['-', ']', '[', '\\', '^'].freeze
    # Leet symbols. They are not word characters for LEFT, so a word may start after them.
    SYMBOLS = '!|@$'
    LEFT = '(?<![\p{L}\p{N}*])'
    RIGHT = '(?![\p{L}\p{N}*])'
    JOIN = '[.\-~]*'
    GAP = '[.\-~ ]*'
    NEVER = /(?!)/
    LETTER = /\p{L}/
    DIGIT = /\p{N}/
    PREFIXED_LOCALES = %i[pl].freeze
    # Trie token for a run of non-letters inside a stem (e.g. the space in a multi-word entry).
    GAP_TOKEN = :gap
    TERMINAL = :end

    attr_reader :mode, :scanner, :entry_patterns, :allow_pattern, :prefixes

    # +entry_patterns+: [entry, anchored (`\G`) regexp of the stem, characters the stem can start
    # with], one per folded spelling. A stem regexp has no prefixes: the matcher tries them.
    # +prefixes+: locale => folded prefixes, longest first (empty for unprefixed locales).
    # +allow_pattern+: the allowlist regexp, or nil.
    def initialize(word_list, mode:)
      raise ArgumentError, "unknown mode #{mode.inspect}, expected #{MODES.inspect}" unless MODES.include?(mode)

      @mode = mode
      @prefixes = folded_prefixes(word_list.prefixes)
      spellings = word_list.entries.map { |entry| [entry, spelling_tokens(entry)] }
      @scanner = build_scanner(spellings, mode)
      @entry_patterns = build_entry_patterns(spellings)
      @allow_pattern = build_allow_pattern(word_list)
      freeze
    end

    def inspect
      "#<#{self.class.name} mode=#{mode.inspect} entries=#{entry_patterns.map(&:first).uniq.size}>"
    end

    private

    def spelling_tokens(entry)
      where = "#{entry.source}: entry #{entry.stem.inspect}"
      entry.spellings.map { |spelling| tokens(spelling, where) }.uniq
    end

    # Folds +word+ and splits it into runs of identical letters, [letter, count, final], with
    # GAP_TOKEN standing for any run of non-letters between them. Only the last run is final.
    def tokens(word, where)
      list = []
      Normalizer.fold(word).each_char do |char|
        raise InvalidWordListError, "#{where}: #{word.inspect} contains a digit" if DIGIT.match?(char)

        if !LETTER.match?(char)
          list << GAP_TOKEN unless list.empty? || list.last == GAP_TOKEN
        elsif list.last.is_a?(Array) && list.last[0] == char
          list[-1] = [char, list.last[1] + 1, false]
        else
          list << [char, 1, false]
        end
      end
      list.pop if list.last == GAP_TOKEN
      raise InvalidWordListError, "#{where}: #{word.inspect} has no letters" if list.empty?

      list[-1] = [*list.last.take(2), true]
      list
    end

    def build_scanner(spellings, mode)
      exact, loose = spellings.partition { |entry, _| entry.exact }
      bounded, free = loose.partition { |entry, _| mode == :words || !entry.embeddable }
      bounded_parts = LOCALES.filter_map { |locale| locale_branch(bounded, locale, guard: :symbols) }
      exact_trie = render_trie(exact.flat_map(&:last), guard: :symbols)
      bounded_parts << "#{exact_trie}#{RIGHT}" if exact_trie
      free_parts = LOCALES.filter_map { |locale| locale_branch(free, locale, guard: :run, prefixed: false) }

      parts = []
      parts << "#{LEFT}(?:#{bounded_parts.join('|')})" unless bounded_parts.empty?
      parts << "(?:#{free_parts.join('|')})" unless free_parts.empty?
      parts.empty? ? NEVER : Regexp.new(parts.join('|'))
    end

    def locale_branch(spellings, locale, guard:, prefixed: true)
      trie = render_trie(spellings.select { |entry, _| entry.locale == locale }.flat_map(&:last), guard: guard)
      return unless trie

      prefixed ? "#{prefix_group(locale)}#{trie}" : trie
    end

    # Folded prefixes per locale, longest first. Only PREFIXED_LOCALES have any.
    def folded_prefixes(prefixes)
      LOCALES.to_h do |locale|
        list = PREFIXED_LOCALES.include?(locale) ? Array(prefixes[locale]) : []
        folded = list.map { |p| Normalizer.fold(p) }.reject(&:empty?).uniq
        [locale, folded.sort_by.with_index { |p, i| [-p.length, i] }.freeze]
      end.freeze
    end

    def prefix_group(locale)
      list = @prefixes[locale]
      list.empty? ? '' : "(?:#{list.map { |p| Regexp.escape(p) }.join('|')})?"
    end

    def build_entry_patterns(spellings)
      spellings.flat_map do |entry, token_lists|
        suffix = entry.exact ? RIGHT : ''
        token_lists.map do |list|
          # The first run is never masked, so a stem starts with a character of its class.
          first_chars = (LEET[list.first[0]] || list.first[0]).chars.freeze
          [entry, Regexp.new("\\G#{render_trie([list])}#{suffix}"), first_chars].freeze
        end
      end.freeze
    end

    def build_allow_pattern(word_list)
      sources = word_list.allow_sources
      lists = word_list.allow.map { |word| tokens(word, "#{sources.fetch(word, 'allow')}: allow word") }
      trie = render_trie(lists, guard: :run)
      trie && Regexp.new("\\G#{trie}")
    end

    # Builds a trie (nested Hashes keyed by token, TERMINAL marks an end) and renders it.
    # Final runs are distinct tokens, so a node is either terminal or has children, never both.
    # +guard+ adds a lookbehind to each root run, so a pattern searched without an anchor
    # cannot start inside a run and rescan it (quadratic without regexp memoization):
    # :run rejects any character of the run's class before it; :symbols rejects two leet
    # symbols of the class (for branches behind LEFT, which a single symbol does not stop:
    # `hello!idiot` must still match).
    def render_trie(token_lists, guard: nil)
      root = {}
      token_lists.each do |list|
        node = list.reduce(root) { |current, token| current[token] ||= {} }
        node[TERMINAL] = true
      end
      render_children(root, nil, guard)
    end

    # Renders the alternatives below +node+, whose own token is +parent+ (nil at the root).
    # Non-final runs come first so the longer spellings are tried first.
    # Returns nil when the node has no children.
    def render_children(node, parent, guard = nil)
      children = node.reject { |token, _| token == TERMINAL }
      children = children.sort_by.with_index { |(token, _), i| [final?(token) ? 1 : 0, i] }
      branches = children.map do |token, child|
        [lead(parent, token), "#{atom(token, parent.nil?, guard)}#{render_children(child, token)}"]
      end
      return if branches.empty?

      leads = branches.map(&:first).uniq
      return "#{leads.first}#{group(branches.map(&:last))}" if leads.size == 1

      group(branches.map { |head, body| "#{head}#{body}" })
    end

    def final?(token)
      token.is_a?(Array) && token[2]
    end

    def group(alternatives)
      alternatives.size == 1 ? alternatives.first : "(?:#{alternatives.join('|')})"
    end

    def lead(parent, token)
      parent.nil? || parent == GAP_TOKEN || token == GAP_TOKEN ? '' : JOIN
    end

    # A run is atomic and greedy. Note: when adjacent runs have overlapping leet classes
    # (i `[i1!|]` and l `[l1|]`), the first run swallows the shared symbols and the match fails.
    # Masks may replace only interior runs, never the first or the last one, and stand for
    # up to as many letters as the run has (`a**hole`).
    def atom(token, first, guard)
      return GAP if token == GAP_TOKEN

      letter, count, final = token
      klass = letter_class(letter)
      return guarded_run(letter, klass, count, guard) if first

      run = "(?>#{klass}#{count == 1 ? '+' : "{#{count},}"})"
      return run if final

      masks = count == 1 ? '\\*' : "\\*{1,#{count}}"
      "(?:#{run}|#{masks})"
    end

    # The guard looks behind the first character of the run rather than before it, so it only
    # runs where that character already matched: the many branches of the scanner tried at
    # every word start stay cheap.
    def guarded_run(letter, klass, count, guard)
      rest = count == 1 ? '*' : "{#{count - 1},}"
      "(?>#{klass}#{guard_behind(letter, klass, guard)}#{klass}#{rest})"
    end

    def guard_behind(letter, klass, guard)
      case guard
      when :run then "(?<!#{klass}{2})"
      when :symbols
        symbols = (LEET[letter] || letter).delete("^#{SYMBOLS}")
        symbols.empty? ? '' : "(?<!#{class_of(symbols.chars)}{2}#{klass})"
      else ''
      end
    end

    def letter_class(letter)
      class_of((LEET[letter] || letter).chars.uniq)
    end

    def class_of(chars)
      "[#{chars.map { |c| CLASS_SPECIALS.include?(c) ? "\\#{c}" : c }.join}]"
    end
  end
end
