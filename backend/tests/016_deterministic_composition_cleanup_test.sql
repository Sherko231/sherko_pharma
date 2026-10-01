\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

select id from public.catalog_create_idempotent(
  '77000000-0000-4000-8000-000000000001',
  'SP040 Raw Preservation',
  null,
  'paraCetamol',
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

do $deterministic_cleanup$
declare
  r record;
  token text;
  product_revision bigint;
  product_updated_at timestamptz;
  lexical_ingredient_id bigint;
  lexical_ingredient_name text;
  raw_component_before text;
  first_result jsonb;
  second_result jsonb;
begin
  if app_private.scientific_cleanup_rule_version() <> 1 then
    raise exception 'unexpected SP-040 cleanup rule version';
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate('paraCetamol');

  if r.candidate_text <> 'Paracetamol'
     or r.cleanup_status <> 'deterministic_candidate'
     or r.cleanup_version <> 1
     or not (r.applied_rules @> array['display_case_normalization']::text[])
     or cardinality(r.review_reasons) <> 0 then
    raise exception 'paraCetamol deterministic case cleanup failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate(
    'calciumCarbonate'
  );

  if r.candidate_text <> 'Calcium carbonate'
     or r.cleanup_status <> 'deterministic_candidate'
     or not (
       r.applied_rules @>
       array['camelcase_known_prefix_split','display_case_normalization']::text[]
     ) then
    raise exception 'calciumCarbonate deterministic split failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate(
    'DIPHENHYDRAMINE HCL'
  );

  if r.candidate_text <> 'Diphenhydramine hydrochloride'
     or r.cleanup_status <> 'deterministic_candidate'
     or not (
       r.applied_rules @>
       array['salt_hcl_expansion','display_case_normalization']::text[]
     ) then
    raise exception 'HCL expansion failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate(
    'DEXTROMETHORPHAN HBR'
  );

  if r.candidate_text <> 'Dextromethorphan hydrobromide'
     or r.cleanup_status <> 'deterministic_candidate'
     or not (r.applied_rules @> array['salt_hbr_expansion']::text[]) then
    raise exception 'HBR expansion failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate('VIT.C');

  if r.candidate_text <> 'Vitamin C'
     or r.cleanup_status <> 'deterministic_candidate'
     or not (r.applied_rules @> array['vitamin_token_format']::text[]) then
    raise exception 'VIT.C lexical formatting failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate('VIT.B3');

  if r.candidate_text <> 'Vitamin B3'
     or r.cleanup_status <> 'deterministic_candidate'
     or lower(r.candidate_text) like '%niacin%'
     or lower(r.candidate_text) like '%nicotinamide%' then
    raise exception 'VIT.B3 was semantically collapsed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate('NH4CL');

  if r.candidate_text <> 'Ammonium chloride'
     or r.cleanup_status <> 'deterministic_candidate'
     or not (
       r.applied_rules @> array['formula_nh4cl_expansion']::text[]
     ) then
    raise exception 'NH4CL deterministic formula expansion failed: %', to_jsonb(r);
  end if;

  foreach token in array array['MG','K','P','PP']::text[]
  loop
    select * into r
    from app_private.scientific_cleanup_component_candidate(token);

    if r.candidate_text <> token
       or r.cleanup_status <> 'needs_review'
       or not (
         r.review_reasons @> array['ambiguous_short_token']::text[]
       ) then
      raise exception 'ambiguous short token % was expanded: %',
        token,
        to_jsonb(r);
    end if;
  end loop;

  select * into r
  from app_private.scientific_cleanup_component_candidate(
    'ALPRAZOLAM 0.5MG / TAB'
  );

  if r.candidate_text <> 'ALPRAZOLAM 0.5MG / TAB'
     or r.cleanup_status <> 'needs_review'
     or not (r.review_reasons @> array['embedded_strength']::text[])
     or not (r.review_reasons @> array['structural_syntax']::text[]) then
    raise exception 'embedded strength was parsed instead of quarantined: %',
      to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate(
    'DICYCLOMINE HCL (DICYCLOVERINE HCL)'
  );

  if r.candidate_text <> 'DICYCLOMINE HCL (DICYCLOVERINE HCL)'
     or r.cleanup_status <> 'needs_review'
     or not (r.review_reasons @> array['structural_syntax']::text[])
     or r.applied_rules @> array['salt_hcl_expansion']::text[] then
    raise exception 'parenthesized alternate-name case was modified: %',
      to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate('FeSO4');

  if r.candidate_text <> 'FeSO4'
     or r.cleanup_status <> 'needs_review'
     or not (
       r.review_reasons @>
       array['unreviewed_formula_or_numeric_token']::text[]
     ) then
    raise exception 'unreviewed formula token was altered: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.scientific_cleanup_component_candidate('HCL');

  if r.candidate_text <> 'HCL'
     or r.cleanup_status <> 'needs_review'
     or not (
       r.review_reasons @>
       array['standalone_abbreviation_or_formula']::text[]
     ) then
    raise exception 'standalone HCL was treated as a substance name: %',
      to_jsonb(r);
  end if;

  select to_jsonb(c) into first_result
  from app_private.scientific_cleanup_component_candidate(
    '  DEXTROMETHORPHAN   HBR  '
  ) c;

  select to_jsonb(c) into second_result
  from app_private.scientific_cleanup_component_candidate(
    '  DEXTROMETHORPHAN   HBR  '
  ) c;

  if first_result is distinct from second_result then
    raise exception 'cleanup function is not deterministic';
  end if;

  if not (
    (first_result -> 'applied_rules') @>
      '["whitespace_collapse","salt_hbr_expansion"]'::jsonb
  ) then
    raise exception 'whitespace/salt rule provenance missing: %', first_result;
  end if;

  select p.revision, p.updated_at
    into product_revision, product_updated_at
  from public.products p
  where p.id = '77000000-0000-4000-8000-000000000001'::uuid;

  select pi.ingredient_id, i.name, pi.raw_component
    into lexical_ingredient_id, lexical_ingredient_name, raw_component_before
  from app_private.product_ingredients pi
  join app_private.catalog_ingredients i on i.id = pi.ingredient_id
  where pi.product_id = '77000000-0000-4000-8000-000000000001'::uuid
    and pi.component_index = 1;

  perform *
  from app_private.scientific_cleanup_component_candidate(raw_component_before);

  if exists (
    select 1
    from public.products p
    where p.id = '77000000-0000-4000-8000-000000000001'::uuid
      and (
        p.composition <> 'paraCetamol'
        or p.revision <> product_revision
        or p.updated_at <> product_updated_at
      )
  ) then
    raise exception 'cleanup candidate generation mutated raw product state';
  end if;

  if not exists (
    select 1
    from app_private.product_ingredients pi
    join app_private.catalog_ingredients i on i.id = pi.ingredient_id
    where pi.product_id = '77000000-0000-4000-8000-000000000001'::uuid
      and pi.component_index = 1
      and pi.ingredient_id = lexical_ingredient_id
      and pi.raw_component = raw_component_before
      and i.name = lexical_ingredient_name
  ) then
    raise exception 'cleanup candidate generation mutated SP-025 lexical state';
  end if;

  begin
    perform *
    from app_private.scientific_cleanup_component_candidate('   ');
    raise exception 'blank cleanup input was accepted';
  exception
    when sqlstate '22023' then null;
  end;
end
$deterministic_cleanup$;

do $deterministic_cleanup_private_access$
begin
  if has_function_privilege(
    'anon',
    'app_private.scientific_cleanup_rule_version()',
    'EXECUTE'
  ) then
    raise exception 'anon can execute private cleanup version function';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.scientific_cleanup_rule_version()',
    'EXECUTE'
  ) then
    raise exception 'authenticated can execute private cleanup version function';
  end if;

  if has_function_privilege(
    'anon',
    'app_private.scientific_cleanup_component_candidate(text)',
    'EXECUTE'
  ) then
    raise exception 'anon can execute private cleanup candidate function';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.scientific_cleanup_component_candidate(text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can execute private cleanup candidate function';
  end if;
end
$deterministic_cleanup_private_access$;

rollback;