-- SP-028: expose conservative pharmaceutical relationships through one bounded,
-- owner-authorized RPC. This query layer does not change normalization state,
-- product data, revisions, prices, barcodes, or order/session behavior.

create or replace function public.catalog_alternatives(
  target_product_id uuid,
  requested_limit_per_group integer default 10
)
returns table (
  relationship_group text,
  group_position integer,
  normalization_status text,
  id uuid,
  name_en text,
  name_ar text,
  composition text,
  manufacturer text,
  strength text,
  dosage_form text,
  package_description text,
  barcode text,
  barcode2 text,
  selling_amount bigint,
  currency text,
  notes text,
  revision bigint,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $catalog_alternatives$
declare
  bounded_limit integer;
  target_exists boolean;
  target_ingredient_set_key text;
  target_composition_status app_private.composition_normalization_status;
  target_ingredient_strength_set_key text;
  target_strength_status app_private.strength_normalization_status;
  target_strict_equivalence_key text;
  target_form_class_key text;
  target_route_class app_private.pharmaceutical_route_class;
  target_release_class app_private.pharmaceutical_release_class;
  target_equivalence_status app_private.pharmaceutical_equivalence_status;
begin
  perform app_private.require_owner();

  select exists (
    select 1
    from public.products p
    where p.id = target_product_id
  )
    into target_exists;

  if not target_exists then
    raise exception 'product not found' using errcode = 'P0002';
  end if;

  bounded_limit := greatest(
    1,
    least(coalesce(requested_limit_per_group, 10), 25)
  );

  select
    c.ingredient_set_key,
    c.status,
    s.ingredient_strength_set_key,
    s.status,
    e.strict_equivalence_key,
    e.form_class_key,
    e.route_class,
    e.release_class,
    e.status
    into
      target_ingredient_set_key,
      target_composition_status,
      target_ingredient_strength_set_key,
      target_strength_status,
      target_strict_equivalence_key,
      target_form_class_key,
      target_route_class,
      target_release_class,
      target_equivalence_status
  from public.products p
  left join app_private.product_composition_normalization c
    on c.product_id = p.id
  left join app_private.product_strength_normalization s
    on s.product_id = p.id
  left join app_private.product_pharmaceutical_equivalence e
    on e.product_id = p.id
  where p.id = target_product_id;

  -- Relationship groups depend on a trusted target across the full SP-025 ->
  -- SP-027 chain. An existing target that cannot be classified safely returns
  -- no rows instead of weakening the comparison rules.
  if target_composition_status is null
     or target_composition_status not in ('auto_verified', 'high_confidence')
     or target_ingredient_set_key is null
     or target_strength_status is null
     or target_strength_status not in ('auto_verified', 'high_confidence')
     or target_ingredient_strength_set_key is null
     or target_equivalence_status is null
     or target_equivalence_status not in ('auto_verified', 'high_confidence')
     or target_strict_equivalence_key is null
     or target_form_class_key is null
     or target_route_class is null
     or target_release_class is null then
    return;
  end if;

  return query
  with relationship_candidates as (
    select
      'exact'::text as candidate_group,
      1 as candidate_group_order,
      case
        when target_equivalence_status = 'high_confidence'
          or e.status = 'high_confidence'
          then 'high_confidence'
        else 'auto_verified'
      end::text as candidate_normalization_status,
      p.id,
      p.name_en,
      p.name_ar,
      p.composition,
      p.manufacturer,
      p.strength,
      p.dosage_form,
      p.package_description,
      p.barcode,
      p.barcode2,
      p.selling_amount,
      p.currency::text as currency,
      p.notes,
      p.revision,
      p.updated_at
    from app_private.product_pharmaceutical_equivalence e
    join public.products p
      on p.id = e.product_id
    where e.product_id <> target_product_id
      and e.status in ('auto_verified', 'high_confidence')
      and e.strict_equivalence_key = target_strict_equivalence_key

    union all

    select
      'same_ingredients_different_strength'::text,
      2,
      case
        when target_equivalence_status = 'high_confidence'
          or e.status = 'high_confidence'
          then 'high_confidence'
        else 'auto_verified'
      end::text,
      p.id,
      p.name_en,
      p.name_ar,
      p.composition,
      p.manufacturer,
      p.strength,
      p.dosage_form,
      p.package_description,
      p.barcode,
      p.barcode2,
      p.selling_amount,
      p.currency::text,
      p.notes,
      p.revision,
      p.updated_at
    from app_private.product_composition_normalization c
    join app_private.product_strength_normalization s
      on s.product_id = c.product_id
    join app_private.product_pharmaceutical_equivalence e
      on e.product_id = c.product_id
    join public.products p
      on p.id = c.product_id
    where c.product_id <> target_product_id
      and c.status in ('auto_verified', 'high_confidence')
      and c.ingredient_set_key = target_ingredient_set_key
      and s.status in ('auto_verified', 'high_confidence')
      and s.ingredient_strength_set_key is not null
      and s.ingredient_strength_set_key <> target_ingredient_strength_set_key
      and e.status in ('auto_verified', 'high_confidence')
      and e.form_class_key = target_form_class_key
      and e.route_class = target_route_class
      and e.release_class = target_release_class

    union all

    select
      'same_ingredients_different_form'::text,
      3,
      case
        when target_equivalence_status = 'high_confidence'
          or e.status = 'high_confidence'
          then 'high_confidence'
        else 'auto_verified'
      end::text,
      p.id,
      p.name_en,
      p.name_ar,
      p.composition,
      p.manufacturer,
      p.strength,
      p.dosage_form,
      p.package_description,
      p.barcode,
      p.barcode2,
      p.selling_amount,
      p.currency::text,
      p.notes,
      p.revision,
      p.updated_at
    from app_private.product_composition_normalization c
    join app_private.product_strength_normalization s
      on s.product_id = c.product_id
    join app_private.product_pharmaceutical_equivalence e
      on e.product_id = c.product_id
    join public.products p
      on p.id = c.product_id
    where c.product_id <> target_product_id
      and c.status in ('auto_verified', 'high_confidence')
      and c.ingredient_set_key = target_ingredient_set_key
      and s.status in ('auto_verified', 'high_confidence')
      and s.ingredient_strength_set_key =
        target_ingredient_strength_set_key
      and e.status in ('auto_verified', 'high_confidence')
      and (
        e.form_class_key is distinct from target_form_class_key
        or e.route_class is distinct from target_route_class
        or e.release_class is distinct from target_release_class
      )
  ),
  ranked as (
    select
      rc.*,
      row_number() over (
        partition by rc.candidate_group
        order by
          lower(coalesce(rc.name_en, rc.name_ar, '')),
          coalesce(rc.name_en, ''),
          coalesce(rc.name_ar, ''),
          rc.id
      ) as candidate_position
    from relationship_candidates rc
  )
  select
    r.candidate_group,
    r.candidate_position::integer,
    r.candidate_normalization_status,
    r.id,
    r.name_en,
    r.name_ar,
    r.composition,
    r.manufacturer,
    r.strength,
    r.dosage_form,
    r.package_description,
    r.barcode,
    r.barcode2,
    r.selling_amount,
    r.currency,
    r.notes,
    r.revision,
    r.updated_at
  from ranked r
  where r.candidate_position <= bounded_limit
  order by
    r.candidate_group_order,
    r.candidate_position;
end;
$catalog_alternatives$;

revoke all on function public.catalog_alternatives(uuid, integer)
from public, anon, authenticated;

grant execute on function public.catalog_alternatives(uuid, integer)
to authenticated;
