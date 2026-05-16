# Phân tích yêu cầu — vai Provider (Core Business)

- Cặp đàm phán: **Pair-08: Core Business ↔ Analytics**
- Product: **Core Business**
- Provider service: **Core Business**
- Consumer service: **Analytics**
- Người viết: Pair-08 Provider Team
- Ngày: 2026-05-14

---

## 1. Event chính Provider phát hành

| Event Type                | Mô tả                                    | Payload bắt buộc                                                                       | Payload tùy chọn             |
| ------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------- |
| `policy.decision.created` | Khi có quyết định truy cập mới từ policy | `eventId`, `decisionId`, `policyId`, `subjectId`, `result`, `reason`, `timestamp`      | `correlationId`, `metadata`  |
| `alert.created`           | Khi phát hiện sự cố/cảnh báo             | `eventId`, `alertId`, `alertType`, `severity`, `message`, `sourceService`, `timestamp` | `relatedEventId`, `metadata` |
| `alert.resolved`          | Khi xử lý xong cảnh báo                  | `eventId`, `alertId`, `resolvedAt`, `reason`                                           | `duration`, `handledBy`      |

---

## 2. Endpoint / Message Queue Pattern

**Queue async (Lab 02 chưa yêu cầu AsyncAPI đầy đủ, chỉ thỏa thuận event schema)**

| Event                     | Queue/Topic                      | Delivery      | Consumer nhận khi nào?         |
| ------------------------- | -------------------------------- | ------------- | ------------------------------ |
| `policy.decision.created` | `core-business/policy-decisions` | At-Least-Once | Ngay khi policy quyết định     |
| `alert.created`           | `core-business/alerts`           | At-Least-Once | Khi event sensor/access fail   |
| `alert.resolved`          | `core-business/alerts`           | At-Least-Once | Khi admin/system resolve alert |

---

## 3. Event Schema Dự Kiến

### Policy Decision Event

```json
{
  "eventType": "policy.decision.created",
  "eventId": "uuid",
  "decisionId": "uuid",
  "policyId": "uuid",
  "subjectId": "string (user/device)",
  "result": "ALLOW | DENY | DEFER",
  "reason": "string (policy rule name)",
  "timestamp": "RFC3339",
  "correlationId": "uuid | null"
}
```

### Alert Events

```json
{
  "eventType": "alert.created",
  "eventId": "uuid",
  "alertId": "uuid",
  "alertType": "UNAUTHORIZED_ACCESS | SENSOR_THRESHOLD | UNKNOWN_PERSON | SYSTEM_ERROR",
  "severity": "LOW | MEDIUM | HIGH | CRITICAL",
  "message": "string",
  "sourceService": "core-business",
  "timestamp": "RFC3339",
  "relatedEventId": "uuid | null"
}
```

---

## 4. Error / Edge Case Provider cần xử lý

| Sự cố              | Cách xử lý                                                   | Impact                          |
| ------------------ | ------------------------------------------------------------ | ------------------------------- |
| Consumer offline   | Ghi vào retry queue, retry sau 5/30/300s                     | Event có thể delay tới 10 phút  |
| Payload sai schema | Ghi log, discard event                                       | Consumer mất thông tin          |
| Trùng eventId      | Provider giả định eventId unique, nhưng Consumer phải handle | Xử lý lặp ở Consumer            |
| Event out-of-order | OK — Alert resolve có thể đến trước create                   | Consumer phải cache & reconcile |
| Network timeout    | Timeout 30s, retry tối đa 3 lần                              | Event queue có thể backed up    |

---

## 5. Giả định bổ sung

- **Authentication:** Cấp API Key cho Analytics, ghi vào header `X-API-Key`
- **Idempotency:** `eventId` là UUID v4, unique toàn cầu
- **Ordering:** Alert events on same `alertId` phải đến theo thứ tự (create → resolve)
- **Timestamp:** UTC RFC3339 format, microsecond precision
- **Retry Policy:** Exponential backoff 5s → 30s → 300s, max 3 lần
- **Rate Limit:** Tối đa 5000 event/phút per Consumer
- **SLA:** 99.5% event delivery dalam 5 phút
- **Payload size:** Tối đa 256 KB mỗi event để tránh timeout.

---

## 5. Câu hỏi cho Consumer

1. Analytics có chấp nhận `correlationId` là optional (có thể null) cho mọi event không?
2. Analytics có cần hỗ trợ batch (nhiều event trong 1 request) hay chỉ 1 event/request?
3. Analytics có yêu cầu chuẩn hóa cấu trúc `metadata` hay chấp nhận schema mở?

---

## 6. Rủi ro tích hợp

| Rủi ro                     | Tác động           | Đề xuất xử lý                         |
| -------------------------- | ------------------ | ------------------------------------- |
| Tên field không thống nhất | Consumer parse lỗi | Chốt naming trong `openapi.yaml`      |
| Payload lớn                | Timeout/mock lỗi   | Thống nhất content-type và size limit |
