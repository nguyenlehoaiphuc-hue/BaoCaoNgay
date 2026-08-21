-- Chạy file này trong SQL Editor NẾU project đã chạy schema.sql phiên bản cũ (không có role/user_id).
-- Sau khi chạy xong, vào Table Editor -> bảng "profiles" -> sửa cột "role" thành "leader" cho
-- đúng 2 tài khoản lãnh đạo (mặc định ai cũng là "staff").
--
-- LƯU Ý: bước này XOÁ SẠCH dữ liệu hiện có trong daily_reports (vì đổi cấu trúc từ "1 số dùng
-- chung" sang "mỗi người 1 bộ số riêng"). Chỉ nên chạy khi dữ liệu cũ chỉ là dữ liệu test.

-- 1) Thêm cột role vào profiles
alter table profiles add column if not exists role text not null default 'staff';
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_role_check'
  ) then
    alter table profiles add constraint profiles_role_check check (role in ('staff','leader'));
  end if;
end $$;

-- 2) Chuyển daily_reports sang lưu theo từng người
truncate table daily_reports;
alter table daily_reports drop constraint if exists daily_reports_pkey;
alter table daily_reports add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table daily_reports alter column user_id set not null;
alter table daily_reports add primary key (report_date, row_index, user_id);

-- 3) Hàm tiện ích: lấy role của user đang đăng nhập
create or replace function public.current_role()
returns text as $$
  select role from public.profiles where id = auth.uid();
$$ language sql stable;

-- 4) RLS mới cho daily_reports
drop policy if exists "authenticated read" on daily_reports;
drop policy if exists "authenticated insert" on daily_reports;
drop policy if exists "authenticated update" on daily_reports;
drop policy if exists "select own or leader" on daily_reports;
drop policy if exists "staff insert own" on daily_reports;
drop policy if exists "staff update own" on daily_reports;

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

-- 5) Chặn user tự đổi role của mình qua app
create or replace function public.prevent_role_self_change()
returns trigger as $$
begin
  if auth.role() = 'authenticated' and new.role is distinct from old.role then
    new.role := old.role;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists protect_profile_role on profiles;
create trigger protect_profile_role
  before update on profiles
  for each row execute procedure public.prevent_role_self_change();
