-- SP-043: conservative complex-composition structure parser.
--
-- Repository-only. This layer separates structural parsing from scientific
-- identity confidence, preserves grouping provenance, and never rewrites raw
-- catalog data or accepts ambiguous scientific meaning automatically.

create type app_private.complex_composition_node_kind as enum (
  'group',
  'ingredient'
);

create type app_private.complex_composition_structure_status as enum (
  'deterministic',
  'needs_review',
  'unresolved'
);

create type app_private.complex_composition_identity_status as enum (
  'trusted',
  'high_confidence',
  'needs_review',
  'unresolved'
);

create or replace function app_private.complex_composition_parser_version()
returns smallint
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select 1::smallint
$$;

revoke all on function app_private.complex_composition_parser_version()
from public, anon, authenticated;

create or replace function app_private.scientific_parentheses_balanced(
  input_text text
)
returns boolean
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
declare
  depth integer := 0;
  position_value integer;
  token text;
begin
  for position_value in 1..char_length(input_text) loop
    token := substr(input_text, position_value, 1);
    if token = '(' then
      depth := depth + 1;
    elsif token = ')' then
      depth := depth - 1;
      if depth < 0 then
        return false;
      end if;
    end if;
  end loop;

  return depth = 0;
end;
$$;

revoke all on function app_private.scientific_parentheses_balanced(text)
from public, anon, authenticated;

create or replace function app_private.scientific_outer_parentheses_enclose(
  input_text text
)
returns boolean
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
declare
  working_text text := btrim(input_text);
  depth integer := 0;
  position_value integer;
  token text;
begin
  if char_length(working_text) < 2
     or left(working_text, 1) <> '('
     or right(working_text, 1) <> ')' then
    return false;
  end if;

  for position_value in 1..char_length(working_text) loop
    token := substr(working_text, position_value, 1);
    if token = '(' then
      depth := depth + 1;
    elsif token = ')' then
      depth := depth - 1;
      if depth < 0 then
        return false;
      end if;
      if depth = 0 and position_value < char_length(working_text) then
        return false;
      end if;
    end if;
  end loop;

  return depth = 0;
end;
$$;

revoke all on function app_private.scientific_outer_parentheses_enclose(text)
from public, anon, authenticated;

create or replace function app_private.scientific_split_complex_top_level(
  input_text text,
  split_comma boolean default false
)
returns table (
  segment_index smallint,
  raw_segment text,
  separator_before text
)
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
declare
  depth integer := 0;
  position_value integer;
  segment_start integer := 1;
  segment_number integer := 0;
  token text;
  pending_separator text := null;
  is_separator boolean;
begin
  for position_value in 1..char_length(input_text) loop
    token := substr(input_text, position_value, 1);

    if token = '(' then
      depth := depth + 1;
    elsif token = ')' then
      depth := depth - 1;
    end if;

    is_separator := depth = 0
      and (
        token in ('+', ';')
        or (split_comma and token = ',')
      );

    if is_separator then
      segment_number := segment_number + 1;
      segment_index := segment_number::smallint;
      raw_segment := substr(
        input_text,
        segment_start,
        position_value - segment_start
      );
      separator_before := pending_separator;
      return next;

      pending_separator := token;
      segment_start := position_value + 1;
    end if;
  end loop;

  segment_number := segment_number + 1;
  segment_index := segment_number::smallint;
  raw_segment := substr(input_text, segment_start);
  separator_before := pending_separator;
  return next;
end;
$$;

revoke all on function app_private.scientific_split_complex_top_level(text,boolean)
from public, anon, authenticated;

-- A comma is accepted as a component separator only for the narrow case where
-- every comma-separated token independently resolves through the SP-041 exact
-- reviewed scientific resolver and all resolved identities are distinct.
-- Otherwise comma syntax remains review-required rather than guessed.
create or replace function app_private.scientific_comma_component_list_safe(
  input_text text
)
returns boolean
language plpgsql
stable
strict
parallel safe
set search_path = ''
as $$
declare
  parts text[];
  part text;
  part_count integer;
  resolved_id bigint;
  resolved_ids bigint[] := array[]::bigint[];
begin
  if position(',' in input_text) = 0
     or input_text ~ '[()+;/]'
     or not app_private.scientific_parentheses_balanced(input_text) then
    return false;
  end if;

  parts := regexp_split_to_array(input_text, ',');
  part_count := coalesce(array_length(parts, 1), 0);
  if part_count < 2 then
    return false;
  end if;

  foreach part in array parts loop
    if nullif(btrim(part), '') is null then
      return false;
    end if;

    resolved_id := null;
    select r.scientific_ingredient_id
      into resolved_id
    from app_private.resolve_reviewed_scientific_alias(btrim(part)) r;

    if resolved_id is null
       or resolved_id = any(resolved_ids) then
      return false;
    end if;

    resolved_ids := array_append(resolved_ids, resolved_id);
  end loop;

  return cardinality(resolved_ids) = part_count;
end;
$$;

revoke all on function app_private.scientific_comma_component_list_safe(text)
from public, anon, authenticated;

create or replace function app_private.scientific_parse_complex_leaf(
  input_text text,
  input_node_path integer[],
  input_parent_path integer[],
  input_separator_before text,
  input_group_raw text
)
returns table (
  node_path integer[],
  parent_path integer[],
  node_kind app_private.complex_composition_node_kind,
  separator_before text,
  group_raw_fragment text,
  raw_fragment text,
  ingredient_source text,
  ingredient_candidate text,
  alternate_name_source text,
  alternate_name_candidate text,
  scientific_ingredient_id bigint,
  preferred_scientific_name text,
  normalized_amount numeric,
  normalized_unit text,
  per_amount numeric,
  per_unit text,
  presentation text,
  identity_hint text,
  structure_status app_private.complex_composition_structure_status,
  identity_status app_private.complex_composition_identity_status,
  parser_version smallint,
  reason_codes text[]
)
language plpgsql
stable
strict
parallel safe
set search_path = ''
as $scientific_parse_complex_leaf$
declare
  working_text text;
  alias_match text[];
  primary_text text;
  alternate_text text;
  embedded record;
  cleanup record;
  alternate_cleanup record;
  resolved_id bigint;
  resolved_name text;
  alternate_resolved_id bigint;
  alternate_resolved_name text;
  reasons text[] := array[]::text[];
  structure_needs_review boolean := false;
  identity_needs_review boolean := false;
  botanical_marker boolean := false;
  bare_mineral boolean := false;
  has_alt boolean := false;
begin
  node_path := input_node_path;
  parent_path := input_parent_path;
  node_kind := 'ingredient';
  separator_before := input_separator_before;
  group_raw_fragment := input_group_raw;
  raw_fragment := input_text;
  parser_version := app_private.complex_composition_parser_version();
  reason_codes := array[]::text[];

  working_text := regexp_replace(
    btrim(normalize(input_text, NFKC)),
    '[[:space:]]+',
    ' ',
    'g'
  );

  if nullif(working_text, '') is null then
    structure_status := 'unresolved';
    identity_status := 'unresolved';
    reason_codes := array['empty_component']::text[];
    return next;
    return;
  end if;

  if working_text !~ '[[:alnum:]]' then
    structure_status := 'unresolved';
    identity_status := 'unresolved';
    reason_codes := array['malformed_component_token']::text[];
    return next;
    return;
  end if;

  if not app_private.scientific_parentheses_balanced(working_text) then
    structure_status := 'unresolved';
    identity_status := 'unresolved';
    reason_codes := array['unbalanced_parentheses']::text[];
    return next;
    return;
  end if;

  alias_match := regexp_match(
    working_text,
    '^(.*[^[:space:]])[[:space:]]+\(([^()]*)\)$'
  );

  if alias_match is not null then
    primary_text := btrim(alias_match[1]);
    alternate_text := btrim(alias_match[2]);
    has_alt := true;

    if nullif(alternate_text, '') is null then
      structure_status := 'unresolved';
      identity_status := 'unresolved';
      reason_codes := array['empty_parenthesized_fragment']::text[];
      return next;
      return;
    end if;

    if alternate_text ~ '[+,;/&|:=]'
       or alternate_text ~ '[0-9]' then
      structure_needs_review := true;
      identity_needs_review := true;
      reasons := array_append(
        reasons,
        'parenthesized_content_not_safe_alias'
      );
    end if;
  else
    primary_text := working_text;
    alternate_text := null;

    if working_text ~ '[()]' then
      structure_needs_review := true;
      identity_needs_review := true;
      reasons := array_append(
        reasons,
        'parenthesized_structure_needs_review'
      );
    end if;
  end if;

  select * into embedded
  from app_private.scientific_parse_embedded_component(primary_text);

  ingredient_source := embedded.ingredient_source;
  normalized_amount := embedded.normalized_amount;
  normalized_unit := embedded.normalized_unit;
  per_amount := embedded.per_amount;
  per_unit := embedded.per_unit;
  presentation := embedded.presentation;

  select * into cleanup
  from app_private.scientific_cleanup_component_candidate(ingredient_source);

  ingredient_candidate := cleanup.candidate_text;

  if embedded.parse_status = 'needs_review' then
    structure_needs_review := true;
    reasons := reasons || coalesce(
      embedded.review_reasons,
      array[]::text[]
    );
  end if;

  if cleanup.cleanup_status = 'needs_review' then
    identity_needs_review := true;
    reasons := reasons || coalesce(
      cleanup.review_reasons,
      array[]::text[]
    );
  end if;

  -- Slash syntax is deterministic only when SP-042 parsed it as a recognized
  -- quantitative denominator or presentation suffix.
  if position('/' in primary_text) > 0
     and embedded.parse_status <> 'deterministic' then
    structure_needs_review := true;
    reasons := array_append(reasons, 'ambiguous_slash_structure');
  end if;

  -- Commas are separators only in the reviewed-distinct-identity list path
  -- handled by the parent parser. A comma reaching a leaf is ambiguous.
  if position(',' in primary_text) > 0 then
    structure_needs_review := true;
    identity_needs_review := true;
    reasons := array_append(reasons, 'ambiguous_comma_structure');
  end if;

  botanical_marker := (
    coalesce(ingredient_candidate, ingredient_source, '') ~* (
      '(^|[^[:alnum:]])(' ||
      'extract|root|leaf|leaves|seed|oil|herb|flower|bark|fruit|' ||
      'ginseng|ginkgo|echinacea|valerian|senna|aloe|garlic|ginger|' ||
      'turmeric|curcumin|silymarin|thistle|palmetto|cranberry|' ||
      'peppermint|chamomile' ||
      ')([^[:alnum:]]|$)'
    )
  );

  if botanical_marker then
    identity_hint := 'botanical_or_extract';
    identity_needs_review := true;
    reasons := array_append(
      reasons,
      'botanical_or_extract_identity_needs_review'
    );
  elsif coalesce(ingredient_candidate, '') ~* '^Vitamin[[:space:]]+' then
    identity_hint := 'vitamin';
    if ingredient_candidate ~* '^Vitamin[[:space:]]+B3$' then
      identity_needs_review := true;
      reasons := array_append(reasons, 'vitamin_form_ambiguous');
    end if;
  elsif coalesce(ingredient_candidate, '') ~* (
    '^(Calcium|Magnesium|Potassium|Sodium|Zinc|Iron|Ferrous|Ferric)([[:space:]]|$)'
  ) then
    identity_hint := 'mineral';
    bare_mineral := ingredient_candidate ~* (
      '^(Calcium|Magnesium|Potassium|Sodium|Zinc|Iron)$'
    );
    if bare_mineral then
      identity_needs_review := true;
      reasons := array_append(reasons, 'bare_mineral_form_ambiguous');
    end if;
  end if;

  resolved_id := null;
  resolved_name := null;
  if cleanup.cleanup_status = 'deterministic_candidate'
     and not botanical_marker
     and not bare_mineral then
    select r.scientific_ingredient_id, r.preferred_name
      into resolved_id, resolved_name
    from app_private.resolve_reviewed_scientific_alias(
      ingredient_candidate
    ) r;
  end if;

  if has_alt then
    alternate_name_source := alternate_text;

    select * into alternate_cleanup
    from app_private.scientific_cleanup_component_candidate(alternate_text);

    alternate_name_candidate := alternate_cleanup.candidate_text;

    if alternate_cleanup.cleanup_status = 'needs_review' then
      identity_needs_review := true;
      reasons := reasons || coalesce(
        alternate_cleanup.review_reasons,
        array[]::text[]
      );
    end if;

    alternate_resolved_id := null;
    alternate_resolved_name := null;
    if alternate_cleanup.cleanup_status = 'deterministic_candidate'
       and not structure_needs_review then
      select r.scientific_ingredient_id, r.preferred_name
        into alternate_resolved_id, alternate_resolved_name
      from app_private.resolve_reviewed_scientific_alias(
        alternate_name_candidate
      ) r;
    end if;

    if not structure_needs_review
       and resolved_id is not null
       and alternate_resolved_id = resolved_id then
      reasons := array_append(
        reasons,
        'parenthesized_alternate_confirmed_by_reviewed_alias'
      );
    else
      identity_needs_review := true;
      resolved_id := null;
      resolved_name := null;
      reasons := array_append(
        reasons,
        'parenthesized_alternate_name_needs_review'
      );
    end if;
  end if;

  structure_status := case
    when structure_needs_review then 'needs_review'
    else 'deterministic'
  end;

  if identity_needs_review then
    identity_status := 'needs_review';
    scientific_ingredient_id := null;
    preferred_scientific_name := null;
  elsif resolved_id is not null then
    identity_status := 'trusted';
    scientific_ingredient_id := resolved_id;
    preferred_scientific_name := resolved_name;
    reasons := array_append(reasons, 'reviewed_scientific_identity');
  elsif nullif(btrim(coalesce(ingredient_candidate, '')), '') is null then
    identity_status := 'unresolved';
    scientific_ingredient_id := null;
    preferred_scientific_name := null;
    reasons := array_append(reasons, 'missing_identity_candidate');
  else
    identity_status := 'high_confidence';
    scientific_ingredient_id := null;
    preferred_scientific_name := null;
    reasons := array_append(reasons, 'scientific_identity_unverified');
  end if;

  select coalesce(array_agg(distinct reason order by reason), array[]::text[])
    into reason_codes
  from unnest(reasons) as reason;

  return next;
end;
$scientific_parse_complex_leaf$;

revoke all on function app_private.scientific_parse_complex_leaf(
  text,
  integer[],
  integer[],
  text,
  text
)
from public, anon, authenticated;

create or replace function app_private.scientific_parse_complex_children(
  input_text text,
  input_parent_path integer[],
  input_group_raw text
)
returns table (
  node_path integer[],
  parent_path integer[],
  node_kind app_private.complex_composition_node_kind,
  separator_before text,
  group_raw_fragment text,
  raw_fragment text,
  ingredient_source text,
  ingredient_candidate text,
  alternate_name_source text,
  alternate_name_candidate text,
  scientific_ingredient_id bigint,
  preferred_scientific_name text,
  normalized_amount numeric,
  normalized_unit text,
  per_amount numeric,
  per_unit text,
  presentation text,
  identity_hint text,
  structure_status app_private.complex_composition_structure_status,
  identity_status app_private.complex_composition_identity_status,
  parser_version smallint,
  reason_codes text[]
)
language plpgsql
stable
strict
parallel safe
set search_path = ''
as $scientific_parse_complex_children$
declare
  split_comma boolean;
  segment record;
  segment_text text;
  current_path integer[];
  inner_text text;
begin
  split_comma := app_private.scientific_comma_component_list_safe(input_text);

  for segment in
    select *
    from app_private.scientific_split_complex_top_level(
      input_text,
      split_comma
    )
    order by segment_index
  loop
    segment_text := btrim(segment.raw_segment);
    current_path := coalesce(input_parent_path, array[]::integer[])
      || segment.segment_index::integer;

    if nullif(segment_text, '') is null then
      node_path := current_path;
      parent_path := input_parent_path;
      node_kind := 'ingredient';
      separator_before := segment.separator_before;
      group_raw_fragment := input_group_raw;
      raw_fragment := segment.raw_segment;
      ingredient_source := null;
      ingredient_candidate := null;
      alternate_name_source := null;
      alternate_name_candidate := null;
      scientific_ingredient_id := null;
      preferred_scientific_name := null;
      normalized_amount := null;
      normalized_unit := null;
      per_amount := null;
      per_unit := null;
      presentation := null;
      identity_hint := null;
      structure_status := 'unresolved';
      identity_status := 'unresolved';
      parser_version := app_private.complex_composition_parser_version();
      reason_codes := array['empty_component']::text[];
      return next;
      continue;
    end if;

    if not app_private.scientific_parentheses_balanced(segment_text) then
      node_path := current_path;
      parent_path := input_parent_path;
      node_kind := 'ingredient';
      separator_before := segment.separator_before;
      group_raw_fragment := input_group_raw;
      raw_fragment := segment_text;
      ingredient_source := null;
      ingredient_candidate := null;
      alternate_name_source := null;
      alternate_name_candidate := null;
      scientific_ingredient_id := null;
      preferred_scientific_name := null;
      normalized_amount := null;
      normalized_unit := null;
      per_amount := null;
      per_unit := null;
      presentation := null;
      identity_hint := null;
      structure_status := 'unresolved';
      identity_status := 'unresolved';
      parser_version := app_private.complex_composition_parser_version();
      reason_codes := array['unbalanced_parentheses']::text[];
      return next;
      continue;
    end if;

    if app_private.scientific_outer_parentheses_enclose(segment_text) then
      node_path := current_path;
      parent_path := input_parent_path;
      node_kind := 'group';
      separator_before := segment.separator_before;
      group_raw_fragment := input_group_raw;
      raw_fragment := segment_text;
      ingredient_source := null;
      ingredient_candidate := null;
      alternate_name_source := null;
      alternate_name_candidate := null;
      scientific_ingredient_id := null;
      preferred_scientific_name := null;
      normalized_amount := null;
      normalized_unit := null;
      per_amount := null;
      per_unit := null;
      presentation := null;
      identity_hint := null;
      structure_status := 'deterministic';
      identity_status := null;
      parser_version := app_private.complex_composition_parser_version();
      reason_codes := array['group_container']::text[];
      return next;

      inner_text := substr(segment_text, 2, char_length(segment_text) - 2);
      return query
      select *
      from app_private.scientific_parse_complex_children(
        inner_text,
        current_path,
        segment_text
      );
      continue;
    end if;

    return query
    select *
    from app_private.scientific_parse_complex_leaf(
      segment_text,
      current_path,
      input_parent_path,
      segment.separator_before,
      input_group_raw
    );
  end loop;
end;
$scientific_parse_complex_children$;

revoke all on function app_private.scientific_parse_complex_children(
  text,
  integer[],
  text
)
from public, anon, authenticated;

create or replace function app_private.scientific_parse_complex_composition(
  input_composition text
)
returns table (
  node_path integer[],
  parent_path integer[],
  node_kind app_private.complex_composition_node_kind,
  separator_before text,
  group_raw_fragment text,
  raw_fragment text,
  ingredient_source text,
  ingredient_candidate text,
  alternate_name_source text,
  alternate_name_candidate text,
  scientific_ingredient_id bigint,
  preferred_scientific_name text,
  normalized_amount numeric,
  normalized_unit text,
  per_amount numeric,
  per_unit text,
  presentation text,
  identity_hint text,
  structure_status app_private.complex_composition_structure_status,
  identity_status app_private.complex_composition_identity_status,
  parser_version smallint,
  reason_codes text[]
)
language plpgsql
stable
parallel safe
set search_path = ''
as $scientific_parse_complex_composition$
begin
  if input_composition is null
     or nullif(btrim(input_composition), '') is null then
    node_path := array[1]::integer[];
    parent_path := null;
    node_kind := 'ingredient';
    separator_before := null;
    group_raw_fragment := null;
    raw_fragment := input_composition;
    ingredient_source := null;
    ingredient_candidate := null;
    alternate_name_source := null;
    alternate_name_candidate := null;
    scientific_ingredient_id := null;
    preferred_scientific_name := null;
    normalized_amount := null;
    normalized_unit := null;
    per_amount := null;
    per_unit := null;
    presentation := null;
    identity_hint := null;
    structure_status := 'unresolved';
    identity_status := 'unresolved';
    parser_version := app_private.complex_composition_parser_version();
    reason_codes := array['blank_composition']::text[];
    return next;
    return;
  end if;

  if not app_private.scientific_parentheses_balanced(input_composition) then
    node_path := array[1]::integer[];
    parent_path := null;
    node_kind := 'ingredient';
    separator_before := null;
    group_raw_fragment := null;
    raw_fragment := input_composition;
    ingredient_source := null;
    ingredient_candidate := null;
    alternate_name_source := null;
    alternate_name_candidate := null;
    scientific_ingredient_id := null;
    preferred_scientific_name := null;
    normalized_amount := null;
    normalized_unit := null;
    per_amount := null;
    per_unit := null;
    presentation := null;
    identity_hint := null;
    structure_status := 'unresolved';
    identity_status := 'unresolved';
    parser_version := app_private.complex_composition_parser_version();
    reason_codes := array['unbalanced_parentheses']::text[];
    return next;
    return;
  end if;

  return query
  select *
  from app_private.scientific_parse_complex_children(
    input_composition,
    null,
    null
  );
end;
$scientific_parse_complex_composition$;

revoke all on function app_private.scientific_parse_complex_composition(text)
from public, anon, authenticated;

create or replace function app_private.scientific_complex_composition_summary(
  input_composition text
)
returns table (
  overall_structure_status app_private.complex_composition_structure_status,
  overall_identity_status app_private.complex_composition_identity_status,
  ingredient_count integer,
  trusted_count integer,
  high_confidence_count integer,
  needs_review_count integer,
  unresolved_count integer,
  parser_version smallint
)
language sql
stable
parallel safe
set search_path = ''
as $$
  with ingredient_rows as (
    select *
    from app_private.scientific_parse_complex_composition(input_composition)
    where node_kind = 'ingredient'
  ),
  counts as (
    select
      count(*)::integer as ingredient_count,
      count(*) filter (where identity_status = 'trusted')::integer
        as trusted_count,
      count(*) filter (where identity_status = 'high_confidence')::integer
        as high_confidence_count,
      count(*) filter (where identity_status = 'needs_review')::integer
        as needs_review_count,
      count(*) filter (where identity_status = 'unresolved')::integer
        as unresolved_count,
      bool_or(structure_status = 'unresolved') as has_structure_unresolved,
      bool_or(structure_status = 'needs_review') as has_structure_review,
      bool_or(identity_status = 'unresolved') as has_identity_unresolved,
      bool_or(identity_status = 'needs_review') as has_identity_review,
      bool_or(identity_status = 'high_confidence') as has_identity_high
    from ingredient_rows
  )
  select
    case
      when has_structure_unresolved then 'unresolved'
      when has_structure_review then 'needs_review'
      else 'deterministic'
    end::app_private.complex_composition_structure_status,
    case
      when has_identity_unresolved then 'unresolved'
      when has_identity_review then 'needs_review'
      when has_identity_high then 'high_confidence'
      else 'trusted'
    end::app_private.complex_composition_identity_status,
    ingredient_count,
    trusted_count,
    high_confidence_count,
    needs_review_count,
    unresolved_count,
    app_private.complex_composition_parser_version()
  from counts
$$;

revoke all on function app_private.scientific_complex_composition_summary(text)
from public, anon, authenticated;