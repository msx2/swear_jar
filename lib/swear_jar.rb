# frozen_string_literal: true

require_relative 'swear_jar/version'
require_relative 'swear_jar/errors'
require_relative 'swear_jar/match'
require_relative 'swear_jar/entry'
require_relative 'swear_jar/word_list'
require_relative 'swear_jar/fold_table'
require_relative 'swear_jar/normalizer'
require_relative 'swear_jar/pattern_builder'
require_relative 'swear_jar/skeleton'
require_relative 'swear_jar/slicer'
require_relative 'swear_jar/matcher'
require_relative 'swear_jar/detector'

module SwearJar
  ROOT_PATH = File.expand_path('..', __dir__)

  LOCALES = %i[pl en].freeze
  SEVERITIES = %i[mild strong severe].freeze
  CATEGORIES = %i[vulgar sexual insult slur religious].freeze
  MODES = %i[words embedded].freeze
end

require_relative 'swear_jar/configuration'

require_relative 'swear_jar/railtie' if defined?(Rails::Railtie)
