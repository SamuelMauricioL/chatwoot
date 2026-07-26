# Root Dockerfile for Railway deployment
# Pinned to chatwoot/chatwoot:develop (latest stable nightly build).
# ⚠️ v4.16.1-ce crashes on boot (bug in enterprise extension loader).
#    When upgrading, test the tag first before deploying to production.
ARG CW_TAG=develop
FROM chatwoot/chatwoot:${CW_TAG}
COPY custom/ /app/custom/
COPY config/application.rb /app/config/application.rb
# Fix cable.yml: upstream uses `.presence` which crashes when ActiveSupport
# core_ext hasn't loaded yet (undefined method 'presence' for nil)
COPY custom/config/cable.yml /app/config/cable.yml
# Fix for jsonb+YAML serialization in installation_configs
COPY lib/custom_coders/jsonb_yaml_coder.rb /app/lib/custom_coders/jsonb_yaml_coder.rb
# Override installation_config.rb from base image: uses CustomCoders::JsonbYamlCoder
COPY app/models/installation_config.rb /app/app/models/installation_config.rb
# Clear stale Redis cache on boot
COPY config/initializers/clear_stale_cache.rb /app/config/initializers/clear_stale_cache.rb
# Railway: skip the entrypoint (pg_isready hangs with Railway's DATABASE_URL),
# just start Rails directly. Railway manages service dependency.
CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
