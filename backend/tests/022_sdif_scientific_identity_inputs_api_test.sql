\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

do $sdif010_privileges$
begin
  if has_function_privilege(
    'anon',
    'public.catalog_sdif_scientific_identities(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'anon can execute catalog_sdif_scientific_identities';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.catalog_sdif_scientific_identities(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute catalog_sdif_scientific_identities';
  end if;
end
$sdif010_privileges$;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '22222222-2222-2222-2222-222222222222';

do $sdif010_non_owner$
begin
  begin
    perform *
    from public.catalog_sdif_scientific_identities(
      array['76000000-0000-4000-8000-000000000001'::uuid]
    );
    raise exception 'non-owner SDIF scientific input call unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
end
$sdif010_non_owner$;

reset role;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

do $sdif010_private_tables$
begin
  begin
    perform * from app_private.product_scientific_canonicalization_nodes;
    raise exception 'owner client can directly read scientific canonicalization nodes';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from app_private.scientific_ingredients;
    raise exception 'owner client can directly read scientific ingredient registry';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform * from app_private.scientific_ingredient_atc_codes;
    raise exception 'owner client can directly read scientific ATC metadata';
  exception
    when insufficient_privilege then null;
  end;
end
$sdif010_private_tables$;

reset role;

do $sdif010_no_atc_identity$
declare
  new_identity_id bigint;
begin
  insert into app_private.scientific_ingredients(
    preferred_name,
    normalized_preferred_name,
    category
  )
  values (
    'SDIF010 No ATC',
    app_private.scientific_name_key('SDIF010 No ATC'),
    'medicinal_substance'
  )
  returning id into new_identity_id;

  insert into app_private.scientific_ingredient_references(
    scientific_ingredient_id,
    reference_system,
    reference_key,
    reference_name,
    reference_version,
    reviewed_at,
    review_note
  )
  values (
    new_identity_id,
    'pubchem',
    'sdif010-no-atc',
    'SDIF010 No ATC',
    'synthetic-test-v1',
    timestamptz '2026-10-02 00:00:00+00',
    'Synthetic reviewed identity deliberately lacking ATC metadata.'
  );
end
$sdif010_no_atc_identity$;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

select id from public.catalog_create_idempotent(
  '76000000-0000-4000-8000-000000000001',
  'SDIF010 Complete',
  null,
  'Amoxicillin + Caffeine',
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
  '76000000-0000-4000-8000-000000000002',
  'SDIF010 Partial',
  null,
  'Amoxicillin + SDIF010 No ATC',
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
  '76000000-0000-4000-8000-000000000003',
  'SDIF010 No ATC Only',
  null,
  'SDIF010 No ATC',
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

select id from public.catalog_create_idempotent(
  '76000000-0000-4000-8000-000000000004',
  'SDIF010 Unreviewed',
  null,
  'SDIF010 UNREVIEWED COMPONENT',
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

select id from public.catalog_create_idempotent(
  '76000000-0000-4000-8000-000000000005',
  'SDIF010 Duplicate Identity',
  null,
  'Amoxicillin + Amoxicillin',
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

do $sdif010_contract$
declare
  complete_id constant uuid :=
    '76000000-0000-4000-8000-000000000001';
  partial_id constant uuid :=
    '76000000-0000-4000-8000-000000000002';
  no_atc_id constant uuid :=
    '76000000-0000-4000-8000-000000000003';
  unreviewed_id constant uuid :=
    '76000000-0000-4000-8000-000000000004';
  duplicate_identity_id constant uuid :=
    '76000000-0000-4000-8000-000000000005';
  missing_id constant uuid :=
    '76000000-0000-4000-8000-999999999999';
begin
  if (
    select count(*)
    from public.catalog_sdif_scientific_identities(array[complete_id])
    where coverage_status = 'complete'
      and product_exists
      and ingredient_count = 2
      and trusted_component_count = 2
      and atc_covered_component_count = 2
      and eligible_identity_count = 2
      and scientific_ingredient_id is not null
  ) <> 2 then
    raise exception 'complete product did not expose both reviewed ATC identities';
  end if;

  if (
    select string_agg(preferred_name, '|' order by identity_position)
    from public.catalog_sdif_scientific_identities(array[complete_id])
  ) <> 'Amoxicillin|Caffeine' then
    raise exception 'complete product scientific identity order is not deterministic';
  end if;

  if not exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[complete_id])
    where preferred_name = 'Amoxicillin'
      and reviewed_atc_codes = array['J01CA04']::text[]
  ) or not exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[complete_id])
    where preferred_name = 'Caffeine'
      and reviewed_atc_codes = array['N06BC01']::text[]
  ) then
    raise exception 'reviewed ATC metadata was not preserved per scientific identity';
  end if;

  if not exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[partial_id])
    where coverage_status = 'partial'
      and product_exists
      and ingredient_count = 2
      and trusted_component_count = 2
      and atc_covered_component_count = 1
      and eligible_identity_count = 1
      and preferred_name = 'Amoxicillin'
      and reviewed_atc_codes = array['J01CA04']::text[]
  ) then
    raise exception 'partial product did not retain its eligible reviewed identity';
  end if;

  if exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[partial_id])
    where preferred_name = 'SDIF010 No ATC'
       or reviewed_atc_codes is null
  ) then
    raise exception 'partial product leaked identity without reviewed ATC metadata';
  end if;

  if not exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[no_atc_id])
    where coverage_status = 'unmapped'
      and product_exists
      and ingredient_count = 1
      and trusted_component_count = 1
      and atc_covered_component_count = 0
      and eligible_identity_count = 0
      and scientific_ingredient_id is null
      and preferred_name is null
      and reviewed_atc_codes is null
  ) then
    raise exception 'reviewed identity without ATC was not kept unmapped';
  end if;

  if not exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[unreviewed_id])
    where coverage_status = 'unmapped'
      and product_exists
      and eligible_identity_count = 0
      and scientific_ingredient_id is null
      and preferred_name is null
      and reviewed_atc_codes is null
  ) then
    raise exception 'unreviewed component did not remain unexposed';
  end if;

  if not exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[missing_id])
    where coverage_status = 'missing'
      and not product_exists
      and canonicalization_status is null
      and ingredient_count = 0
      and trusted_component_count = 0
      and atc_covered_component_count = 0
      and eligible_identity_count = 0
      and scientific_ingredient_id is null
  ) then
    raise exception 'missing product was silently omitted or misclassified';
  end if;

  if (
    select count(*)
    from public.catalog_sdif_scientific_identities(array[duplicate_identity_id])
    where coverage_status = 'complete'
      and ingredient_count = 2
      and atc_covered_component_count = 2
      and eligible_identity_count = 1
      and preferred_name = 'Amoxicillin'
  ) <> 1 then
    raise exception 'repeated scientific identity was not deduplicated per product';
  end if;

  if (
    select count(*)
    from public.catalog_sdif_scientific_identities(
      array[partial_id, complete_id, partial_id, missing_id]
    )
  ) <> 4 then
    raise exception 'duplicate requested product was not deduplicated deterministically';
  end if;

  if exists (
    select 1
    from public.catalog_sdif_scientific_identities(
      array[partial_id, complete_id, partial_id, missing_id]
    )
    where product_id = partial_id
      and request_position <> 1
  ) then
    raise exception 'duplicate product did not retain first request position';
  end if;

  if not exists (
    select 1
    from public.catalog_sdif_scientific_identities(
      array[partial_id, complete_id, partial_id, missing_id]
    )
    where product_id = complete_id
      and request_position = 2
  ) or not exists (
    select 1
    from public.catalog_sdif_scientific_identities(
      array[partial_id, complete_id, partial_id, missing_id]
    )
    where product_id = missing_id
      and request_position = 4
  ) then
    raise exception 'deduplicated SDIF request ordering was not preserved';
  end if;

  if exists (
    select 1
    from public.catalog_sdif_scientific_identities(array[]::uuid[])
  ) then
    raise exception 'empty product request unexpectedly returned rows';
  end if;

  begin
    perform *
    from public.catalog_sdif_scientific_identities(null::uuid[]);
    raise exception 'null request was accepted';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    perform *
    from public.catalog_sdif_scientific_identities(
      array[complete_id, null::uuid]
    );
    raise exception 'request containing null product id was accepted';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    perform *
    from public.catalog_sdif_scientific_identities(
      array_fill(complete_id, array[51])
    );
    raise exception 'request above the hard product bound was accepted';
  exception
    when invalid_parameter_value then null;
  end;
end
$sdif010_contract$;

reset role;
rollback;
