# GO-MAU Delivery (`gps_delivery_app`)

Ứng dụng giao hàng Flutter gồm bốn phân hệ: khách hàng, tài xế, cửa hàng và quản trị viên. Khi khởi động, ứng dụng mặc định khởi tạo kết nối Supabase tới dự án `yvnbfurazjbhbopahtmx`. SQLite/localStorage vẫn lưu dữ liệu thiết bị hiện có; cấu hình kết nối không tự chuyển tài khoản và đơn local lên cloud.

> 📖 **Tài liệu đầy đủ về kiến trúc, sơ đồ hệ thống, thuật toán và toàn bộ tính năng**: Xem tại [`../README.md`](../README.md) ở thư mục gốc của kho lưu trữ.

---

## 1. Khởi chạy nhanh

Kế hoạch thương mại hóa: [COMMERCIALIZATION_PLAN.md](COMMERCIALIZATION_PLAN.md).
Ma trận local/cloud và tiến độ P0: [P0_SYNC_MATRIX.md](P0_SYNC_MATRIX.md).

Sổ địa chỉ cloud nằm ở biểu tượng **Sổ địa chỉ** trong màn hình đơn hàng cloud;
form tạo đơn có bộ chọn địa chỉ lấy/giao đã lưu. Lưu tối đa 25 địa chỉ mỗi tài khoản,
kiểm tra phiên bản khi sửa/xóa và giữ một địa chỉ mặc định. Backend cần migration
`20261029_cloud_addresses.sql`; `npm run migrate:cloud` đã gồm migration này.
Nhập tọa độ chỉ kiểm tra giới hạn địa lý, không chứng minh địa chỉ khớp thực địa.

```powershell
flutter pub get
flutter run -d chrome --web-port=8080
```

- **Cổng Người dùng (Khách hàng / Tài xế / Cửa hàng B2B)**: `http://localhost:8080/`
- **Cổng Quản trị viên độc lập (Admin CMS)**: `http://localhost:8080/admin` (hoặc `http://localhost:8080/#/admin`)
  - Khi hệ thống chưa có quản trị viên nào, cổng `/admin` sẽ hiển thị màn hình **Thiết lập quản trị viên đầu tiên**. Không sử dụng tài khoản hay mật khẩu dùng chung mặc định.

Supabase ưu tiên cặp URL/public key đã lưu trên thiết bị, sau đó cặp `--dart-define=SUPABASE_URL=...` và `--dart-define=SUPABASE_ANON_KEY=...`, cuối cùng là cấu hình công khai tại `lib/core/config/default_cloud_connection.dart`. Cấu hình thiếu một nửa hoặc chứa server secret bị từ chối; không ghép URL của dự án này với key của dự án khác. Không cần nhập lại kết nối mặc định cho bản cài mới. `DATABASE_URL` và service-role key chỉ được lưu tại backend.

Google OAuth và gửi OTP cần cấu hình nhà cung cấp tương ứng; luồng đăng nhập chính hiện vẫn xác thực tài khoản đã tạo trên thiết bị. Tài khoản Supabase Auth là danh tính riêng, không tự được tạo từ SQLite hoặc suy ra mật khẩu từ bản hash local. Bản Web gửi Email OTP qua HTTP relay; Gmail App Password lưu tại backend. Web dùng phiên Supabase để xác thực với backend từ xa, không nhúng relay token vào bản build.

## 2. Điểm nhấn tính năng trong phiên bản hiện tại

Các tích hợp nâng cao gồm OCR nhãn vận đơn, Photon tra cứu địa chỉ, Realtime theo
từng đơn, ảnh giao hàng riêng tư, FCM, VROOM xem phương án phân tuyến, Turnstile,
Gemini hỗ trợ khiếu nại và Telegram cảnh báo nội bộ. Dịch vụ chưa có khóa hoặc
chưa chạy được hiển thị là chưa cấu hình; không thay bằng dữ liệu demo. Hướng dẫn
cấu hình và migration nằm tại `backend/otp-relay/INTEGRATIONS.md`.

Các chức năng mới của Nhân được hợp nhất với backend/API và cấu hình cloud hiện có:
giao 2H, đa điểm, khứ hồi, xe điện, thực đơn B2B, khuyến mãi và tra cứu vận đơn.
Menu gợi ý lấy từ dữ liệu cửa hàng, không tự chèn danh mục quán mẫu.
GrabFood dùng màn hình 13, đơn nháp dùng màn hình 14.

SQLite v8 lưu các trường nghiệp vụ mới và giữ dữ liệu khi nâng cấp. Các trường
này có mapping PostGIS trong datasource legacy, nhưng chưa được đồng nhất với
RPC `delivery_cloud_*`. Không chạy toàn bộ `database/schema.sql` lên database
đang vận hành để thay cho migration. Backend cloud vẫn dùng ba migration tại
`database/migrations/`, kiểm tra quyền và phiên Supabase riêng. Tài khoản local,
thưởng khuyến mãi local và đơn tạo từ màn hình legacy chưa tự chuyển lên cloud.

---

## 3. Cấu hình Tùy chọn (Cloud PostGIS & OTP Relay)

- **Supabase PostGIS**: Truyền qua `--dart-define=SUPABASE_URL=...` và `--dart-define=SUPABASE_ANON_KEY=...` (hoặc cấu hình nóng ngay trong cổng Quản trị viên).
- **Email OTP cho bản Web**: Chạy dịch vụ phụ trợ tại [`backend/otp-relay`](backend/otp-relay/README.md) để bảo vệ `SMTP_PASS` ở phía máy chủ, sau đó truyền `--dart-define=OTP_EMAIL_WEBHOOK_URL=http://127.0.0.1:8787/otp-email` và `--dart-define=OTP_EMAIL_WEBHOOK_TOKEN=...`.

---

## 4. Kiểm tra chất lượng mã nguồn

Dữ liệu mẫu kiểm thử nằm riêng tại test/fixtures/app_state_test_fixtures.dart, không được nạp khi chạy ứng dụng. Không xóa toàn bộ CSDL để làm sạch demo.

## Kiểm tra

### API công cộng đã tích hợp

- MET Norway Locationforecast: dự báo nhiệt độ, gió, mưa giờ tới tại khu vực lấy/giao hàng. Hiển thị trên màn hình tạo đơn và chuyến đi của tài xế khi có tọa độ thật. Ghi rõ thời điểm dự báo và nguồn CC BY 4.0; không tự thay đổi cước phí theo thời tiết.
- VietQR `GET /v2/banks`: bộ chọn ngân hàng có tìm kiếm tại hồ sơ tài xế/cửa hàng. Danh sách lấy từ API, cache 24 giờ, chỉ giữ ngân hàng hỗ trợ chuyển khoản. Không xác minh chủ tài khoản, xác nhận thanh toán hay chuyển tiền.
- OSRM Table: quản trị vào Đội xe, chọn đơn đang tìm tài xế, bấm biểu tượng so sánh đường bộ. Chỉ dùng tài xế rảnh, đã duyệt, đủ ký quỹ, phù hợp phương tiện và có GPS đã xác minh. So sánh tối đa 10 ứng viên gần nhất bằng ma trận đường bộ; kết quả có thể khác thứ tự khoảng cách thẳng. Đây là mô hình đường ô tô, không có dữ liệu giao thông trực tiếp hay cam kết ETA xe máy.

Ba tích hợp này không cần API key, tài khoản mới hoặc thông tin thẻ. HTTP client có timeout 10 giây, gộp yêu cầu đồng thời, cache, tuân thủ `Expires`, `Last-Modified`/304 và `Retry-After` khi HTTP 429. Tọa độ thời tiết được làm tròn theo khu vực, không gửi GPS chính xác. Lỗi mạng hoặc dữ liệu sai hiển thị trạng thái chưa có dữ liệu; không thêm dữ liệu mẫu vào app.

Trên máy local, chạy `npm run configure:desktop` tại `backend/otp-relay` để lưu `deliveryApiBaseUrl` cùng token relay vào cấu hình ngoài thư mục build (giữ nguyên Google OAuth). Khởi động backend bằng `npm start`. App gọi `GET /delivery/weather?lat=...&lon=...` có Bearer token; backend truy vấn MET Norway bằng Node với xác minh TLS đầy đủ và cache dùng chung. Cách này xử lý trường hợp chuỗi chứng chỉ của MET Norway chưa được Dart trên Windows tin cậy. Khi không cấu hình proxy, app gọi MET Norway trực tiếp. Bản web có thể đặt `--dart-define=DELIVERY_API_BASE_URL=https://your-backend/delivery/` cùng token relay và Origin trong allowlist; dùng HTTPS khi triển khai ngoài máy local.

Nguồn và giới hạn sử dụng: [MET Norway Terms](https://api.met.no/doc/TermsOfService), [VietQR Banks](https://www.vietqr.io/danh-sach-api/api-danh-sach-ma-ngan-hang), [OSRM API](https://github.com/Project-OSRM/osrm-backend/blob/master/docs/http.md). OSRM mặc định là máy chủ demo công cộng, không có SLA và không phù hợp tải sản xuất lớn; có thể chuyển sang máy chủ tự vận hành bằng `--dart-define=OSRM_TABLE_ENDPOINT=https://your-router/table/v1/driving`. Dữ liệu đường bộ ghi nguồn OpenStreetMap. Nominatim cũ chỉ dành cho thao tác tra cứu trực tiếp, không dùng làm autocomplete; theo [chính sách Nominatim](https://operations.osmfoundation.org/policies/nominatim/), dịch vụ theo dõi vận chuyển thương mại cần nhà cung cấp hoặc instance riêng.

Kiểm tra API thật riêng, cần kết nối mạng:

~~~sh
flutter test test/free_api_live_test.dart --dart-define=RUN_LIVE_API_TESTS=true
~~~

~~~sh
flutter analyze
flutter test --concurrency=1
flutter build web
~~~

Test clean_start_test.dart kiểm tra khởi tạo sạch, màn hình thiết lập quản trị viên, hồ sơ mới không có dữ liệu giả, GPS và migration giữ dữ liệu thật kể cả khi trùng mã với mẫu cũ. Test widget_test.dart kiểm tra nghiệp vụ và giao diện nhiều kích thước bằng fixtures riêng.

### Phạm vi đồng bộ tài khoản

SQLite v9 bổ sung `owner_scope` cho hàng đợi, gồm URL dự án, ID Supabase Auth và ID tài khoản local. Chỉ phát lại khi phiên cloud còn đăng nhập và email hoặc số điện thoại khớp tài khoản local. Bản ghi cũ không có chủ sở hữu vẫn được giữ trên máy, không tự gán cho người đăng nhập tiếp theo. Bộ gửi dừng khi đổi tài khoản/dự án và giữ token của phiên ban đầu cho yêu cầu đang gửi.

Thao tác ghi legacy có `table`/`record` được lưu hàng đợi trước khi gửi, kể cả khi online. Chỉ xóa sau xác nhận của máy chủ; lỗi và thao tác chưa có handler không được báo thành công. Các bản ghi hết lượt thử vẫn được tính là chưa xác nhận. Quyền ghi vẫn do RLS của database quyết định.

Đây chưa phải chuyển toàn bộ app sang cloud: đăng nhập local, menu, khuyến mãi và các bảng legacy vẫn khác `delivery_cloud_*`. Hàng đợi này không tự chuyển tài khoản SQLite sang Supabase Auth, không tự nhập đơn local vào workflow cloud và không đồng bộ toàn bộ database thiết bị. Luồng cloud tiếp tục dùng API có JWT và RPC để kiểm tra quyền, báo giá và chuyển trạng thái.

`test/offline_sync_identity_test.dart` kiểm tra migration v8 → v9, giữ dữ liệu chưa xác định chủ sở hữu, lọc hàng đợi theo phiên, trạng thái lỗi và đổi tài khoản giữa lúc gửi. Kiểm thử HTTP dùng máy chủ loopback cùng tài khoản fixture, không ghi vào cloud thật.

### Nhập đơn CSV local

Xem trước và xác nhận dùng chung bộ kiểm tra; tọa độ đã kiểm tra được truyền vào đơn đã lưu. Hỗ trợ 4 cột rút gọn, 7 cột đầy đủ, 8 cột có địa chỉ lấy riêng, hoặc 12 cột bổ sung `pickup_lat,pickup_lng,dropoff_lat,dropoff_lng`. Mẫu tải xuống chỉ có tiêu đề, không chèn đơn giả.

Địa chỉ cần tọa độ đã tra cứu, tọa độ kho thuộc cửa hàng đang đăng nhập, hoặc cặp tọa độ trong CSV. Không lấy GPS thiết bị thay cho địa chỉ chưa xác định. Tọa độ nhập tay chỉ được kiểm tra giới hạn địa lý, chưa chứng minh khớp địa chỉ thực tế. COD phải là số nguyên từ 0 đến 20 triệu đồng; khối lượng lớn hơn 0 và không quá 500 kg. CSV có dấu phẩy trong ngoặc kép, xuống dòng và BOM được hỗ trợ. Luồng này tạo đơn local, không tự tải lên cloud.

`test/csv_order_validation_test.dart` kiểm tra preview, lưu và nạp lại tọa độ, dữ liệu không hợp lệ và phụ phí vùng. Dữ liệu fixture chỉ nằm trong database kiểm thử riêng.
