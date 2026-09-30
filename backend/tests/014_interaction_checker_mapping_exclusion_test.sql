\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

select id from public.catalog_create_idempotent(
  '76000000-0000-4000-8000-000000000001',
  'SP098 Glucosamine',
  null,
  'GLUCOSAMINE',
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

reset role;

do $exclusion_private$
begin
  if has_table_privilege(
    'authenticated',
    'app_private.interaction_checker_mapping_exclusions',
    'SELECT'
  ) then
    raise exception 'authenticated can read private mapping exclusions';
  end if;
end
$exclusion_private$;

select *
from app_private.reconcile_interaction_checker_mappings(
  '{
    "count": 1,
    "results": [
      {
        "id":"glucosamine",
        "name":"Glucosamine and chondroitin",
        "kind":"other",
        "brands":[]
      }
    ]
  }'::jsonb,
  '2026-09-30T00:00:00Z'::timestamptz
);

do $glucosamine_excluded$
declare
  target_ingredient_id bigint;
begin
  select id into target_ingredient_id
  from app_private.catalog_ingredients
  where normalized_name = 'glucosamine';

  if target_ingredient_id is null then
    raise exception 'synthetic glucosamine ingredient was not created';
  end if;

  if not exists (
    select 1
    from app_private.interaction_checker_ingredient_mappings
    where ingredient_id = target_ingredient_id
      and status = 'unmapped'
      and mapping_method = 'manual'
      and provider_substance_id is null
      and candidate_substance_ids @>
        array['glucosamine']::text[]
      and confidence = 100
  ) then
    raise exception 'glucosamine exclusion was not enforced';
  end if;
end
$glucosamine_excluded$;

-- A repeated provider reconciliation must preserve the manual exclusion.
select *
from app_private.reconcile_interaction_checker_mappings(
  '{
    "count": 1,
    "results": [
      {
        "id":"glucosamine",
        "name":"Glucosamine and chondroitin",
        "kind":"other",
        "brands":[]
      }
    ]
  }'::jsonb,
  '2026-10-01T00:00:00Z'::timestamptz
);

do $glucosamine_exclusion_persists$
declare
  target_ingredient_id bigint;
begin
  select id into target_ingredient_id
  from app_private.catalog_ingredients
  where normalized_name = 'glucosamine';

  if not exists (
    select 1
    from app_private.interaction_checker_ingredient_mappings
    where ingredient_id = target_ingredient_id
      and status = 'unmapped'
      and mapping_method = 'manual'
      and provider_substance_id is null
      and candidate_substance_ids @>
        array['glucosamine']::text[]
      and confidence = 100
  ) then
    raise exception 'glucosamine exclusion did not survive reconciliation';
  end if;
end
$glucosamine_exclusion_persists$;

rollback;
