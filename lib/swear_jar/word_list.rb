# frozen_string_literal: true

require 'yaml'

module SwearJar
  # @api private
  class WordList
    FILE_KEYS = %w[locale prefixes words allow].freeze
    EXTRA_SOURCE = 'extra_words'
    ALLOW_SOURCE = 'allow option'
    GLOB_CHARS = /[*?\[{]/

    # +allow_sources+: each allow word => where it came from, for error messages.
    attr_reader :locales, :entries, :prefixes, :allow, :allow_sources

    def self.load(locales: LOCALES, min_severity: :mild, categories: nil, extra_paths: [], extra_words: [], allow: [])
      locales = validated_option(:locales, symbolize(Array(locales)), LOCALES)
      min_severity = validated_option(:min_severity, symbolize([min_severity]), SEVERITIES).first
      categories = validated_option(:categories, symbolize(Array(categories)), CATEGORIES) if categories
      new(locales: locales, min_severity: min_severity, categories: categories,
          extra_paths: extra_paths, extra_words: extra_words, allow: allow)
    end

    # An empty list is rejected too: it would build a detector that silently finds nothing.
    def self.validated_option(name, values, allowed)
      raise ArgumentError, "#{name} must not be empty, expected some of #{allowed.inspect}" if values.empty?

      unknown = values - allowed
      return values if unknown.empty?

      raise ArgumentError, "unknown #{name} #{unknown.inspect}, expected #{allowed.inspect}"
    end

    def self.symbolize(values)
      values.map { |v| v.respond_to?(:to_sym) ? v.to_sym : v }
    end
    private_class_method :validated_option, :symbolize

    def initialize(locales:, min_severity:, categories:, extra_paths:, extra_words:, allow:)
      @locales = locales.freeze
      sources = bundled_sources(locales) + extra_sources(extra_paths, locales) + extra_word_sources(extra_words)
      min_rank = SEVERITIES.index(min_severity)
      @entries = sources.flat_map { |s| s[:entries] }.select { |e| keep?(e, locales, min_rank, categories) }.freeze
      @prefixes = collect_prefixes(sources, locales)
      @allow_sources = collect_allow(sources, allow)
      @allow = @allow_sources.keys.freeze
      freeze
    end

    def inspect
      "#<#{self.class.name} entries=#{entries.size} allow=#{allow.size}>"
    end

    private

    def keep?(entry, locales, min_rank, categories)
      locales.include?(entry.locale) && entry.rank >= min_rank &&
        (categories.nil? || (categories & entry.categories).any?)
    end

    def collect_prefixes(sources, locales)
      locales.to_h do |locale|
        list = sources.select { |s| s[:locale] == locale }.flat_map { |s| s[:prefixes] }.uniq
        [locale, list.sort_by.with_index { |p, i| [-p.length, i] }.freeze]
      end.freeze
    end

    # Allow words in order, without duplicates => the source of their first occurrence.
    def collect_allow(sources, allow)
      pairs = sources.flat_map { |s| s[:allow].map { |word| [word, s[:path]] } }
      pairs += Array(allow).map { |word| [word.to_s.dup.freeze, ALLOW_SOURCE] }
      pairs.each_with_object({}) { |(word, source), all| all[word] ||= source }.freeze
    end

    def bundled_sources(locales)
      locales.map { |locale| read_file(File.join(ROOT_PATH, 'locales', locale.to_s, 'words.yml'), locale) }
    end

    def extra_sources(extra_paths, locales)
      Array(extra_paths).flat_map { |pattern| extra_files(pattern.to_s) }.filter_map do |path|
        source = read_file(path, nil)
        source if locales.include?(source[:locale])
      end
    end

    # A glob may match nothing. A plain path is read as is, so a missing file raises.
    def extra_files(pattern)
      pattern.match?(GLOB_CHARS) ? Dir.glob(pattern).sort : [pattern]
    end

    def extra_word_sources(extra_words)
      Array(extra_words).map do |hash|
        raise InvalidWordListError, "#{EXTRA_SOURCE}: entry #{hash.inspect} is not a Hash" unless hash.is_a?(Hash)

        attrs = hash.transform_keys(&:to_sym)
        locale = attrs.delete(:locale)
        unless LOCALES.include?(locale.respond_to?(:to_sym) ? locale.to_sym : nil)
          raise InvalidWordListError,
                "#{EXTRA_SOURCE}: entry #{hash[:stem].inspect} needs a locale (#{LOCALES.join(' or ')})"
        end

        check_variants(attrs, EXTRA_SOURCE)
        locale = locale.to_sym
        { locale: locale, path: EXTRA_SOURCE, prefixes: [], allow: [],
          entries: [Entry.build(attrs, locale: locale, source: EXTRA_SOURCE)] }
      end
    end

    # +locale+ is nil for extra files, which must declare it.
    def read_file(path, locale)
      data = YAML.safe_load(File.read(path)) # rubocop:disable Style/YAMLFileRead
      fail_in(path, 'root must be a Hash') unless data.is_a?(Hash)
      unknown = data.keys - FILE_KEYS
      fail_in(path, "unknown top-level keys #{unknown.inspect}") unless unknown.empty?

      locale ||= file_locale(data['locale'], path)
      {
        locale: locale,
        path: path,
        prefixes: string_list(data['prefixes'], 'prefixes', path),
        allow: string_list(data['allow'], 'allow', path),
        entries: build_entries(data['words'], locale, path)
      }
    rescue Psych::Exception, SystemCallError => e
      raise InvalidWordListError, "#{path}: #{e.message}"
    end

    def file_locale(value, path)
      locale = value.is_a?(String) ? value.to_sym : nil
      return locale if LOCALES.include?(locale)

      fail_in(path, "top-level locale must be one of #{LOCALES.inspect}, got #{value.inspect}")
    end

    def string_list(value, key, path)
      return [] if value.nil?
      return value.map { |w| w.dup.freeze }.freeze if value.is_a?(Array) && value.all?(String)

      fail_in(path, "#{key} must be an Array of strings")
    end

    def build_entries(words, locale, path)
      return [] if words.nil?
      fail_in(path, 'words must be an Array') unless words.is_a?(Array)

      words.map do |hash|
        fail_in(path, "entry #{hash.inspect} must be a Hash") unless hash.is_a?(Hash)
        check_variants(hash, path)
        Entry.build(hash, locale: locale, source: path)
      end
    end

    def check_variants(hash, path)
      key = ['variants', :variants].find { |k| hash.key?(k) }
      return unless key

      variants = hash[key]
      return if variants.is_a?(Array) && variants.all? { |v| v.is_a?(String) && !v.strip.empty? }

      fail_in(path, "entry #{(hash['stem'] || hash[:stem]).inspect}: variants must be an Array of non-blank strings")
    end

    def fail_in(path, message)
      raise InvalidWordListError, "#{path}: #{message}"
    end
  end
end
