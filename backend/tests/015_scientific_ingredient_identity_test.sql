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
  'SP039 Diphenhydramine',
  null,
  'DIPHENHYDRAMINE HCL',
  null,
  '25 MG',
  'Tablet',
  null,
  null,
  null,
  1000,
  'SYP',
  null
);

select id from public.catalog_create_idempotent(
  '76000000-0000-4000-8000-000000000002',
  'SP039 Paracetamol',
  null,
  'PARACETAMOL',
  null,
  '500 MG',
  'Tablet',
  null,
  null,
  null,
  2000,
  'SYP',
  null
);

select id from public.catalog_create_idempotent(
  '76000000-0000-4000-8000-000000000003',
  'SP039 Ambiguous K',
  null,
  'K',
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
  'SP039 Botanical',
  null,
  'ECHINACEA EXTRACT',
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

reset role;

do $scientific_identity_model$
declare
  diphenhydramine_lexical_id bigint;
  paracetamol_lexical_id bigint;
  k_lexical_id bigint;
  botanical_lexical_id bigint;
  diphenhydramine_lexical_name text;
  diphenhydramine_id bigint;
  diphenhydramine_hcl_id bigint;
  paracetamol_id bigint;
  potassium_id bigint;
  vitamin_k_id bigint;
  equivalence_before jsonb;
  equivalence_after jsonb;
begin
  select pi.ingredient_id, i.name
    into diphenhydramine_lexical_id, diphenhydramine_lexical_name
  from app_private.product_ingredients pi
  join app_private.catalog_ingredients i on i.id = pi.ingredient_id
  where pi.product_id = '76000000-0000-4000-8000-000000000001'::uuid
    and pi.component_index = 1;

  select pi.ingredient_id into paracetamol_lexical_id
  from app_private.product_ingredients pi
  where pi.product_id = '76000000-0000-4000-8000-000000000002'::uuid
    and pi.component_index = 1;

  select pi.ingredient_id into k_lexical_id
  from app_private.product_ingredients pi
  where pi.product_id = '76000000-0000-4000-8000-000000000003'::uuid
    and pi.component_index = 1;

  select pi.ingredient_id into botanical_lexical_id
  from app_private.product_ingredients pi
  where pi.product_id = '76000000-0000-4000-8000-000000000004'::uuid
    and pi.component_index = 1;

  select to_jsonb(e) into equivalence_before
  from app_private.product_pharmaceutical_equivalence e
  where e.product_id = '76000000-0000-4000-8000-000000000002'::uuid;

  insert into app_private.scientific_ingredients(
    preferred_name,
    normalized_preferred_name,
    category
  )
  values (
    'Diphenhydramine',
    app_private.scientific_name_key('Diphenhydramine'),
    'medicinal_substance'
  )
  returning id into diphenhydramine_id;

  insert into app_private.scientific_ingredients(
    preferred_name,
    normalized_preferred_name,
    category,
    parent_scientific_ingredient_id,
    parent_relation
  )
  values (
    'Diphenhydramine hydrochloride',
    app_private.scientific_name_key('Diphenhydramine hydrochloride'),
    'medicinal_substance',
    diphenhydramine_id,
    'salt_of'
  )
  returning id into diphenhydramine_hcl_id;

  insert into app_private.scientific_ingredients(
    preferred_name,
    normalized_preferred_name,
    category
  )
  values (
    'Paracetamol',
    app_private.scientific_name_key('Paracetamol'),
    'medicinal_substance'
  )
  returning id into paracetamol_id;

  insert into app_private.scientific_ingredients(
    preferred_name,
    normalized_preferred_name,
    category
  )
  values (
    'Potassium',
    app_private.scientific_name_key('Potassium'),
    'mineral'
  )
  returning id into potassium_id;

  insert into app_private.scientific_ingredients(
    preferred_name,
    normalized_preferred_name,
    category
  )
  values (
    'Vitamin K',
    app_private.scientific_name_key('Vitamin K'),
    'vitamin'
  )
  returning id into vitamin_k_id;

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
    paracetamol_id,
    'who_inn',
    'PARACETAMOL',
    'Paracetamol',
    'synthetic-test',
    '2026-10-01T00:00:00Z'::timestamptz,
    'Synthetic SP-039 regression fixture.'
  );

  insert into app_private.scientific_ingredient_atc_codes(
    scientific_ingredient_id,
    atc_code,
    atc_name,
    reference_version,
    reviewed_at,
    review_note
  )
  values (
    paracetamol_id,
    'N02BE01',
    'Paracetamol',
    'synthetic-test',
    '2026-10-01T00:00:00Z'::timestamptz,
    'Synthetic SP-039 regression fixture.'
  );

  insert into app_private.scientific_ingredient_aliases(
    normalized_alias,
    scientific_ingredient_id,
    alias_text,
    alias_kind,
    reference_source,
    reference_version,
    reviewed_at,
    review_note
  )
  values (
    app_private.scientific_name_key('Diphenhydramine HCl'),
    diphenhydramine_hcl_id,
    'Diphenhydramine HCl',
    'legacy_name',
    'SP-039 synthetic review',
    '1',
    '2026-10-01T00:00:00Z'::timestamptz,
    'Synthetic reviewed abbreviation fixture.'
  );

  insert into app_private.catalog_ingredient_scientific_mappings(
    ingredient_id,
    scientific_ingredient_id,
    status,
    mapping_method,
    confidence,
    reference_source,
    reference_version,
    reviewed_at,
    review_note
  )
  values
    (
      diphenhydramine_lexical_id,
      diphenhydramine_hcl_id,
      'verified',
      'reviewed_alias',
      100,
      'SP-039 synthetic review',
      '1',
      '2026-10-01T00:00:00Z'::timestamptz,
      'Synthetic reviewed salt-form fixture.'
    ),
    (
      paracetamol_lexical_id,
      paracetamol_id,
      'verified',
      'exact_reference',
      100,
      'WHO INN synthetic fixture',
      'synthetic-test',
      '2026-10-01T00:00:00Z'::timestamptz,
      'Synthetic exact-reference fixture.'
    ),
    (
      k_lexical_id,
      null,
      'needs_review',
      'context',
      50,
      'SP-039 synthetic review',
      '1',
      null,
      'K is overloaded and requires product-specific scientific review.'
    ),
    (
      botanical_lexical_id,
      null,
      'unresolved',
      'none',
      0,
      null,
      null,
      '2026-10-01T00:00:00Z'::timestamptz,
      'Reviewed fixture remains unresolved rather than guessed.'
    );

  insert into app_private.catalog_ingredient_scientific_review_candidates(
    ingredient_id,
    scientific_ingredient_id,
    mapping_method,
    confidence,
    reference_source,
    reference_version,
    candidate_note
  )
  values
    (
      k_lexical_id,
      potassium_id,
      'context',
      50,
      'SP-039 synthetic review',
      '1',
      'K may denote potassium in some product contexts.'
    ),
    (
      k_lexical_id,
      vitamin_k_id,
      'context',
      50,
      'SP-039 synthetic review',
      '1',
      'K may denote Vitamin K in some product contexts.'
    );

  if not exists (
    select 1
    from app_private.scientific_ingredients
    where id = diphenhydramine_hcl_id
      and parent_scientific_ingredient_id = diphenhydramine_id
      and parent_relation = 'salt_of'
  ) then
    raise exception 'salt identity did not retain explicit parent relationship';
  end if;

  if not exists (
    select 1
    from app_private.catalog_ingredient_scientific_mappings
    where ingredient_id = diphenhydramine_lexical_id
      and scientific_ingredient_id = diphenhydramine_hcl_id
      and status = 'verified'
      and confidence = 100
  ) then
    raise exception 'reviewed diphenhydramine HCl mapping was not retained';
  end if;

  if (
    select count(*)
    from app_private.catalog_ingredient_scientific_review_candidates
    where ingredient_id = k_lexical_id
  ) <> 2 then
    raise exception 'ambiguous K identity did not retain multiple candidates';
  end if;

  if not exists (
    select 1
    from app_private.catalog_ingredient_scientific_mappings
    where ingredient_id = botanical_lexical_id
      and scientific_ingredient_id is null
      and status = 'unresolved'
      and reviewed_at is not null
  ) then
    raise exception 'reviewed unresolved botanical received a guessed identity';
  end if;

  if (
    select composition
    from public.products
    where id = '76000000-0000-4000-8000-000000000001'::uuid
  ) <> 'DIPHENHYDRAMINE HCL' then
    raise exception 'scientific mapping rewrote raw product composition';
  end if;

  if not exists (
    select 1
    from app_private.catalog_ingredients
    where id = diphenhydramine_lexical_id
      and name = diphenhydramine_lexical_name
      and normalized_name =
        app_private.catalog_search_normalize('DIPHENHYDRAMINE HCL')
  ) then
    raise exception 'scientific mapping changed the SP-025 lexical identity';
  end if;

  select to_jsonb(e) into equivalence_after
  from app_private.product_pharmaceutical_equivalence e
  where e.product_id = '76000000-0000-4000-8000-000000000002'::uuid;

  if equivalence_after is distinct from equivalence_before then
    raise exception 'scientific mapping changed existing equivalence state';
  end if;

  if not exists (
    select 1
    from app_private.scientific_ingredient_references
    where scientific_ingredient_id = paracetamol_id
      and reference_system = 'who_inn'
      and reference_key = 'PARACETAMOL'
  ) then
    raise exception 'scientific reference metadata was not retained';
  end if;

  if not exists (
    select 1
    from app_private.scientific_ingredient_atc_codes
    where scientific_ingredient_id = paracetamol_id
      and atc_code = 'N02BE01'
  ) then
    raise exception 'optional ATC metadata was not retained';
  end if;

  if app_private.scientific_name_key('Alpha-Beta') =
     app_private.scientific_name_key('Alpha Beta') then
    raise exception 'scientific identity key discarded punctuation';
  end if;

  begin
    insert into app_private.scientific_ingredients(
      preferred_name,
      normalized_preferred_name,
      category
    )
    values (
      'PARACETAMOL',
      app_private.scientific_name_key('PARACETAMOL'),
      'medicinal_substance'
    );
    raise exception 'duplicate canonical normalized name was accepted';
  exception
    when unique_violation then null;
  end;

  begin
    insert into app_private.scientific_ingredient_references(
      scientific_ingredient_id,
      reference_system,
      reference_key,
      reference_name,
      reviewed_at
    )
    values (
      diphenhydramine_id,
      'who_inn',
      'PARACETAMOL',
      'Wrong identity fixture',
      '2026-10-01T00:00:00Z'::timestamptz
    );
    raise exception 'one external reference key mapped to multiple identities';
  exception
    when unique_violation then null;
  end;

  begin
    insert into app_private.scientific_ingredient_aliases(
      normalized_alias,
      scientific_ingredient_id,
      alias_text,
      alias_kind,
      reference_source,
      reviewed_at
    )
    values (
      app_private.scientific_name_key('Diphenhydramine HCl'),
      paracetamol_id,
      'Diphenhydramine HCl',
      'legacy_name',
      'SP-039 collision fixture',
      '2026-10-01T00:00:00Z'::timestamptz
    );
    raise exception 'one reviewed alias mapped to multiple identities';
  exception
    when unique_violation then null;
  end;

  begin
    update app_private.scientific_ingredients
    set
      parent_scientific_ingredient_id = diphenhydramine_hcl_id,
      parent_relation = 'derivative_of'
    where id = diphenhydramine_id;
    raise exception 'scientific parent cycle was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into app_private.scientific_ingredients(
      preferred_name,
      normalized_preferred_name,
      category,
      parent_relation
    )
    values (
      'Broken Parent Fixture',
      app_private.scientific_name_key('Broken Parent Fixture'),
      'other',
      'salt_of'
    );
    raise exception 'parent relation without parent identity was accepted';
  exception
    when check_violation then null;
  end;

  begin
    update app_private.catalog_ingredient_scientific_mappings
    set
      scientific_ingredient_id = potassium_id,
      status = 'verified',
      mapping_method = 'manual',
      confidence = 100,
      reference_source = 'SP-039 invalid resolution fixture',
      reviewed_at = '2026-10-01T00:00:00Z'::timestamptz,
      review_note = 'Candidate rows must be cleared before resolution.'
    where ingredient_id = k_lexical_id;
    raise exception 'needs-review mapping resolved while candidates remained';
  exception
    when foreign_key_violation then null;
  end;

  delete from app_private.catalog_ingredient_scientific_review_candidates
  where ingredient_id = k_lexical_id;

  delete from app_private.catalog_ingredient_scientific_mappings
  where ingredient_id = k_lexical_id;

  begin
    insert into app_private.catalog_ingredient_scientific_mappings(
      ingredient_id,
      scientific_ingredient_id,
      status,
      mapping_method,
      confidence,
      reference_source,
      reviewed_at,
      review_note
    )
    values (
      k_lexical_id,
      null,
      'verified',
      'manual',
      100,
      'SP-039 invalid fixture',
      '2026-10-01T00:00:00Z'::timestamptz,
      'Must fail because verified requires a scientific identity.'
    );
    raise exception 'verified mapping without scientific identity was accepted';
  exception
    when check_violation then null;
  end;

  begin
    insert into app_private.catalog_ingredient_scientific_mappings(
      ingredient_id,
      scientific_ingredient_id,
      status,
      mapping_method,
      confidence,
      reference_source,
      reviewed_at,
      review_note
    )
    values (
      k_lexical_id,
      paracetamol_id,
      'unresolved',
      'none',
      0,
      null,
      '2026-10-01T00:00:00Z'::timestamptz,
      'Must fail because unresolved cannot carry an accepted identity.'
    );
    raise exception 'unresolved mapping carried a scientific identity';
  exception
    when check_violation then null;
  end;

  insert into app_private.catalog_ingredient_scientific_mappings(
    ingredient_id,
    scientific_ingredient_id,
    status,
    mapping_method,
    confidence,
    reference_source,
    reviewed_at,
    review_note
  )
  values (
    k_lexical_id,
    null,
    'needs_review',
    'context',
    50,
    'SP-039 synthetic review',
    '2026-10-01T00:00:00Z'::timestamptz,
    'K remains review-required after invalid-shape regressions.'
  );
end
$scientific_identity_model$;

do $scientific_identity_private_access$
declare
  table_name text;
  role_name text;
  rls_enabled boolean;
begin
  foreach role_name in array array['anon', 'authenticated']
  loop
    foreach table_name in array array[
      'app_private.scientific_ingredients',
      'app_private.scientific_ingredient_references',
      'app_private.scientific_ingredient_atc_codes',
      'app_private.scientific_ingredient_aliases',
      'app_private.catalog_ingredient_scientific_mappings',
      'app_private.catalog_ingredient_scientific_review_candidates'
    ]
    loop
      if has_table_privilege(role_name, table_name, 'SELECT')
         or has_table_privilege(role_name, table_name, 'INSERT')
         or has_table_privilege(role_name, table_name, 'UPDATE')
         or has_table_privilege(role_name, table_name, 'DELETE') then
        raise exception '% has direct access to private table %',
          role_name,
          table_name;
      end if;

      select c.relrowsecurity
        into rls_enabled
      from pg_catalog.pg_class c
      where c.oid = table_name::regclass;

      if not rls_enabled then
        raise exception 'RLS is disabled on private table %', table_name;
      end if;
    end loop;
  end loop;
end
$scientific_identity_private_access$;

rollback;
