-- Chạy trong Supabase SQL Editor (New query -> dán -> Run)

create table if not exists daily_reports (
  report_date date not null,
  row_index int not null,
  kpi_name text not null,
  unit text not null,
  value text default '',
  note text default '',
  who text default '',
  room text default 'TÂY THẠNH',
  updated_at timestamptz default now(),
  primary key (report_date, row_index)
);

alter table daily_reports enable row level security;

-- Chỉ user đã đăng nhập (bất kỳ tài khoản nào được admin tạo) mới đọc/ghi được.
create policy "authenticated read" on daily_reports
  for select using (auth.role() = 'authenticated');

create policy "authenticated insert" on daily_reports
  for insert with check (auth.role() = 'authenticated');

create policy "authenticated update" on daily_reports
  for update using (auth.role() = 'authenticated');

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

-- ==== Bảng hồ sơ người dùng: tên hiển thị gắn với tài khoản đăng nhập ====

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  created_at timestamptz default now()
);

alter table profiles enable row level security;

-- Ai đã đăng nhập cũng đọc được tên hiển thị của người khác (để show cột "Người cập nhật").
create policy "authenticated read profiles" on profiles
  for select using (auth.role() = 'authenticated');

-- Mỗi người chỉ được tự sửa/tạo hồ sơ của chính mình.
create policy "user manages own profile insert" on profiles
  for insert with check (auth.uid() = id);

create policy "user manages own profile update" on profiles
  for update using (auth.uid() = id);

-- Tự động tạo hồ sơ khi admin tạo tài khoản mới (Authentication -> Users -> Add user).
-- Nếu điền "User Metadata" dạng {"full_name": "Nguyễn Văn A"} lúc tạo user, tên đó sẽ tự
-- điền sẵn vào profiles; nếu không, mặc định lấy email và người dùng có thể tự đổi ở lần
-- đăng nhập đầu (banner "Bạn chưa có tên hiển thị" trên giao diện).
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
