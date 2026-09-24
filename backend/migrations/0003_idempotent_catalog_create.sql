-- SP-008: additive idempotent manual product creation.
-- The legacy catalog_create RPC remains available for compatibility.

create or replace function public.catalog_create_idempotent(
  product_id uuid,
  product_name_en text,
  product_name_ar text,
  product_composition text,
  product_manufacturer text,
  product_strength text,
  product_dosage_form text,
  product_package_description text,
  product_barcode text,
  product_barcode2 text,
  product_selling_amount bigint,
  product_currency text,
  product_notes text
)
returns table (
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
set search_path = pg_catalog, public, app_private
as $$
declare
  inserted_id uuid;
begin
  perform app_private.require_owner();

  insert into public.products (
    id,
    name_en,
    name_ar,
    composition,
    manufacturer,
    strength,
    dosage_form,
    package_description,
    barcode,
    barcode2,
    selling_amount,
    currency,
    notes
  ) values (
    product_id,
    nullif(product_name_en, ''),
    nullif(product_name_ar, ''),
    nullif(product_composition, ''),
    nullif(product_manufacturer, ''),
    nullif(product_strength, ''),
    nullif(product_dosage_form, ''),
    nullif(product_package_description, ''),
    nullif(product_barcode, ''),
    nullif(product_barcode2, ''),
    product_selling_amount,
    product_currency,
    nullif(product_notes, '')
  )
  on conflict on constraint products_pkey do nothing
  returning products.id into inserted_id;

  if inserted_id is not null then
    return query select * from public.catalog_get(inserted_id);
    return;
  end if;

  if exists (
    select 1
    from public.products p
    where p.id = product_id
      and p.name_en is not distinct from nullif(product_name_en, '')
      and p.name_ar is not distinct from nullif(product_name_ar, '')
      and p.composition is not distinct from nullif(product_composition, '')
      and p.manufacturer is not distinct from nullif(product_manufacturer, '')
      and p.strength is not distinct from nullif(product_strength, '')
      and p.dosage_form is not distinct from nullif(product_dosage_form, '')
      and p.package_description is not distinct from nullif(product_package_description, '')
      and p.barcode is not distinct from nullif(product_barcode, '')
      and p.barcode2 is not distinct from nullif(product_barcode2, '')
      and p.selling_amount = product_selling_amount
      and p.currency = product_currency
      and p.notes is not distinct from nullif(product_notes, '')
  ) then
    return query select * from public.catalog_get(product_id);
    return;
  end if;

  raise exception 'product create request conflicts with existing identity'
    using errcode = '40001';
end;
$$;

revoke all on function public.catalog_create_idempotent(
  uuid,text,text,text,text,text,text,text,text,text,bigint,text,text
) from public, anon;

grant execute on function public.catalog_create_idempotent(
  uuid,text,text,text,text,text,text,text,text,text,bigint,text,text
) to authenticated;
