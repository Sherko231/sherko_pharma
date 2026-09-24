\set ON_ERROR_STOP on

insert into public.products (
  name_en,
  selling_amount,
  currency,
  source_dataset,
  source_id,
  source_item_id,
  source_num,
  source_payload
) values (
  'Unexpected synthetic source row',
  1,
  'SYP',
  'synthetic-sp005@sha256:dc5f9cac91a5c80a891f62e3d3606831ad60dd0f465dd363eb331cf4c55a3ec6',
  999,
  999,
  999,
  '{"synthetic":"unexpected"}'::jsonb
);
