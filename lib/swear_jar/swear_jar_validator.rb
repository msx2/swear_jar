# frozen_string_literal: true

require 'swear_jar'
require 'active_model'
require 'i18n'

I18n.load_path |= Dir[File.join(SwearJar::ROOT_PATH, 'config', 'locales', '*.yml')]

# Validates that an attribute contains no profanity. Without detector options it uses
# +SwearJar.detector+; otherwise it uses a detector cached per option set.
class SwearJarValidator < ActiveModel::EachValidator
  STANDARD_OPTIONS = %i[message if unless on allow_nil allow_blank strict].freeze

  @detectors = {}
  @mutex = Mutex.new

  class << self
    def detector_for(detector_options)
      key = detector_options.sort_by { |name, _| name.to_s }.to_h { |name, value| [name, freeze_value(value)] }.freeze
      @detectors[key] || @mutex.synchronize { @detectors[key] ||= SwearJar::Detector.new(**key) }
    end
  end

  def self.freeze_value(value)
    value.is_a?(Array) ? value.map { |item| freeze_value(item) }.freeze : value.dup.freeze
  end
  private_class_method :freeze_value

  def validate_each(record, attribute, value)
    return if value.blank?

    # A custom message replaces only the text: the error type stays :profane.
    record.errors.add(attribute, :profane, **options.slice(:message)) if detector.profane?(value.to_s)
  end

  private

  def detector
    detector_options = options.except(*STANDARD_OPTIONS)
    return SwearJar.detector if detector_options.empty?

    self.class.detector_for(detector_options)
  end
end
