# Phân tích yêu cầu — vai Consumer (Analytics)

- Cặp đàm phán: **Pair-08: Core Business ↔ Analytics**
- Product: **Analytics**
- Consumer service: **Analytics**
- Provider service: **Core Business**
- Người viết: Pair-08 Consumer Team
- Ngày: 2026-05-14

---

## 1. Event Consumer cần nhận & xử lý

| Event Type                | Consumer dùng để làm gì?                    | Field bắt buộc                                                          | Field có thể tùy chọn             |
| ------------------------- | ------------------------------------------- | ----------------------------------------------------------------------- | --------------------------------- |
| `policy.decision.created` | Tính KPI quyết định/deny, thống kê truy cập | `eventId`, `decisionId`, `policyId`, `subjectId`, `result`, `timestamp` | `correlationId`, `metadata`       |
| `alert.created`           | Thống kê cảnh báo, phân tích xu hướng sự cố | `eventId`, `alertId`, `alertType`, `severity`, `timestamp`              | `relatedEventId`, `sourceService` |
| `alert.resolved`          | Tính MTTR (Mean Time To Resolution)         | `eventId`, `alertId`, `resolvedAt`                                      | `duration`, `reason`              |

---

## 2. Event Consumer cần lắng nghe

| Event                     | Topic/Queue                      | Lúc nào lắng nghe   | Kỳ vọng latency |
| ------------------------- | -------------------------------- | ------------------- | --------------- |
| `policy.decision.created` | `core-business/policy-decisions` | Realtime monitoring | < 5s            |
| `alert.created`           | `core-business/alerts`           | Realtime dashboard  | < 5s            |
| `alert.resolved`          | `core-business/alerts`           | Realtime dashboard  | < 5s            |

---

## 3. Error case Consumer cần xử lý

|              Status | Tình huống                         | Consumer xử lý thế nào?                 |
| ------------------: | ---------------------------------- | --------------------------------------- |
|             Timeout | Provider không gửi event trong 30s | Retry ngay, nếu fail lâu → alert ops    |
|      Malformed JSON | Event không đúng schema            | Log & discard, khỏi crash Consumer      |
| Authentication fail | API Key hết hạn/sai                | Refresh key, notify ops                 |
|   Duplicate eventId | Nhận cùng event 2 lần              | Check cache/DB, skip nếu đã xử lý       |
|  Out-of-order event | Alert resolve đến trước create     | Cache & reconcile sau, không xử lý ngay |
|  Unknown event type | Event type không nằm trong list    | Log warning & discard gracefully        |

---

## 4. Data Requirement Consumer cần

### Minimum Data để tính KPI:

- Policy Decision: `subjectId`, `result`, `timestamp` → tính % allow/deny/day
- Alert: `alertType`, `severity`, `timestamp` → tính alert distribution
- Alert Resolved: `alertId`, `resolvedAt` → tính MTTR, escalation time

### Ideal Data:

- `correlationId` → trace cross-service
- `reason` / message → analysis tại sao decision/alert
- `sourceService` → biết alert từ đâu

---

## 5. Giả định bổ sung

- **API Key Authentication:** Analytics sẽ register & nhận API Key từ Core Business
- **Delivery Guarantee:** At-Least-Once — Consumer phải handle duplicate
- **Processing:** Consumer sẽ batch write KPI metrics mỗi 1 phút
- **Retention:** Store event ≥ 30 ngày cho audit/replay
- **Ordering:** Alert events on same alertId phải xử lý theo thứ tự create → resolve
- **Idempotency Check:** Consumer store `eventId` → dedup
- **Failure Mode:** Nếu Consumer crashed, Provider lưu queue tối thiểu 24h
- **Monitoring:** Consumer report "last event received at" để Core Business kiểm tra health

---

## 5. Câu hỏi cho Provider

1. Provider có cam kết FIFO theo `alertId` và `subjectId` không?
2. Provider có gửi `eventSchemaVersion` cố định "1.0" và thông báo trước khi bump version không?
3. Provider có hỗ trợ replay event khi Consumer outage (retention tối thiểu 24h) không?

---

## 6. Rủi ro tích hợp

| Rủi ro                    | Tác động               | Đề xuất xử lý             |
| ------------------------- | ---------------------- | ------------------------- |
| Provider đổi kiểu dữ liệu | Consumer parse lỗi     | Chốt type/format/pattern  |
| Provider thiếu mã lỗi     | Consumer khó xử lý lỗi | Chuẩn hóa Problem Details |
