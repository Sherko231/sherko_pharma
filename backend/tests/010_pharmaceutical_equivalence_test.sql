\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

do $pharmaceutical_equivalence_test$
declare
  plain_a_id uuid;
  plain_b_id uuid;
  extended_id uuid;
  delayed_id uuid;
  eye_id uuid;
  ear_id uuid;
  vaginal_id uuid;
  injection_id uuid;
  unknown_id uuid;
  combo_a_id uuid;
  combo_b_id uuid;
  plain_key text;
  extended_key text;
  delayed_key text;
  combo_a_key text;
  combo_b_key text;
  plain_revision bigint;
begin
  if not exists (
    select 1
    from app_private.catalog_classify_dosage_form('Tablet')
    where form_class_key = 'oral_tablet'
      and route_class = 'oral'
      and release_class = 'immediate_release'
      and status in ('auto_verified', 'high_confidence')
  ) then
    raise exception 'plain tablet classification failed';
  end if;

  if not exists (
    select 1
    from app_private.catalog_classify_dosage_form('Extended Release Tablet')
    where form_class_key = 'oral_tablet'
      and route_class = 'oral'
      and release_class = 'extended_release'
      and status in ('auto_verified', 'high_confidence')
  ) then
    raise exception 'extended-release tablet classification failed';
  end if;

  if not exists (
    select 1
    from app_private.catalog_classify_dosage_form('Enteric Coated Tablet')
    where form_class_key = 'oral_tablet'
      and route_class = 'oral'
      and release_class = 'delayed_release'
      and status in ('auto_verified', 'high_confidence')
  ) then
    raise exception 'delayed-release tablet classification failed';
  end if;

  if not exists (
    select 1
    from app_private.catalog_classify_dosage_form('محلول للحقن/حبابات')
    where route_class = 'parenteral_unspecified'
      and status = 'needs_review'
  ) then
    raise exception 'unspecified injection route was trusted';
  end if;

  if not exists (
    select 1
    from app_private.catalog_classify_dosage_form('أقراص مديدة التحرر')
    where form_class_key = 'oral_tablet'
      and route_class = 'oral'
      and release_class = 'extended_release'
      and status in ('auto_verified', 'high_confidence')
  ) then
    raise exception 'Arabic extended-release tablet classification failed';
  end if;

  if not exists (
    select 1
    from app_private.catalog_classify_dosage_form('أقراص ملبسة معوياً')
    where form_class_key = 'oral_tablet'
      and route_class = 'oral'
      and release_class = 'delayed_release'
      and status in ('auto_verified', 'high_confidence')
  ) then
    raise exception 'Arabic enteric tablet classification failed';
  end if;

  if not exists (
    select 1
    from app_private.catalog_classify_dosage_form('قطرة عينية انفيةأذنية')
    where status = 'needs_review'
      and reason_code = 'multiple_route_markers'
  ) then
    raise exception 'mixed-route dosage form was not quarantined';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.catalog_classify_dosage_form(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'app_private.refresh_product_pharmaceutical_equivalence(uuid)',
    'EXECUTE'
  ) then
    raise exception 'private equivalence helpers are executable by authenticated';
  end if;

  if has_table_privilege(
    'authenticated',
    'app_private.product_pharmaceutical_equivalence',
    'SELECT'
  ) or has_table_privilege(
    'authenticated',
    'app_private.catalog_dosage_form_equivalence_profiles',
    'SELECT'
  ) then
    raise exception 'private equivalence tables are readable by authenticated';
  end if;

  set local role authenticated;
  set local "request.jwt.claim.sub" =
    '11111111-1111-1111-1111-111111111111';

  select id into plain_a_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000001',
    'Plain Tablet A',
    null,
    'PARACETAMOL',
    null,
    '500 MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into plain_b_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000002',
    'Plain Tablet B',
    null,
    'PARACETAMOL',
    null,
    '500 MG/CTD TAB.',
    'Film Coated Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into extended_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000003',
    'Extended Tablet',
    null,
    'PARACETAMOL',
    null,
    '500 MG/CTD TAB.',
    'Extended Release Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into delayed_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000004',
    'Delayed Tablet',
    null,
    'PARACETAMOL',
    null,
    '500 MG/CTD TAB.',
    'Enteric Coated Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into eye_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000005',
    'Eye Drop',
    null,
    'MOXIFLOXACIN',
    null,
    '0.5%',
    'Eye Drops',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into ear_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000006',
    'Ear Drop',
    null,
    'MOXIFLOXACIN',
    null,
    '0.5%',
    'Ear Drops',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into vaginal_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000007',
    'Vaginal Tablet',
    null,
    'CLOTRIMAZOLE',
    null,
    '500 MG',
    'Vaginal Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into injection_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000008',
    'Injection',
    null,
    'CEFTRIAXONE',
    null,
    '1 G/VIAL',
    'Solution for Injection',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into unknown_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000009',
    'Unknown Form',
    null,
    'PARACETAMOL',
    null,
    '500 MG',
    'Unclassified Device Form',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into combo_a_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000010',
    'Combo A',
    null,
    'AMOXICILLIN+CLAVULANIC ACID',
    null,
    '875MG+125MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into combo_b_id
  from public.catalog_create_idempotent(
    '72000000-0000-4000-8000-000000000011',
    'Combo B',
    null,
    'CLAVULANIC ACID+AMOXICILLIN',
    null,
    '125MG+875MG/CTD TAB.',
    'Film Coated Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  select strict_equivalence_key
    into plain_key
  from app_private.product_pharmaceutical_equivalence
  where product_id = plain_a_id;

  if plain_key is null then
    raise exception 'trusted plain tablet did not receive strict equivalence key';
  end if;

  if plain_key <> (
    select strict_equivalence_key
    from app_private.product_pharmaceutical_equivalence
    where product_id = plain_b_id
  ) then
    raise exception 'compatible plain tablet forms did not compare equal';
  end if;

  select strict_equivalence_key
    into extended_key
  from app_private.product_pharmaceutical_equivalence
  where product_id = extended_id;

  select strict_equivalence_key
    into delayed_key
  from app_private.product_pharmaceutical_equivalence
  where product_id = delayed_id;

  if extended_key is null or delayed_key is null then
    raise exception 'recognized modified-release forms did not receive strict keys';
  end if;

  if plain_key = extended_key
     or plain_key = delayed_key
     or extended_key = delayed_key then
    raise exception 'release semantics collapsed into the same strict key';
  end if;

  if (
    select strict_equivalence_key
    from app_private.product_pharmaceutical_equivalence
    where product_id = eye_id
  ) is null
     or (
       select strict_equivalence_key
       from app_private.product_pharmaceutical_equivalence
       where product_id = ear_id
     ) is null
     or (
       select strict_equivalence_key
       from app_private.product_pharmaceutical_equivalence
       where product_id = eye_id
     ) = (
       select strict_equivalence_key
       from app_private.product_pharmaceutical_equivalence
       where product_id = ear_id
     ) then
    raise exception 'ophthalmic and otic routes were not strictly separated';
  end if;

  if (
    select route_class
    from app_private.product_pharmaceutical_equivalence
    where product_id = vaginal_id
  ) <> 'vaginal' then
    raise exception 'vaginal tablet route was not preserved';
  end if;

  if (
    select status
    from app_private.product_pharmaceutical_equivalence
    where product_id = injection_id
  ) <> 'needs_review'
     or (
       select strict_equivalence_key
       from app_private.product_pharmaceutical_equivalence
       where product_id = injection_id
     ) is not null then
    raise exception 'unspecified injection route received strict equivalence';
  end if;

  if (
    select status
    from app_private.product_pharmaceutical_equivalence
    where product_id = unknown_id
  ) <> 'unresolved'
     or (
       select strict_equivalence_key
       from app_private.product_pharmaceutical_equivalence
       where product_id = unknown_id
     ) is not null then
    raise exception 'unknown dosage form received strict equivalence';
  end if;

  select strict_equivalence_key
    into combo_a_key
  from app_private.product_pharmaceutical_equivalence
  where product_id = combo_a_id;

  select strict_equivalence_key
    into combo_b_key
  from app_private.product_pharmaceutical_equivalence
  where product_id = combo_b_id;

  if combo_a_key is null
     or combo_b_key is null
     or combo_a_key <> combo_b_key then
    raise exception 'ingredient order leaked into pharmaceutical equivalence key';
  end if;

  if (
    select status
    from app_private.product_pharmaceutical_equivalence
    where product_id = combo_a_id
  ) <> 'high_confidence' then
    raise exception 'upstream high-confidence pairing was silently upgraded';
  end if;

  select revision
    into plain_revision
  from public.products
  where id = plain_a_id;

  set local role authenticated;
  set local "request.jwt.claim.sub" =
    '11111111-1111-1111-1111-111111111111';

  perform *
  from public.catalog_update(
    plain_a_id,
    plain_revision,
    'Plain Tablet A',
    null,
    'PARACETAMOL',
    null,
    '500 MG/CTD TAB.',
    'Extended Release Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  if (
    select strict_equivalence_key
    from app_private.product_pharmaceutical_equivalence
    where product_id = plain_a_id
  ) <> extended_key then
    raise exception 'dosage-form update did not refresh pharmaceutical equivalence';
  end if;

  if (
    select revision
    from public.products
    where id = plain_a_id
  ) <> plain_revision + 1 then
    raise exception 'equivalence refresh changed catalog revision semantics';
  end if;
end
$pharmaceutical_equivalence_test$;

rollback;
