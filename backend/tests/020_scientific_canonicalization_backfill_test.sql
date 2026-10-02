\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

-- A canonical scientific row without reviewed reference evidence is deliberately
-- present to prove SP-044 does not inherit SP-043 lexical trust as final truth.
insert into app_private.scientific_ingredients(
  preferred_name,
  normalized_preferred_name,
  category
)
values (
  'Unreferenced SP044',
  app_private.scientific_name_key('Unreferenced SP044'),
  'medicinal_substance'
);

do $sp044_fixture$
declare
  alias_product uuid;
  embedded_product uuid;
  ambiguous_product uuid;
  grouped_product uuid;
  unreviewed_product uuid;
begin
  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  select id into alias_product
  from public.catalog_create_idempotent(
    '79000000-0000-4000-8000-000000000101',
    'SP044 Alias', null, 'Amoxicilline', null, null, 'Tablet', null,
    null, null, 1000, 'SYP', null
  );

  select id into embedded_product
  from public.catalog_create_idempotent(
    '79000000-0000-4000-8000-000000000102',
    'SP044 Embedded', null, 'amoxicilline 250mg / 5ml', null,
    '50mg/ml', 'Suspension', null, null, null, 1000, 'SYP', null
  );

  select id into ambiguous_product
  from public.catalog_create_idempotent(
    '79000000-0000-4000-8000-000000000103',
    'SP044 Ambiguous', null, 'K', null, null, 'Tablet', null,
    null, null, 1000, 'SYP', null
  );

  select id into grouped_product
  from public.catalog_create_idempotent(
    '79000000-0000-4000-8000-000000000104',
    'SP044 Grouped', null,
    'ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)', null, null, 'Tablet', null,
    null, null, 1000, 'SYP', null
  );

  select id into unreviewed_product
  from public.catalog_create_idempotent(
    '79000000-0000-4000-8000-000000000105',
    'SP044 Unreviewed Canonical', null, 'Unreferenced SP044', null,
    null, 'Tablet', null, null, null, 1000, 'SYP', null
  );

  reset role;
end
$sp044_fixture$;

do $sp044_reviewed_mapping$
declare
  r record;
begin
  select m.*, i.name as lexical_name, s.preferred_name
    into r
  from app_private.catalog_ingredient_scientific_mappings m
  join app_private.catalog_ingredients i on i.id = m.ingredient_id
  left join app_private.scientific_ingredients s on s.id = m.scientific_ingredient_id
  where app_private.scientific_name_key(i.name) = app_private.scientific_name_key('Amoxicilline');

  if r.status <> 'verified'
     or r.mapping_method <> 'reviewed_alias'
     or r.confidence <> 100
     or r.preferred_name <> 'Amoxicillin'
     or r.reviewed_at is null then
    raise exception 'reviewed Amoxicilline mapping failed: %', to_jsonb(r);
  end if;

  select m.*, i.name as lexical_name
    into r
  from app_private.catalog_ingredient_scientific_mappings m
  join app_private.catalog_ingredients i on i.id = m.ingredient_id
  where i.normalized_name = app_private.catalog_search_normalize('K');

  if r.status <> 'needs_review'
     or r.scientific_ingredient_id is not null
     or r.mapping_method <> 'none'
     or r.confidence <> 0 then
    raise exception 'ambiguous K mapping was incorrectly accepted: %', to_jsonb(r);
  end if;

  select m.* into r
  from app_private.catalog_ingredient_scientific_mappings m
  join app_private.catalog_ingredients i on i.id = m.ingredient_id
  where app_private.scientific_name_key(i.name) =
        app_private.scientific_name_key('Unreferenced SP044');

  if r.status <> 'needs_review'
     or r.scientific_ingredient_id is not null then
    raise exception 'unreferenced canonical identity was incorrectly verified: %', to_jsonb(r);
  end if;
end
$sp044_reviewed_mapping$;

do $sp044_product_derivation$
declare
  r record;
begin
  select s.* into r
  from app_private.product_scientific_canonicalization s
  join public.products p on p.id = s.product_id
  where p.name_en = 'SP044 Alias';

  if r.overall_structure_status <> 'deterministic'
     or r.overall_identity_status <> 'trusted'
     or r.trusted_count <> 1
     or r.alias_resolved_count <> 1
     or r.embedded_strength_component_count <> 0 then
    raise exception 'alias product derivation failed: %', to_jsonb(r);
  end if;

  select s.* into r
  from app_private.product_scientific_canonicalization s
  join public.products p on p.id = s.product_id
  where p.name_en = 'SP044 Embedded';

  if r.overall_identity_status <> 'trusted'
     or r.alias_resolved_count <> 1
     or r.embedded_strength_component_count <> 1
     or r.strength_comparison_status <> 'matches' then
    raise exception 'embedded-strength alias derivation failed: %', to_jsonb(r);
  end if;

  select s.* into r
  from app_private.product_scientific_canonicalization s
  join public.products p on p.id = s.product_id
  where p.name_en = 'SP044 Ambiguous';

  if r.overall_identity_status <> 'needs_review'
     or r.trusted_count <> 0
     or r.needs_review_count <> 1 then
    raise exception 'ambiguous product was not quarantined: %', to_jsonb(r);
  end if;

  select s.* into r
  from app_private.product_scientific_canonicalization s
  join public.products p on p.id = s.product_id
  where p.name_en = 'SP044 Grouped';

  if r.overall_structure_status <> 'deterministic'
     or r.overall_identity_status <> 'high_confidence'
     or r.ingredient_count <> 3
     or r.high_confidence_count <> 3 then
    raise exception 'grouped product derivation failed: %', to_jsonb(r);
  end if;

  select s.* into r
  from app_private.product_scientific_canonicalization s
  join public.products p on p.id = s.product_id
  where p.name_en = 'SP044 Unreviewed Canonical';

  if r.overall_structure_status <> 'deterministic'
     or r.overall_identity_status <> 'high_confidence'
     or r.trusted_count <> 0
     or r.high_confidence_count <> 1 then
    raise exception 'unreferenced canonical identity was incorrectly trusted: %', to_jsonb(r);
  end if;

  if not exists (
    select 1
    from app_private.product_scientific_canonicalization_nodes n
    join public.products p on p.id = n.product_id
    where p.name_en = 'SP044 Unreviewed Canonical'
      and n.reason_codes @> array['scientific_identity_missing_reviewed_provenance']::text[]
  ) then
    raise exception 'missing reviewed-provenance quarantine reason';
  end if;
end
$sp044_product_derivation$;

do $sp044_idempotence$
declare
  summary_before timestamptz;
  summary_after timestamptz;
  mapping_before timestamptz;
  mapping_after timestamptz;
  nodes_before text;
  nodes_after text;
  product_id_value uuid;
  ingredient_id_value bigint;
begin
  select p.id into product_id_value
  from public.products p
  where p.name_en = 'SP044 Alias';

  select pi.ingredient_id into ingredient_id_value
  from app_private.product_ingredients pi
  where pi.product_id = product_id_value
  order by pi.component_index
  limit 1;

  select normalized_at into summary_before
  from app_private.product_scientific_canonicalization
  where product_id = product_id_value;

  select updated_at into mapping_before
  from app_private.catalog_ingredient_scientific_mappings
  where ingredient_id = ingredient_id_value;

  select md5(string_agg(to_jsonb(n)::text, '|' order by n.node_path)) into nodes_before
  from app_private.product_scientific_canonicalization_nodes n
  where n.product_id = product_id_value;

  perform app_private.refresh_all_scientific_canonicalization();

  select normalized_at into summary_after
  from app_private.product_scientific_canonicalization
  where product_id = product_id_value;

  select updated_at into mapping_after
  from app_private.catalog_ingredient_scientific_mappings
  where ingredient_id = ingredient_id_value;

  select md5(string_agg(to_jsonb(n)::text, '|' order by n.node_path)) into nodes_after
  from app_private.product_scientific_canonicalization_nodes n
  where n.product_id = product_id_value;

  if summary_after is distinct from summary_before
     or mapping_after is distinct from mapping_before
     or nodes_after is distinct from nodes_before then
    raise exception 'same-version SP-044 rerun was not idempotent';
  end if;
end
$sp044_idempotence$;

do $sp044_source_preservation$
declare
  before_fp text;
  after_fp text;
  sp025_before text;
  sp025_after text;
  ddi_before text;
  ddi_after text;
begin
  select md5(string_agg(
    p.id::text || ':' ||
    coalesce(encode(convert_to(p.composition, 'UTF8'), 'hex'), '<NULL>') || ':' ||
    coalesce(encode(convert_to(p.strength, 'UTF8'), 'hex'), '<NULL>') || ':' ||
    coalesce(p.barcode, '<NULL>') || ':' || coalesce(p.barcode2, '<NULL>') || ':' ||
    p.selling_amount::text || ':' || p.currency::text || ':' ||
    p.revision::text || ':' || p.updated_at::text,
    '|' order by p.id
  )) into before_fp
  from public.products p;

  select md5(string_agg(to_jsonb(pi)::text, '|' order by pi.product_id, pi.component_index))
    into sp025_before
  from app_private.product_ingredients pi;

  select md5(string_agg(to_jsonb(m)::text, '|' order by m.ingredient_id))
    into ddi_before
  from app_private.interaction_checker_ingredient_mappings m;

  perform app_private.refresh_all_scientific_canonicalization();

  select md5(string_agg(
    p.id::text || ':' ||
    coalesce(encode(convert_to(p.composition, 'UTF8'), 'hex'), '<NULL>') || ':' ||
    coalesce(encode(convert_to(p.strength, 'UTF8'), 'hex'), '<NULL>') || ':' ||
    coalesce(p.barcode, '<NULL>') || ':' || coalesce(p.barcode2, '<NULL>') || ':' ||
    p.selling_amount::text || ':' || p.currency::text || ':' ||
    p.revision::text || ':' || p.updated_at::text,
    '|' order by p.id
  )) into after_fp
  from public.products p;

  select md5(string_agg(to_jsonb(pi)::text, '|' order by pi.product_id, pi.component_index))
    into sp025_after
  from app_private.product_ingredients pi;

  select md5(string_agg(to_jsonb(m)::text, '|' order by m.ingredient_id))
    into ddi_after
  from app_private.interaction_checker_ingredient_mappings m;

  if after_fp is distinct from before_fp
     or sp025_after is distinct from sp025_before
     or ddi_after is distinct from ddi_before then
    raise exception 'SP-044 rerun changed authoritative/SP-025/DDI state';
  end if;
end
$sp044_source_preservation$;

do $sp044_private_access$
begin
  if has_function_privilege(
    'authenticated',
    'app_private.refresh_all_scientific_canonicalization()',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'app_private.refresh_all_scientific_canonicalization()',
    'EXECUTE'
  ) then
    raise exception 'normal client role can execute SP-044 backfill';
  end if;

  if has_table_privilege(
    'authenticated',
    'app_private.product_scientific_canonicalization',
    'SELECT'
  ) or has_table_privilege(
    'anon',
    'app_private.product_scientific_canonicalization_nodes',
    'SELECT'
  ) then
    raise exception 'normal client role can read SP-044 private derived tables';
  end if;
end
$sp044_private_access$;

rollback;
