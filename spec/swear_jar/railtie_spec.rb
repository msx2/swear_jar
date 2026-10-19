# frozen_string_literal: true

begin
  require 'rails'
rescue LoadError
  RSpec.describe 'SwearJar::Railtie' do
    it('is skipped without railties') { skip 'railties is not installed' }
  end

  return
end

require 'spec_helper'
require 'swear_jar/railtie'

RSpec.describe SwearJar::Railtie do
  after { SwearJar.reset_configuration! }

  it 'exposes config.swear_jar as OrderedOptions' do
    expect(described_class.config.swear_jar).to be_a(ActiveSupport::OrderedOptions)
  end

  it 'registers its initializers' do
    names = described_class.initializers.map(&:name)
    expect(names).to include('swear_jar.configure', 'swear_jar.validator')
  end

  it 'runs the configure initializer after config/initializers are loaded' do
    initializer = described_class.initializers.find { |i| i.name == 'swear_jar.configure' }
    expect(initializer.after).to eq(:load_config_initializers)
  end

  it 'builds the global detector at boot, so preloaded app servers share it' do
    SwearJar.reset_configuration!
    initializer = described_class.initializers.find { |i| i.name == 'swear_jar.configure' }
    app = Struct.new(:config).new(Struct.new(:swear_jar).new(ActiveSupport::OrderedOptions.new))
    initializer.run(app)
    expect(SwearJar.instance_variable_get(:@detector)).to be_a(SwearJar::Detector)
  end

  describe '.apply_config' do
    it 'validates every key before configuring anything' do
      detector = SwearJar.detector
      expect { described_class.apply_config(mode: :embedded, bogus: 1) }.to raise_error(ArgumentError, /bogus/)
      expect(SwearJar.detector).to equal(detector)
    end

    it 'maps options onto the global configuration' do
      described_class.apply_config(mode: :embedded)
      expect(SwearJar.detector.profane?('KurwiMistrz')).to be(true)
    end

    it 'raises ArgumentError naming an unknown key' do
      expect { described_class.apply_config(bogus: 1) }.to raise_error(ArgumentError, /bogus/)
    end

    it 'does nothing when no options are set' do
      detector = SwearJar.detector
      described_class.apply_config({})
      expect(SwearJar.detector).to equal(detector)
    end
  end
end
