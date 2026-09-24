-- SP-004: owner-only bounded catalog API.
-- Production owner UUID provisioning and remote deployment are separate deployment steps.

create schema if not exists app_private;
revoke all on schema app_private from public;

create table app_private.owner_account (
  singleton boolean primary key default true check (singleton),
  user_id uuid not null unique
);
revoke all on app_private.owner_account from public, anon, authenticated;

create or replace function app_private.require_owner()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  current_user_id uuid;
begin
  current_user_id := auth.uid();

  if current_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from app_private.owner_account
    where singleton = true and user_id = current_user_id
  ) then
    raise exception 'owner authorization required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function app_private.require_owner() from public, anon, authenticated;

alter table public.products enable row level security;
revoke all on public.products from public, anon, authenticated;

create or replace function public.catalog_search(
  search_text text,
  requested_limit integer default 25
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
  normalized_query text;
  bounded_limit integer;
begin
  perform app_private.require_owner();

  normalized_query := btrim(coalesce(search_text, ''));
  if normalized_query = '' then
    return;
  end if;

  bounded_limit := greatest(1, least(coalesce(requested_limit, 25), 50));

  return query
  select
    p.id, p.name_en, p.name_ar, p.composition, p.manufacturer, p.strength,
    p.dosage_form, p.package_description, p.barcode, p.barcode2,
    p.selling_amount, p.currency, p.notes, p.revision, p.updated_at
  from public.products p
  where
    strpos(lower(coalesce(p.name_en, '')), lower(normalized_query)) > 0
    or strpos(lower(coalesce(p.name_ar, '')), lower(normalized_query)) > 0
    or strpos(lower(coalesce(p.composition, '')), lower(normalized_query)) > 0
  order by
    case when lower(coalesce(p.name_en, '')) = lower(normalized_query) then 0 else 1 end,
    p.name_en nulls last,
    p.name_ar nulls last,
    p.id
  limit bounded_limit;
end;
$$;

create or replace function public.catalog_get(product_id uuid)
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
begin
  perform app_private.require_owner();

  return query
  select
    p.id, p.name_en, p.name_ar, p.composition, p.manufacturer, p.strength,
    p.dosage_form, p.package_description, p.barcode, p.barcode2,
    p.selling_amount, p.currency, p.notes, p.revision, p.updated_at
  from public.products p
  where p.id = product_id;
end;
$$;

create or replace function public.catalog_lookup_barcode(code text)
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
  lookup_code text;
begin
  perform app_private.require_owner();

  lookup_code := coalesce(code, '');
  if lookup_code = '' then
    return;
  end if;

  return query
  select
    p.id, p.name_en, p.name_ar, p.composition, p.manufacturer, p.strength,
    p.dosage_form, p.package_description, p.barcode, p.barcode2,
    p.selling_amount, p.currency, p.notes, p.revision, p.updated_at
  from public.products p
  where p.barcode = lookup_code or p.barcode2 = lookup_code
  order by p.id
  limit 50;
end;
$$;

create or replace function public.catalog_create(
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
  created_id uuid;
begin
  perform app_private.require_owner();

  insert into public.products (
    name_en, name_ar, composition, manufacturer, strength, dosage_form,
    package_description, barcode, barcode2, selling_amount, currency, notes
  ) values (
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
  returning products.id into created_id;

  return query select * from public.catalog_get(created_id);
end;
$$;

create or replace function public.catalog_update(
  product_id uuid,
  expected_revision bigint,
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
  updated_id uuid;
begin
  perform app_private.require_owner();

  update public.products p
  set
    name_en = nullif(product_name_en, ''),
    name_ar = nullif(product_name_ar, ''),
    composition = nullif(product_composition, ''),
    manufacturer = nullif(product_manufacturer, ''),
    strength = nullif(product_strength, ''),
    dosage_form = nullif(product_dosage_form, ''),
    package_description = nullif(product_package_description, ''),
    barcode = nullif(product_barcode, ''),
    barcode2 = nullif(product_barcode2, ''),
    selling_amount = product_selling_amount,
    currency = product_currency,
    notes = nullif(product_notes, '')
  where p.id = product_id and p.revision = expected_revision
  returning p.id into updated_id;

  if updated_id is null then
    if exists (select 1 from public.products where products.id = product_id) then
      raise exception 'revision conflict' using errcode = '40001';
    end if;
    raise exception 'product not found' using errcode = 'P0002';
  end if;

  return query select * from public.catalog_get(updated_id);
end;
$$;

revoke all on function public.catalog_search(text, integer) from public, anon;
revoke all on function public.catalog_get(uuid) from public, anon;
revoke all on function public.catalog_lookup_barcode(text) from public, anon;
revoke all on function public.catalog_create(text,text,text,text,text,text,text,text,text,bigint,text,text) from public, anon;
revoke all on function public.catalog_update(uuid,bigint,text,text,text,text,text,text,text,text,text,bigint,text,text) from public, anon;

grant execute on function public.catalog_search(text, integer) to authenticated;
grant execute on function public.catalog_get(uuid) to authenticated;
grant execute on function public.catalog_lookup_barcode(text) to authenticated;
grant execute on function public.catalog_create(text,text,text,text,text,text,text,text,text,bigint,text,text) to authenticated;
grant execute on function public.catalog_update(uuid,bigint,text,text,text,text,text,text,text,text,text,bigint,text,text) to authenticated;
