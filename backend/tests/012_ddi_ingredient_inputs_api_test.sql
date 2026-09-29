\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

do $ddi_ingredient_privileges$
begin
  if has_function_privilege(
    'anon',
    'public.catalog_ddi_ingredients(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'anon can execute catalog_ddi_ingredients';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.catalog_ddi_ingredients(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute catalog_ddi_ingredients';
  end if;
end
$ddi_ingredient_privileges$;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '22222222-2222-2222-2222-222222222222';

do $ddi_non_owner$
begin
  begin
    perform *
    from public.catalog_ddi_ingredients(
      array['74000000-0000-4000-8000-000000000001'::uuid]
    );
    raise exception 'non-owner DDI ingredient call unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
end
$ddi_non_owner$;

reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

do $ddi_private_registry_owner$
begin
  begin
    perform *
    from app_private.catalog_ingredients;
    raise exception 'owner client can directly read private ingredient registry';
  exception
    when insufficient_privilege then null;
  end;
end
$ddi_private_registry_owner$;

perform public.catalog_create_idempotent(
  '74000000-0000-4000-8000-000000000001',
  'SP031 Single',
  null,
  'SP031ACTIVEA',
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

perform public.catalog_create_idempotent(
  '74000000-0000-4000-8000-000000000002',
  'SP031 Combo',
  null,
  'SP031ACTIVEA + SP031ACTIVEB',
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

perform public.catalog_create_idempotent(
  '74000000-0000-4000-8000-000000000003',
  'SP031 Needs Review',
  null,
  'SP031 REVIEW (SP031 ALIAS)',
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

perform public.catalog_create_idempotent(
  '74000000-0000-4000-8000-000000000004',
  'SP031 Unresolved',
  null,
  '+ SP031ACTIVEA',
  null,
  null,
  null,
  null,
  null,
  null,
  4000,
  'SYP',
  null
);

perform public.catalog_create_idempotent(
  '74000000-0000-4000-8000-000000000005',
  'SP031 Canonical',
  null,
  'SP031CANONICAL',
  null,
  null,
  null,
  null,
  null,
  null,
  5000,
  'SYP',
  null
);

reset role;

do $ddi_verified_alias_setup$
declare
  canonical_ingredient_id bigint;
begin
  select i.id
    into canonical_ingredient_id
  from app_private.catalog_ingredients i
  where i.normalized_name =
    app_private.catalog_search_normalize('SP031CANONICAL');

  if canonical_ingredient_id is null then
    raise exception 'canonical fixture ingredient was not created';
  end if;

  insert into app_private.catalog_ingredient_aliases(
    normalized_alias,
    ingredient_id,
    alias_kind,
    preferred_spelling
  )
  values (
    app_private.catalog_search_normalize('SP031 VERIFIED SYNONYM'),
    canonical_ingredient_id,
    'verified_synonym',
    'SP031 VERIFIED SYNONYM'
  );
end
$ddi_verified_alias_setup$;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

perform public.catalog_create_idempotent(
  '74000000-0000-4000-8000-000000000006',
  'SP031 Verified Synonym',
  null,
  'SP031 VERIFIED SYNONYM',
  null,
  null,
  null,
  null,
  null,
  null,
  6000,
  'SYP',
  null
);

do $ddi_ingredient_inputs$
declare
  single_id constant uuid :=
    '74000000-0000-4000-8000-000000000001';
  combo_id constant uuid :=
    '74000000-0000-4000-8000-000000000002';
  review_id constant uuid :=
    '74000000-0000-4000-8000-000000000003';
  unresolved_id constant uuid :=
    '74000000-0000-4000-8000-000000000004';
  synonym_id constant uuid :=
    '74000000-0000-4000-8000-000000000006';
  missing_id constant uuid :=
    '74000000-0000-4000-8000-999999999999';
begin
  if (
    select count(*)
    from public.catalog_ddi_ingredients(array[combo_id])
    where coverage_status = 'trusted'
      and normalization_status = 'auto_verified'
      and product_exists
      and ingredient_id is not null
  ) <> 2 then
    raise exception 'trusted combination did not expose both ingredients';
  end if;

  if (
    select string_agg(normalized_ingredient_name, '|' order by component_index)
    from public.catalog_ddi_ingredients(array[combo_id])
  ) <> 'sp031activea|sp031activeb' then
    raise exception 'trusted combination ingredient ordering is not deterministic';
  end if;

  if not exists (
    select 1
    from public.catalog_ddi_ingredients(array[synonym_id])
    where coverage_status = 'trusted'
      and normalization_status = 'high_confidence'
      and ingredient_name = 'SP031CANONICAL'
      and normalized_ingredient_name = 'sp031canonical'
  ) then
    raise exception 'high-confidence verified synonym was not exposed as trusted';
  end if;

  if not exists (
    select 1
    from public.catalog_ddi_ingredients(array[review_id])
    where coverage_status = 'needs_review'
      and normalization_status = 'needs_review'
      and product_exists
      and ingredient_id is null
      and ingredient_name is null
      and normalized_ingredient_name is null
  ) then
    raise exception 'needs-review product leaked an untrusted ingredient identity';
  end if;

  if not exists (
    select 1
    from public.catalog_ddi_ingredients(array[unresolved_id])
    where coverage_status = 'unresolved'
      and normalization_status = 'unresolved'
      and product_exists
      and ingredient_id is null
  ) then
    raise exception 'unresolved product did not stay explicitly uncheckable';
  end if;

  if not exists (
    select 1
    from public.catalog_ddi_ingredients(array[missing_id])
    where coverage_status = 'missing'
      and normalization_status is null
      and not product_exists
      and ingredient_id is null
  ) then
    raise exception 'missing product was silently omitted or misclassified';
  end if;

  if (
    select count(*)
    from public.catalog_ddi_ingredients(
      array[combo_id, single_id, combo_id, missing_id]
    )
  ) <> 4 then
    raise exception 'duplicate request was not deduplicated deterministically';
  end if;

  if exists (
    select 1
    from public.catalog_ddi_ingredients(
      array[combo_id, single_id, combo_id, missing_id]
    )
    where product_id = combo_id
      and request_position <> 1
  ) then
    raise exception 'duplicate product did not retain first request position';
  end if;

  if not exists (
    select 1
    from public.catalog_ddi_ingredients(
      array[combo_id, single_id, combo_id, missing_id]
    )
    where product_id = single_id
      and request_position = 2
  ) or not exists (
    select 1
    from public.catalog_ddi_ingredients(
      array[combo_id, single_id, combo_id, missing_id]
    )
    where product_id = missing_id
      and request_position = 4
  ) then
    raise exception 'deduplicated request ordering was not preserved';
  end if;

  if exists (
    select 1
    from public.catalog_ddi_ingredients(array[]::uuid[])
  ) then
    raise exception 'empty product request unexpectedly returned rows';
  end if;

  begin
    perform *
    from public.catalog_ddi_ingredients(null::uuid[]);
    raise exception 'null request was accepted';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    perform *
    from public.catalog_ddi_ingredients(
      array[single_id, null::uuid]
    );
    raise exception 'request containing null product id was accepted';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    perform *
    from public.catalog_ddi_ingredients(
      array_fill(single_id, array[51])
    );
    raise exception 'request above the hard product bound was accepted';
  exception
    when invalid_parameter_value then null;
  end;
end
$ddi_ingredient_inputs$;

reset role;

rollback;
