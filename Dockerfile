# Root Dockerfile for Railway deployment
ARG CW_TAG=develop
FROM chatwoot/chatwoot:${CW_TAG}
COPY custom/ /app/custom/
COPY config/application.rb /app/config/application.rb
# Use the same entrypoint as local dev: waits for DB, then execs CMD
ENTRYPOINT ["docker/entrypoints/rails.sh"]
# Base image has CMD ["irb"] - override to start Rails
CMD ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
