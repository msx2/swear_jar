# frozen_string_literal: true

module SwearJar
  # @api private
  class Entry
    KEYS = %i[stem variants severity categories embeddable exact].freeze

    # +source+ names where the entry came from (a file path or `extra_words`), for error messages.
    attr_reader :stem, :variants, :locale, :severity, :categories, :embeddable, :exact, :source

    def self.build(hash, locale:, source:)
      new(hash, locale: locale, source: source)
    end

    def initialize(hash, locale:, source:)
      attrs = hash.to_h { |key, value| [key.respond_to?(:to_sym) ? key.to_sym : key, value] }
      @locale = locale
      @source = source.to_s.dup.freeze
      @stem = validated_stem(attrs, source)
      where = "#{source}: entry #{@stem.inspect}"
      reject_unknown_keys(attrs, where)
      @variants = freeze_strings(attrs[:variants] || [])
      @severity = validated_severity(attrs[:severity], where)
      @categories = validated_categories(attrs[:categories], where)
      @embeddable = validated_boolean(attrs, :embeddable, true, where)
      @exact = validated_boolean(attrs, :exact, false, where)
      freeze
    end

    def spellings
      [stem, *variants]
    end

    def rank
      SEVERITIES.index(severity)
    end

    private

    def validated_stem(attrs, source)
      stem = attrs[:stem]
      return stem.to_s.dup.freeze if stem.is_a?(String) && !stem.strip.empty?

      raise InvalidWordListError, "#{source}: entry #{stem.inspect} has a missing or blank stem"
    end

    def reject_unknown_keys(attrs, where)
      unknown = attrs.keys - KEYS
      raise InvalidWordListError, "#{where} has unknown keys #{unknown.inspect}" unless unknown.empty?
    end

    def freeze_strings(list)
      list.map { |item| item.to_s.dup.freeze }.freeze
    end

    def validated_severity(value, where)
      severity = value.respond_to?(:to_sym) ? value.to_sym : nil
      return severity if SEVERITIES.include?(severity)

      raise InvalidWordListError, "#{where} has unknown severity #{value.inspect}"
    end

    def validated_categories(value, where)
      list = Array(value).map { |c| c.respond_to?(:to_sym) ? c.to_sym : c }
      raise InvalidWordListError, "#{where} has empty categories" if list.empty?

      unknown = list - CATEGORIES
      raise InvalidWordListError, "#{where} has unknown categories #{unknown.inspect}" unless unknown.empty?

      list.freeze
    end

    def validated_boolean(attrs, key, default, where)
      return default unless attrs.key?(key)

      value = attrs[key]
      return value if [true, false].include?(value)

      raise InvalidWordListError, "#{where} has non-boolean #{key}: #{value.inspect}"
    end
  end
end
