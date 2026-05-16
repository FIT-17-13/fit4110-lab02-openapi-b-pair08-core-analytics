#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4010}"
API_KEY_HEADER="X-API-Key: test-api-key"

echo "[Lab02] Testing Prism mock server at $BASE_URL"
echo

echo "[1/5] Happy path: GET /health"
curl -i "$BASE_URL/health"
echo "
---"

echo "[2/5] Happy path: POST /events/policy-decisions"
curl -i -X POST "$BASE_URL/events/policy-decisions" \
  -H "$API_KEY_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "policy.decision.created",
    "eventSchemaVersion": "1.0",
    "eventId": "550e8400-e29b-41d4-a716-446655440000",
    "decisionId": "650e8400-e29b-41d4-a716-446655440000",
    "policyId": "750e8400-e29b-41d4-a716-446655440000",
    "subjectId": "USER-2026-001",
    "result": "ALLOW",
    "reason": "Default access policy for workspace",
    "timestamp": "2026-05-14T10:30:00.123456Z",
    "correlationId": "850e8400-e29b-41d4-a716-446655440000"
  }'
echo "
---"

echo "[3/5] Happy path: POST /events/alerts"
curl -i -X POST "$BASE_URL/events/alerts" \
  -H "$API_KEY_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "alert.created",
    "eventSchemaVersion": "1.0",
    "eventId": "951e8400-e29b-41d4-a716-446655440000",
    "alertId": "a51e8400-e29b-41d4-a716-446655440000",
    "alertType": "UNAUTHORIZED_ACCESS",
    "severity": "HIGH",
    "message": "Unauthorized access attempt at Gate-01",
    "sourceService": "core-business",
    "timestamp": "2026-05-14T10:31:00.456789Z",
    "relatedEventId": "650e8400-e29b-41d4-a716-446655440000"
  }'
echo "
---"

echo "[4/5] Happy path: POST /events/alerts/resolved"
curl -i -X POST "$BASE_URL/events/alerts/resolved" \
  -H "$API_KEY_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "alert.resolved",
    "eventSchemaVersion": "1.0",
    "eventId": "b51e8400-e29b-41d4-a716-446655440000",
    "alertId": "a51e8400-e29b-41d4-a716-446655440000",
    "resolvedAt": "2026-05-14T10:35:00.789012Z",
    "reason": "Confirmed false positive - training badge",
    "duration": 300,
    "handledBy": "ADMIN-2026-001"
  }'
echo "
---"

echo "[5/5] Error case: POST /events invalid payload"
curl -i -X POST "$BASE_URL/events" \
  -H "$API_KEY_HEADER" \
  -H "Content-Type: application/json" \
  -d '{ "eventType": "alert.created" }'
echo
