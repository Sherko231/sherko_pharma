-- SDIF-010: expose a bounded owner-only read path from requested catalog
-- products to reviewed scientific identities with reviewed ATC metadata.
-- Private canonicalization tables remain inaccessible to normal clients.

create or replace function public.catalog_sdif_scientific_identities(
  requested_product_ids uuid[]
)
returns table (
  request_position integer,
  product_id uuid,
  product_exists boolean,
  coverage_status text,
  canonicalization_status text,
  ingredient_count integer,
  trusted_component_count integer,
  atc_covered_component_count integer,
  eligible_identity_count integer,
  identity_position integer,
  scientific_ingredient_id bigint,
  preferred_name text,
  reviewed_atc_codes text[]
)
language plpgsql
security definer
set search_path = ''
as $catalog_sdif_scientific_identities$
declare
  requested_count integer;
begin
  perform app_private.require_owner();

  if requested_product_ids is null then
    raise exception 'requested product ids must not be null'
      using errcode = '22023';
  end if;

  requested_count := coalesce(
    pg_catalog.cardinality(requested_product_ids),
    0
  );

  if requested_count = 0 then
    return;
  end if;

  if requested_count > 50 then
    raise exception 'at most 50 product ids may be requested'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from pg_catalog.unnest(requested_product_ids) as requested(product_id)
    where requested.product_id is null
  ) then
    raise exception 'requested product ids must not contain null'
      using errcode = '22023';
  end if;

  return query
  with requested as (
    select
      input.product_id,
      min(input.ordinality)::integer as request_position
    from pg_catalog.unnest(requested_product_ids)
      with ordinality as input(product_id, ordinality)
    group by input.product_id
  ),
  ingredient_nodes as (
    select
      n.product_id,
      n.node_path,
      n.identity_status::text as identity_status,
      n.scientific_ingredient_id
    from app_private.product_scientific_canonicalization_nodes n
    join requested r
      on r.product_id = n.product_id
    where n.node_kind = 'ingredient'
  ),
  component_stats as (
    select
      n.product_id,
      count(n.node_path)::integer as ingredient_count,
      count(n.node_path) filter (
        where n.identity_status = 'trusted'
          and n.scientific_ingredient_id is not null
      )::integer as trusted_component_count,
      count(n.node_path) filter (
        where n.identity_status = 'trusted'
          and n.scientific_ingredient_id is not null
          and exists (
            select 1
            from app_private.scientific_ingredient_atc_codes a
            where a.scientific_ingredient_id = n.scientific_ingredient_id
          )
      )::integer as atc_covered_component_count,
      count(distinct n.scientific_ingredient_id) filter (
        where n.identity_status = 'trusted'
          and n.scientific_ingredient_id is not null
          and exists (
            select 1
            from app_private.scientific_ingredient_atc_codes a
            where a.scientific_ingredient_id = n.scientific_ingredient_id
          )
      )::integer as eligible_identity_count
    from ingredient_nodes n
    group by n.product_id
  ),
  identity_seeds as (
    select
      n.product_id,
      n.scientific_ingredient_id,
      min(n.node_path) as first_node_path
    from ingredient_nodes n
    where n.identity_status = 'trusted'
      and n.scientific_ingredient_id is not null
      and exists (
        select 1
        from app_private.scientific_ingredient_atc_codes a
        where a.scientific_ingredient_id = n.scientific_ingredient_id
      )
    group by n.product_id, n.scientific_ingredient_id
  ),
  eligible_identities as (
    select
      seed.product_id,
      seed.scientific_ingredient_id,
      seed.first_node_path,
      s.preferred_name,
      atc.reviewed_atc_codes
    from identity_seeds seed
    join app_private.scientific_ingredients s
      on s.id = seed.scientific_ingredient_id
    join lateral (
      select pg_catalog.array_agg(a.atc_code order by a.atc_code)
        as reviewed_atc_codes
      from app_private.scientific_ingredient_atc_codes a
      where a.scientific_ingredient_id = seed.scientific_ingredient_id
    ) atc on pg_catalog.cardinality(atc.reviewed_atc_codes) > 0
  ),
  ranked_identities as (
    select
      e.*,
      pg_catalog.row_number() over (
        partition by e.product_id
        order by e.first_node_path, e.scientific_ingredient_id
      )::integer as identity_position
    from eligible_identities e
  ),
  product_base as (
    select
      r.request_position,
      r.product_id,
      p.id is not null as product_exists,
      c.overall_identity_status::text as canonicalization_status,
      coalesce(stats.ingredient_count, 0)::integer as ingredient_count,
      coalesce(stats.trusted_component_count, 0)::integer
        as trusted_component_count,
      coalesce(stats.atc_covered_component_count, 0)::integer
        as atc_covered_component_count,
      coalesce(stats.eligible_identity_count, 0)::integer
        as eligible_identity_count
    from requested r
    left join public.products p
      on p.id = r.product_id
    left join app_private.product_scientific_canonicalization c
      on c.product_id = p.id
    left join component_stats stats
      on stats.product_id = p.id
  ),
  classified as (
    select
      b.*,
      case
        when not b.product_exists then 'missing'
        when b.ingredient_count > 0
          and b.atc_covered_component_count = b.ingredient_count
          then 'complete'
        when b.atc_covered_component_count > 0 then 'partial'
        else 'unmapped'
      end::text as coverage_status
    from product_base b
  )
  select
    c.request_position,
    c.product_id,
    c.product_exists,
    c.coverage_status,
    c.canonicalization_status,
    c.ingredient_count,
    c.trusted_component_count,
    c.atc_covered_component_count,
    c.eligible_identity_count,
    e.identity_position,
    e.scientific_ingredient_id,
    e.preferred_name,
    e.reviewed_atc_codes
  from classified c
  left join ranked_identities e
    on e.product_id = c.product_id
  order by
    c.request_position,
    e.identity_position nulls first;
end;
$catalog_sdif_scientific_identities$;

revoke all on function public.catalog_sdif_scientific_identities(uuid[])
from public, anon, authenticated;

grant execute on function public.catalog_sdif_scientific_identities(uuid[])
to authenticated;

comment on function public.catalog_sdif_scientific_identities(uuid[]) is
  'SDIF-010 bounded owner-only product-to-reviewed-scientific-identity and reviewed-ATC input mapping.';
