#!/usr/bin/env bash
# Use :CurlRun to execute one block; running this file directly executes every request.

ENV=local
case "$ENV" in
  local) APPLICATIONS_URL=http://localhost:8099/api/v1/applications ;;
  dev) APPLICATIONS_URL=https://dev.example.invalid/api/v1/applications ;;
  *) printf 'Unknown environment: %s\n' "$ENV" >&2; exit 1 ;;
esac

### Read application
APPLICATION_ID=48047
curl "$APPLICATIONS_URL/$APPLICATION_ID" \
  --header 'X-Cache-Bypass: true'

### Create application
curl --request POST "$APPLICATIONS_URL" \
  --header 'Content-Type: application/json' \
  --data '{
    "requestType": "lease-bav",
    "name": "Example application"
  }'

### Update application with interpolated payload
APPLICATION_ID=48047
curl --request PATCH "$APPLICATIONS_URL/$APPLICATION_ID" \
  --header 'Content-Type: application/json' --data @- <<EOF
{
  "applicationId": "$APPLICATION_ID",
  "name": "Customer's application"
}
EOF
