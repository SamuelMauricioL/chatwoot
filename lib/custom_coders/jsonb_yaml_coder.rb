# frozen_string_literal: true

module CustomCoders
  # Custom coder for installation_configs.serialized_value (jsonb column)
  #
  # The column is `jsonb` but Chatwoot uses `serialize :serialized_value, coder: YAML`.
  # This causes problems because:
  #   - Old records: data is stored as a JSON string containing YAML ("---\n:value: ...\n")
  #   - After jsonb parsing, the YAML coder receives a String → works fine
  #   - Corrupted/newer records: data is stored as a JSON object {"value": "..."}
  #   - After jsonb parsing, the YAML coder receives a Hash → YAML.safe_load(hash) → TypeError
  #
  # This coder handles both formats transparently.
  #
  class JsonbYamlCoder
    # Serialize for storage: return as-is so jsonb column handles JSON serialization
    def self.dump(obj)
      obj
    end

    # Deserialize: handle both YAML strings (old format) and Hashes (jsonb native)
    def self.load(payload)
      return {}.with_indifferent_access if payload.nil?

      case payload
      when String
        # Old format: YAML string stored inside JSON
        parsed = YAML.safe_load(payload, permitted_classes: [ActiveSupport::HashWithIndifferentAccess, Symbol]) || {}
        parsed = { value: parsed } unless parsed.is_a?(Hash)
        parsed.with_indifferent_access
      when Hash
        # Native jsonb format: already a Hash from PG parser
        payload.with_indifferent_access
      else
        { value: payload }.with_indifferent_access
      end
    rescue StandardError => e
      Rails.logger.warn "[JsonbYamlCoder] Failed to parse serialized_value: #{e.message}"
      { value: payload }.with_indifferent_access
    end
  end
end
