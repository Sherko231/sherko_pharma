\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

do $$
declare
  created_id uuid;
  manufacturer_label text;
  dosage_label text;
  created_currency text;
  manufacturer_ref_count integer;
  dosage_ref_count integer;
begin
  select id, manufacturer, dosage_form, currency
    into created_id, manufacturer_label, dosage_label, created_currency
  from public.catalog_create_idempotent(
    '55555555-5555-4555-8555-555555555555',
    'Reference Test',
    null,
    'PARACETAMOL',
    'أفاميا',
    '500 MG',
    'اقراص',
    '20 tablets',
    null,
    null,
    1000,
    'SYP',
    null
  );

  if manufacturer_label <> 'افاميا' then
    raise exception 'manufacturer alias did not resolve to canonical spelling: %',
      manufacturer_label;
  end if;

  if dosage_label <> 'أقراص' then
    raise exception 'dosage-form alias did not resolve to canonical spelling: %',
      dosage_label;
  end if;

  if created_currency <> 'SYP' then
    raise exception 'typed currency was not exposed as the compatible RPC label';
  end if;

  reset role;

  if not exists (
    select 1
    from public.products p
    join app_private.catalog_manufacturers m on m.id = p.manufacturer_id
    where p.id = created_id
      and m.normalized_name = app_private.catalog_reference_key('أفاميا')
  ) then
    raise exception 'manufacturer FK/reference was not persisted';
  end if;

  if not exists (
    select 1
    from public.products p
    join app_private.catalog_dosage_forms f on f.id = p.dosage_form_id
    where p.id = created_id
      and f.normalized_name = app_private.catalog_reference_key('اقراص')
  ) then
    raise exception 'dosage-form FK/reference was not persisted';
  end if;

  select count(*) into manufacturer_ref_count
  from app_private.catalog_manufacturers
  where normalized_name = app_private.catalog_reference_key('أفاميا');

  if manufacturer_ref_count <> 1 then
    raise exception 'spelling-equivalent manufacturer created duplicate reference';
  end if;

  select count(*) into dosage_ref_count
  from app_private.catalog_dosage_forms
  where normalized_name = app_private.catalog_reference_key('اقراص');

  if dosage_ref_count <> 1 then
    raise exception 'spelling-equivalent dosage form created duplicate reference';
  end if;

  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  perform *
  from public.catalog_update(
    created_id,
    1,
    'Reference Test',
    null,
    'PARACETAMOL',
    null,
    '500 MG',
    null,
    '20 tablets',
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  if exists (
    select 1
    from public.products
    where id = created_id
      and (
        manufacturer is not null
        or manufacturer_id is not null
        or dosage_form is not null
        or dosage_form_id is not null
      )
  ) then
    raise exception 'clearing reference text did not clear its FK/cache pair';
  end if;

  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  begin
    perform *
    from public.catalog_create_idempotent(
      '66666666-6666-4666-8666-666666666666',
      'Bad Currency',
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      1,
      'EUR',
      null
    );
    raise exception 'unsupported enum currency unexpectedly succeeded';
  exception when invalid_text_representation then
    null;
  end;
end
$$;

do $$
begin
  if has_function_privilege(
    'anon',
    'public.catalog_reference_options(text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'anonymous reference-list access unexpectedly exists';
  end if;

  if (
    select count(*)
    from public.catalog_reference_options('manufacturer', 'افام', 20)
    where label = 'افاميا'
  ) <> 1 then
    raise exception 'owner manufacturer reference options failed';
  end if;

  if (
    select count(*)
    from public.catalog_reference_options('dosage_form', 'اقرا', 20)
    where label = 'أقراص'
  ) <> 1 then
    raise exception 'owner dosage-form reference options failed';
  end if;
end
$$;

reset role;
rollback;
