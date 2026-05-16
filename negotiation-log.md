# Biên bản đàm phán hợp đồng API — Pair-08: Core Business ↔ Analytics

- **Cặp đàm phán:** Pair-08
- **Product A (Provider):** Core Business
- **Product B (Consumer):** Analytics
- **Provider Representative:** [Core Business Team]
- **Consumer Representative:** [Analytics Team]
- **Phiên:** v1.0
- **Ngày đàm phán:** 2026-05-14
- **Loại kết nối:** Queue Async (Policy Decision & Alert Events)

---

## Issue #1: Event Schema & Payload Structure

**Raised by:** Consumer (Analytics)  
**Endpoint/Event:** `policy.decision.created`, `alert.created`, `alert.resolved`

**Concern:**

- Analytics cần biết rõ các field bắt buộc vs tùy chọn
- Cần uniform timestamp format để so sánh KPI
- Cần correlationId để trace request cross-service

**Proposal:**

- ✅ `eventId` (UUID) — bắt buộc, unique toàn cầu
- ✅ `timestamp` — bắt buộc, RFC3339 format (UTC, microsecond)
- ✅ `correlationId` — tùy chọn, kế thừa từ origin request

**Resolution:** **Accepted**

**Rationale:**

- RFC3339 là standard HTTP header date format
- Unique eventId giúp dedup & idempotency
- Correlation ID giúp debugging cross-service

**Impact:**

- Core Business: Thêm logic generate UUID v4 & timestamp
- Analytics: Parse & store timestamp, dedup by eventId

**Sign-off:**

- Provider: ✅ Approved
- Consumer: ✅ Approved

---

## Issue #2: Authentication & Authorization

**Raised by:** Provider (Core Business)  
**Endpoint/Event:** Tất cả events

**Concern:**

- Cần xác thực Analytics là service hợp lệ
- Cần trace/audit ai gửi event
- Provider không muốn event public exposure

**Proposal:**

- ✅ API Key authentication: header `X-API-Key: <key>`
- ✅ Mỗi Consumer nhận unique API Key từ Provider
- ✅ Provider log mỗi event + API Key tương ứng

**Resolution:** **Accepted**

**Rationale:**

- API Key đơn giản, phù hợp queue async
- Không cần JWT overhead cho internal service
- Dễ revoke/rotate API Key nếu có breach

**Impact:**

- Core Business: Cấp API Key cho Analytics, xác thực header
- Analytics: Inject API Key vào connection string

**Sign-off:**

- Provider: ✅ Approved
- Consumer: ✅ Approved

---

## Issue #3: Duplicate Event Handling & Idempotency

**Raised by:** Consumer (Analytics)  
**Endpoint/Event:** Tất cả events

**Concern:**

- Queue có thể deliver event 2 lần (At-Least-Once)
- Analytics không muốn KPI bị double-count
- Cần rõ ràng who handle dedup

**Proposal:**

- ✅ **Provider guarantee:** eventId duy nhất, không bao giờ reuse
- ✅ **Consumer responsibility:** cache eventId 30 ngày, check trước insert
- ✅ Nếu duplicate → log warning, skip processing

**Resolution:** **Accepted**

**Rationale:**

- At-Least-Once delivery yêu cầu consumer handle dedup
- Cache eventId 30 ngày match data retention requirement
- Provider không cần retry logic phức tạp

**Impact:**

- Core Business: Đảm bảo eventId = UUID v4 (never repeat)
- Analytics: Add dedup logic, maintain eventId cache

**Sign-off:**

- Provider: ✅ Approved
- Consumer: ✅ Approved

---

## Issue #4: Event Ordering & Out-of-Order Handling

**Raised by:** Provider (Core Business)  
**Endpoint/Event:** `alert.created` + `alert.resolved`

**Concern:**

- Alert resolve event có thể đến trước create event (network delay)
- Analytics không thể tính MTTR nếu out-of-order
- Cần chiến lược reconcile

**Proposal:**

- ✅ **Provider guarantee:** Alert events on same alertId deliver in order (FIFO per partition)
- ✅ **Consumer strategy:** Cache unmatched `alert.resolved` tối đa 5 phút, reconcile lúc alert.created đến
- ✅ Nếu alert.resolved không match sau 5 phút → log error (orphaned resolve event)

**Resolution:** **Accepted**

**Rationale:**

- FIFO per alertId đảm bảo causality cho events cùng resource
- 5 phút buffer đủ cho network delay trong LAN
- Orphaned event report giúp debug inconsistency

**Impact:**

- Core Business: Partition events by alertId để maintain FIFO
- Analytics: Implement out-of-order buffer + reconciliation logic

**Sign-off:**

- Provider: ✅ Approved
- Consumer: ✅ Approved

---

## Issue #5: Retry Policy & Failure Mode

**Raised by:** Provider (Core Business)  
**Endpoint/Event:** Tất cả events

**Concern:**

- Analytics có thể offline (maintenance, crash)
- Cần rõ: Provider giữ event bao lâu?
- Làm sao Consumer biết đã miss sự kiện?

**Proposal:**

- ✅ **Retry Policy:** Exponential backoff 5s → 30s → 300s, max 3 attempts
- ✅ **Retention:** Provider lưu queue tối thiểu **24 giờ**
- ✅ **Health Check:** Analytics phải heartbeat tối thiểu 6 giờ/lần, nếu không → alert ops

**Resolution:** **Accepted**

**Rationale:**

- Exponential backoff tránh overwhelming destination
- 24h retention cho phép Consumer recover từ outage
- Heartbeat giúp detect dead Consumer

**Impact:**

- Core Business: Implement retry mechanism, queue persistence 24h, monitor heartbeat
- Analytics: Send heartbeat signal, implement replay capability

**Sign-off:**

- Provider: ✅ Approved
- Consumer: ✅ Approved

---

## Issue #6: Rate Limit & Backpressure

**Raised by:** Consumer (Analytics)  
**Endpoint/Event:** `policy.decision.created`, `alert.created`

**Concern:**

- Trong peak hours, Core Business tạo hàng ngàn events/phút
- Analytics cần biết ngưỡng để plan infrastructure
- Cần backpressure mechanism nếu Consumer lag

**Proposal:**

- ✅ **Rate Limit:** Tối đa 5000 events/phút per Consumer
- ✅ **Queue Depth Monitoring:** Nếu queue > 100k events → Core Business slow down (log warning)
- ✅ **Consumer Capacity Planning:** Analytics ensure xử lý tối thiểu 5000 e/min + 20% buffer

**Resolution:** **Accepted**

**Rationale:**

- 5000 e/min = ~83 e/sec, reasonable cho typical policy + alert volume
- 100k backlog threshold cho warning trước khi system overwhelm
- 20% buffer anticipate peak + retries

**Impact:**

- Core Business: Monitor queue depth, graceful degradation nếu overload
- Analytics: Capacity test, horizontal scaling strategy

**Sign-off:**

- Provider: ✅ Approved
- Consumer: ✅ Approved

---

## Issue #7: Event Type Versioning & Backward Compatibility

**Raised by:** Consumer (Analytics)  
**Endpoint/Event:** Tất cả events

**Concern:**

- Lab 02 định nghĩa event type & schema
- Nếu sau này Core Business cần thêm field → có phát sinh conflict?
- Cần chiến lược versioning

**Proposal:**

- ✅ **Versioning Scheme:** Events có `eventSchemaVersion: "1.0"`
- ✅ **Backward Compatibility:** Core Business chỉ thêm **optional** field
- ✅ **Consumer Resilience:** Ignore unknown fields, xử lý gracefully nếu missing optional
- ✅ **Breaking Change:** Nếu cần remove/rename field → phải tạo `eventSchemaVersion: "2.0"`

**Resolution:** **Accepted**

**Rationale:**

- Schema versioning giúp track evolution
- Optional-only additions không break existing Consumer
- Explicit version bump cho breaking changes

**Impact:**

- Core Business: Add `eventSchemaVersion` field, document schema evolution
- Analytics: Handle version check, support multiple versions tối thiểu 1 release

**Sign-off:**

- Provider: ✅ Approved
- Consumer: ✅ Approved

---

## Summary of Decisions

| Issue | Topic           | Decision                                                   |
| ----- | --------------- | ---------------------------------------------------------- |
| #1    | Event Schema    | RFC3339 timestamp, UUID eventId, optional correlationId ✅ |
| #2    | Authentication  | API Key header (X-API-Key) ✅                              |
| #3    | Dedup           | Provider unique eventId, Consumer cache 30d ✅             |
| #4    | Ordering        | FIFO per alertId, 5min out-of-order buffer ✅              |
| #5    | Retry/Retention | Exponential backoff, 24h queue retention, heartbeat ✅     |
| #6    | Rate Limit      | 5000 e/min, 100k queue depth threshold ✅                  |
| #7    | Versioning      | eventSchemaVersion field, backward-compatible additions ✅ |

---

## Next Steps (Lab 03 & Beyond)

- [ ] Implement AsyncAPI 3.0 spec với event schema chi tiết
- [ ] Implement event replay mechanism (từ K8s PVC hoặc S3)
- [ ] Metrics dashboard: event lag, dedup count, orphaned events
- [ ] Load test: sustain 5000+ e/min
- [ ] Circuit breaker pattern: if Analytics lag > 10min → alert + slow down Core Business

---

## Appendix: Event Payload Examples

### policy.decision.created

```json
{
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
}
```

### alert.created

```json
{
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
}
```

### alert.resolved

```json
{
  "eventType": "alert.resolved",
  "eventSchemaVersion": "1.0",
  "eventId": "b51e8400-e29b-41d4-a716-446655440000",
  "alertId": "a51e8400-e29b-41d4-a716-446655440000",
  "resolvedAt": "2026-05-14T10:35:00.789012Z",
  "reason": "Confirmed false positive - training badge",
  "duration": 300,
  "handledBy": "ADMIN-2026-001"
}
```

# Chốt hợp đồng v1.0

Provider sign-off: Core Business Team  
Consumer sign-off: Analytics Team  
Witness (GV/TA): N/A  
Date: 2026-05-14

---

## Ghi chú warning nếu Spectral còn cảnh báo

| Warning | Lý do chấp nhận tạm thời | Kế hoạch sửa |
| ------- | ------------------------ | ------------ |
| None    | N/A                      | N/A          |
