-- SP-042: deterministic extraction of embedded strength/presentation text
-- from composition components. This migration is repository-only.
-- It does not rewrite products.composition or products.strength, backfill
-- scientific mappings, or change pharmaceutical-equivalence behavior.

create type app_private.embedded_composition_parse_status as enum (
  'deterministic',
  'needs_review',
  'not_present'
);

create type app_private.embedded_strength_comparison_status as enum (
  'source_missing',
  'matches',
  'conflicts',
  'source_unparseable',
  'not_comparable'
);

create or replace function app_private.embedded_composition_parser_version()
returns smallint
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select 1::smallint
$$;

revoke all on function app_private.embedded_composition_parser_version()
from public, anon, authenticated;

create or replace function app_private.catalog_strength_presentation_name(
  input_text text
)
returns text
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog, app_private
as $$
declare
  suffix_key text;
begin
  suffix_key := regexp_replace(
    app_private.catalog_strength_clean(input_text),
    '[^A-Z0-9]+',
    '',
    'g'
  );

  return case
    when suffix_key in ('TAB', 'CTDTAB') then 'tablet'
    when suffix_key in ('CAP', 'CAPS') then 'capsule'
    when suffix_key = 'VIAL' then 'vial'
    when suffix_key = 'AMP' then 'ampoule'
    when suffix_key = 'SUPP' then 'suppository'
    when suffix_key in ('OVULE', 'OVULES') then 'ovule'
    when suffix_key = 'SACHET' then 'sachet'
    when suffix_key = 'DOSE' then 'dose'
    when suffix_key = 'CHEWTAB' then 'chewable_tablet'
    when suffix_key = 'EFFTAB' then 'effervescent_tablet'
    when suffix_key = 'LOZENGE' then 'lozenge'
    when suffix_key in ('SGCAP', 'SOFTCAP', 'SOFTGCAP')
      then 'softgel_capsule'
    when suffix_key in ('ENTERICTAB', 'ENTERICCTDTAB')
      then 'enteric_tablet'
    when suffix_key = 'DELAYEDRELEASETAB'
      then 'delayed_release_tablet'
    when suffix_key in ('DELAYEDRELEASECAP', 'DRCAP')
      then 'delayed_release_capsule'
    when suffix_key in ('EXTENDEDRELEASETAB', 'EXTENDEDRTAB', 'XRTAB', 'XRCTDTAB')
      then 'extended_release_tablet'
    when suffix_key = 'EXTENDEDRELEASECAP'
      then 'extended_release_capsule'
    when suffix_key = 'PROLONGEDRELEASETAB'
      then 'prolonged_release_tablet'
    when suffix_key = 'PROLONGEDRELEASECAP'
      then 'prolonged_release_capsule'
    when suffix_key in ('SUSTAINEDRELEASETAB', 'SRTAB')
      then 'sustained_release_tablet'
    when suffix_key in ('SUSTAINEDRELEASECAP', 'SRCAP')
      then 'sustained_release_capsule'
    when suffix_key = 'VAGTAB' then 'vaginal_tablet'
    when suffix_key = 'DISINTEGRATINGTAB'
      then 'disintegrating_tablet'
    when suffix_key = 'DISPERSIBLETAB' then 'dispersible_tablet'
    when suffix_key = 'PLASTICAMP' then 'plastic_ampoule'
    when suffix_key = 'ORALVIAL' then 'oral_vial'
    when suffix_key = 'LIQUIDVIAL' then 'liquid_vial'
    else null
  end;
end;
$$;

revoke all on function app_private.catalog_strength_presentation_name(text)
from public, anon, authenticated;

create or replace function app_private.scientific_parse_embedded_component(
  input_text text
)
returns table (
  raw_component text,
  ingredient_source text,
  ingredient_candidate text,
  cleanup_status app_private.scientific_cleanup_status,
  normalized_amount numeric,
  normalized_unit text,
  per_amount numeric,
  per_unit text,
  presentation text,
  suffix_kind text,
  parse_status app_private.embedded_composition_parse_status,
  parser_version smallint,
  review_reasons text[]
)
language plpgsql
immutable
strict
parallel safe
set search_path = ''
as $scientific_parse_embedded_component$
declare
  working_text text;
  matched text[];
  measure_text text;
  suffix_text text;
  cleanup record;
  measure_amount numeric;
  measure_unit text;
  denominator_amount numeric;
  denominator_unit text;
  presentation_value text;
begin
  if nullif(btrim(input_text), '') is null then
    raise exception 'embedded composition input must not be blank'
      using errcode = '22023';
  end if;

  raw_component := input_text;
  parser_version := app_private.embedded_composition_parser_version();
  review_reasons := array[]::text[];
  suffix_kind := 'none';

  working_text := regexp_replace(
    btrim(normalize(input_text, NFKC)),
    '[[:space:]]+',
    ' ',
    'g'
  );

  matched := regexp_match(
    working_text,
    '^(.*[^[:space:]])[[:space:]]+([0-9]+([.,][0-9]+)?[[:space:]]*(MCG|UG|µG|μG|MG|KG|G|IU|I[.]?U[.]?|UI|U[.]?I[.]?|U|MEQ|MMOL|%))([[:space:]]*/[[:space:]]*.+)?$',
    'i'
  );

  if matched is null then
    ingredient_source := working_text;

    select * into cleanup
    from app_private.scientific_cleanup_component_candidate(ingredient_source);

    ingredient_candidate := cleanup.candidate_text;
    cleanup_status := cleanup.cleanup_status;
    parse_status := 'not_present';
    review_reasons := array['no_embedded_strength']::text[];
    return next;
    return;
  end if;

  ingredient_source := btrim(matched[1]);
  measure_text := matched[2];
  suffix_text := nullif(btrim(coalesce(matched[5], '')), '');

  select m.normalized_amount, m.normalized_unit
    into measure_amount, measure_unit
  from app_private.catalog_parse_strength_measure(measure_text) m;

  if measure_unit is null then
    ingredient_candidate := ingredient_source;
    cleanup_status := 'needs_review';
    parse_status := 'needs_review';
    review_reasons := array['unsupported_embedded_strength_syntax']::text[];
    return next;
    return;
  end if;

  normalized_amount := measure_amount;
  normalized_unit := measure_unit;

  if suffix_text is not null then
    select d.normalized_per_amount, d.normalized_per_unit
      into denominator_amount, denominator_unit
    from app_private.catalog_parse_strength_denominator(suffix_text) d;

    if denominator_unit is not null then
      per_amount := denominator_amount;
      per_unit := denominator_unit;
      suffix_kind := 'denominator';
    else
      presentation_value :=
        app_private.catalog_strength_presentation_name(suffix_text);

      if presentation_value is null then
        ingredient_candidate := ingredient_source;
        cleanup_status := 'needs_review';
        parse_status := 'needs_review';
        review_reasons := array[
          'unsupported_embedded_denominator_or_presentation'
        ]::text[];
        return next;
        return;
      end if;

      presentation := presentation_value;
      suffix_kind := 'presentation';
    end if;
  end if;

  select * into cleanup
  from app_private.scientific_cleanup_component_candidate(ingredient_source);

  ingredient_candidate := cleanup.candidate_text;
  cleanup_status := cleanup.cleanup_status;

  if cleanup.cleanup_status <> 'deterministic_candidate' then
    parse_status := 'needs_review';
    review_reasons := array_append(
      coalesce(cleanup.review_reasons, array[]::text[]),
      'ingredient_candidate_needs_review'
    );
    return next;
    return;
  end if;

  parse_status := 'deterministic';
  return next;
end;
$scientific_parse_embedded_component$;

revoke all on function app_private.scientific_parse_embedded_component(text)
from public, anon, authenticated;

create or replace function app_private.scientific_parse_embedded_composition(
  input_composition text
)
returns table (
  component_index smallint,
  raw_component text,
  ingredient_candidate text,
  normalized_amount numeric,
  normalized_unit text,
  per_amount numeric,
  per_unit text,
  presentation text,
  parse_status app_private.embedded_composition_parse_status,
  parser_version smallint,
  review_reasons text[]
)
language plpgsql
immutable
strict
parallel safe
set search_path = ''
as $scientific_parse_embedded_composition$
declare
  raw_parts text[];
  component_count integer;
  index_value integer;
  parsed record;
  last_parsed record;
  embedded_count integer := 0;
  deterministic_count integer := 0;
  suffix_count integer := 0;
  has_empty_component boolean := false;
  has_grouped_plus boolean := false;
  shared_suffix boolean := false;
  global_review boolean := false;
  global_reason text;
begin
  if nullif(btrim(input_composition), '') is null then
    raise exception 'composition input must not be blank'
      using errcode = '22023';
  end if;

  raw_parts := regexp_split_to_array(input_composition, '[+]');
  component_count := coalesce(array_length(raw_parts, 1), 0);

  has_grouped_plus := input_composition ~ '\([^)]*[+][^)]*\)';

  for index_value in 1..component_count loop
    if nullif(btrim(raw_parts[index_value]), '') is null then
      has_empty_component := true;
      continue;
    end if;

    select * into parsed
    from app_private.scientific_parse_embedded_component(
      raw_parts[index_value]
    );

    if parsed.parse_status <> 'not_present' then
      embedded_count := embedded_count + 1;
    end if;

    if parsed.parse_status = 'deterministic' then
      deterministic_count := deterministic_count + 1;
    end if;

    if parsed.suffix_kind <> 'none' then
      suffix_count := suffix_count + 1;
    end if;

    if index_value = component_count then
      last_parsed := parsed;
    end if;
  end loop;

  if has_grouped_plus then
    global_review := true;
    global_reason := 'grouped_plus_requires_sp043';
  elsif has_empty_component then
    global_review := true;
    global_reason := 'empty_component';
  elsif embedded_count = 0 then
    global_review := false;
  elsif component_count > 1
        and deterministic_count <> component_count then
    global_review := true;
    global_reason := 'ambiguous_multi_component_embedded_strength';
  elsif component_count > 1 then
    if suffix_count = 0 then
      shared_suffix := false;
    elsif suffix_count = component_count then
      shared_suffix := false;
    elsif suffix_count = 1
          and last_parsed.suffix_kind in ('denominator', 'presentation') then
      shared_suffix := true;
    else
      global_review := true;
      global_reason := 'ambiguous_multi_component_suffix_scope';
    end if;
  end if;

  for index_value in 1..component_count loop
    component_index := index_value::smallint;
    raw_component := btrim(raw_parts[index_value]);
    parser_version := app_private.embedded_composition_parser_version();

    if nullif(raw_component, '') is null then
      ingredient_candidate := null;
      normalized_amount := null;
      normalized_unit := null;
      per_amount := null;
      per_unit := null;
      presentation := null;
      parse_status := 'needs_review';
      review_reasons := array['empty_component']::text[];
      return next;
      continue;
    end if;

    select * into parsed
    from app_private.scientific_parse_embedded_component(raw_component);

    ingredient_candidate := parsed.ingredient_candidate;
    normalized_amount := parsed.normalized_amount;
    normalized_unit := parsed.normalized_unit;
    per_amount := parsed.per_amount;
    per_unit := parsed.per_unit;
    presentation := parsed.presentation;
    parse_status := parsed.parse_status;
    review_reasons := coalesce(parsed.review_reasons, array[]::text[]);

    if global_review then
      parse_status := 'needs_review';
      review_reasons := array_append(review_reasons, global_reason);
    elsif embedded_count > 0 and shared_suffix
          and parsed.suffix_kind = 'none' then
      if last_parsed.suffix_kind = 'denominator' then
        per_amount := last_parsed.per_amount;
        per_unit := last_parsed.per_unit;
      elsif last_parsed.suffix_kind = 'presentation' then
        presentation := last_parsed.presentation;
      end if;
    end if;

    return next;
  end loop;
end;
$scientific_parse_embedded_composition$;

revoke all on function app_private.scientific_parse_embedded_composition(text)
from public, anon, authenticated;

create or replace function app_private.scientific_source_strength_vector_key(
  input_strength text
)
returns text
language plpgsql
immutable
strict
parallel safe
set search_path = ''
as $scientific_source_strength_vector_key$
declare
  raw_parts text[];
  parse_parts text[];
  component_count integer;
  last_index integer;
  last_clean text;
  last_match text[];
  shared_tail text;
  shared_per_amount numeric;
  shared_per_unit text;
  shared_denominator boolean := false;
  component_index_value integer;
  measure_amount numeric;
  measure_unit text;
  component_key text;
  keys text[] := array[]::text[];
begin
  if nullif(btrim(input_strength), '') is null then
    return null;
  end if;

  raw_parts := regexp_split_to_array(input_strength, '[+]');
  component_count := coalesce(array_length(raw_parts, 1), 0);

  if component_count = 0 then
    return null;
  end if;

  parse_parts := raw_parts;
  last_index := component_count;
  last_clean := regexp_replace(
    app_private.catalog_strength_clean(raw_parts[last_index]),
    '[.]+$',
    ''
  );

  last_match := regexp_match(
    last_clean,
    '^([0-9]+([.][0-9]+)?)(MCG|UG|MG|KG|G|IU|I[.]?U[.]?|UI|U[.]?I[.]?|U|MEQ|MMOL|%)(.*)$'
  );

  if last_match is null then
    return null;
  end if;

  shared_tail := coalesce(last_match[4], '');
  parse_parts[last_index] := last_match[1] || last_match[3];

  if shared_tail <> '' then
    if left(shared_tail, 1) <> '/' then
      return null;
    end if;

    select d.normalized_per_amount, d.normalized_per_unit
      into shared_per_amount, shared_per_unit
    from app_private.catalog_parse_strength_denominator(shared_tail) d;

    if shared_per_unit is not null then
      shared_denominator := true;
    elsif not app_private.catalog_strength_is_presentation_suffix(shared_tail) then
      return null;
    end if;
  end if;

  for component_index_value in 1..component_count loop
    if nullif(btrim(raw_parts[component_index_value]), '') is null then
      return null;
    end if;

    measure_amount := null;
    measure_unit := null;

    select m.normalized_amount, m.normalized_unit
      into measure_amount, measure_unit
    from app_private.catalog_parse_strength_measure(
      parse_parts[component_index_value]
    ) m;

    if measure_unit is null then
      return null;
    end if;

    if shared_denominator then
      component_key :=
        measure_unit || '/' || shared_per_unit || ':' ||
        app_private.catalog_numeric_key(
          measure_amount / shared_per_amount
        );
    else
      component_key :=
        measure_unit || ':' ||
        app_private.catalog_numeric_key(measure_amount);
    end if;

    keys := array_append(keys, component_key);
  end loop;

  return array_to_string(keys, '|');
end;
$scientific_source_strength_vector_key$;

revoke all on function app_private.scientific_source_strength_vector_key(text)
from public, anon, authenticated;

create or replace function app_private.scientific_embedded_strength_vector_key(
  input_composition text
)
returns text
language sql
immutable
strict
parallel safe
set search_path = ''
as $$
  select case
    when count(*) = 0 then null
    when bool_and(parse_status = 'deterministic') then
      string_agg(
        normalized_unit ||
          case
            when per_unit is not null then '/' || per_unit
            else ''
          end || ':' ||
          app_private.catalog_numeric_key(
            normalized_amount / coalesce(per_amount, 1)
          ),
        '|'
        order by component_index
      )
    else null
  end
  from app_private.scientific_parse_embedded_composition(input_composition)
$$;

revoke all on function app_private.scientific_embedded_strength_vector_key(text)
from public, anon, authenticated;

create or replace function app_private.scientific_compare_embedded_source_strength(
  input_composition text,
  source_strength text
)
returns table (
  comparison_status app_private.embedded_strength_comparison_status,
  embedded_strength_key text,
  source_strength_key text
)
language plpgsql
immutable
parallel safe
set search_path = ''
as $scientific_compare_embedded_source_strength$
begin
  embedded_strength_key :=
    app_private.scientific_embedded_strength_vector_key(input_composition);

  if embedded_strength_key is null then
    comparison_status := 'not_comparable';
    source_strength_key := null;
    return next;
    return;
  end if;

  if source_strength is null or nullif(btrim(source_strength), '') is null then
    comparison_status := 'source_missing';
    source_strength_key := null;
    return next;
    return;
  end if;

  source_strength_key :=
    app_private.scientific_source_strength_vector_key(source_strength);

  if source_strength_key is null then
    comparison_status := 'source_unparseable';
  elsif source_strength_key = embedded_strength_key then
    comparison_status := 'matches';
  else
    comparison_status := 'conflicts';
  end if;

  return next;
end;
$scientific_compare_embedded_source_strength$;

revoke all on function app_private.scientific_compare_embedded_source_strength(
  text,
  text
)
from public, anon, authenticated;
