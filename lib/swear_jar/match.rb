# frozen_string_literal: true

module SwearJar
  Match = Struct.new(:text, :range, :stem, :locale, :severity, :categories, keyword_init: true) do
    def initialize(*)
      super
      freeze
    end
  end
end
