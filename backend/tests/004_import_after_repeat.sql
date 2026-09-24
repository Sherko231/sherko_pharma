\set ON_ERROR_STOP on

do $$
begin
  if (select count(*) from public.products where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6') <> 3 then
    raise exception 'rerun did not recover exactly the missing approved row';
  end if;

  if not exists (
    select 1 from public.products
    where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 1
      and name_en = 'Owner Edited After Import'
      and notes = 'later owner edit'
      and revision = 2
  ) then
    raise exception 'rerun overwrote a later owner edit or reset its revision';
  end if;

  if not exists (
    select 1 from public.products
    where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 3 and revision = 1
  ) then
    raise exception 'missing source row was not safely restored on rerun';
  end if;

  if not exists (
    select 1 from public.products
    where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 2
      and selling_amount = 0 and currency = 'SYP'
  ) then
    raise exception 'source price/currency changed during rerun';
  end if;
end
$$;
