FROM dart:stable

RUN apt-get update \
    && apt-get install -y ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64|amd64) tuna_arch="amd64" ;; \
      aarch64|arm64) tuna_arch="arm64" ;; \
      *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://releases.tuna.am/tuna/latest/tuna_linux_${tuna_arch}.tar.gz" -o /tmp/tuna.tar.gz; \
    tar -xzf /tmp/tuna.tar.gz -C /tmp; \
    install -m 0755 /tmp/tuna /usr/local/bin/tuna; \
    rm -f /tmp/tuna /tmp/tuna.tar.gz

WORKDIR /app

COPY services/api_gateway/pubspec.* /app/services/api_gateway/
WORKDIR /app/services/api_gateway
RUN dart pub get

COPY services/api_gateway /app/services/api_gateway
RUN rm -rf /app/services/api_gateway/.dart_tool \
    && dart pub get \
    && chmod +x /app/services/api_gateway/docker/entrypoint.sh

COPY services/auth_service/specs /app/services/auth_service/specs
COPY services/user_service/specs /app/services/user_service/specs
COPY services/schedule_service/specs /app/services/schedule_service/specs
COPY services/event_service/specs /app/services/event_service/specs
COPY services/rating_service/specs /app/services/rating_service/specs
COPY services/chat_service/specs /app/services/chat_service/specs
COPY services/notification_service/specs /app/services/notification_service/specs

ENV SPEC_PATHS=/app/services/auth_service/specs/openapi.yaml;/app/services/user_service/specs/openapi.yaml;/app/services/schedule_service/specs/openapi.yaml;/app/services/event_service/specs/openapi.yaml;/app/services/rating_service/specs/openapi.yaml;/app/services/chat_service/specs/openapi.yaml;/app/services/notification_service/specs/openapi.yaml

EXPOSE 8087

CMD ["/app/services/api_gateway/docker/entrypoint.sh"]
