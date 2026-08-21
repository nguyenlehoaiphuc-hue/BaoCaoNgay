# Báo cáo hàng ngày (realtime qua Supabase, có đăng nhập)

Trang tĩnh (không cần server riêng) để cả phòng cùng nhập KPI hàng ngày. Dữ liệu lưu trong
Supabase (Postgres) và đồng bộ realtime tới mọi người đang mở trang — không cần bấm lưu.
Đăng nhập bằng tài khoản Supabase Auth; tên hiển thị góc trên bên phải lấy tự động từ hồ sơ
của tài khoản đang đăng nhập.

Có 2 vai trò:
- **Nhân viên** — nhập và chỉ nhìn thấy số liệu của chính mình.
- **Lãnh đạo** — xem bảng tổng hợp (từng nhân viên + cột Tổng), không nhập được số.

## Có 2 file — dùng cho 1 phòng hay nhiều phòng ban

- [`public/index.html`](public/index.html) — bản gốc cho **1 phòng duy nhất** (PGD Tây Thạnh),
  có ô "Phòng" gõ tự do.
- [`public/bao-cao-chi-nhanh.html`](public/bao-cao-chi-nhanh.html) — bản mở rộng cho **nhiều
  phòng ban cùng lúc** (7 phòng: Phòng DVKH, Phòng Bán Lẻ, Phòng Doanh Nghiệp, Phòng KTTH,
  PGD Tây Thạnh, PGD Hưng Phát, PGD Phan Đăng Lưu). Mỗi tài khoản gắn cố định với 1 phòng ban;
  lãnh đạo chỉ xem tổng hợp của đúng phòng ban mình, không thấy phòng khác. File này còn có thêm
  nút **"Đổi mật khẩu"** để mỗi người tự đặt lại mật khẩu sau khi admin cấp tài khoản ban đầu.

Cả 2 file dùng chung 1 Supabase project — chạy đúng thứ tự file migration bên dưới để nâng cấp
database hỗ trợ cả 2.

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

### Muốn dùng bản nhiều phòng ban (`bao-cao-chi-nhanh.html`)?

Chạy tiếp file [`supabase/migration_departments.sql`](supabase/migration_departments.sql) trong
SQL Editor (sau `migration_roles.sql`). Script này:
- Thêm cột `department` vào `profiles`, giới hạn đúng 7 tên phòng ban cố định.
- Gán toàn bộ tài khoản cũ (đang test Tây Thạnh) vào phòng `PGD Tây Thạnh`.
- Sửa lại RLS: lãnh đạo chỉ xem được nhân viên **cùng phòng ban**, không thấy phòng khác.

Từ giờ khi **Add user**, điền thêm `department` trong User Metadata để tạo tài khoản đã đúng
phòng ban ngay từ đầu, không cần vào Table Editor sửa tay:

```json
{"full_name": "Nguyễn Văn A", "role": "staff", "department": "Phòng DVKH"}
```

`department` phải là đúng 1 trong 7 giá trị: `Phòng DVKH`, `Phòng Bán Lẻ`, `Phòng Doanh Nghiệp`,
`Phòng KTTH`, `PGD Tây Thạnh`, `PGD Hưng Phát`, `PGD Phan Đăng Lưu` — gõ sai chính tả sẽ bị
Supabase từ chối tạo user (nhờ check constraint). `role` bỏ trống sẽ mặc định `staff`.

## 3. Điền cấu hình vào trang

Mở [`public/index.html`](public/index.html) **và** [`public/bao-cao-chi-nhanh.html`](public/bao-cao-chi-nhanh.html)
(nếu dùng cả 2), sửa 2 dòng ở đầu thẻ `<script>` cuối mỗi file — cùng 1 project thì giá trị
giống nhau ở cả 2 file:

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

Vì cả 2 file cùng nằm trong `public/`, Render tự phục vụ cả hai — chia sẻ
`https://ten-app.onrender.com/index.html` cho phòng Tây Thạnh (bản cũ) hoặc
`https://ten-app.onrender.com/bao-cao-chi-nhanh.html` cho bản nhiều phòng ban, tuỳ nhu cầu.

## Bảo mật (lưu ý)

- Anon key an toàn để đặt trong code phía client — nó không phải bí mật, quyền truy cập được kiểm
  soát bởi Row Level Security policies trong `schema.sql` (chỉ user đã đăng nhập mới đọc/ghi được
  dữ liệu báo cáo). Không dùng `service_role` key ở đây.
- Tắt "Allow new users to sign up" (bước 1.6) để không ai lạ tự tạo tài khoản truy cập.
- Muốn xoá quyền truy cập của ai đó: **Authentication → Users** → xoá tài khoản tương ứng.
- Nút "Đổi mật khẩu" trong `bao-cao-chi-nhanh.html` dùng thẳng hàm tự đổi mật khẩu của Supabase
  Auth, không cần mật khẩu cũ — hoạt động vì **Secure password change** đang tắt trong project
  (Authentication → Sign In/Providers → Email). Nếu sau này bật tuỳ chọn đó lên, người dùng cần
  đăng nhập lại gần đây mới đổi được mật khẩu, và có thể cần sửa thêm code mới hỗ trợ đúng luồng
  đó.
