# frozen_string_literal: true

# Clear stale Redis cache after Rails boot
# The serialized_value column was previously using coder: YAML on a jsonb column,
# which stored corrupted values in the GlobalConfig Redis cache. After migrating
# to CustomCoders::JsonbYamlCoder, stale cached values must be cleared so new
# reads come from the database and use the correct deserialization.
Rails.application.config.after_initialize do
  GlobalConfig.clear_cache
  Rails.logger.info '[clear_stale_cache] Cleared stale GlobalConfig Redis cache'
end
