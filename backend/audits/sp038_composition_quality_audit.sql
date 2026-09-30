-- SP-038 composition-quality production audit.
-- READ-ONLY: every statement in this file is SELECT-only.
-- Do not add DDL/DML or raw catalog exports to this audit.
-- Run against the dedicated Sherko Pharma database through a read-only
-- database surface where available.

-- 1. Core SP-025 baseline and status accounting.
select
  (select count(*) from public.products) as total_products,
  (select count(*) from public.products where nullif(btrim(composition),'') is not null) as products_with_composition,
  (select count(*) from public.products where nullif(btrim(composition),'') is null) as products_without_composition,
  (select count(*) from app_private.product_ingredients) as product_component_rows,
  (select count(distinct raw_component) from app_private.product_ingredients) as distinct_raw_components,
  (select count(distinct normalized_component) from app_private.product_ingredients) as distinct_normalized_components,
  (select count(*) from app_private.catalog_ingredients) as catalog_ingredient_identities,
  (select count(*) from app_private.catalog_ingredient_alias_spellings) as observed_component_spellings,
  (select count(*) from app_private.catalog_ingredient_aliases) as lexical_alias_keys,
  (select count(*) from app_private.product_composition_normalization where status='auto_verified') as status_auto_verified,
  (select count(*) from app_private.product_composition_normalization where status='high_confidence') as status_high_confidence,
  (select count(*) from app_private.product_composition_normalization where status='needs_review') as status_needs_review,
  (select count(*) from app_private.product_composition_normalization where status='unresolved') as status_unresolved,
  (select count(*) from (
     select normalized_alias
     from app_private.catalog_ingredient_alias_spellings
     group by normalized_alias
     having count(*) > 1
   ) s) as alias_keys_with_multiple_spellings,
  (select coalesce(sum(n),0) from (
     select count(*) as n
     from app_private.catalog_ingredient_alias_spellings
     group by normalized_alias
     having count(*) > 1
   ) s) as spellings_in_multispelling_aliases,
  (select coalesce(max(n),0) from (
     select count(*) as n
     from app_private.catalog_ingredient_alias_spellings
     group by normalized_alias
   ) s) as max_spellings_for_one_alias;

-- 2. Component-level deterministic audit flags.
with c as (
  select pi.product_id, pi.raw_component, pi.normalized_component
  from app_private.product_ingredients pi
),
flags as (
  select
    product_id,
    raw_component,
    normalized_component,
    (raw_component ~ '[[:lower:]][[:upper:]]') as camel_case,
    (raw_component ~ '[()]') as parenthesized,
    (
      raw_component ~ '[/,;:&=|]'
      or position('[' in raw_component) > 0
      or position(']' in raw_component) > 0
      or position('{' in raw_component) > 0
      or position('}' in raw_component) > 0
    ) as structural_delimiter,
    (
      raw_component ~* (
        '(^|[^[:alnum:]])[0-9]+([.,][0-9]+)?' ||
        '[[:space:]]*(mg|mcg|ug|µg|g|ml|iu|%)' ||
        '($|[^[:alnum:]])'
      )
    ) as embedded_strength,
    (
      raw_component ~* (
        '/[[:space:]]*(' ||
        '[0-9]+([.,][0-9]+)?[[:space:]]*(ml|mg|mcg|ug|µg|g|iu|%)' ||
        '|tab(let)?s?\.?|cap(sule)?s?\.?|amp(oule)?s?\.?|vials?\.?|' ||
        'sachets?\.?|doses?\.?|puffs?\.?|actuations?\.?|' ||
        'supp(ositor(y|ies))?\.?' ||
        ')[[:space:]]*$'
      )
    ) as denominator_or_presentation_suffix,
    (
      raw_component ~* (
        '(^|[^[:alnum:]])(' ||
        'hcl|hbr|hydrochloride|hydrobromide|sodium|potassium|calcium|' ||
        'acetate|succinate|tartrate|citrate|maleate|fumarate|mesylate|besylate|' ||
        'phosphate|sulfate|sulphate|nitrate|oxalate|lactate|gluconate|' ||
        'pamoate|palmitate|propionate|valerate|hemifumarate|tosylate' ||
        ')([^[:alnum:]]|$)'
      )
    ) as salt_or_ester_marker,
    (
      raw_component ~* (
        '(^|[^[:alnum:]])(' ||
        'vit[.]?[[:space:]]*[a-z0-9]+|vitamin[[:space:]]+[a-z0-9]+|' ||
        'nh4cl|nacl|kcl|hcl|hbr' ||
        ')([^[:alnum:]]|$)'
      )
    ) as abbreviation_or_formula_marker,
    (
      raw_component ~* (
        '(^|[^[:alnum:]])(' ||
        'extract|root|leaf|leaves|seed|oil|herb|flower|bark|fruit|' ||
        'ginseng|ginkgo|echinacea|valerian|senna|aloe|garlic|ginger|' ||
        'turmeric|curcumin|silymarin|thistle|palmetto|cranberry|' ||
        'peppermint|chamomile' ||
        ')([^[:alnum:]]|$)'
      )
    ) as botanical_marker,
    (normalized_component ~ '^(k|p|pp|mg)$') as ambiguous_short_token,
    (
      (length(raw_component)-length(replace(raw_component,'(',''))) <>
      (length(raw_component)-length(replace(raw_component,')','')))
      or
      (length(raw_component)-length(replace(raw_component,'[',''))) <>
      (length(raw_component)-length(replace(raw_component,']','')))
      or
      (length(raw_component)-length(replace(raw_component,'{',''))) <>
      (length(raw_component)-length(replace(raw_component,'}','')))
    ) as unbalanced_grouping
  from c
)
select
  count(*) filter (where camel_case) as camel_case_component_rows,
  count(distinct raw_component) filter (where camel_case) as camel_case_distinct_strings,
  count(distinct product_id) filter (where camel_case) as camel_case_products,
  count(*) filter (where parenthesized) as parenthesized_component_rows,
  count(distinct raw_component) filter (where parenthesized) as parenthesized_distinct_strings,
  count(distinct product_id) filter (where parenthesized) as parenthesized_products,
  count(*) filter (where structural_delimiter) as structural_delimiter_component_rows,
  count(distinct raw_component) filter (where structural_delimiter) as structural_delimiter_distinct_strings,
  count(distinct product_id) filter (where structural_delimiter) as structural_delimiter_products,
  count(*) filter (where embedded_strength) as embedded_strength_component_rows,
  count(distinct raw_component) filter (where embedded_strength) as embedded_strength_distinct_strings,
  count(distinct product_id) filter (where embedded_strength) as embedded_strength_products,
  count(*) filter (where denominator_or_presentation_suffix) as denominator_presentation_component_rows,
  count(distinct raw_component) filter (where denominator_or_presentation_suffix) as denominator_presentation_distinct_strings,
  count(distinct product_id) filter (where denominator_or_presentation_suffix) as denominator_presentation_products,
  count(*) filter (where salt_or_ester_marker) as salt_ester_component_rows,
  count(distinct raw_component) filter (where salt_or_ester_marker) as salt_ester_distinct_strings,
  count(distinct product_id) filter (where salt_or_ester_marker) as salt_ester_products,
  count(*) filter (where abbreviation_or_formula_marker) as abbreviation_formula_component_rows,
  count(distinct raw_component) filter (where abbreviation_or_formula_marker) as abbreviation_formula_distinct_strings,
  count(distinct product_id) filter (where abbreviation_or_formula_marker) as abbreviation_formula_products,
  count(*) filter (where botanical_marker) as botanical_component_rows,
  count(distinct raw_component) filter (where botanical_marker) as botanical_distinct_strings,
  count(distinct product_id) filter (where botanical_marker) as botanical_products,
  count(*) filter (where ambiguous_short_token) as ambiguous_short_component_rows,
  count(distinct raw_component) filter (where ambiguous_short_token) as ambiguous_short_distinct_strings,
  count(distinct product_id) filter (where ambiguous_short_token) as ambiguous_short_products,
  count(*) filter (where unbalanced_grouping) as unbalanced_grouping_component_rows,
  count(distinct raw_component) filter (where unbalanced_grouping) as unbalanced_grouping_distinct_strings,
  count(distinct product_id) filter (where unbalanced_grouping) as unbalanced_grouping_products
from flags;

-- 3. Explain every current SP-025 review/unresolved product.
with product_flags as (
  select
    p.id,
    p.composition,
    n.status,
    (
      nullif(btrim(p.composition),'') is not null
      and (
        p.composition ~ '(^|[+])[[:space:]]*[+]'
        or p.composition ~ '[+][[:space:]]*$'
      )
    ) as has_empty_plus_segment,
    (p.composition ~ '\([^)]*[+][^)]*\)') as has_grouped_plus_expression,
    (
      exists (
        select 1
        from app_private.product_ingredients a
        join app_private.product_ingredients b
          on b.product_id=a.product_id
         and b.component_index>a.component_index
         and b.normalized_component=a.normalized_component
        where a.product_id=p.id
      )
    ) as has_duplicate_normalized_component,
    (
      exists (
        select 1
        from app_private.product_ingredients pi
        where pi.product_id=p.id
          and (
            pi.raw_component ~ '[()/,;:&=|]'
            or position('[' in pi.raw_component)>0
            or position(']' in pi.raw_component)>0
            or position('{' in pi.raw_component)>0
            or position('}' in pi.raw_component)>0
            or pi.raw_component ~* (
              '(^|[^[:alnum:]])[0-9]+([.,][0-9]+)?' ||
              '[[:space:]]*(mg|mcg|ug|µg|g|ml|iu|%)' ||
              '($|[^[:alnum:]])'
            )
          )
      )
    ) as has_sp025_review_pattern
  from public.products p
  join app_private.product_composition_normalization n on n.product_id=p.id
)
select
  count(*) filter (where has_grouped_plus_expression) as grouped_plus_products,
  count(*) filter (where has_empty_plus_segment) as empty_plus_segment_products,
  count(*) filter (where status='needs_review' and has_duplicate_normalized_component) as needs_review_duplicate_products,
  count(*) filter (where status='needs_review' and has_sp025_review_pattern) as needs_review_pattern_products,
  count(*) filter (where status='needs_review' and has_duplicate_normalized_component and has_sp025_review_pattern) as needs_review_both_products,
  count(*) filter (where status='needs_review' and not has_duplicate_normalized_component and not has_sp025_review_pattern) as needs_review_unaccounted_products,
  count(*) filter (where status='unresolved' and nullif(btrim(composition),'') is not null) as unresolved_nonblank_products,
  count(*) filter (where status='unresolved' and has_empty_plus_segment) as unresolved_empty_segment_products,
  count(*) filter (where status='unresolved' and nullif(btrim(composition),'') is not null and not has_empty_plus_segment) as unresolved_nonblank_other_products
from product_flags;

-- 4. Conservative orthographic-neighbor workload sizing.
with pairs as (
  select
    a.id as a_id,
    b.id as b_id,
    similarity(a.normalized_name,b.normalized_name) as sim
  from app_private.catalog_ingredients a
  join app_private.catalog_ingredients b
    on b.id>a.id
   and left(a.normalized_name,3)=left(b.normalized_name,3)
   and abs(length(a.normalized_name)-length(b.normalized_name))<=2
   and length(a.normalized_name)>=5
   and length(b.normalized_name)>=5
),
accepted_for_review_queue as (
  select a_id,b_id
  from pairs
  where sim>=0.85
),
endpoints as (
  select a_id as id from accepted_for_review_queue
  union
  select b_id as id from accepted_for_review_queue
)
select
  (select count(*) from accepted_for_review_queue) as candidate_pairs,
  (select count(*) from endpoints) as candidate_identities,
  (select count(*) from app_private.product_ingredients where ingredient_id in (select id from endpoints)) as candidate_component_rows,
  (select count(distinct product_id) from app_private.product_ingredients where ingredient_id in (select id from endpoints)) as candidate_products;

-- 5. Wider supplement/botanical and parenthesized-name candidates.
with multispelling_aliases as (
  select normalized_alias
  from app_private.catalog_ingredient_alias_spellings
  group by normalized_alias
  having count(*) > 1
),
component_flags as (
  select
    pi.product_id,
    pi.raw_component,
    pi.normalized_component,
    (pi.normalized_component in (select normalized_alias from multispelling_aliases)) as lexical_variant_alias,
    (
      pi.raw_component ~* (
        '(^|[^[:alnum:]])(' ||
        'extract|root|leaf|leaves|seed|oil|herb|flower|bark|fruit|' ||
        'ginseng|ginkgo|echinacea|valerian|senna|aloe|garlic|ginger|' ||
        'turmeric|curcumin|silymarin|thistle|palmetto|cranberry|' ||
        'peppermint|chamomile|vitamin|multivitamin|mineral|omega[- ]?3|' ||
        'fish[[:space:]]+oil|coenzyme|probiotic|lactobacillus|' ||
        'bifidobacterium|collagen|glucosamine|chondroitin' ||
        ')([^[:alnum:]]|$)'
      )
      or pi.raw_component ~* '(^|[^[:alnum:]])vit[.]?[[:space:]]*[a-z0-9]+([^[:alnum:]]|$)'
    ) as supplement_or_botanical_marker,
    (
      pi.raw_component ~ '\([^)]*[[:alpha:]][^)]*\)'
      and not pi.raw_component ~* '[0-9]+([.,][0-9]+)?[[:space:]]*(mg|mcg|ug|µg|g|ml|iu|%)'
    ) as parenthesized_name_candidate
  from app_private.product_ingredients pi
)
select
  (select count(*) from multispelling_aliases) as lexical_variant_alias_keys,
  (select count(*) from app_private.catalog_ingredient_alias_spellings s
   where s.normalized_alias in (select normalized_alias from multispelling_aliases)) as lexical_variant_observed_spellings,
  count(*) filter (where lexical_variant_alias) as lexical_variant_component_rows,
  count(distinct product_id) filter (where lexical_variant_alias) as lexical_variant_products,
  count(*) filter (where supplement_or_botanical_marker) as supplement_botanical_component_rows,
  count(distinct raw_component) filter (where supplement_or_botanical_marker) as supplement_botanical_distinct_strings,
  count(distinct product_id) filter (where supplement_or_botanical_marker) as supplement_botanical_products,
  count(*) filter (where parenthesized_name_candidate) as parenthesized_name_component_rows,
  count(distinct raw_component) filter (where parenthesized_name_candidate) as parenthesized_name_distinct_strings,
  count(distinct product_id) filter (where parenthesized_name_candidate) as parenthesized_name_products
from component_flags;

-- 6. Embedded composition strength versus the separate authoritative strength.
with flagged as (
  select distinct
    pi.product_id,
    (
      pi.raw_component ~* (
        '(^|[^[:alnum:]])[0-9]+([.,][0-9]+)?' ||
        '[[:space:]]*(mg|mcg|ug|µg|g|ml|iu|%)' ||
        '($|[^[:alnum:]])'
      )
    ) as embedded_strength,
    (
      pi.raw_component ~* (
        '/[[:space:]]*(' ||
        '[0-9]+([.,][0-9]+)?[[:space:]]*(ml|mg|mcg|ug|µg|g|iu|%)' ||
        '|tab(let)?s?\.?|cap(sule)?s?\.?|amp(oule)?s?\.?|vials?\.?|' ||
        'sachets?\.?|doses?\.?|puffs?\.?|actuations?\.?|' ||
        'supp(ositor(y|ies))?\.?' ||
        ')[[:space:]]*$'
      )
    ) as denom_presentation
  from app_private.product_ingredients pi
),
per_product as (
  select
    product_id,
    bool_or(embedded_strength) as embedded_strength,
    bool_or(denom_presentation) as denom_presentation
  from flagged
  group by product_id
)
select
  count(*) filter (where f.embedded_strength) as embedded_strength_products,
  count(*) filter (where f.embedded_strength and nullif(btrim(p.strength),'') is not null) as embedded_strength_with_separate_strength,
  count(*) filter (where f.embedded_strength and nullif(btrim(p.strength),'') is null) as embedded_strength_without_separate_strength,
  count(*) filter (where f.embedded_strength and sn.status='auto_verified') as embedded_strength_strength_auto_verified,
  count(*) filter (where f.embedded_strength and sn.status='high_confidence') as embedded_strength_strength_high_confidence,
  count(*) filter (where f.embedded_strength and sn.status='needs_review') as embedded_strength_strength_needs_review,
  count(*) filter (where f.embedded_strength and sn.status='unresolved') as embedded_strength_strength_unresolved,
  count(*) filter (where f.denom_presentation) as denom_presentation_products,
  count(*) filter (where f.denom_presentation and nullif(btrim(p.strength),'') is not null) as denom_presentation_with_separate_strength,
  count(*) filter (where f.denom_presentation and nullif(btrim(p.strength),'') is null) as denom_presentation_without_separate_strength
from per_product f
join public.products p on p.id=f.product_id
join app_private.product_strength_normalization sn on sn.product_id=f.product_id;

-- 7. Component-count distribution.
select component_count, count(*) as products
from app_private.product_composition_normalization
group by component_count
order by component_count;

-- 8. Exact counts for examples already named in Issue #100 / planned tasks.
select
  count(*) filter (where lower(raw_component) like 'amoxicilline%') as amoxicilline_component_rows,
  count(*) filter (where lower(raw_component) like 'cafeine%') as cafeine_component_rows,
  count(*) filter (where raw_component like '%paraCetamol%') as paracetamol_camelcase_rows,
  count(*) filter (where raw_component like '%calciumCarbonate%') as calciumcarbonate_camelcase_rows,
  count(*) filter (where upper(raw_component)='VIT.C') as vit_c_rows,
  count(*) filter (where upper(raw_component)='NH4CL') as nh4cl_rows,
  count(*) filter (where upper(raw_component)='K') as k_rows,
  count(*) filter (where upper(raw_component)='P') as p_rows,
  count(*) filter (where upper(raw_component)='PP') as pp_rows,
  count(*) filter (where upper(raw_component)='MG') as mg_rows
from app_private.product_ingredients;
