\set ON_ERROR_STOP on

delete from public.products
where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6';

do $$
begin
  if exists (select 1 from public.products where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6') then
    raise exception 'synthetic import cleanup failed';
  end if;
end
$$;
