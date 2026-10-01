\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

do $sp043_grouped_structure$
declare
  group_row record;
  first_row record;
  second_group_first record;
  second_group_second record;
  summary_row record;
begin
  select * into group_row
  from app_private.scientific_parse_complex_composition(
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)'
  )
  where node_kind = 'group'
    and node_path = array[2];

  if group_row.raw_fragment <> '(SULFADOXINE+PYRIMETHAMINE)'
     or group_row.parent_path is not null
     or group_row.separator_before <> '+'
     or group_row.structure_status <> 'deterministic'
     or group_row.identity_status is not null then
    raise exception 'group provenance was not preserved: %', to_jsonb(group_row);
  end if;

  select * into first_row
  from app_private.scientific_parse_complex_composition(
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)'
  )
  where node_kind = 'ingredient'
    and node_path = array[1];

  select * into second_group_first
  from app_private.scientific_parse_complex_composition(
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)'
  )
  where node_kind = 'ingredient'
    and node_path = array[2,1];

  select * into second_group_second
  from app_private.scientific_parse_complex_composition(
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)'
  )
  where node_kind = 'ingredient'
    and node_path = array[2,2];

  if first_row.ingredient_candidate <> 'Artesunate'
     or first_row.structure_status <> 'deterministic'
     or first_row.identity_status <> 'high_confidence'
     or second_group_first.ingredient_candidate <> 'Sulfadoxine'
     or second_group_first.parent_path <> array[2]
     or second_group_first.group_raw_fragment <> '(SULFADOXINE+PYRIMETHAMINE)'
     or second_group_second.ingredient_candidate <> 'Pyrimethamine'
     or second_group_second.parent_path <> array[2]
     or second_group_second.separator_before <> '+' then
    raise exception 'grouped leaf decomposition failed';
  end if;

  select * into summary_row
  from app_private.scientific_complex_composition_summary(
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)'
  );

  if summary_row.overall_structure_status <> 'deterministic'
     or summary_row.overall_identity_status <> 'high_confidence'
     or summary_row.ingredient_count <> 3
     or summary_row.high_confidence_count <> 3
     or summary_row.parser_version <> 1 then
    raise exception 'grouped composition summary failed: %', to_jsonb(summary_row);
  end if;
end
$sp043_grouped_structure$;

do $sp043_parenthesized_alias$
declare
  r record;
  trusted_alias record;
  ingredient_rows integer;
begin
  select count(*) into ingredient_rows
  from app_private.scientific_parse_complex_composition(
    'DICYCLOMINE HCL (DICYCLOVERINE HCL)'
  )
  where node_kind = 'ingredient';

  if ingredient_rows <> 1 then
    raise exception 'parenthesized alternate was split into multiple active ingredients';
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition(
    'DICYCLOMINE HCL (DICYCLOVERINE HCL)'
  )
  where node_kind = 'ingredient';

  if r.ingredient_candidate <> 'Dicyclomine hydrochloride'
     or r.alternate_name_candidate <> 'Dicycloverine hydrochloride'
     or r.structure_status <> 'deterministic'
     or r.identity_status <> 'needs_review'
     or r.scientific_ingredient_id is not null
     or not ('parenthesized_alternate_name_needs_review' = any(r.reason_codes)) then
    raise exception 'parenthesized alternate-name review case failed: %', to_jsonb(r);
  end if;

  select * into trusted_alias
  from app_private.scientific_parse_complex_composition(
    'Amoxicilline (Amoxicillin)'
  )
  where node_kind = 'ingredient';

  if trusted_alias.structure_status <> 'deterministic'
     or trusted_alias.identity_status <> 'trusted'
     or trusted_alias.preferred_scientific_name <> 'Amoxicillin'
     or trusted_alias.scientific_ingredient_id is null
     or not ('parenthesized_alternate_confirmed_by_reviewed_alias' = any(trusted_alias.reason_codes)) then
    raise exception 'reviewed parenthesized alias confirmation failed: %',
      to_jsonb(trusted_alias);
  end if;
end
$sp043_parenthesized_alias$;

do $sp043_delimiters$
declare
  r record;
  count_value integer;
begin
  select count(*) into count_value
  from app_private.scientific_parse_complex_composition(
    'Amoxicillin;Caffeine'
  )
  where node_kind = 'ingredient'
    and identity_status = 'trusted';

  if count_value <> 2 then
    raise exception 'semicolon component list was not parsed deterministically';
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition(
    'Amoxicillin;Caffeine'
  )
  where node_kind = 'ingredient'
    and node_path = array[2];

  if r.separator_before <> ';'
     or r.preferred_scientific_name <> 'Caffeine' then
    raise exception 'semicolon provenance failed: %', to_jsonb(r);
  end if;

  select count(*) into count_value
  from app_private.scientific_parse_complex_composition(
    'Amoxicillin, Caffeine'
  )
  where node_kind = 'ingredient'
    and identity_status = 'trusted';

  if count_value <> 2 then
    raise exception 'reviewed distinct-identity comma list was not parsed';
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition(
    'Amoxicillin, Caffeine'
  )
  where node_kind = 'ingredient'
    and node_path = array[2];

  if r.separator_before <> ','
     or r.preferred_scientific_name <> 'Caffeine' then
    raise exception 'comma provenance failed: %', to_jsonb(r);
  end if;

  select count(*) into count_value
  from app_private.scientific_parse_complex_composition(
    'Paracetamol, Acetaminophen'
  )
  where node_kind = 'ingredient';

  if count_value <> 1 then
    raise exception 'same-identity comma text was incorrectly split';
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition(
    'Paracetamol, Acetaminophen'
  )
  where node_kind = 'ingredient';

  if r.structure_status <> 'needs_review'
     or r.identity_status <> 'needs_review'
     or not ('ambiguous_comma_structure' = any(r.reason_codes)) then
    raise exception 'ambiguous comma syntax was not quarantined: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition(
    'amoxicilline 250mg / 5ml'
  )
  where node_kind = 'ingredient';

  if r.structure_status <> 'deterministic'
     or r.identity_status <> 'trusted'
     or r.preferred_scientific_name <> 'Amoxicillin'
     or r.normalized_amount <> 250
     or r.normalized_unit <> 'mg'
     or r.per_amount <> 5
     or r.per_unit <> 'ml' then
    raise exception 'SP-042 slash/strength handoff failed: %', to_jsonb(r);
  end if;
end
$sp043_delimiters$;

do $sp043_contextual_identity$
declare
  r record;
  token text;
begin
  select * into r
  from app_private.scientific_parse_complex_composition('Ginseng extract')
  where node_kind = 'ingredient';

  if r.structure_status <> 'deterministic'
     or r.identity_status <> 'needs_review'
     or r.identity_hint <> 'botanical_or_extract'
     or not ('botanical_or_extract_identity_needs_review' = any(r.reason_codes)) then
    raise exception 'botanical/extract identity was not quarantined: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition('VIT.C')
  where node_kind = 'ingredient';

  if r.ingredient_candidate <> 'Vitamin C'
     or r.identity_hint <> 'vitamin'
     or r.structure_status <> 'deterministic'
     or r.identity_status <> 'high_confidence'
     or r.scientific_ingredient_id is not null then
    raise exception 'Vitamin C lexical candidate boundary failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition('VIT.B3')
  where node_kind = 'ingredient';

  if r.ingredient_candidate <> 'Vitamin B3'
     or r.identity_status <> 'needs_review'
     or not ('vitamin_form_ambiguous' = any(r.reason_codes)) then
    raise exception 'Vitamin B3 ambiguity was not preserved: %', to_jsonb(r);
  end if;

  foreach token in array array['K','P','PP']::text[] loop
    select * into r
    from app_private.scientific_parse_complex_composition(token)
    where node_kind = 'ingredient';

    if r.structure_status <> 'deterministic'
       or r.identity_status <> 'needs_review'
       or r.scientific_ingredient_id is not null
       or not ('ambiguous_short_token' = any(r.reason_codes)) then
      raise exception 'ambiguous short token % was incorrectly resolved: %',
        token, to_jsonb(r);
    end if;
  end loop;

  select * into r
  from app_private.scientific_parse_complex_composition('Potassium')
  where node_kind = 'ingredient';

  if r.identity_hint <> 'mineral'
     or r.identity_status <> 'needs_review'
     or not ('bare_mineral_form_ambiguous' = any(r.reason_codes)) then
    raise exception 'bare mineral form ambiguity failed: %', to_jsonb(r);
  end if;
end
$sp043_contextual_identity$;

do $sp043_malformed$
declare
  r record;
  summary_row record;
  unresolved_rows integer;
begin
  select * into r
  from app_private.scientific_parse_complex_composition(
    'PARACETAMOL+(CAFFEINE'
  )
  where node_kind = 'ingredient';

  if r.structure_status <> 'unresolved'
     or r.identity_status <> 'unresolved'
     or not ('unbalanced_parentheses' = any(r.reason_codes)) then
    raise exception 'unbalanced parentheses did not remain unresolved: %', to_jsonb(r);
  end if;

  select count(*) into unresolved_rows
  from app_private.scientific_parse_complex_composition(
    'PARACETAMOL++CAFFEINE'
  )
  where node_kind = 'ingredient'
    and structure_status = 'unresolved'
    and 'empty_component' = any(reason_codes);

  if unresolved_rows <> 1 then
    raise exception 'empty component was not represented as unresolved';
  end if;

  select * into summary_row
  from app_private.scientific_complex_composition_summary(
    'PARACETAMOL++CAFFEINE'
  );

  if summary_row.overall_structure_status <> 'unresolved'
     or summary_row.overall_identity_status <> 'unresolved'
     or summary_row.ingredient_count <> 3
     or summary_row.trusted_count <> 2
     or summary_row.unresolved_count <> 1 then
    raise exception 'malformed composition summary failed: %', to_jsonb(summary_row);
  end if;

  select * into r
  from app_private.scientific_parse_complex_composition('PARACETAMOL [BASE]')
  where node_kind = 'ingredient';

  if r.structure_status <> 'needs_review'
     or r.identity_status <> 'needs_review' then
    raise exception 'unsupported bracket structure was not quarantined: %', to_jsonb(r);
  end if;
end
$sp043_malformed$;

do $sp043_raw_preservation$
declare
  product_id uuid;
  composition_before text;
  strength_before text;
  revision_before bigint;
  updated_before timestamptz;
begin
  set local role authenticated;
  set local "request.jwt.claim.sub" =
    '11111111-1111-1111-1111-111111111111';

  select id into product_id
  from public.catalog_create_idempotent(
    '79000000-0000-4000-8000-000000000001',
    'SP043 Raw Preservation',
    null,
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)',
    null,
    null,
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  reset role;

  select composition, strength, revision, updated_at
    into composition_before, strength_before, revision_before, updated_before
  from public.products
  where id = product_id;

  perform *
  from app_private.scientific_parse_complex_composition(composition_before);

  if not exists (
    select 1
    from public.products
    where id = product_id
      and composition = composition_before
      and strength is not distinct from strength_before
      and revision = revision_before
      and updated_at = updated_before
  ) then
    raise exception 'complex parsing mutated authoritative product state';
  end if;
end
$sp043_raw_preservation$;

do $sp043_private_access$
begin
  if has_function_privilege(
    'authenticated',
    'app_private.scientific_parse_complex_composition(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'app_private.scientific_parse_complex_composition(text)',
    'EXECUTE'
  ) then
    raise exception 'normal client role can execute complex composition parser';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.scientific_complex_composition_summary(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'app_private.scientific_complex_composition_summary(text)',
    'EXECUTE'
  ) then
    raise exception 'normal client role can execute complex composition summary';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.scientific_comma_component_list_safe(text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'app_private.scientific_parse_complex_leaf(text,integer[],integer[],text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'app_private.scientific_parse_complex_children(text,integer[],text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can execute private SP-043 helper';
  end if;
end
$sp043_private_access$;

rollback;