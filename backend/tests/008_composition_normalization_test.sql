\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

do $$
declare
  first_id uuid;
  second_id uuid;
  lower_case_id uuid;
  b12_id uuid;
  cyanocobalamin_id uuid;
  review_id uuid;
  unresolved_id uuid;
  first_key text;
  second_key text;
  first_revision bigint;
  first_updated_at timestamptz;
begin
  select id into first_id
  from public.catalog_create_idempotent(
    '70000000-0000-4000-8000-000000000001',
    'Combo A',
    null,
    'METFORMIN + SITAGLIPTIN',
    null,
    '50 MG + 1000 MG',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into second_id
  from public.catalog_create_idempotent(
    '70000000-0000-4000-8000-000000000002',
    'Combo B',
    null,
    'SITAGLIPTIN+METFORMIN',
    null,
    '1000 MG + 50 MG',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into lower_case_id
  from public.catalog_create_idempotent(
    '70000000-0000-4000-8000-000000000003',
    'Combo C',
    null,
    'metformin + sitagliptin',
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

  select id into b12_id
  from public.catalog_create_idempotent(
    '70000000-0000-4000-8000-000000000004',
    'B12 Generic',
    null,
    'VITAMIN B12',
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

  select id into cyanocobalamin_id
  from public.catalog_create_idempotent(
    '70000000-0000-4000-8000-000000000005',
    'B12 Chemical',
    null,
    'CYANOCOBALAMIN',
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

  select id into review_id
  from public.catalog_create_idempotent(
    '70000000-0000-4000-8000-000000000006',
    'Review Case',
    null,
    'DICYCLOMINE HCL (DICYCLOVERINE HCL)',
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

  select id into unresolved_id
  from public.catalog_create_idempotent(
    '70000000-0000-4000-8000-000000000007',
    'Unresolved Case',
    null,
    '+ METFORMIN',
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

  select ingredient_set_key
    into first_key
  from app_private.product_composition_normalization
  where product_id = first_id
    and status = 'auto_verified';

  select ingredient_set_key
    into second_key
  from app_private.product_composition_normalization
  where product_id = second_id
    and status = 'auto_verified';

  if first_key is null or second_key is null or first_key <> second_key then
    raise exception 'ingredient set key is not order independent';
  end if;

  if (
    select count(*)
    from app_private.product_ingredients
    where product_id = first_id
  ) <> 2 then
    raise exception 'first combination did not produce two ingredient links';
  end if;

  if (
    select count(distinct ingredient_id)
    from app_private.product_ingredients
    where product_id in (first_id, second_id, lower_case_id)
  ) <> 2 then
    raise exception 'lexical spelling/case variants created duplicate ingredients';
  end if;

  if not exists (
    select 1
    from app_private.catalog_ingredient_alias_spellings
    where normalized_alias =
      app_private.catalog_search_normalize('METFORMIN')
      and spelling = 'metformin'
  ) then
    raise exception 'observed lexical alias spelling was not retained';
  end if;

  if (
    select ingredient_set_key
    from app_private.product_composition_normalization
    where product_id = b12_id
  ) = (
    select ingredient_set_key
    from app_private.product_composition_normalization
    where product_id = cyanocobalamin_id
  ) then
    raise exception 'semantic synonym candidates were merged automatically';
  end if;

  if (
    select status
    from app_private.product_composition_normalization
    where product_id = review_id
  ) <> 'needs_review' then
    raise exception 'parenthesized synonym candidate was not quarantined for review';
  end if;

  if (
    select status
    from app_private.product_composition_normalization
    where product_id = unresolved_id
  ) <> 'unresolved' then
    raise exception 'empty composition component was not marked unresolved';
  end if;

  if (
    select ingredient_set_key
    from app_private.product_composition_normalization
    where product_id = unresolved_id
  ) is not null then
    raise exception 'unresolved composition unexpectedly has a trusted set key';
  end if;

  if (
    select composition
    from public.products
    where id = first_id
  ) <> 'METFORMIN + SITAGLIPTIN' then
    raise exception 'raw product composition was rewritten';
  end if;

  select revision, updated_at
    into first_revision, first_updated_at
  from public.products
  where id = first_id;

  perform app_private.refresh_product_composition_normalization(
    first_id,
    'METFORMIN + SITAGLIPTIN'
  );

  if exists (
    select 1
    from public.products
    where id = first_id
      and (
        revision <> first_revision
        or updated_at <> first_updated_at
        or composition <> 'METFORMIN + SITAGLIPTIN'
      )
  ) then
    raise exception 'derived refresh mutated product revision/source state';
  end if;

  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  perform *
  from public.catalog_update(
    first_id,
    first_revision,
    'Combo A',
    null,
    'METFORMIN',
    null,
    '1000 MG',
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
    select count(*)
    from app_private.product_ingredients
    where product_id = first_id
  ) <> 1 then
    raise exception 'composition update did not replace derived ingredient links';
  end if;

  if (
    select status
    from app_private.product_composition_normalization
    where product_id = first_id
  ) <> 'auto_verified' then
    raise exception 'updated simple composition did not normalize automatically';
  end if;

  if (
    select source_composition
    from app_private.product_composition_normalization
    where product_id = first_id
  ) <> 'METFORMIN' then
    raise exception 'normalization snapshot did not follow composition update';
  end if;

  if (
    select revision
    from public.products
    where id = first_id
  ) <> first_revision + 1 then
    raise exception 'normal catalog update revision semantics changed';
  end if;
end
$$;

rollback;
