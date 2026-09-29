-- SP-031: expose only trusted product ingredient identities needed for
-- downstream DDI analysis. Private normalization tables remain inaccessible to
-- normal clients and raw composition text is not reparsed here.

create or replace function public.catalog_ddi_ingredients(
  requested_product_ids uuid[]
)
returns table (
  request_position integer,
  product_id uuid,
  product_exists boolean,
  coverage_status text,
  normalization_status text,
  component_count integer,
  resolved_component_count integer,
  component_index smallint,
  ingredient_id bigint,
  ingredient_name text,
  normalized_ingredient_name text
)
language plpgsql
security definer
set search_path = ''
as $catalog_ddi_ingredients$
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
  base as (
    select
      r.request_position,
      r.product_id,
      p.id is not null as product_exists,
      n.status,
      n.ingredient_set_key,
      n.component_count,
      n.resolved_component_count,
      coalesce(links.linked_component_count, 0) as linked_component_count
    from requested r
    left join public.products p
      on p.id = r.product_id
    left join app_private.product_composition_normalization n
      on n.product_id = p.id
    left join lateral (
      select count(*)::integer as linked_component_count
      from app_private.product_ingredients pi_count
      where pi_count.product_id = p.id
    ) links on true
  ),
  coverage as (
    select
      b.*,
      (
        b.product_exists
        and b.status in ('auto_verified', 'high_confidence')
        and b.ingredient_set_key is not null
        and b.component_count > 0
        and b.resolved_component_count = b.component_count
        and b.linked_component_count = b.component_count
      ) as is_trusted,
      case
        when not b.product_exists then 'missing'
        when b.status = 'needs_review' then 'needs_review'
        when b.status = 'unresolved' or b.status is null then 'unresolved'
        when b.status in ('auto_verified', 'high_confidence')
          and b.ingredient_set_key is not null
          and b.component_count > 0
          and b.resolved_component_count = b.component_count
          and b.linked_component_count = b.component_count
          then 'trusted'
        else 'unresolved'
      end::text as coverage_status
    from base b
  )
  select
    c.request_position,
    c.product_id,
    c.product_exists,
    c.coverage_status,
    c.status::text as normalization_status,
    c.component_count,
    c.resolved_component_count,
    pi.component_index,
    case when c.is_trusted then i.id else null end as ingredient_id,
    case when c.is_trusted then i.name else null end as ingredient_name,
    case
      when c.is_trusted then i.normalized_name
      else null
    end as normalized_ingredient_name
  from coverage c
  left join app_private.product_ingredients pi
    on c.is_trusted
    and pi.product_id = c.product_id
  left join app_private.catalog_ingredients i
    on i.id = pi.ingredient_id
  order by
    c.request_position,
    pi.component_index nulls first;
end;
$catalog_ddi_ingredients$;

revoke all on function public.catalog_ddi_ingredients(uuid[])
from public, anon, authenticated;

grant execute on function public.catalog_ddi_ingredients(uuid[])
to authenticated;

comment on function public.catalog_ddi_ingredients(uuid[]) is
  'SP-031 bounded owner-only product-to-trusted-ingredient input mapping for DDI analysis.';
