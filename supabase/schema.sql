-- Chạy trong Supabase SQL Editor (New query -> dán -> Run)
-- Đây là schema đầy đủ, dùng cho project MỚI tạo lần đầu.
-- Nếu project đã chạy schema.sql phiên bản cũ rồi, dùng file migration_roles.sql thay vì chạy lại file này.

create table if not exists daily_reports (
  report_date date not null,
  row_index int not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  kpi_name text not null,
  unit text not null,
  value text default '',
  note text default '',
  who text default '',
  room text default 'TÂY THẠNH',
  updated_at timestamptz default now(),
  primary key (report_date, row_index, user_id)
);

alter table daily_reports enable row level security;

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'staff' check (role in ('staff', 'leader')),
  created_at timestamptz default now()
);

alter table profiles enable row level security;

-- Hàm tiện ích: lấy role của user đang đăng nhập (dùng trong policy bên dưới).
create or replace function public.current_role()
returns text as $$
  select role from public.profiles where id = auth.uid();
$$ language sql stable;

-- Nhân viên chỉ đọc/ghi số liệu của chính mình. Lãnh đạo đọc được tất cả (để xem tổng hợp)
-- nhưng không insert/update được (chỉ xem, không nhập).
create policy "select own or leader" on daily_reports
  for select using (
    auth.uid() = user_id or public.current_role() = 'leader'
  );

create policy "staff insert own" on daily_reports
  for insert with check (
    auth.uid() = user_id and coalesce(public.current_role(), 'staff') <> 'leader'
  );

create policy "staff update own" on daily_reports
  for update using (
    auth.uid() = user_id and coalesce(public.current_role(), 'staff') <> 'leader'
  );

-- Bật realtime cho bảng (nếu không bật được qua UI Table Editor).
alter publication supabase_realtime add table daily_reports;

create table if not exists report_meta (
  report_date date primary key,
  room text default 'TÂY THẠNH'
);

alter table report_meta enable row level security;

create policy "authenticated read meta" on report_meta
  for select using (auth.role() = 'authenticated');

create policy "authenticated insert meta" on report_meta
  for insert with check (auth.role() = 'authenticated');

create policy "authenticated update meta" on report_meta
  for update using (auth.role() = 'authenticated');

alter publication supabase_realtime add table report_meta;

-- Ai đã đăng nhập cũng đọc được tên hiển thị + role của người khác (để show tên cột trong
-- bảng tổng hợp của lãnh đạo, và cột "Người cập nhật").
create policy "authenticated read profiles" on profiles
  for select using (auth.role() = 'authenticated');

-- Mỗi người chỉ được tự sửa/tạo hồ sơ của chính mình (tên hiển thị) — riêng cột "role"
-- được chặn tự đổi bởi trigger bên dưới, chỉ admin sửa qua Table Editor/SQL Editor.
create policy "user manages own profile insert" on profiles
  for insert with check (auth.uid() = id);

create policy "user manages own profile update" on profiles
  for update using (auth.uid() = id);

-- Chặn user tự đổi role của mình qua app (ví dụ gọi thẳng API để tự phong "leader").
create or replace function public.prevent_role_self_change()
returns trigger as $$
begin
  if auth.role() = 'authenticated' and new.role is distinct from old.role then
    new.role := old.role;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger protect_profile_role
  before update on profiles
  for each row execute procedure public.prevent_role_self_change();

-- Tự động tạo hồ sơ khi admin tạo tài khoản mới (Authentication -> Users -> Add user).
-- Nếu điền "User Metadata" dạng {"full_name": "Nguyễn Văn A"} lúc tạo user, tên đó sẽ tự
-- điền sẵn vào profiles; role mặc định là 'staff' — admin tự đổi thành 'leader' cho 2 tài
-- khoản lãnh đạo qua Table Editor sau khi tạo.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
