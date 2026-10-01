-- SP-044 aggregate-only coverage report.
-- Safe output: counts, percentages, status buckets and reason-code aggregates.
-- It intentionally emits no product names, barcodes, prices, raw compositions,
-- full ingredient lists, account identifiers, or source payloads.

select
  app_private.scientific_canonicalization_version() as canonicalization_version,
  count(*)::bigint as lexical_ingredient_count,
  count(*) filter (where status = 'verified')::bigint as mapped_canonical_ingredient_count,
  count(*) filter (
    where status = 'verified' and mapping_method = 'reviewed_alias'
  )::bigint as synonym_alias_resolved_ingredient_count,
  count(*) filter (where status = 'needs_review')::bigint as review_required_ingredient_count,
  count(*) filter (where status = 'unresolved')::bigint as unresolved_ingredient_count
from app_private.catalog_ingredient_scientific_mappings;

select
  status::text as mapping_status,
  mapping_method::text as mapping_method,
  count(*)::bigint as ingredient_count
from app_private.catalog_ingredient_scientific_mappings
group by status, mapping_method
order by status, mapping_method;

select
  count(*)::bigint as product_count,
  count(*) filter (
    where nullif(btrim(source_composition), '') is not null
  )::bigint as products_with_composition,
  count(*) filter (
    where overall_structure_status = 'deterministic'
      and overall_identity_status = 'trusted'
  )::bigint as fully_trusted_product_count,
  count(*) filter (
    where nullif(btrim(source_composition), '') is not null
      and overall_structure_status = 'deterministic'
      and overall_identity_status = 'trusted'
  )::bigint as fully_trusted_nonblank_product_count,
  round(
    100.0 * count(*) filter (
      where nullif(btrim(source_composition), '') is not null
        and overall_structure_status = 'deterministic'
        and overall_identity_status = 'trusted'
    ) / nullif(count(*) filter (
      where nullif(btrim(source_composition), '') is not null
    ), 0),
    2
  ) as trusted_nonblank_product_percent,
  sum(alias_resolved_count)::bigint as synonym_alias_resolved_component_count,
  count(*) filter (where alias_resolved_count > 0)::bigint as products_with_alias_resolution,
  sum(embedded_strength_component_count)::bigint as embedded_strength_cleanup_component_count,
  count(*) filter (where embedded_strength_component_count > 0)::bigint as products_with_embedded_strength_cleanup,
  sum(needs_review_count)::bigint as review_required_component_count,
  sum(unresolved_count)::bigint as unresolved_component_count
from app_private.product_scientific_canonicalization;

select
  overall_structure_status::text as structure_status,
  overall_identity_status::text as identity_status,
  count(*)::bigint as product_count
from app_private.product_scientific_canonicalization
group by overall_structure_status, overall_identity_status
order by overall_structure_status, overall_identity_status;

select
  strength_comparison_status::text as strength_comparison_status,
  count(*)::bigint as product_count
from app_private.product_scientific_canonicalization
group by strength_comparison_status
order by strength_comparison_status;

with ingredient_nodes as (
  select unnest(reason_codes) as reason_code
  from app_private.product_scientific_canonicalization_nodes
  where node_kind = 'ingredient'
    and identity_status in ('needs_review', 'unresolved')
)
select
  reason_code,
  count(*)::bigint as affected_component_count
from ingredient_nodes
group by reason_code
order by affected_component_count desc, reason_code;

select
  count(*)::bigint as trusted_node_count,
  count(*) filter (where resolution_kind = 'canonical')::bigint as canonical_name_node_count,
  count(*) filter (where resolution_kind = 'reviewed_alias')::bigint as reviewed_alias_node_count
from app_private.product_scientific_canonicalization_nodes
where node_kind = 'ingredient'
  and identity_status = 'trusted';