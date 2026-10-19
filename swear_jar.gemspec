# frozen_string_literal: true

require_relative 'lib/swear_jar/version'

Gem::Specification.new do |spec|
  spec.name = 'swear_jar'
  spec.version = SwearJar::VERSION
  spec.authors = ['Konrad Jurkowski']
  spec.email = ['konrad@jurkowski.me']
  spec.description = 'Detects profanity in Polish and English text, including inflection and obfuscation, ' \
                     'and returns exact matches with their positions in the original text'
  spec.summary = 'Swear Jar, a fast profanity detector for Polish and English.'
  spec.homepage = 'https://github.com/msx2/swear_jar'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir[
    'lib/**/*.rb', 'locales/**/*.yml', 'config/locales/*.yml',
    'README.md', 'CHANGELOG.md', 'LICENSE.txt'
  ]
  spec.require_paths = ['lib']
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
end
