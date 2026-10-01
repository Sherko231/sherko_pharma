\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

do $embedded_component_parser$
declare
  r record;
  c record;
begin
  select * into r
  from app_private.scientific_parse_embedded_component(
    'alprazolam 0.5mg / tab'
  );

  if r.raw_component <> 'alprazolam 0.5mg / tab'
     or r.ingredient_candidate <> 'Alprazolam'
     or r.normalized_amount <> 0.5
     or r.normalized_unit <> 'mg'
     or r.per_amount is not null
     or r.per_unit is not null
     or r.presentation <> 'tablet'
     or r.suffix_kind <> 'presentation'
     or r.parse_status <> 'deterministic'
     or r.parser_version <> 1 then
    raise exception 'alprazolam embedded presentation parse failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_embedded_component(
    'amoxicilline 250mg / 5ml'
  );

  if r.ingredient_candidate <> 'Amoxicilline'
     or r.normalized_amount <> 250
     or r.normalized_unit <> 'mg'
     or r.per_amount <> 5
     or r.per_unit <> 'ml'
     or r.presentation is not null
     or r.suffix_kind <> 'denominator'
     or r.parse_status <> 'deterministic' then
    raise exception 'amoxicilline concentration parse failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_embedded_component(
    'dextropropoxyphene 75mg / amp'
  );

  if r.ingredient_candidate <> 'Dextropropoxyphene'
     or r.normalized_amount <> 75
     or r.normalized_unit <> 'mg'
     or r.presentation <> 'ampoule'
     or r.parse_status <> 'deterministic' then
    raise exception 'ampoule presentation parse failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_embedded_component(
    'Vitamin B12 1000mcg'
  );

  if r.ingredient_candidate <> 'Vitamin B12'
     or r.normalized_amount <> 1
     or r.normalized_unit <> 'mg'
     or r.parse_status <> 'needs_review'
     or not ('ingredient_candidate_needs_review' = any(r.review_reasons)) then
    raise exception 'SP-040 numeric ingredient review boundary was not preserved: %',
      to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_embedded_component(
    'paracetamol 500mg / bottle'
  );

  if r.parse_status <> 'needs_review'
     or not ('unsupported_embedded_denominator_or_presentation' = any(r.review_reasons)) then
    raise exception 'unsupported presentation was not quarantined: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_embedded_component('paracetamol');

  if r.ingredient_candidate <> 'Paracetamol'
     or r.parse_status <> 'not_present'
     or not ('no_embedded_strength' = any(r.review_reasons)) then
    raise exception 'non-contaminated component state failed: %', to_jsonb(r);
  end if;

  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    'amoxicilline 250mg / 5ml',
    '50 MG/ML'
  );

  if c.comparison_status <> 'matches'
     or c.embedded_strength_key <> 'mg/ml:50'
     or c.source_strength_key <> 'mg/ml:50' then
    raise exception 'equivalent concentration comparison failed: %', to_jsonb(c);
  end if;
end
$embedded_component_parser$;

do $embedded_combination_parser$
declare
  first_component record;
  second_component record;
  c record;
begin
  select * into first_component
  from app_private.scientific_parse_embedded_composition(
    'amoxicillin 125mg+clavulanic acid 31.25mg / 5ml'
  )
  where component_index = 1;

  select * into second_component
  from app_private.scientific_parse_embedded_composition(
    'amoxicillin 125mg+clavulanic acid 31.25mg / 5ml'
  )
  where component_index = 2;

  if first_component.ingredient_candidate <> 'Amoxicillin'
     or first_component.normalized_amount <> 125
     or first_component.per_amount <> 5
     or first_component.per_unit <> 'ml'
     or first_component.parse_status <> 'deterministic'
     or second_component.ingredient_candidate <> 'Clavulanic acid'
     or second_component.normalized_amount <> 31.25
     or second_component.per_amount <> 5
     or second_component.per_unit <> 'ml'
     or second_component.parse_status <> 'deterministic' then
    raise exception 'shared denominator combination parse failed: first %, second %',
      to_jsonb(first_component), to_jsonb(second_component);
  end if;

  if app_private.scientific_embedded_strength_vector_key(
    'amoxicillin 125mg+clavulanic acid 31.25mg / 5ml'
  ) <> 'mg/ml:25|mg/ml:6.25' then
    raise exception 'embedded combination vector key failed';
  end if;

  select * into first_component
  from app_private.scientific_parse_embedded_composition(
    'amoxicillin+clavulanic acid 31.25mg / 5ml'
  )
  where component_index = 1;

  select * into second_component
  from app_private.scientific_parse_embedded_composition(
    'amoxicillin+clavulanic acid 31.25mg / 5ml'
  )
  where component_index = 2;

  if first_component.parse_status <> 'needs_review'
     or second_component.parse_status <> 'needs_review'
     or not ('ambiguous_multi_component_embedded_strength' = any(first_component.review_reasons))
     or not ('ambiguous_multi_component_embedded_strength' = any(second_component.review_reasons)) then
    raise exception 'ambiguous partial combination was not quarantined';
  end if;

  if app_private.scientific_embedded_strength_vector_key(
    'amoxicillin+clavulanic acid 31.25mg / 5ml'
  ) is not null then
    raise exception 'ambiguous combination produced a trusted vector key';
  end if;

  select * into first_component
  from app_private.scientific_parse_embedded_composition(
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE) 500mg'
  )
  limit 1;

  if first_component.parse_status <> 'needs_review'
     or not ('grouped_plus_requires_sp043' = any(first_component.review_reasons)) then
    raise exception 'grouped plus expression was not reserved for SP-043: %',
      to_jsonb(first_component);
  end if;

  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    'amoxicillin 125mg+clavulanic acid 31.25mg / 5ml',
    '125 MG+31.25 MG/5ML.'
  );

  if c.comparison_status <> 'matches'
     or c.embedded_strength_key <> 'mg/ml:25|mg/ml:6.25'
     or c.source_strength_key <> 'mg/ml:25|mg/ml:6.25' then
    raise exception 'combination source-strength comparison failed: %', to_jsonb(c);
  end if;
end
$embedded_combination_parser$;

do $embedded_source_conflicts$
declare
  c record;
begin
  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    'amoxicilline 250mg / 5ml',
    '125 MG/5ML'
  );

  if c.comparison_status <> 'conflicts'
     or c.embedded_strength_key <> 'mg/ml:50'
     or c.source_strength_key <> 'mg/ml:25' then
    raise exception 'source conflict was not exposed: %', to_jsonb(c);
  end if;

  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    'alprazolam 0.5mg / tab',
    '0.5 MG/CTD TAB.'
  );

  if c.comparison_status <> 'matches'
     or c.embedded_strength_key <> 'mg:0.5'
     or c.source_strength_key <> 'mg:0.5' then
    raise exception 'presentation-insensitive strength comparison failed: %', to_jsonb(c);
  end if;

  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    'alprazolam 0.5mg / tab',
    null
  );

  if c.comparison_status <> 'source_missing'
     or c.embedded_strength_key <> 'mg:0.5'
     or c.source_strength_key is not null then
    raise exception 'missing source strength state failed: %', to_jsonb(c);
  end if;

  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    'alprazolam 0.5mg / tab',
    'MEN'
  );

  if c.comparison_status <> 'source_unparseable'
     or c.embedded_strength_key <> 'mg:0.5'
     or c.source_strength_key is not null then
    raise exception 'unparseable source strength state failed: %', to_jsonb(c);
  end if;

  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    'amoxicillin+clavulanic acid 31.25mg / 5ml',
    '125 MG+31.25 MG/5ML.'
  );

  if c.comparison_status <> 'not_comparable'
     or c.embedded_strength_key is not null then
    raise exception 'ambiguous embedded strength became comparable: %', to_jsonb(c);
  end if;

  if app_private.scientific_source_strength_vector_key('1 G/VIAL') <> 'mg:1000' then
    raise exception 'source-strength presentation key did not reuse SP-026 normalization';
  end if;

  if app_private.scientific_source_strength_vector_key('1000 MCG/CTD TAB.') <> 'mg:1' then
    raise exception 'source-strength microgram normalization diverged from SP-026';
  end if;
end
$embedded_source_conflicts$;

do $embedded_raw_preservation$
declare
  product_id uuid;
  revision_before bigint;
  updated_before timestamptz;
  composition_before text;
  strength_before text;
  lexical_ingredient_id bigint;
  lexical_name text;
  c record;
begin
  set local role authenticated;
  set local "request.jwt.claim.sub" =
    '11111111-1111-1111-1111-111111111111';

  select id into product_id
  from public.catalog_create_idempotent(
    '78000000-0000-4000-8000-000000000001',
    'SP042 Raw Preservation',
    null,
    'amoxicilline 250mg / 5ml',
    null,
    '125 MG/5ML',
    'Suspension',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  select p.composition, p.strength, p.revision, p.updated_at
    into composition_before, strength_before, revision_before, updated_before
  from public.products p
  where p.id = product_id;

  select pi.ingredient_id, i.name
    into lexical_ingredient_id, lexical_name
  from app_private.product_ingredients pi
  join app_private.catalog_ingredients i on i.id = pi.ingredient_id
  where pi.product_id = product_id
    and pi.component_index = 1;

  select * into c
  from app_private.scientific_compare_embedded_source_strength(
    composition_before,
    strength_before
  );

  if c.comparison_status <> 'conflicts' then
    raise exception 'synthetic raw-product conflict fixture did not compare as conflict';
  end if;

  perform *
  from app_private.scientific_parse_embedded_composition(composition_before);

  if not exists (
    select 1
    from public.products p
    where p.id = product_id
      and p.composition = composition_before
      and p.strength = strength_before
      and p.revision = revision_before
      and p.updated_at = updated_before
  ) then
    raise exception 'embedded parsing mutated authoritative product fields';
  end if;

  if not exists (
    select 1
    from app_private.product_ingredients pi
    join app_private.catalog_ingredients i on i.id = pi.ingredient_id
    where pi.product_id = product_id
      and pi.component_index = 1
      and pi.ingredient_id = lexical_ingredient_id
      and i.name = lexical_name
      and pi.raw_component = composition_before
  ) then
    raise exception 'embedded parsing mutated SP-025 lexical identity/source spelling';
  end if;
end
$embedded_raw_preservation$;

do $embedded_private_access$
begin
  if has_function_privilege(
    'authenticated',
    'app_private.scientific_parse_embedded_component(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'app_private.scientific_parse_embedded_component(text)',
    'EXECUTE'
  ) then
    raise exception 'client role can execute embedded component parser';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.scientific_parse_embedded_composition(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'app_private.scientific_parse_embedded_composition(text)',
    'EXECUTE'
  ) then
    raise exception 'client role can execute embedded composition parser';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.scientific_compare_embedded_source_strength(text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'app_private.scientific_compare_embedded_source_strength(text,text)',
    'EXECUTE'
  ) then
    raise exception 'client role can execute embedded/source comparison';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.scientific_embedded_strength_vector_key(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'app_private.scientific_source_strength_vector_key(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'app_private.catalog_strength_presentation_name(text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can execute private SP-042 helper';
  end if;
end
$embedded_private_access$;

rollback;
