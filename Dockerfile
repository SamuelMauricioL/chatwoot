# Root Dockerfile for Railway deployment
ARG CW_TAG=develop
FROM chatwoot/chatwoot:${CW_TAG}
COPY custom/ /app/custom/
COPY config/application.rb /app/config/application.rb
# Fix cable.yml: upstream uses `.presence` which crashes when ActiveSupport
# core_ext hasn't loaded yet (undefined method 'presence' for nil)
COPY custom/config/cable.yml /app/config/cable.yml
# Railway: skip the entrypoint (pg_isready hangs with Railway's DATABASE_URL),
# just start Rails directly. Railway manages service dependency.
CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
