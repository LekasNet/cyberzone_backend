#!/bin/sh
set -e

if [ -n "$TUNA_TOKEN" ]; then
  http_subdomain="${TUNA_HTTP_SUBDOMAIN:-cyberzone}"
  ws_subdomain="${TUNA_WS_SUBDOMAIN:-cyberzone-ws}"

  tuna http 8087 --subdomain="$http_subdomain" --token="$TUNA_TOKEN" &
  tuna http 8087 --subdomain="$ws_subdomain" --token="$TUNA_TOKEN" &
fi

exec dart run bin/api_gateway.dart
