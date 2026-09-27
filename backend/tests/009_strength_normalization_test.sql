\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

do $$
declare
  tablet_id uuid;
  liquid_id uuid;
  combo_id uuid;
  combo_reverse_id uuid;
  shared_liquid_id uuid;
  mismatch_id uuid;
  unitless_id uuid;
  descriptive_id uuid;
  gram_id uuid;
  milligram_id uuid;
  microgram_id uuid;
  one_mg_id uuid;
  partial_id uuid;
  tablet_revision bigint;
  tablet_normalized_at timestamptz;
  combo_key text;
  combo_reverse_key text;
begin
  select id into tablet_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000001',
    'Strength Tablet',
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

  select id into liquid_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000002',
    'Strength Liquid',
    null,
    'PARACETAMOL',
    null,
    '250 MG/5 ML.',
    'Syrup',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into combo_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000003',
    'Strength Combo',
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

  select id into combo_reverse_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000004',
    'Strength Combo Reverse',
    null,
    'CLAVULANIC ACID+AMOXICILLIN',
    null,
    '125MG+875MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into shared_liquid_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000005',
    'Strength Shared Liquid',
    null,
    'AMOXICILLIN+CLAVULANIC ACID',
    null,
    '125 MG+31.25 MG/5ML.',
    'Suspension',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into mismatch_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000006',
    'Strength Mismatch',
    null,
    'AMPICILLIN+CLOXACILLIN',
    null,
    '500 MG/CAP.',
    'Capsule',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into unitless_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000007',
    'Strength Unitless',
    null,
    'PARACETAMOL',
    null,
    '0.02',
    null,
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into descriptive_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000008',
    'Strength Descriptive',
    null,
    'PARACETAMOL',
    null,
    'MEN',
    null,
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into gram_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000009',
    'Strength Gram',
    null,
    'CEFTRIAXONE',
    null,
    '1 G/VIAL',
    'Vial',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into milligram_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000010',
    'Strength Milligram',
    null,
    'CEFTRIAXONE',
    null,
    '1000 MG/VIAL',
    'Vial',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into microgram_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000011',
    'Strength Microgram',
    null,
    'VITAMIN B12',
    null,
    '1000 MCG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into one_mg_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000012',
    'Strength One Milligram',
    null,
    'VITAMIN B12',
    null,
    '1 MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into partial_id
  from public.catalog_create_idempotent(
    '71000000-0000-4000-8000-000000000013',
    'Strength Partial',
    null,
    'PARACETAMOL+CAFFEINE',
    null,
    '500MG+50MG+',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  if (
    select status
    from app_private.product_strength_normalization
    where product_id = tablet_id
  ) <> 'auto_verified' then
    raise exception 'recognized tablet suffix was not auto verified';
  end if;

  if not exists (
    select 1
    from app_private.product_ingredient_strengths
    where product_id = tablet_id
      and normalized_amount = 500
      and normalized_unit = 'mg'
      and per_amount is null
      and per_unit is null
      and normalized_strength_key = 'mg:500'
  ) then
    raise exception 'tablet presentation suffix was misparsed as a denominator';
  end if;

  if not exists (
    select 1
    from app_private.product_ingredient_strengths
    where product_id = liquid_id
      and normalized_amount = 250
      and normalized_unit = 'mg'
      and per_amount = 5
      and per_unit = 'ml'
      and normalized_strength_key = 'mg/ml:50'
  ) then
    raise exception 'quantitative liquid denominator did not normalize';
  end if;

  select ingredient_strength_set_key
    into combo_key
  from app_private.product_strength_normalization
  where product_id = combo_id
    and status = 'auto_verified';

  select ingredient_strength_set_key
    into combo_reverse_key
  from app_private.product_strength_normalization
  where product_id = combo_reverse_id
    and status = 'auto_verified';

  if combo_key is null
     or combo_reverse_key is null
     or combo_key <> combo_reverse_key then
    raise exception 'ingredient-strength set key is not order independent';
  end if;

  if (
    select count(*)
    from app_private.product_ingredient_strengths
    where product_id = combo_id
  ) <> 2 then
    raise exception 'explicit combination did not link two strengths';
  end if;

  if (
    select status
    from app_private.product_strength_normalization
    where product_id = shared_liquid_id
  ) <> 'high_confidence' then
    raise exception 'shared quantitative denominator should be high confidence';
  end if;

  if (
    select count(*)
    from app_private.product_ingredient_strengths
    where product_id = shared_liquid_id
      and per_amount = 5
      and per_unit = 'ml'
  ) <> 2 then
    raise exception 'shared liquid denominator was not applied to both components';
  end if;

  if not exists (
    select 1
    from app_private.product_ingredient_strengths
    where product_id = shared_liquid_id
      and component_index = 1
      and normalized_strength_key = 'mg/ml:25'
  ) or not exists (
    select 1
    from app_private.product_ingredient_strengths
    where product_id = shared_liquid_id
      and component_index = 2
      and normalized_strength_key = 'mg/ml:6.25'
  ) then
    raise exception 'shared liquid normalized ratios are incorrect';
  end if;

  if (
    select status
    from app_private.product_strength_normalization
    where product_id = mismatch_id
  ) <> 'needs_review' then
    raise exception 'ingredient/strength count mismatch was trusted';
  end if;

  if exists (
    select 1
    from app_private.product_ingredient_strengths
    where product_id = mismatch_id
  ) then
    raise exception 'mismatched combination retained trusted strength links';
  end if;

  if (
    select status
    from app_private.product_strength_normalization
    where product_id = unitless_id
  ) <> 'unresolved' then
    raise exception 'unitless numeric strength was inferred';
  end if;

  if (
    select status
    from app_private.product_strength_normalization
    where product_id = descriptive_id
  ) <> 'unresolved' then
    raise exception 'descriptive strength value was inferred';
  end if;

  if (
    select ingredient_strength_set_key
    from app_private.product_strength_normalization
    where product_id = gram_id
  ) <> (
    select ingredient_strength_set_key
    from app_private.product_strength_normalization
    where product_id = milligram_id
  ) then
    raise exception '1 G and 1000 MG did not normalize equivalently';
  end if;

  if (
    select ingredient_strength_set_key
    from app_private.product_strength_normalization
    where product_id = microgram_id
  ) <> (
    select ingredient_strength_set_key
    from app_private.product_strength_normalization
    where product_id = one_mg_id
  ) then
    raise exception '1000 MCG and 1 MG did not normalize equivalently';
  end if;

  if (
    select status
    from app_private.product_strength_normalization
    where product_id = partial_id
  ) <> 'needs_review' then
    raise exception 'partial combination was not quarantined';
  end if;

  if exists (
    select 1
    from app_private.product_ingredient_strengths
    where product_id = partial_id
  ) then
    raise exception 'partial combination retained trusted links';
  end if;

  select revision
    into tablet_revision
  from public.products
  where id = tablet_id;

  select normalized_at
    into tablet_normalized_at
  from app_private.product_strength_normalization
  where product_id = tablet_id;

  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  perform *
  from public.catalog_update(
    tablet_id,
    tablet_revision,
    'Strength Tablet',
    null,
    'PARACETAMOL',
    null,
    '1000 MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  if not exists (
    select 1
    from app_private.product_ingredient_strengths
    where product_id = tablet_id
      and normalized_amount = 1000
      and normalized_unit = 'mg'
      and normalized_strength_key = 'mg:1000'
  ) then
    raise exception 'strength-only catalog update did not refresh derived strength';
  end if;

  if (
    select revision
    from public.products
    where id = tablet_id
  ) <> tablet_revision + 1 then
    raise exception 'strength normalization changed catalog revision semantics';
  end if;

  if (
    select normalized_at
    from app_private.product_strength_normalization
    where product_id = tablet_id
  ) = tablet_normalized_at then
    raise exception 'strength update did not refresh normalization timestamp';
  end if;

  tablet_revision := tablet_revision + 1;

  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  perform *
  from public.catalog_update(
    tablet_id,
    tablet_revision,
    'Strength Tablet',
    null,
    'IBUPROFEN',
    null,
    '400 MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  if not exists (
    select 1
    from app_private.product_ingredient_strengths s
    join app_private.catalog_ingredients i
      on i.id = s.ingredient_id
    where s.product_id = tablet_id
      and i.normalized_name =
        app_private.catalog_search_normalize('IBUPROFEN')
      and s.normalized_amount = 400
      and s.normalized_strength_key = 'mg:400'
  ) then
    raise exception 'composition+strength update did not refresh in dependency order';
  end if;

  if (
    select source_composition
    from app_private.product_composition_normalization
    where product_id = tablet_id
  ) <> 'IBUPROFEN' then
    raise exception 'composition normalization was not refreshed before strength';
  end if;

  if (
    select source_strength
    from app_private.product_strength_normalization
    where product_id = tablet_id
  ) <> '400 MG/CTD TAB.' then
    raise exception 'strength snapshot did not follow combined update';
  end if;
end
$$;

rollback;
