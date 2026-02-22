API gateway for Cyberzone backend. Routes external requests to internal
microservices.

## Run

```bash
dart pub get
dart run bin/api_gateway.dart
```

## Environment

- PORT (default 8087)
- AUTH_SERVICE_URL (default http://localhost:8080)
- USER_SERVICE_URL (default http://localhost:8081)
- SCHEDULE_SERVICE_URL (default http://localhost:8082)
- EVENT_SERVICE_URL (default http://localhost:8083)
- RATING_SERVICE_URL (default http://localhost:8084)
- CHAT_SERVICE_URL (default http://localhost:8085)
- NOTIFICATION_SERVICE_URL (default http://localhost:8086)
- PROXY_TIMEOUT_MS (default 10000)
- SPEC_SEARCH_DEPTH (default 5)
- SPEC_PATHS (default: list of `services/*/specs/openapi.yaml`, separated by `;`)

## Docs

Gateway serves merged OpenAPI:

- `GET /openapi.yaml`
- `GET /docs/`
