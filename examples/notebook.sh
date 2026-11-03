#!/usr/bin/env bash
# Open in Neovim and use :CurlRun inside one block, not bash notebook.sh.
# Requests use the public httpbin service by default; do not send real secrets.

ENV=httpbin
case "$ENV" in
  httpbin) BASE_URL=https://httpbin.org ;;
  local) BASE_URL=http://localhost:8000 ;;
  *) printf 'Unknown environment: %s\n' "$ENV" >&2; exit 1 ;;
esac

### GET with query parameters
curl --silent --show-error --max-time 20 \
  --get "$BASE_URL/get" \
  --data-urlencode 'search=hello notebook' \
  --data-urlencode "environment=$ENV"

### POST literal multiline JSON
curl --silent --show-error --max-time 20 \
  "$BASE_URL/post" \
  --header 'Content-Type: application/json' \
  --data '{
    "message": "Hello from a .sh notebook",
    "tags": ["curl", "neovim"],
    "literalVariable": "$ENV"
  }'

### POST interpolated JSON with a request-local ID
CUSTOMER_ID=48047
curl --silent --show-error --max-time 20 \
  "$BASE_URL/post" \
  --header 'Content-Type: application/json' \
  --data @- <<EOF
{
  "customerId": "$CUSTOMER_ID",
  "environment": "$ENV",
  "message": "Customer's request"
}
EOF

### HTTP error with headers and successful process status
curl --silent --show-error --max-time 20 \
  --include "$BASE_URL/status/404"

### HTTP error with a nonzero process status
curl --silent --show-error --max-time 20 \
  --fail-with-body "$BASE_URL/status/418"

### Slow response for testing CurlCancel
printf 'Waiting for the response; use :CurlCancel in the source buffer.\n' >&2
curl --silent --show-error --max-time 30 "$BASE_URL/delay/10"

### Transport failure with both output streams
printf 'This block intentionally connects to a closed local port.\n'
curl --silent --show-error --connect-timeout 2 --max-time 3 \
  http://127.0.0.1:1
