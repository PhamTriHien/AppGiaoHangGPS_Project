# GHST / GO-MAU — Cloud Backend & Admin Portal (`backend-admin`)

Nhánh chuyên biệt gọn nhẹ dùng để triển khai **API Backend (`otp-relay`) + Database Migrations + Giao diện Quản trị Cloud (`/#/admin`)** lên các nền tảng đám mây (**Render, Railway, Fly.io, Google Cloud Run, Docker VPS**).

## Cấu trúc nhánh

- `Dockerfile`, `render.yaml`, `railway.json`, `package.json`: Cấu hình triển khai Cloud tự động (Node.js 22 slim, non-root `node`, cổng `PORT=8787`, `BIND_HOST=0.0.0.0`, `TRUST_PROXY=1`).
- `gps_delivery_app/backend/otp-relay/`: Toàn bộ Express API Gateway (`/health`, `/delivery/cloud/*`, `/delivery/admin/*`, `/delivery/places`, `/delivery/reverse`, `/delivery/route`, `/delivery/matrix`, `/delivery/tracking/lookup`, worker `delivery_market_run_jobs`).
- `gps_delivery_app/backend/otp-relay/public-admin/`: Bản build Web Admin Portal dùng đường dẫn tương đối `/delivery/` (tự động nhận đúng domain HTTPS của mọi máy chủ Cloud, không chứa bất kỳ khóa bí mật nào).
- `gps_delivery_app/database/migrations/`: Toàn bộ 13 bản SQL migration (`20261027` → `20261107_cloud_commercial_suite.sql`, `workflowVersion: 13`).

## Biến môi trường cần khai báo trên Cloud (Render / Railway)

Nhờ cơ chế đồng bộ cấu hình tự động từ bảng `public.delivery_backend_config` (RLS-locked trên Supabase Cloud PostgreSQL), bạn **chỉ cần khai báo 3 biến kết nối gốc** trên trang quản lý của dịch vụ Cloud:

| Biến môi trường | Bắt buộc | Mô tả |
| --- | --- | --- |
| `DATABASE_URL` | Có | Chuỗi kết nối PostgreSQL của project Supabase |
| `SUPABASE_URL` | Có | URL project Supabase (`https://<project-ref>.supabase.co`) |
| `SUPABASE_ANON_KEY` | Có | Publishable / `anon` key của Supabase |
| `BIND_HOST` | Tự động (`0.0.0.0`) | Đã đặt sẵn trong `Dockerfile` / `render.yaml` |
| `TRUST_PROXY` | Tự động (`1`) | Bật nhận diện IP qua HTTPS Reverse Proxy cho `express-rate-limit` |
| `WEB_ORIGINS` | Tùy chọn | Danh sách domain frontend bên ngoài được phép gọi CORS (cách nhau bằng dấu phẩy). Giao diện `/#/admin` chạy cùng domain tự động được cho phép. |
| `PUBLIC_BASE_URL` | Tùy chọn | URL HTTPS công khai của backend khi cấu hình webhook `payOS` / `GHN` |

Toàn bộ các khóa dịch vụ đã lưu (`TRACKASIA_API_KEY`, `TRACKASIA_ENABLED`, `SMTP_*`, `GOOGLE_*`, `MARKET_JOBS_ENABLED`...) sẽ được nạp trực tiếp từ bảng `public.delivery_backend_config` trên Supabase ngay khi container khởi động.

## Hướng dẫn Deploy nhanh

### 1. Render.com
1. Vào **New + → Blueprint** (hoặc **Web Service**), chọn repo `AppGiaoHangGPS_Project`.
2. Chọn nhánh **`backend-admin`** (Runtime: **Docker**).
3. Điền 3 biến `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` → bấm **Deploy**.
4. Sau khi lên sóng, mở `https://<ten-dich-vu>.onrender.com/` (tự chuyển về `/#/admin`) và đăng nhập bằng tài khoản Operator Cloud.

### 2. Railway.app
1. Chọn **New Project → Deploy from GitHub repo** → chọn nhánh **`backend-admin`**.
2. Vào tab **Variables**, thêm `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
3. Bật **Generate Domain** trong tab **Settings → Networking** để lấy địa chỉ HTTPS truy cập `/#/admin`.

### 3. Docker độc lập (VPS / Cloud Run / Fly.io)
```bash
docker build -t ghst-backend-admin .
docker run -d --name ghst-backend-admin -p 8787:8787 \
  -e DATABASE_URL="postgresql://..." \
  -e SUPABASE_URL="https://<project-ref>.supabase.co" \
  -e SUPABASE_ANON_KEY="sb_publishable_..." \
  ghst-backend-admin
```
