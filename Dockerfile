# Root Dockerfile for Railway deployment
# Uses the official pre-built image and overlays custom extensions
ARG CW_TAG=latest
FROM chatwoot/chatwoot:${CW_TAG}

# Copy custom extensions on top of the pre-built image
# El Rails autoloader + ChatwootApp.extensions detectan custom/ automáticamente
COPY custom/ /app/custom/
COPY config/application.rb /app/config/application.rb
