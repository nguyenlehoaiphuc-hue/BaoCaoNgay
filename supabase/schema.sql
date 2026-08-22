-- Chạy trong Supabase SQL Editor (New query -> dán -> Run)
-- Đây là schema đầy đủ, dùng cho project MỚI tạo lần đầu (hỗ trợ sẵn nhiều phòng ban).
-- Nếu project đã chạy các phiên bản schema cũ rồi, dùng lần lượt các file migration_*.sql
-- thay vì chạy lại file này.

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'staff' check (role in ('staff', 'leader')),
  department text not null check (
    department in (
      'Phòng DVKH',
      'Phòng Bán Lẻ',
      'Phòng Doanh Nghiệp',
      'Phòng KTTH',
      'PGD Tây Thạnh',
      'PGD Hưng Phát',
      'PGD Phan Đăng Lưu'
    )
  ),
  created_at timestamptz default now()
);

alter table profiles enable row level security;

create table if not exists daily_reports (
  report_date date not null,
  row_index int not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  kpi_name text not null,
  unit text not null,
  value text default '',
  note text default '',
  who text default '',
  updated_at timestamptz default now(),
  primary key (report_date, row_index, user_id)
);

alter table daily_reports enable row level security;

-- Hàm tiện ích: role / phòng ban của user đang đăng nhập (dùng trong policy bên dưới).
create or replace function public.current_role()
returns text as $$
  select role from public.profiles where id = auth.uid();
$$ language sql stable;

create or replace function public.current_department()
returns text as $$
  select department from public.profiles where id = auth.uid();
$$ language sql stable;

-- Nhân viên chỉ đọc/ghi số liệu của chính mình. Lãnh đạo đọc được số liệu của nhân viên
-- CÙNG phòng ban với mình (để xem tổng hợp), nhưng không insert/update được (chỉ xem).
create policy "select own or dept leader" on daily_reports
  for select using (
    auth.uid() = user_id
    or (
      public.current_role() = 'leader'
      and exists (
        select 1 from public.profiles p
        where p.id = daily_reports.user_id
          and p.department = public.current_department()
      )
    )
  );

-- Nhân viên tự ghi số của mình; lãnh đạo cũng ghi/sửa được số của nhân viên cùng phòng ban
-- (dùng ở chế độ "Xem chi tiết" để lãnh đạo chỉnh lại số liệu khi cần).
create policy "insert own or dept leader" on daily_reports
  for insert with check (
    auth.uid() = user_id
    or (
      public.current_role() = 'leader'
      and exists (
        select 1 from public.profiles p
        where p.id = daily_reports.user_id
          and p.department = public.current_department()
      )
    )
  );

create policy "update own or dept leader" on daily_reports
  for update using (
    auth.uid() = user_id
    or (
      public.current_role() = 'leader'
      and exists (
        select 1 from public.profiles p
        where p.id = daily_reports.user_id
          and p.department = public.current_department()
      )
    )
  );

-- Bật realtime cho bảng (nếu không bật được qua UI Table Editor).
alter publication supabase_realtime add table daily_reports;

-- Ai đã đăng nhập cũng đọc được tên hiển thị + role + phòng ban của người khác (để hiển thị
-- tên cột trong bảng tổng hợp của lãnh đạo, và cột "Người cập nhật").
create policy "authenticated read profiles" on profiles
  for select using (auth.role() = 'authenticated');

-- Mỗi người chỉ được tự sửa/tạo hồ sơ của chính mình (tên hiển thị) — cột "role" và
-- "department" được chặn tự đổi bởi trigger bên dưới, chỉ admin sửa qua Table Editor/SQL Editor.
create policy "user manages own profile insert" on profiles
  for insert with check (auth.uid() = id);

create policy "user manages own profile update" on profiles
  for update using (auth.uid() = id);

-- Chặn user tự đổi role/phòng ban của mình qua app (ví dụ gọi thẳng API để tự phong "leader"
-- hoặc tự chuyển sang phòng ban khác).
create or replace function public.prevent_role_self_change()
returns trigger as $$
begin
  if auth.role() = 'authenticated' then
    if new.role is distinct from old.role then
      new.role := old.role;
    end if;
    if new.department is distinct from old.department then
      new.department := old.department;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger protect_profile_role
  before update on profiles
  for each row execute procedure public.prevent_role_self_change();

-- Tự động tạo hồ sơ khi admin tạo tài khoản mới (Authentication -> Users -> Add user).
-- Điền "User Metadata" dạng:
--   {"full_name": "Nguyễn Văn A", "role": "staff", "department": "Phòng DVKH"}
-- để tên hiển thị, vai trò và phòng ban đúng ngay từ lần đăng nhập đầu, đỡ phải vào Table
-- Editor sửa tay từng người. Bỏ "role" sẽ mặc định "staff"; "department" bắt buộc phải có
-- (đúng 1 trong 7 tên phòng ban ở check constraint phía trên), thiếu sẽ khiến việc tạo user lỗi.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role, department)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    coalesce(new.raw_user_meta_data->>'role', 'staff'),
    new.raw_user_meta_data->>'department'
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
