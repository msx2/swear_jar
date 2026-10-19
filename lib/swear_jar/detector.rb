# frozen_string_literal: true

module SwearJar
  # All option processing and pattern compilation happens in +new+; the detector is frozen and
  # safe to share between threads.
  class Detector
    def initialize(locales: Configuration::DEFAULTS[:locales], mode: Configuration::DEFAULTS[:mode],
                   min_severity: Configuration::DEFAULTS[:min_severity],
                   categories: Configuration::DEFAULTS[:categories],
                   extra_paths: Configuration::DEFAULTS[:extra_paths],
                   extra_words: Configuration::DEFAULTS[:extra_words], allow: Configuration::DEFAULTS[:allow])
      mode = mode.to_sym if mode.respond_to?(:to_sym)
      word_list = WordList.load(locales: locales, min_severity: min_severity, categories: categories,
                                extra_paths: extra_paths, extra_words: extra_words, allow: allow)
      @matcher = Matcher.new(PatternBuilder.new(word_list, mode: mode))
      @summary = "locales=#{word_list.locales.inspect} mode=#{mode.inspect} entries=#{word_list.entries.size}"
      freeze
    end

    # The default inspect would dump the compiled patterns (tens of kilobytes).
    def inspect
      "#<#{self.class.name} #{@summary}>"
    end

    # Stops at the first match.
    def profane?(text)
      @matcher.each_match(text) { return true }
      false
    end

    # Sorted by position and never overlapping.
    def matches(text)
      result = []
      @matcher.each_match(text) { |match| result << match }
      result
    end

    # Each match is replaced by the block's return value for it, else by +with+, else by one `*`
    # per character. nil stays nil.
    def censor(text, with: nil)
      raise ArgumentError, 'pass with: or a block, not both' if with && block_given?

      original = Matcher.coerce(text)
      return if original.nil?

      result = +''
      pos = 0
      @matcher.each_match(original) do |match|
        replacement = if block_given? then yield(match)
                      else with || ('*' * match.text.length)
                      end
        result << original[pos...match.range.begin] << replacement.to_s
        pos = match.range.end
      end
      result << original[pos..]
    end
  end
end
