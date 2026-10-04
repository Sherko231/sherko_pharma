-- SP-040: deterministic lexical cleanup for scientific-name candidates.
--
-- This migration defines a private, side-effect-free candidate generator only.
-- It does not backfill catalog rows, rewrite raw composition, create scientific
-- mappings, or promote any candidate to a verified scientific identity.

create type app_private.scientific_cleanup_status as enum (
  'deterministic_candidate',
  'needs_review'
);

create or replace function app_private.scientific_cleanup_rule_version()
returns smallint
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select 1::smallint
$$;

revoke all on function app_private.scientific_cleanup_rule_version()
from public, anon, authenticated;

create or replace function app_private.scientific_cleanup_component_candidate(
  input_text text
)
returns table (
  raw_component text,
  candidate_text text,
  cleanup_status app_private.scientific_cleanup_status,
  cleanup_version smallint,
  applied_rules text[],
  review_reasons text[]
)
language plpgsql
immutable
parallel safe
set search_path = pg_catalog
as $scientific_cleanup_component_candidate$
declare
  working_text text;
  normalized_text text;
  lower_text text;
  vitamin_token text;
  camel_prefix text;
  has_embedded_strength boolean := false;
  has_structural_syntax boolean := false;
  has_compact_formula_shape boolean := false;
begin
  if input_text is null or nullif(btrim(input_text), '') is null then
    raise exception 'scientific cleanup input must not be blank'
      using errcode = '22023';
  end if;

  raw_component := input_text;
  cleanup_version := app_private.scientific_cleanup_rule_version();
  applied_rules := array[]::text[];
  review_reasons := array[]::text[];

  working_text := normalize(input_text, NFKC);
  if working_text is distinct from input_text then
    applied_rules := array_append(applied_rules, 'unicode_nfkc');
  end if;

  normalized_text := regexp_replace(
    btrim(working_text),
    '[[:space:]]+',
    ' ',
    'g'
  );
  if normalized_text is distinct from working_text then
    applied_rules := array_append(applied_rules, 'whitespace_collapse');
  end if;
  working_text := normalized_text;

  -- Exact short tokens are overloaded in the source catalog and remain
  -- review-required rather than receiving a global expansion.
  if upper(working_text) = any(array['MG', 'K', 'P', 'PP']::text[]) then
    candidate_text := working_text;
    cleanup_status := 'needs_review';
    review_reasons := array['ambiguous_short_token']::text[];
    return next;
    return;
  end if;

  -- Vitamin notation may be normalized lexically without claiming a specific
  -- chemical form. For example VIT.B3 -> Vitamin B3 is formatting only; it does
  -- not choose niacin over nicotinamide.
  if upper(working_text) ~ '^VIT[.]?[[:space:]-]*[A-Z][0-9]{0,2}$' then
    vitamin_token := regexp_replace(
      upper(working_text),
      '^VIT[.]?[[:space:]-]*',
      ''
    );
    candidate_text := 'Vitamin ' || vitamin_token;
    cleanup_status := 'deterministic_candidate';
    applied_rules := array_append(applied_rules, 'vitamin_token_format');
    return next;
    return;
  end if;

  -- NH4CL is an explicitly reviewed, unambiguous formula expansion in SP-040.
  -- Other formula-like tokens are not generalized by this rule.
  if upper(working_text) = 'NH4CL' then
    candidate_text := 'Ammonium chloride';
    cleanup_status := 'deterministic_candidate';
    applied_rules := array_append(applied_rules, 'formula_nh4cl_expansion');
    return next;
    return;
  end if;

  -- NFKC may canonicalize MICRO SIGN (µ) to GREEK SMALL LETTER MU (μ), so the
  -- contamination detector accepts both code points. SP-040 only quarantines
  -- the strength text; SP-042 owns quantitative parsing.
  has_embedded_strength := working_text ~* (
    '(^|[^[:alnum:]])[0-9]+([.,][0-9]+)?' ||
    '[[:space:]]*(mg|mcg|ug|µg|μg|g|ml|iu|%)' ||
    '($|[^[:alnum:]])'
  );

  has_structural_syntax := (
    working_text ~ '[()/,;:&=|]'
    or position('[' in working_text) > 0
    or position(']' in working_text) > 0
    or position('{' in working_text) > 0
    or position('}' in working_text) > 0
  );

  -- Compact element-symbol sequences such as NaCl or NaOH must not pass
  -- through generic display-case normalization, which would corrupt the
  -- conventional formula casing. Requiring a lowercase letter keeps all-caps
  -- acronyms such as HCL on the separate abbreviation review path below.
  has_compact_formula_shape := (
    char_length(working_text) between 2 and 12
    and working_text ~ '[a-z]'
    and working_text ~ '^([A-Z][a-z]?){2,}$'
  );

  if has_embedded_strength then
    review_reasons := array_append(review_reasons, 'embedded_strength');
  end if;
  if has_structural_syntax then
    review_reasons := array_append(review_reasons, 'structural_syntax');
  end if;
  if has_compact_formula_shape then
    review_reasons := array_append(review_reasons, 'compact_formula');
  end if;

  -- Numeric/formula-like tokens outside the one explicit NH4CL rule remain
  -- review-only. SP-042 handles strength contamination; SP-043 handles complex
  -- structure; neither concern is silently parsed here.
  if not has_embedded_strength
     and working_text ~ '[0-9]' then
    review_reasons := array_append(
      review_reasons,
      'unreviewed_formula_or_numeric_token'
    );
  end if;

  if cardinality(review_reasons) > 0 then
    candidate_text := working_text;
    cleanup_status := 'needs_review';
    return next;
    return;
  end if;

  -- Expand only terminal salt abbreviations with a nonblank substance name.
  -- Standalone HCL/HBR are deliberately not treated as a drug substance.
  if working_text ~* '^.+[[:space:]]+HCL$' then
    working_text := regexp_replace(
      working_text,
      '[[:space:]]+HCL$',
      ' hydrochloride',
      'i'
    );
    applied_rules := array_append(applied_rules, 'salt_hcl_expansion');
  elsif working_text ~* '^.+[[:space:]]+HBR$' then
    working_text := regexp_replace(
      working_text,
      '[[:space:]]+HBR$',
      ' hydrobromide',
      'i'
    );
    applied_rules := array_append(applied_rules, 'salt_hbr_expansion');
  end if;

  -- A small reviewed prefix set allows deterministic camelCase word-boundary
  -- recovery for legacy forms such as calciumCarbonate. Arbitrary mixed-case
  -- strings are not split: paraCetamol therefore stays one token and is fixed
  -- only by display-case normalization below.
  foreach camel_prefix in array array[
    'calcium',
    'magnesium',
    'sodium',
    'potassium',
    'ferrous',
    'ferric',
    'zinc',
    'aluminium',
    'aluminum'
  ]::text[]
  loop
    if working_text ~ ('^' || camel_prefix || '[A-Z][[:alpha:]-]+$') then
      working_text := regexp_replace(
        working_text,
        '^(' || camel_prefix || ')([A-Z])',
        E'\\1 \\2'
      );
      applied_rules := array_append(
        applied_rules,
        'camelcase_known_prefix_split'
      );
      exit;
    end if;
  end loop;

  -- Do not alter the case of standalone abbreviation/formula-like tokens that
  -- were not explicitly reviewed above. HCL, HBR, CA, FE, ZN, etc. therefore
  -- remain visible for review rather than being corrupted to Hcl/Ca/Fe/Zn.
  if working_text ~ '^[A-Z0-9]{1,5}$' then
    candidate_text := working_text;
    cleanup_status := 'needs_review';
    review_reasons := array['standalone_abbreviation_or_formula']::text[];
    return next;
    return;
  end if;

  lower_text := lower(working_text);
  candidate_text := upper(substr(lower_text, 1, 1)) || substr(lower_text, 2);
  if candidate_text is distinct from working_text then
    applied_rules := array_append(applied_rules, 'display_case_normalization');
  end if;

  cleanup_status := 'deterministic_candidate';
  return next;
end;
$scientific_cleanup_component_candidate$;

revoke all on function app_private.scientific_cleanup_component_candidate(text)
from public, anon, authenticated;
