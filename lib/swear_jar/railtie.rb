# frozen_string_literal: true

require 'rails/railtie'

module SwearJar
  class Railtie < Rails::Railtie
    config.swear_jar = ActiveSupport::OrderedOptions.new

    # Unknown keys raise ArgumentError.
    def self.apply_config(options)
      return if options.empty?

      options.each_key do |key|
        raise ArgumentError, "unknown config.swear_jar option: #{key.inspect}" unless Configuration::DEFAULTS.key?(key.to_sym)
      end

      SwearJar.configure do |configuration|
        options.each { |key, value| configuration.public_send(:"#{key}=", value) }
      end
    end

    # Builds the global detector at boot rather than on first use, so app servers that preload
    # the app (Puma preload_app!) share it between workers through copy-on-write.
    initializer 'swear_jar.configure', after: :load_config_initializers do |app|
      Railtie.apply_config(app.config.swear_jar)
      SwearJar.detector
    end

    initializer 'swear_jar.validator' do
      require 'swear_jar/swear_jar_validator'
    rescue LoadError => e
      # railties does not depend on activemodel; only skip when that is what is missing.
      raise unless e.path == 'active_model'
    end
  end
end
