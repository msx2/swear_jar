# frozen_string_literal: true

module SwearJar
  # Single source of truth for the default option values: +Detector.new+ reads DEFAULTS too.
  class Configuration
    DEFAULTS = {
      locales: LOCALES, mode: :words, min_severity: :mild, categories: nil,
      extra_paths: [].freeze, extra_words: [].freeze, allow: [].freeze
    }.freeze

    attr_accessor(*DEFAULTS.keys)

    def initialize
      DEFAULTS.each { |key, value| public_send(:"#{key}=", value.frozen? && value.is_a?(Array) ? value.dup : value) }
    end

    def to_h
      DEFAULTS.each_key.to_h { |key| [key, public_send(key)] }
    end
  end

  @mutex = Mutex.new
  @detector = nil

  class << self
    # Yields a fresh Configuration, builds the detector first (so an invalid configuration raises
    # and leaves the current detector untouched), then swaps it in under the mutex.
    def configure
      config = Configuration.new
      yield config
      new_detector = Detector.new(**config.to_h)
      @mutex.synchronize { @detector = new_detector }
    end

    # Readers do not lock once the detector exists.
    def detector
      @detector || @mutex.synchronize { @detector ||= Detector.new(**Configuration.new.to_h) }
    end

    def profane?(text)
      detector.profane?(text)
    end

    def matches(text)
      detector.matches(text)
    end

    def censor(text, with: nil, &block)
      detector.censor(text, with: with, &block)
    end

    def reset_configuration!
      @mutex.synchronize { @detector = nil }
    end
  end
end
