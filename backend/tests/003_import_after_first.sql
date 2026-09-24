\set ON_ERROR_STOP on

do $$
begin
  if (select count(*) from public.products where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6') <> 3 then
    raise exception 'first import row count mismatch';
  end if;

  if exists (
    select 1 from public.products
    where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and currency <> 'SYP'
  ) then
    raise exception 'initial import currency was not SYP';
  end if;

  if not exists (
    select 1 from public.products
    where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 1
      and barcode = '00123' and barcode2 = 'ALT-001'
      and source_payload->>'barcode' = '00123'
      and (select count(*) from jsonb_object_keys(source_payload)) = 25
  ) then
    raise exception 'primary/secondary barcode or source payload was not preserved';
  end if;

  if not exists (
    select 1 from public.products
    where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 2
      and barcode = '-1002' and barcode2 is null and selling_amount = 0
  ) then
    raise exception 'non-digit barcode or zero-price source anomaly was not preserved';
  end if;
end
$$;

update public.products
set name_en = 'Owner Edited After Import', notes = 'later owner edit'
where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 1;

delete from public.products
where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 3;

do $$
begin
  if (
    select revision from public.products
    where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6' and source_id = 1
  ) <> 2 then
    raise exception 'owner edit did not advance revision before rerun';
  end if;

  if (select count(*) from public.products where source_dataset = 'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6') <> 2 then
    raise exception 'missing-row rerun setup failed';
  end if;
end
$$;
