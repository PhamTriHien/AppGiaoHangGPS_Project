# GO-MAU Delivery (`gps_delivery_app`)

Ứng dụng giao hàng và thương mại đa cửa hàng Flutter gồm bốn phân hệ trên nền Cloud: khách hàng, tài xế, cửa hàng (kèm nhân sự ủy quyền `manager`/`staff`) và quản trị viên (`operator`). Khi khởi động, ứng dụng mặc định khởi tạo kết nối Supabase tới dự án đã cấu hình; dữ liệu SQLite/localStorage cũ vẫn được bảo toàn biệt lập tại `/legacy` và `/legacy-admin`, không tự động chuyển tài khoản hay đơn hàng local lên Cloud.

> 📖 **Tài liệu đầy đủ về kiến trúc, sơ đồ hệ thống, thuật toán và toàn bộ tính năng**: Xem tại [`../README.md`](../README.md) ở thư mục gốc của kho lưu trữ.

---

## 1. Khởi chạy nhanh & Định tuyến

- Kế hoạch thương mại hóa: [COMMERCIALIZATION_PLAN.md](COMMERCIALIZATION_PLAN.md)
- Tiến độ & cổng nghiệm thu triển khai: [EXECUTION_CHECKLIST.md](EXECUTION_CHECKLIST.md)
- Ma trận dữ liệu Cloud / Legacy: [P0_SYNC_MATRIX.md](P0_SYNC_MATRIX.md)

```powershell
# 1. Khởi chạy backend tại gps_delivery_app/backend/otp-relay
cd backend/otp-relay
npm ci
npm start

# 2. Chạy hoặc build ứng dụng Flutter tại gps_delivery_app
cd ../..
flutter pub get
flutter build web --no-wasm-dry-run --no-web-resources-cdn `
  --dart-define=DELIVERY_API_BASE_URL=http://127.0.0.1:8787/delivery/
```

- **Cổng Người dùng chính (`/` và `/#/cloud`)**: Dùng `MarketplaceScreen` + `GhstUserShell` với đăng nhập **Supabase Auth** (Email/Mật khẩu & Google OAuth PKCE). Cùng một khung giao diện hiển thị thêm mục công việc khi tài khoản được duyệt quyền Chủ shop, Nhân sự shop hoặc Tài xế.
- **Cổng Quản trị Cloud Operator (`/admin` hoặc `/#/admin`)**: Tách biệt hoàn toàn khỏi giao diện người tiêu dùng, yêu cầu tài khoản Supabase có quyền `operator` xác minh từ `delivery_api_profiles`.
- **Tra cứu & Chia sẻ hành trình công khai (`/track` và `/share`)**: Tra cứu vận đơn Cloud qua `POST /delivery/tracking/lookup` (mã đơn + 4 số cuối SĐT người nhận hoặc mã chia sẻ 64-hex) và xem tiến độ đơn mua qua token 256-bit băm `SHA-256`, không đọc `AppStateStore` local.
- **Lưu trữ cục bộ cũ (`/legacy` và `/legacy-admin`)**: Bảo toàn nguyên vẹn dữ liệu SQLite/localStorage cũ mà không gắn danh tính local vào phiên Cloud.

Supabase ưu tiên cặp URL/public key hợp lệ đã lưu trên thiết bị, sau đó đến `--dart-define=SUPABASE_URL=...` / `--dart-define=SUPABASE_ANON_KEY=...`, cuối cùng là cấu hình công khai mặc định tại `lib/core/config/default_cloud_connection.dart`. `DATABASE_URL`, khóa `payOS`/`GHN`/`GOOGLE_MAPS_API_KEY` và service-role key chỉ được lưu ở phía backend.

---

## 2. Đặt đơn trên Bản đồ, Thương mại Cloud & Lưu trữ Local

### Chọn & tìm kiếm địa chỉ trực tiếp trên bản đồ (`CloudOrderForm`)
- Form **Tạo đơn hàng mới** nhúng trực tiếp bản đồ tương tác (`Map3dPerspectiveWidget`) cho phép chạm để ghim điểm lấy `[A]`, điểm giao `[B]` và các điểm dừng trung gian (`#1..#5`) kèm dịch ngược tên đường tự động (`/delivery/reverse`), nút `Vị trí hiện tại (GPS)`, hoặc gõ tìm kiếm địa chỉ trực tiếp (`/delivery/places`) và xem trước lộ trình `[A] -> [B]`.
- Toàn bộ ô nhập tọa độ thủ công (`Vĩ độ`, `Kinh độ`) đã được gỡ bỏ khỏi form Tạo đơn hàng. Nếu người dùng gõ địa chỉ rồi bấm lấy báo giá mà chưa chạm ghim, ứng dụng tự phân giải tọa độ qua `/delivery/places` và từ chối báo giá nếu chưa xác định được vị trí hợp lệ.
- **Sổ địa chỉ Cloud (`CloudAddressBookScreen`)** lưu tối đa 25 địa chỉ mỗi tài khoản có kiểm tra `version` và giữ một địa chỉ mặc định; form tạo đơn hỗ trợ chọn nhanh địa chỉ đã lưu.

### Đồng bộ Schema Cloud (`workflowVersion: 13`)
- Toàn bộ 12 migration bổ sung trong `database/migrations/` (đến `20261107_cloud_commercial_suite.sql`, `workflowVersion: 13`, `schema_version: 3`) bao phủ: 5 chế độ giao hàng Cloud (`standard`, `express`, `saving`, `same_day_2h`, `truck`), đa điểm dừng, khứ hồi, khai giá bảo hiểm, EV/Quỹ Xanh, cổng bắt buộc POD + OTP 6 số người nhận (`delivery_cloud_order_otp`), catalog đa biến thể SKU, phân quyền nhân sự shop, checkout COD/trả trước nhiều shop, tách kiện hàng (`delivery_market_shipments`), đính kèm bằng chứng riêng tư (`delivery-private-evidence`), đối soát bút toán kép, Voucher ngân sách, Flash Sale và Ví Xu server.
- Không chạy đè tệp legacy `database/schema.sql` lên dự án Supabase đang vận hành; chỉ áp dụng chuỗi migration bổ sung qua `npm run migrate:cloud` hoặc mục **Sẵn sàng triển khai** trong `/admin`.

### Phạm vi hàng đợi Offline SQLite v9 & Nhập CSV local (`/legacy`)
- SQLite `v9` bổ sung `owner_scope` (URL dự án, ID Supabase Auth và ID tài khoản local) cho hàng đợi đồng bộ, không tự gán bản ghi cũ chưa định danh cho người đăng nhập tiếp theo và dừng gửi ngay khi đổi phiên.
- Chức năng nhập đơn hàng loạt bằng tệp CSV chuẩn RFC-4180 tại `/legacy` dùng chung bộ kiểm tra preview/lưu (4, 7, 8 hoặc 12 cột), chỉ tạo đơn trong lưu trữ local và không tự tải lên Cloud.

---

## 3. Tích hợp API & Dịch vụ phụ trợ

Chi tiết cấu hình từng dịch vụ nằm tại [`backend/otp-relay/INTEGRATIONS.md`](backend/otp-relay/INTEGRATIONS.md), [`CLOUD_ORDERS.md`](backend/otp-relay/CLOUD_ORDERS.md), [`COMMERCE.md`](backend/otp-relay/COMMERCE.md) và [`MARKETPLACE.md`](backend/otp-relay/MARKETPLACE.md):
- **Tra cứu địa chỉ & Dịch ngược tọa độ (`/delivery/places`, `/delivery/reverse`)**: Mặc định sử dụng OpenStreetMap / Photon có chuẩn hóa khu vực Việt Nam và giới hạn tốc độ; tùy chọn bật `google_maps` (`GOOGLE_MAPS_ENABLED`, `GOOGLE_MAPS_API_KEY`) ở phía backend để ủy quyền qua Google Places API (New) và Geocoding API mà không lộ khóa ra client (lưu ý kiểm tra điều khoản lãnh thổ của Google Maps Platform trước khi bật thương mại).
- **Định tuyến đường bộ, Ngân hàng & Thời tiết**: OSRM (`/delivery/route`, `/delivery/matrix`), danh mục ngân hàng chuyển khoản VietQR (`GET /delivery/banks`, cache 24 giờ) và dự báo thời tiết MET Norway (`GET /delivery/weather`, làm tròn tọa độ theo khu vực, ghi nguồn CC BY 4.0).
- **Dịch vụ nâng cao tùy chọn**: OCR nhãn vận đơn, VROOM đề xuất phân tuyến, Cloudflare Turnstile, Gemini tóm tắt hỗ trợ có che thông tin nhạy cảm, Telegram cảnh báo nội bộ, Firebase FCM, `payOS` và `GHN`. Các dịch vụ chưa cấu hình khóa luôn hiển thị rõ trạng thái chưa cấu hình, tuyệt đối không trả kết quả giả lập.

---

## 4. Kiểm tra chất lượng mã nguồn

Dữ liệu mẫu kiểm thử nằm riêng trong `test/fixtures/`, không bao giờ được nạp khi chạy ứng dụng.

```powershell
# Phân tích tĩnh & kiểm thử đơn vị / giao diện Flutter
flutter analyze --no-pub
flutter test --no-pub

# Kiểm thử API công cộng trực tuyến (tùy chọn khi có mạng)
flutter test test/free_api_live_test.dart --dart-define=RUN_LIVE_API_TESTS=true

# Kiểm thử trình duyệt hồi quy (Playwright + Edge trên bản build/web)
node tool/check-cloud-browser.cjs
node tool/check-marketplace-browser.cjs
node tool/check-admin-browser.cjs
node tool/check-full-ui-acceptance.cjs
```
