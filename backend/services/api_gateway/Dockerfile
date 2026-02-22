FROM dart:stable

WORKDIR /app

COPY services/api_gateway/pubspec.* /app/services/api_gateway/
WORKDIR /app/services/api_gateway
RUN dart pub get

COPY services/api_gateway /app/services/api_gateway
COPY services/auth_service/specs /app/services/auth_service/specs
COPY services/user_service/specs /app/services/user_service/specs
COPY services/schedule_service/specs /app/services/schedule_service/specs
COPY services/event_service/specs /app/services/event_service/specs
COPY services/rating_service/specs /app/services/rating_service/specs
COPY services/chat_service/specs /app/services/chat_service/specs
COPY services/notification_service/specs /app/services/notification_service/specs

ENV SPEC_PATHS=/app/services/auth_service/specs/openapi.yaml;/app/services/user_service/specs/openapi.yaml;/app/services/schedule_service/specs/openapi.yaml;/app/services/event_service/specs/openapi.yaml;/app/services/rating_service/specs/openapi.yaml;/app/services/chat_service/specs/openapi.yaml;/app/services/notification_service/specs/openapi.yaml

EXPOSE 8087

CMD ["dart", "run", "bin/api_gateway.dart"]
