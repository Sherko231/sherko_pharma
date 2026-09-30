\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

select id from public.catalog_create_idempotent(
  '75000000-0000-4000-8000-000000000001',
  'SP098 Aspirin',
  null,
  'ACETYLSALICYLIC ACID',
  null,
  null,
  null,
  null,
  null,
  null,
  1000,
  'SYP',
  null
);

select id from public.catalog_create_idempotent(
  '75000000-0000-4000-8000-000000000002',
  'SP098 Diclofenac',
  null,
  'DICLOFENAC SODIUM',
  null,
  null,
  null,
  null,
  null,
  null,
  2000,
  'SYP',
  null
);

select id from public.catalog_create_idempotent(
  '75000000-0000-4000-8000-000000000003',
  'ASIA-TONIC SP098',
  null,
  'K+B12',
  null,
  null,
  null,
  null,
  null,
  null,
  3000,
  'SYP',
  null
);

reset role;

select *
from app_private.reconcile_interaction_checker_mappings(
  '{
    "count": 6,
    "results": [
      {"id":"aspirin","name":"Aspirin","kind":"drug","brands":[]},
      {"id":"diclofenac","name":"Diclofenac","kind":"drug","brands":[]},
      {"id":"potassium","name":"Potassium","kind":"other","brands":[]},
      {"id":"vitamin-k","name":"Vitamin K","kind":"other","brands":[]},
      {"id":"vitamin-b12","name":"Vitamin B12","kind":"other","brands":[]},
      {"id":"niacin","name":"Niacin","kind":"drug","brands":[]}
    ]
  }'::jsonb,
  '2026-09-30T00:00:00Z'::timestamptz
);

do $provider_mapping_private$
begin
  if has_table_privilege(
    'authenticated',
    'app_private.interaction_checker_ingredient_mappings',
    'SELECT'
  ) then
    raise exception 'authenticated can read private global provider mappings';
  end if;

  if has_table_privilege(
    'authenticated',
    'app_private.interaction_checker_component_overrides',
    'SELECT'
  ) then
    raise exception 'authenticated can read private provider overrides';
  end if;
end
$provider_mapping_private$;

do $provider_mapping_rows$
declare
  aspirin_ingredient_id bigint;
  diclofenac_ingredient_id bigint;
  k_ingredient_id bigint;
  b12_ingredient_id bigint;
begin
  select id into aspirin_ingredient_id
  from app_private.catalog_ingredients
  where normalized_name = 'acetylsalicylic acid';

  select id into diclofenac_ingredient_id
  from app_private.catalog_ingredients
  where normalized_name = 'diclofenac sodium';

  select id into k_ingredient_id
  from app_private.catalog_ingredients
  where normalized_name = 'k';

  select id into b12_ingredient_id
  from app_private.catalog_ingredients
  where normalized_name = 'b12';

  if not exists (
    select 1
    from app_private.interaction_checker_ingredient_mappings
    where ingredient_id = aspirin_ingredient_id
      and status = 'mapped'
      and provider_substance_id = 'aspirin'
      and mapping_method = 'provider_alias'
      and confidence = 100
  ) then
    raise exception 'aspirin provider alias mapping was not created';
  end if;

  if not exists (
    select 1
    from app_private.interaction_checker_ingredient_mappings
    where ingredient_id = diclofenac_ingredient_id
      and status = 'mapped'
      and provider_substance_id = 'diclofenac'
      and mapping_method = 'salt_base'
  ) then
    raise exception 'diclofenac salt/base mapping was not created';
  end if;

  if not exists (
    select 1
    from app_private.interaction_checker_ingredient_mappings
    where ingredient_id = b12_ingredient_id
      and status = 'mapped'
      and provider_substance_id = 'vitamin-b12'
      and mapping_method = 'context'
  ) then
    raise exception 'B12 provider context mapping was not created';
  end if;

  if not exists (
    select 1
    from app_private.interaction_checker_ingredient_mappings
    where ingredient_id = k_ingredient_id
      and status = 'ambiguous'
      and provider_substance_id is null
      and candidate_substance_ids @> array['potassium','vitamin-k']::text[]
  ) then
    raise exception 'global K mapping was not preserved as ambiguous';
  end if;

  if not exists (
    select 1
    from app_private.interaction_checker_component_overrides o
    where o.product_id =
      '75000000-0000-4000-8000-000000000003'::uuid
      and o.ingredient_id = k_ingredient_id
      and o.status = 'mapped'
      and o.provider_substance_id = 'potassium'
      and o.mapping_method = 'context'
  ) then
    raise exception 'ASIA-TONIC K component override was not created';
  end if;
end
$provider_mapping_rows$;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

do $provider_mapping_rpc$
begin
  if not exists (
    select 1
    from public.catalog_ddi_ingredients(
      array['75000000-0000-4000-8000-000000000001'::uuid]
    )
    where coverage_status = 'trusted'
      and provider_mapping_status = 'mapped'
      and provider_substance_id = 'aspirin'
      and provider_substance_name = 'Aspirin'
      and provider_substance_kind = 'drug'
  ) then
    raise exception 'RPC did not expose aspirin provider identity';
  end if;

  if not exists (
    select 1
    from public.catalog_ddi_ingredients(
      array['75000000-0000-4000-8000-000000000002'::uuid]
    )
    where provider_mapping_status = 'mapped'
      and provider_substance_id = 'diclofenac'
      and provider_mapping_method = 'salt_base'
  ) then
    raise exception 'RPC did not expose diclofenac provider mapping';
  end if;

  if not exists (
    select 1
    from public.catalog_ddi_ingredients(
      array['75000000-0000-4000-8000-000000000003'::uuid]
    )
    where normalized_ingredient_name = 'k'
      and provider_mapping_status = 'mapped'
      and provider_substance_id = 'potassium'
      and provider_mapping_method = 'context'
  ) then
    raise exception 'RPC did not prioritize product-component override';
  end if;
end
$provider_mapping_rpc$;

reset role;

rollback;
