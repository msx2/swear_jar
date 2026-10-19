# frozen_string_literal: true

require 'active_model'
require 'swear_jar/swear_jar_validator'

RSpec.describe SwearJarValidator do
  def build_model(**options)
    Class.new do
      include ActiveModel::Validations

      attr_accessor :name

      def self.name = 'Hero'

      validates :name, swear_jar: options.empty? || options
    end
  end

  let(:model_class) { build_model(mode: :embedded) }

  after do
    I18n.locale = I18n.default_locale
    SwearJar.reset_configuration!
  end

  it 'marks profane values invalid with the :profane error' do
    hero = model_class.new.tap { |m| m.name = 'KurwiMistrz' }
    expect(hero).not_to be_valid
    expect(hero.errors.details[:name]).to eq([{ error: :profane }])
    expect(hero.errors[:name]).to eq(['contains inappropriate language'])
  end

  it 'accepts clean values' do
    expect(model_class.new.tap { |m| m.name = 'Aragorn' }).to be_valid
  end

  it 'accepts blank values' do
    expect(model_class.new.tap { |m| m.name = '' }).to be_valid
    expect(model_class.new).to be_valid
  end

  it 'translates the message to Polish' do
    I18n.locale = :pl
    hero = model_class.new.tap { |m| m.name = 'KurwiMistrz' }
    hero.valid?
    expect(hero.errors[:name]).to eq(['zawiera niedozwolone słowa'])
  end

  it 'honours a custom message and keeps the :profane error type' do
    klass = build_model(mode: :embedded, message: 'nope')
    hero = klass.new.tap { |m| m.name = 'KurwiMistrz' }
    hero.valid?
    expect(hero.errors[:name]).to eq(['nope'])
    expect(hero.errors.added?(:name, :profane)).to be(true)
    expect(hero.errors.details[:name]).to eq([{ error: :profane }])
  end

  it 'honours a custom message given as a translation key' do
    I18n.backend.store_translations(:en, errors: { messages: { inappropriate: 'is not nice' } })
    klass = build_model(mode: :embedded, message: :inappropriate)
    hero = klass.new.tap { |m| m.name = 'KurwiMistrz' }
    hero.valid?
    expect(hero.errors[:name]).to eq(['is not nice'])
    expect(hero.errors.added?(:name, :profane)).to be(true)
  end

  it 'shares one detector between models with the same options' do
    a = build_model(mode: :embedded)
    b = build_model(mode: :embedded)
    detector_a = a.validators.first.send(:detector)
    expect(b.validators.first.send(:detector)).to equal(detector_a)
  end

  it 'gives different detectors for different options' do
    words = build_model(mode: :words).validators.first.send(:detector)
    expect(words).not_to equal(model_class.validators.first.send(:detector))
  end

  it 'is not affected by later mutation of option arrays' do
    paths = []
    first = build_model(extra_words: paths).validators.first.send(:detector)
    paths << 'zzz'
    expect(build_model(extra_words: []).validators.first.send(:detector)).to equal(first)
  end

  it 'uses the global detector when no detector options are given' do
    klass = build_model
    expect(klass.validators.first.send(:detector)).to equal(SwearJar.detector)
  end

  it 'ignores standard validator options when choosing the detector' do
    klass = build_model(allow_nil: true, message: 'x')
    expect(klass.validators.first.send(:detector)).to equal(SwearJar.detector)
  end
end
