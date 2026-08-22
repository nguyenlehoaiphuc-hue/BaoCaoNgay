-- Chạy sau migration_departments.sql. Cho phép lãnh đạo SỬA được số liệu/ghi chú của nhân viên
-- cùng phòng ban (trước đây lãnh đạo chỉ xem, không sửa được).

drop policy if exists "staff insert own" on daily_reports;
drop policy if exists "staff update own" on daily_reports;

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
