# Integration Tests

This tool runs cross-service checks for the Cyberzone backend. It assumes all services are running.

## Run

```bash
dart pub get
dart run bin/run.dart
```

## Run via gateway

```bash
dart pub get
dart run bin/run_gateway.dart
```

## WebSocket chat scenario

```bash
dart pub get
dart run bin/run_ws_chat.dart
```

## Report

HTML report is saved to `backend/test_logs/` with collapsible sections per service and per request.
Override with `REPORT_DIR` if needed.

## Environment

- AUTH_URL (default http://localhost:8080)
- USER_URL (default http://localhost:8081)
- SCHEDULE_URL (default http://localhost:8082)
- EVENT_URL (default http://localhost:8083)
- RATING_URL (default http://localhost:8084)
- CHAT_URL (default http://localhost:8085)
- NOTIFICATION_URL (default http://localhost:8086)
- INTERNAL_API_KEY (default dev_internal_key)
- GATEWAY_URL (default http://localhost:8087) for `bin/run_gateway.dart`

Note: `bin/run_gateway.dart` still calls `/internal/events/*` directly via
`EVENT_URL`, because gateway blocks `/internal/*` routes.

User DB connection (used to promote a test user to superadmin):
- USER_DB_HOST (default localhost)
- USER_DB_PORT (default 5432)
- USER_DB_NAME (default cyberzone_user)
- USER_DB_USER (default cyberzone)
- USER_DB_PASSWORD (default password)

The script will:
1) Check /health for each service.
2) Register an admin user and promote to superadmin in the user DB.
3) Register a regular user.
4) Create an event, set cast, approve with chat creation.
5) Send a chat message and fetch messages.
6) Finish event and post ratings.
7) Verify rating summary and minRating filters.
8) Create availability and search with minRating.
9) Register and unregister a notification token.
