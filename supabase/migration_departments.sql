-- Chạy SAU KHI đã chạy schema.sql + migration_roles.sql.
-- Mở rộng từ 1 phòng (PGD Tây Thạnh) sang 7 phòng ban, mỗi phòng có nhân viên + lãnh đạo riêng,
-- lãnh đạo chỉ xem được nhân viên CÙNG phòng ban với mình (không thấy phòng khác).

alter table profiles add column if not exists department text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_department_check'
  ) then
    alter table profiles add constraint profiles_department_check check (
      department in (
        'Phòng DVKH',
        'Phòng Bán Lẻ',
        'Phòng Doanh Nghiệp',
        'Phòng KTTH',
        'PGD Tây Thạnh',
        'PGD Hưng Phát',
        'PGD Phan Đăng Lưu'
      )
    );
  end if;
end $$;

-- Gán department cho các tài khoản đã tạo trước đó (toàn bộ đang là Tây Thạnh).
update profiles set department = 'PGD Tây Thạnh' where department is null;

-- Từ giờ department là bắt buộc cho mọi tài khoản mới.
alter table profiles alter column department set not null;

-- Hàm tiện ích: lấy phòng ban của user đang đăng nhập.
create or replace function public.current_department()
returns text as $$
  select department from public.profiles where id = auth.uid();
$$ language sql stable;

-- RLS mới: lãnh đạo chỉ xem được nhân viên CÙNG phòng ban (trước đây thấy được hết mọi phòng).
drop policy if exists "select own or leader" on daily_reports;
drop policy if exists "select own or dept leader" on daily_reports;

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

-- Cho phép admin gán sẵn role + department ngay lúc tạo tài khoản qua User Metadata dạng:
-- {"full_name": "Nguyễn Văn A", "role": "staff", "department": "Phòng DVKH"}
-- đỡ phải vào Table Editor sửa tay từng người sau khi tạo.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role, department)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    coalesce(new.raw_user_meta_data->>'role', 'staff'),
    coalesce(new.raw_user_meta_data->>'department', 'PGD Tây Thạnh')
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public;
