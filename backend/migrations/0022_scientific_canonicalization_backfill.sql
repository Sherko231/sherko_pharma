-- SP-044: persist reviewed scientific canonicalization as a private derived layer.
-- Raw catalog composition/strength, SP-025 identities, DDI mappings, product
-- revisions, barcodes, prices, orders, and Flutter behavior remain unchanged.

create or replace function app_private.scientific_canonicalization_version()
returns smallint
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$ select 1::smallint $$;

revoke all on function app_private.scientific_canonicalization_version()
from public, anon, authenticated;

create table app_private.scientific_canonicalization_versions (
  canonicalization_version smallint primary key check (canonicalization_version > 0),
  cleanup_version smallint not null check (cleanup_version > 0),
  embedded_parser_version smallint not null check (embedded_parser_version > 0),
  complex_parser_version smallint not null check (complex_parser_version > 0),
  description text not null check (btrim(description) <> ''),
  created_at timestamptz not null default now()
);

insert into app_private.scientific_canonicalization_versions(
  canonicalization_version,
  cleanup_version,
  embedded_parser_version,
  complex_parser_version,
  description
)
values (
  app_private.scientific_canonicalization_version(),
  app_private.scientific_cleanup_rule_version(),
  app_private.embedded_composition_parser_version(),
  app_private.complex_composition_parser_version(),
  'SP-044 v1: SP-040 cleanup + SP-041 reviewed identities + SP-042 embedded strength + SP-043 complex structure'
);

create table app_private.product_scientific_canonicalization_nodes (
  product_id uuid not null references public.products(id) on delete cascade,
  node_path integer[] not null,
  parent_path integer[],
  node_kind app_private.complex_composition_node_kind not null,
  separator_before text,
  group_raw_fragment text,
  raw_fragment text,
  ingredient_source text,
  ingredient_candidate text,
  alternate_name_source text,
  alternate_name_candidate text,
  scientific_ingredient_id bigint
    references app_private.scientific_ingredients(id) on delete restrict,
  preferred_scientific_name text,
  resolution_kind text,
  normalized_amount numeric,
  normalized_unit text,
  per_amount numeric,
  per_unit text,
  presentation text,
  identity_hint text,
  structure_status app_private.complex_composition_structure_status not null,
  identity_status app_private.complex_composition_identity_status,
  parser_version smallint not null check (parser_version > 0),
  reason_codes text[] not null default array[]::text[],
  canonicalization_version smallint not null
    references app_private.scientific_canonicalization_versions(canonicalization_version),
  normalized_at timestamptz not null default now(),
  primary key (product_id, node_path),
  check (cardinality(node_path) > 0),
  check (parent_path is null or cardinality(parent_path) < cardinality(node_path)),
  check (resolution_kind is null or resolution_kind in ('canonical', 'reviewed_alias')),
  check (
    node_kind <> 'group'
    or (identity_status is null and scientific_ingredient_id is null and resolution_kind is null)
  ),
  check (
    identity_status <> 'trusted'
    or (scientific_ingredient_id is not null and resolution_kind is not null)
  )
);

create table app_private.product_scientific_canonicalization (
  product_id uuid primary key references public.products(id) on delete cascade,
  source_composition text,
  source_strength text,
  source_fingerprint text not null check (btrim(source_fingerprint) <> ''),
  overall_structure_status app_private.complex_composition_structure_status not null,
  overall_identity_status app_private.complex_composition_identity_status not null,
  ingredient_count integer not null check (ingredient_count >= 0),
  trusted_count integer not null check (trusted_count >= 0),
  high_confidence_count integer not null check (high_confidence_count >= 0),
  needs_review_count integer not null check (needs_review_count >= 0),
  unresolved_count integer not null check (unresolved_count >= 0),
  alias_resolved_count integer not null check (alias_resolved_count >= 0),
  embedded_strength_component_count integer not null check (embedded_strength_component_count >= 0),
  strength_comparison_status app_private.embedded_strength_comparison_status not null,
  embedded_strength_key text,
  source_strength_key text,
  parser_version smallint not null check (parser_version > 0),
  canonicalization_version smallint not null
    references app_private.scientific_canonicalization_versions(canonicalization_version),
  normalized_at timestamptz not null default now(),
  check (
    trusted_count + high_confidence_count + needs_review_count + unresolved_count = ingredient_count
  ),
  check (alias_resolved_count <= trusted_count),
  check (embedded_strength_component_count <= ingredient_count)
);

create index product_scientific_nodes_identity_idx
  on app_private.product_scientific_canonicalization_nodes(scientific_ingredient_id, product_id)
  where scientific_ingredient_id is not null;
create index product_scientific_nodes_status_idx
  on app_private.product_scientific_canonicalization_nodes(identity_status, structure_status, product_id)
  where node_kind = 'ingredient';
create index product_scientific_summary_status_idx
  on app_private.product_scientific_canonicalization(overall_identity_status, overall_structure_status);

alter table app_private.scientific_canonicalization_versions enable row level security;
alter table app_private.product_scientific_canonicalization_nodes enable row level security;
alter table app_private.product_scientific_canonicalization enable row level security;

revoke all on app_private.scientific_canonicalization_versions from public, anon, authenticated;
revoke all on app_private.product_scientific_canonicalization_nodes from public, anon, authenticated;
revoke all on app_private.product_scientific_canonicalization from public, anon, authenticated;

create or replace function app_private.scientific_canonicalization_source_fingerprint(
  input_composition text,
  input_strength text
)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select md5(
    coalesce(encode(convert_to(input_composition, 'UTF8'), 'hex'), '<NULL>') || ':' ||
    coalesce(encode(convert_to(input_strength, 'UTF8'), 'hex'), '<NULL>')
  )
$$;

revoke all on function app_private.scientific_canonicalization_source_fingerprint(text,text)
from public, anon, authenticated;

create or replace function app_private.refresh_catalog_ingredient_scientific_mapping(
  target_ingredient_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $refresh_catalog_ingredient_scientific_mapping$
declare
  ingredient_name text;
  cleanup record;
  resolved_id bigint;
  resolved_name text;
  resolved_match text;
  resolved_alias_source text;
  resolved_alias_version text;
  resolved_alias_reviewed_at timestamptz;
  ref_system app_private.scientific_ingredient_reference_system;
  ref_key text;
  ref_version text;
  ref_reviewed_at timestamptz;
  target_scientific_id bigint := null;
  target_status app_private.scientific_ingredient_mapping_status := 'needs_review';
  target_method app_private.scientific_ingredient_mapping_method := 'none';
  target_confidence smallint := 0;
  target_source text := null;
  target_version text := null;
  target_reviewed_at timestamptz := null;
  target_note text;
begin
  if exists (
    select 1
    from app_private.catalog_ingredient_scientific_mappings m
    where m.ingredient_id = target_ingredient_id
      and m.status = 'verified'
      and m.mapping_method = 'manual'
  ) then
    return;
  end if;

  select i.name into ingredient_name
  from app_private.catalog_ingredients i
  where i.id = target_ingredient_id;

  if ingredient_name is null then
    raise exception 'unknown catalog ingredient id %', target_ingredient_id using errcode = '22023';
  end if;

  select * into cleanup
  from app_private.scientific_cleanup_component_candidate(ingredient_name);

  if cleanup.cleanup_status = 'deterministic_candidate' then
    select
      r.scientific_ingredient_id,
      r.preferred_name,
      r.match_kind,
      r.reference_source,
      r.reference_version,
      r.reviewed_at
      into
        resolved_id,
        resolved_name,
        resolved_match,
        resolved_alias_source,
        resolved_alias_version,
        resolved_alias_reviewed_at
    from app_private.resolve_reviewed_scientific_alias(cleanup.candidate_text) r;

    if resolved_id is not null
       and resolved_match = 'reviewed_alias'
       and resolved_alias_reviewed_at is not null
       and nullif(btrim(resolved_alias_source), '') is not null then
      target_scientific_id := resolved_id;
      target_status := 'verified';
      target_method := 'reviewed_alias';
      target_confidence := 100;
      target_source := resolved_alias_source;
      target_version := resolved_alias_version;
      target_reviewed_at := resolved_alias_reviewed_at;
      target_note := 'SP-044 v1 exact reviewed alias after deterministic cleanup: ' || cleanup.candidate_text;
    elsif resolved_id is not null and resolved_match = 'canonical' then
      select r.reference_system, r.reference_key, r.reference_version, r.reviewed_at
        into ref_system, ref_key, ref_version, ref_reviewed_at
      from app_private.scientific_ingredient_references r
      where r.scientific_ingredient_id = resolved_id
      order by r.reviewed_at desc, r.reference_system, r.reference_key
      limit 1;

      if ref_reviewed_at is not null then
        target_scientific_id := resolved_id;
        target_status := 'verified';
        target_method := 'exact_reference';
        target_confidence := 100;
        target_source := 'scientific_ingredient_references:' || ref_system::text || ':' || ref_key;
        target_version := ref_version;
        target_reviewed_at := ref_reviewed_at;
        target_note := 'SP-044 v1 exact reviewed canonical name after deterministic cleanup: ' || cleanup.candidate_text;
      end if;
    end if;
  end if;

  if target_status <> 'verified' then
    target_note := case
      when cleanup.cleanup_status = 'needs_review' then
        'SP-044 v1 needs review; cleanup reasons=' || array_to_string(cleanup.review_reasons, ',')
      else
        'SP-044 v1 needs scientific review; no reviewed SP-041 identity for candidate: ' || cleanup.candidate_text
    end;
  end if;

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
  values (
    target_ingredient_id,
    target_scientific_id,
    target_status,
    target_method,
    target_confidence,
    target_source,
    target_version,
    target_reviewed_at,
    target_note
  )
  on conflict (ingredient_id) do update
  set
    scientific_ingredient_id = excluded.scientific_ingredient_id,
    status = excluded.status,
    mapping_method = excluded.mapping_method,
    confidence = excluded.confidence,
    reference_source = excluded.reference_source,
    reference_version = excluded.reference_version,
    reviewed_at = excluded.reviewed_at,
    review_note = excluded.review_note,
    updated_at = now()
  where (
    app_private.catalog_ingredient_scientific_mappings.scientific_ingredient_id,
    app_private.catalog_ingredient_scientific_mappings.status,
    app_private.catalog_ingredient_scientific_mappings.mapping_method,
    app_private.catalog_ingredient_scientific_mappings.confidence,
    app_private.catalog_ingredient_scientific_mappings.reference_source,
    app_private.catalog_ingredient_scientific_mappings.reference_version,
    app_private.catalog_ingredient_scientific_mappings.reviewed_at,
    app_private.catalog_ingredient_scientific_mappings.review_note
  ) is distinct from (
    excluded.scientific_ingredient_id,
    excluded.status,
    excluded.mapping_method,
    excluded.confidence,
    excluded.reference_source,
    excluded.reference_version,
    excluded.reviewed_at,
    excluded.review_note
  );
end;
$refresh_catalog_ingredient_scientific_mapping$;

revoke all on function app_private.refresh_catalog_ingredient_scientific_mapping(bigint)
from public, anon, authenticated;

create or replace function app_private.refresh_product_scientific_canonicalization(
  target_product_id uuid,
  input_composition text,
  input_strength text
)
returns void
language plpgsql
security definer
set search_path = ''
as $refresh_product_scientific_canonicalization$
declare
  source_fp text := app_private.scientific_canonicalization_source_fingerprint(input_composition, input_strength);
  version_value smallint := app_private.scientific_canonicalization_version();
  parser_version_value smallint := app_private.complex_composition_parser_version();
  existing_fp text;
  existing_version smallint;
  existing_parser smallint;
  parsed record;
  summary_row record;
  comparison_row record;
  resolution_kind_value text;
  alias_count_value integer;
  embedded_count_value integer;
begin
  select s.source_fingerprint, s.canonicalization_version, s.parser_version
    into existing_fp, existing_version, existing_parser
  from app_private.product_scientific_canonicalization s
  where s.product_id = target_product_id;

  if existing_fp = source_fp
     and existing_version = version_value
     and existing_parser = parser_version_value then
    return;
  end if;

  delete from app_private.product_scientific_canonicalization_nodes
  where product_id = target_product_id;

  for parsed in
    select *
    from app_private.scientific_parse_complex_composition(input_composition)
    order by node_path
  loop
    resolution_kind_value := null;
    if parsed.node_kind = 'ingredient'
       and parsed.identity_status = 'trusted'
       and parsed.ingredient_candidate is not null then
      select r.match_kind into resolution_kind_value
      from app_private.resolve_reviewed_scientific_alias(parsed.ingredient_candidate) r;
    end if;

    insert into app_private.product_scientific_canonicalization_nodes(
      product_id, node_path, parent_path, node_kind, separator_before,
      group_raw_fragment, raw_fragment, ingredient_source, ingredient_candidate,
      alternate_name_source, alternate_name_candidate, scientific_ingredient_id,
      preferred_scientific_name, resolution_kind, normalized_amount,
      normalized_unit, per_amount, per_unit, presentation, identity_hint,
      structure_status, identity_status, parser_version, reason_codes,
      canonicalization_version
    )
    values (
      target_product_id, parsed.node_path, parsed.parent_path, parsed.node_kind,
      parsed.separator_before, parsed.group_raw_fragment, parsed.raw_fragment,
      parsed.ingredient_source, parsed.ingredient_candidate,
      parsed.alternate_name_source, parsed.alternate_name_candidate,
      parsed.scientific_ingredient_id, parsed.preferred_scientific_name,
      resolution_kind_value, parsed.normalized_amount, parsed.normalized_unit,
      parsed.per_amount, parsed.per_unit, parsed.presentation,
      parsed.identity_hint, parsed.structure_status, parsed.identity_status,
      parsed.parser_version, coalesce(parsed.reason_codes, array[]::text[]),
      version_value
    );
  end loop;

  select * into summary_row
  from app_private.scientific_complex_composition_summary(input_composition);

  select * into comparison_row
  from app_private.scientific_compare_embedded_source_strength(input_composition, input_strength);

  select
    count(*) filter (where node_kind = 'ingredient' and resolution_kind = 'reviewed_alias')::integer,
    count(*) filter (
      where node_kind = 'ingredient'
        and (normalized_amount is not null or presentation is not null)
    )::integer
    into alias_count_value, embedded_count_value
  from app_private.product_scientific_canonicalization_nodes
  where product_id = target_product_id;

  insert into app_private.product_scientific_canonicalization(
    product_id, source_composition, source_strength, source_fingerprint,
    overall_structure_status, overall_identity_status, ingredient_count,
    trusted_count, high_confidence_count, needs_review_count, unresolved_count,
    alias_resolved_count, embedded_strength_component_count,
    strength_comparison_status, embedded_strength_key, source_strength_key,
    parser_version, canonicalization_version
  )
  values (
    target_product_id, input_composition, input_strength, source_fp,
    summary_row.overall_structure_status, summary_row.overall_identity_status,
    summary_row.ingredient_count, summary_row.trusted_count,
    summary_row.high_confidence_count, summary_row.needs_review_count,
    summary_row.unresolved_count, coalesce(alias_count_value, 0),
    coalesce(embedded_count_value, 0), comparison_row.comparison_status,
    comparison_row.embedded_strength_key, comparison_row.source_strength_key,
    summary_row.parser_version, version_value
  )
  on conflict (product_id) do update
  set
    source_composition = excluded.source_composition,
    source_strength = excluded.source_strength,
    source_fingerprint = excluded.source_fingerprint,
    overall_structure_status = excluded.overall_structure_status,
    overall_identity_status = excluded.overall_identity_status,
    ingredient_count = excluded.ingredient_count,
    trusted_count = excluded.trusted_count,
    high_confidence_count = excluded.high_confidence_count,
    needs_review_count = excluded.needs_review_count,
    unresolved_count = excluded.unresolved_count,
    alias_resolved_count = excluded.alias_resolved_count,
    embedded_strength_component_count = excluded.embedded_strength_component_count,
    strength_comparison_status = excluded.strength_comparison_status,
    embedded_strength_key = excluded.embedded_strength_key,
    source_strength_key = excluded.source_strength_key,
    parser_version = excluded.parser_version,
    canonicalization_version = excluded.canonicalization_version,
    normalized_at = now();
end;
$refresh_product_scientific_canonicalization$;

revoke all on function app_private.refresh_product_scientific_canonicalization(uuid,text,text)
from public, anon, authenticated;

create or replace function app_private.refresh_all_scientific_canonicalization()
returns void
language plpgsql
security definer
set search_path = ''
as $refresh_all_scientific_canonicalization$
declare
  r record;
begin
  for r in select id from app_private.catalog_ingredients order by id loop
    perform app_private.refresh_catalog_ingredient_scientific_mapping(r.id);
  end loop;

  for r in select id, composition, strength from public.products order by id loop
    perform app_private.refresh_product_scientific_canonicalization(r.id, r.composition, r.strength);
  end loop;
end;
$refresh_all_scientific_canonicalization$;

revoke all on function app_private.refresh_all_scientific_canonicalization()
from public, anon, authenticated;

create or replace function app_private.sync_product_scientific_canonicalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $sync_product_scientific_canonicalization$
declare
  ingredient_row record;
begin
  if tg_op = 'UPDATE'
     and new.composition is not distinct from old.composition
     and new.strength is not distinct from old.strength then
    return new;
  end if;

  if tg_op = 'INSERT' or new.composition is distinct from old.composition then
    for ingredient_row in
      select distinct pi.ingredient_id
      from app_private.product_ingredients pi
      where pi.product_id = new.id
      order by pi.ingredient_id
    loop
      perform app_private.refresh_catalog_ingredient_scientific_mapping(
        ingredient_row.ingredient_id
      );
    end loop;
  end if;

  perform app_private.refresh_product_scientific_canonicalization(
    new.id,
    new.composition,
    new.strength
  );
  return new;
end;
$sync_product_scientific_canonicalization$;

revoke all on function app_private.sync_product_scientific_canonicalization()
from public, anon, authenticated;

create trigger products_scientific_canonicalization_sync
after insert or update of composition, strength
on public.products
for each row
execute function app_private.sync_product_scientific_canonicalization();

-- Capture source and existing derived-state fingerprints before the backfill.
create temporary table sp044_product_state_before on commit drop as
select id, composition, strength, barcode, barcode2, selling_amount, currency, revision, updated_at
from public.products;

create temporary table sp044_upstream_state_before on commit drop as
select
  (select count(*) from app_private.catalog_ingredients) as ingredient_count,
  (select count(*) from app_private.product_ingredients) as component_count,
  (select md5(string_agg(to_jsonb(x)::text, '|' order by x.id))
     from app_private.catalog_ingredients x) as ingredient_fingerprint,
  (select md5(string_agg(to_jsonb(x)::text, '|' order by x.product_id, x.component_index))
     from app_private.product_ingredients x) as component_fingerprint,
  (select md5(string_agg(to_jsonb(x)::text, '|' order by x.product_id))
     from app_private.product_composition_normalization x) as composition_fingerprint,
  (select md5(string_agg(to_jsonb(x)::text, '|' order by x.ingredient_id))
     from app_private.interaction_checker_ingredient_mappings x) as ddi_mapping_fingerprint,
  (select md5(string_agg(to_jsonb(x)::text, '|' order by x.product_id, x.component_index))
     from app_private.interaction_checker_component_overrides x) as ddi_override_fingerprint;

select app_private.refresh_all_scientific_canonicalization();

do $sp044_backfill_invariants$
begin
  if (select count(*) from app_private.catalog_ingredient_scientific_mappings)
     <> (select count(*) from app_private.catalog_ingredients) then
    raise exception 'SP-044 catalog scientific mapping row count mismatch';
  end if;

  if (select count(*) from app_private.product_scientific_canonicalization)
     <> (select count(*) from public.products) then
    raise exception 'SP-044 product scientific summary row count mismatch';
  end if;

  if exists (
    select 1
    from public.products p
    join sp044_product_state_before b using (id)
    where p.composition is distinct from b.composition
       or p.strength is distinct from b.strength
       or p.barcode is distinct from b.barcode
       or p.barcode2 is distinct from b.barcode2
       or p.selling_amount is distinct from b.selling_amount
       or p.currency is distinct from b.currency
       or p.revision is distinct from b.revision
       or p.updated_at is distinct from b.updated_at
  ) then
    raise exception 'SP-044 mutated authoritative/commercial product state';
  end if;

  if exists (
    select 1
    from public.products p
    join app_private.product_scientific_canonicalization s on s.product_id = p.id
    where s.source_composition is distinct from p.composition
       or s.source_strength is distinct from p.strength
       or s.source_fingerprint is distinct from
          app_private.scientific_canonicalization_source_fingerprint(p.composition, p.strength)
  ) then
    raise exception 'SP-044 source snapshot/fingerprint mismatch';
  end if;

  if exists (
    select 1
    from app_private.catalog_ingredient_scientific_mappings m
    where m.status = 'verified'
      and (
        m.scientific_ingredient_id is null
        or m.confidence <> 100
        or m.mapping_method not in ('exact_reference', 'reviewed_alias')
        or m.reviewed_at is null
      )
  ) then
    raise exception 'SP-044 persisted an unreviewed verified mapping';
  end if;

  if exists (
    select 1
    from app_private.product_scientific_canonicalization_nodes n
    where n.identity_status = 'trusted'
      and (n.scientific_ingredient_id is null or n.resolution_kind is null)
  ) then
    raise exception 'SP-044 persisted trusted product identity without reviewed resolution';
  end if;

  if (select ingredient_count from sp044_upstream_state_before)
       <> (select count(*) from app_private.catalog_ingredients)
     or (select component_count from sp044_upstream_state_before)
       <> (select count(*) from app_private.product_ingredients)
     or (select ingredient_fingerprint from sp044_upstream_state_before) is distinct from
       (select md5(string_agg(to_jsonb(x)::text, '|' order by x.id)) from app_private.catalog_ingredients x)
     or (select component_fingerprint from sp044_upstream_state_before) is distinct from
       (select md5(string_agg(to_jsonb(x)::text, '|' order by x.product_id, x.component_index)) from app_private.product_ingredients x)
     or (select composition_fingerprint from sp044_upstream_state_before) is distinct from
       (select md5(string_agg(to_jsonb(x)::text, '|' order by x.product_id)) from app_private.product_composition_normalization x)
     or (select ddi_mapping_fingerprint from sp044_upstream_state_before) is distinct from
       (select md5(string_agg(to_jsonb(x)::text, '|' order by x.ingredient_id)) from app_private.interaction_checker_ingredient_mappings x)
     or (select ddi_override_fingerprint from sp044_upstream_state_before) is distinct from
       (select md5(string_agg(to_jsonb(x)::text, '|' order by x.product_id, x.component_index)) from app_private.interaction_checker_component_overrides x)
  then
    raise exception 'SP-044 changed SP-025 or DDI derived state';
  end if;
end;
$sp044_backfill_invariants$;