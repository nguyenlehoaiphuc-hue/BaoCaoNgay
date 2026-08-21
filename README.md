# Báo cáo hàng ngày (realtime qua Supabase, có đăng nhập)

Trang tĩnh (không cần server riêng) để cả phòng cùng nhập KPI hàng ngày. Dữ liệu lưu trong
Supabase (Postgres) và đồng bộ realtime tới mọi người đang mở trang — không cần bấm lưu.
Đăng nhập bằng tài khoản Supabase Auth; tên hiển thị góc trên bên phải lấy tự động từ hồ sơ
của tài khoản đang đăng nhập.

Có 2 vai trò:
- **Nhân viên** — nhập và chỉ nhìn thấy số liệu của chính mình.
- **Lãnh đạo** — xem bảng tổng hợp (từng nhân viên + cột Tổng), không nhập được số.

## 1. Tạo Supabase project

1. Vào [supabase.com](https://supabase.com) → đăng nhập → **New project**.
2. Đặt tên, chọn vùng gần nhất, đặt mật khẩu DB → **Create new project** (đợi ~1-2 phút).
3. **SQL Editor** → **New query** → dán nội dung file [`supabase/schema.sql`](supabase/schema.sql) → **Run**.
   Script này tạo bảng `daily_reports`, `report_meta`, `profiles` (hồ sơ tên hiển thị) và một
   trigger tự tạo hồ sơ mỗi khi có tài khoản mới.
4. **Table Editor** → chọn từng bảng `daily_reports`, `report_meta`, `profiles` → bật toggle
   **Realtime** (nếu chưa tự bật qua câu lệnh `alter publication` trong schema.sql).
5. **Project Settings → API** → copy **Project URL** và **anon public key**.
6. **Authentication → Providers → Email** → tắt **"Allow new users to sign up"** (chỉ admin tạo
   tài khoản qua Dashboard, không cho ai tự đăng ký) — phù hợp vì đây là công cụ nội bộ phòng.

## 2. Tạo tài khoản cho từng thành viên (đăng nhập bằng tên đăng nhập, không cần email thật)

Supabase Auth luôn yêu cầu dạng email, nên trang dùng một domain giả cố định
(`baocaongay.local`, khai báo ở hằng số `LOGIN_DOMAIN` trong `index.html`) để giả lập đăng nhập
bằng "tên đăng nhập". Người dùng chỉ gõ tên, không cần biết email phía sau.

**Authentication → Users → Add user**:
- **Email**: `tenuser@baocaongay.local` — ví dụ tài khoản cho "anhA" thì điền `anha@baocaongay.local`
  (chỉ dùng chữ thường, không dấu, không khoảng trắng để tránh lỗi định dạng email).
- **Password**: mật khẩu tạm, gửi riêng cho từng người.
- Tick **Auto Confirm User** (bắt buộc, vì email giả không nhận được thư xác nhận).
- Ở mục **User Metadata**, điền `{"full_name": "Nguyễn Văn A"}` để tên hiển thị đúng ngay từ lần
  đăng nhập đầu. Nếu bỏ trống, hệ thống sẽ hiện banner "Bạn chưa có tên hiển thị" để người đó tự
  đặt tên trong lần đăng nhập đầu tiên.

Khi đăng nhập, người dùng chỉ cần gõ **`anha`** (không cần `@baocaongay.local`) và mật khẩu —
trang tự ghép domain phía sau trước khi gửi lên Supabase.

Mặc định mọi tài khoản mới đều là **staff** (nhân viên). Sau khi tạo xong cả 6 tài khoản:
1. **Table Editor** → bảng `profiles`
2. Tìm đúng 2 tài khoản lãnh đạo → sửa cột **role** từ `staff` thành `leader`

> Đã có project chạy `schema.sql` bản cũ (không có role/user_id) từ trước? Chạy file
> [`supabase/migration_roles.sql`](supabase/migration_roles.sql) trong SQL Editor trước, rồi mới
> làm bước gán role ở trên. **Lưu ý**: migration này xoá sạch dữ liệu test đã nhập trong
> `daily_reports` vì đổi cấu trúc bảng.

## 3. Điền cấu hình vào trang

Mở [`public/index.html`](public/index.html), sửa 2 dòng ở đầu thẻ `<script>` cuối file:

```js
const SUPABASE_URL = 'https://xxxxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJ...';
```

## 4. Chạy thử local

```bash
npx serve public
```

Mở địa chỉ hiện ra (thường `http://localhost:3000`), đăng nhập bằng một tài khoản vừa tạo ở bước 2.

## 5. Deploy lên Render (Static Site — miễn phí, không lo mất dữ liệu)

Vì trang không còn giữ state gì phía server (Supabase lo hết), dùng loại **Static Site** của Render
là đơn giản và ổn định nhất — không có vấn đề ổ đĩa/khởi động lại như deploy dạng Web Service.

1. Đẩy thư mục `webapp/` lên một repo GitHub.
2. Trên Render: **New +** → **Static Site** → chọn repo.
3. Cấu hình:
   - **Build Command**: để trống (không cần build)
   - **Publish Directory**: `public`
4. **Create Static Site** → đợi deploy → nhận URL dạng `https://ten-app.onrender.com`, gửi cho cả phòng.

## Bảo mật (lưu ý)

- Anon key an toàn để đặt trong code phía client — nó không phải bí mật, quyền truy cập được kiểm
  soát bởi Row Level Security policies trong `schema.sql` (chỉ user đã đăng nhập mới đọc/ghi được
  dữ liệu báo cáo). Không dùng `service_role` key ở đây.
- Tắt "Allow new users to sign up" (bước 1.6) để không ai lạ tự tạo tài khoản truy cập.
- Muốn xoá quyền truy cập của ai đó: **Authentication → Users** → xoá tài khoản tương ứng.
