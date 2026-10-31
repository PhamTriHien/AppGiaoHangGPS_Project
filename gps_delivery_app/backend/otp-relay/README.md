# GO-MAU OTP relay

Backend này nhận yêu cầu gửi Email OTP từ Flutter Web rồi gửi email bằng Gmail SMTP. App Password chỉ nằm trong backend, không nằm trong JavaScript của trình duyệt.

## Cài đặt

```powershell
cd gps_delivery_app/backend/otp-relay
npm install
Copy-Item .env.example .env
```

Mở `.env` và điền:

- `SMTP_USER`: Gmail dùng để gửi thư.
- `SMTP_PASS`: Gmail App Password 16 ký tự.
- `RELAY_TOKEN`: chuỗi ngẫu nhiên cho quản trị native local; không bắt buộc khi backend cloud đã cấu hình Supabase.
- `WEB_ORIGINS`: domain chạy Flutter Web, phân tách bằng dấu phẩy.

Không dùng mật khẩu Gmail thông thường và không commit `.env`.

Backend cloud dùng `SUPABASE_URL` và `SUPABASE_ANON_KEY` để xác thực tài khoản.
Sau khi cấp quyền operator đầu tiên, quản trị viên cấu hình PostgreSQL tại
**API & Dịch vụ > Quản lý API backend > Triển khai backend**, Gmail tại **Gmail / SMTP**,
và xác nhận cập nhật database tại **Sẵn sàng triển khai**. Khóa bí mật lưu trên
backend đang hiển thị trong Admin. Xem phần triển khai và lưu cấu hình bền vững
trong [INTEGRATIONS.md](INTEGRATIONS.md).

## Chạy

```powershell
npm start
```

Kiểm tra:

```powershell
Invoke-RestMethod http://127.0.0.1:8787/health
```

## Chạy Flutter Web

Từ thư mục `gps_delivery_app`:

```powershell
node backend/otp-relay/build-local-web.mjs
```

Khi deploy, dùng URL HTTPS của backend và thêm domain production vào `WEB_ORIGINS`.
Không nhúng relay token vào Web. Web dùng phiên Supabase Auth; các route OTP
local cũ chỉ dành cho desktop tin cậy. Xem [INTEGRATIONS.md](INTEGRATIONS.md).

## Kết nối Windows Desktop

Chạy trong thư mục backend:

```powershell
npm run configure:desktop
```

Lệnh này lưu URL và token relay vào `%LOCALAPPDATA%/GHST/auth-providers.json`.
App desktop tự nạp file khi khởi động, sau đó lưu cấu hình trong SQLite.
Gmail App Password vẫn chỉ ở backend; build lại Flutter không cần truyền lại
token qua `--dart-define`. Backend cần chạy khi gửi OTP.

Google OAuth là cấu hình riêng, không dùng Gmail App Password. Nút đăng nhập
Google chỉ xuất hiện khi có Client ID. Quản trị viên có thể lưu cấu hình tại
**API & Dịch vụ > Quản lý API backend > Google OAuth desktop**. Chạy
`npm run setup:central` để chuyển cấu hình cũ sang backend mà không ghi đè giá trị
đã có; backend giữ Client Secret, Gmail App Password và khóa SMS.

## API thời tiết miễn phí

Backend có `GET /delivery/weather?lat=...&lon=...`, dùng cùng Bearer token của relay. Endpoint chỉ truy vấn MET Norway cố định, kiểm tra tọa độ, làm tròn theo khu vực, gộp yêu cầu đồng thời và cache theo `Expires`/`Last-Modified`. Lỗi upstream trả 502; giới hạn yêu cầu trả 429 cùng `Retry-After`. Xác minh TLS vẫn được bật.

`npm run configure:desktop` cũng ghi `deliveryApiBaseUrl` vào cấu hình local, giữ lại Google OAuth và các giá trị hiện có. Backend phải chạy để app desktop lấy thời tiết qua proxy. `npm test` kiểm tra xác thực tọa độ, cache, HTTP 304 và cooldown 429. [Nguồn dữ liệu và điều khoản MET Norway](https://api.met.no/doc/TermsOfService).
