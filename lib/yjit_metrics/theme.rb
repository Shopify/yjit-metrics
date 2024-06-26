# frozen_string_literal: true

require "yaml"

# Style information stored in root theme.yaml file.
module YJITMetrics
  module Theme
    FILE = File.expand_path("../../theme.yaml", __dir__)
    CONFIG = YAML.safe_load_file(FILE, aliases: true, symbolize_names: true)

    # Define methods for each key in the yaml hash.
    module_eval CONFIG.map { |key, _val| "def self.#{key}; CONFIG.fetch(:#{key}); end" }.join("\n")
  end
end
