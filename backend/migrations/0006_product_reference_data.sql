-- SP-024: normalize categorical product reference data without losing source text.
-- Manufacturer and dosage form are dynamic reference entities, not PostgreSQL enums.
-- Existing product text columns remain compatibility/search caches maintained from
-- the reference identity by a trigger, so current RPC shapes do not change.

create or replace function app_private.catalog_reference_key(input_text text)
returns text
language sql
immutable
strict
parallel safe
set search_path = pg_catalog
as $
  select coalesce(
    nullif(app_private.catalog_search_normalize(input_text), ''),
    'raw:' || lower(normalize(btrim(input_text), NFKC))
  )
$;

revoke all on function app_private.catalog_reference_key(text)
from public, anon, authenticated;

create table app_private.catalog_manufacturers (
  id bigint generated always as identity primary key,
  name text not null,
  normalized_name text not null unique,
  created_at timestamptz not null default now(),
  constraint catalog_manufacturers_name_nonblank
    check (btrim(name) <> ''),
  constraint catalog_manufacturers_normalized_name_nonblank
    check (btrim(normalized_name) <> ''),
  constraint catalog_manufacturers_normalized_name_matches
    check (normalized_name = app_private.catalog_reference_key(name))
);

create table app_private.catalog_manufacturer_aliases (
  manufacturer_id bigint not null
    references app_private.catalog_manufacturers(id) on delete cascade,
  alias text not null,
  primary key (manufacturer_id, alias),
  constraint catalog_manufacturer_aliases_nonblank
    check (btrim(alias) <> '')
);

create unique index catalog_manufacturer_aliases_alias_idx
  on app_private.catalog_manufacturer_aliases(alias);

create table app_private.catalog_dosage_forms (
  id bigint generated always as identity primary key,
  name text not null,
  normalized_name text not null unique,
  created_at timestamptz not null default now(),
  constraint catalog_dosage_forms_name_nonblank
    check (btrim(name) <> ''),
  constraint catalog_dosage_forms_normalized_name_nonblank
    check (btrim(normalized_name) <> ''),
  constraint catalog_dosage_forms_normalized_name_matches
    check (normalized_name = app_private.catalog_reference_key(name))
);

create table app_private.catalog_dosage_form_aliases (
  dosage_form_id bigint not null
    references app_private.catalog_dosage_forms(id) on delete cascade,
  alias text not null,
  primary key (dosage_form_id, alias),
  constraint catalog_dosage_form_aliases_nonblank
    check (btrim(alias) <> '')
);

create unique index catalog_dosage_form_aliases_alias_idx
  on app_private.catalog_dosage_form_aliases(alias);

revoke all on app_private.catalog_manufacturers
from public, anon, authenticated;
revoke all on app_private.catalog_manufacturer_aliases
from public, anon, authenticated;
revoke all on app_private.catalog_dosage_forms
from public, anon, authenticated;
revoke all on app_private.catalog_dosage_form_aliases
from public, anon, authenticated;

-- Build one canonical row per normalized key. The most common existing spelling
-- wins; aliases retain every distinct observed spelling.
with counted as (
  select
    app_private.catalog_reference_key(btrim(manufacturer)) as normalized_name,
    btrim(manufacturer) as name,
    count(*) as usage_count
  from public.products
  where nullif(btrim(manufacturer), '') is not null
  group by 1, 2
),
ranked as (
  select *,
    row_number() over (
      partition by normalized_name
      order by usage_count desc, name
    ) as preference
  from counted
)
insert into app_private.catalog_manufacturers(name, normalized_name)
select name, normalized_name
from ranked
where preference = 1
order by normalized_name;

insert into app_private.catalog_manufacturer_aliases(manufacturer_id, alias)
select distinct m.id, btrim(p.manufacturer)
from public.products p
join app_private.catalog_manufacturers m
  on m.normalized_name =
     app_private.catalog_reference_key(btrim(p.manufacturer))
where nullif(btrim(p.manufacturer), '') is not null;

with counted as (
  select
    app_private.catalog_reference_key(btrim(dosage_form)) as normalized_name,
    btrim(dosage_form) as name,
    count(*) as usage_count
  from public.products
  where nullif(btrim(dosage_form), '') is not null
  group by 1, 2
),
ranked as (
  select *,
    row_number() over (
      partition by normalized_name
      order by usage_count desc, name
    ) as preference
  from counted
)
insert into app_private.catalog_dosage_forms(name, normalized_name)
select name, normalized_name
from ranked
where preference = 1
order by normalized_name;

insert into app_private.catalog_dosage_form_aliases(dosage_form_id, alias)
select distinct f.id, btrim(p.dosage_form)
from public.products p
join app_private.catalog_dosage_forms f
  on f.normalized_name =
     app_private.catalog_reference_key(btrim(p.dosage_form))
where nullif(btrim(p.dosage_form), '') is not null;

alter table public.products
  add column manufacturer_id bigint
    references app_private.catalog_manufacturers(id),
  add column dosage_form_id bigint
    references app_private.catalog_dosage_forms(id);

-- This is a structural normalization, not a catalog edit. Preserve product
-- revision/updated_at while backfilling IDs and canonical display spellings.
alter table public.products disable trigger products_set_revision;

update public.products p
set
  manufacturer_id = m.id,
  manufacturer = m.name
from app_private.catalog_manufacturers m
where nullif(btrim(p.manufacturer), '') is not null
  and m.normalized_name =
      app_private.catalog_reference_key(btrim(p.manufacturer));

update public.products p
set
  dosage_form_id = f.id,
  dosage_form = f.name
from app_private.catalog_dosage_forms f
where nullif(btrim(p.dosage_form), '') is not null
  and f.normalized_name =
      app_private.catalog_reference_key(btrim(p.dosage_form));

alter table public.products enable trigger products_set_revision;

create index products_manufacturer_id_idx
  on public.products(manufacturer_id)
  where manufacturer_id is not null;

create index products_dosage_form_id_idx
  on public.products(dosage_form_id)
  where dosage_form_id is not null;

create or replace function app_private.sync_product_references()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  input_label text;
  normalized_label text;
  reference_id bigint;
  canonical_label text;
begin
  input_label := nullif(btrim(new.manufacturer), '');

  if input_label is null and new.manufacturer_id is null then
    new.manufacturer := null;
    new.manufacturer_id := null;
  elsif input_label is null then
    select m.name
      into canonical_label
    from app_private.catalog_manufacturers m
    where m.id = new.manufacturer_id;

    if canonical_label is null then
      raise exception 'unknown manufacturer reference'
        using errcode = '23503';
    end if;

    new.manufacturer := canonical_label;
  else
    normalized_label :=
      app_private.catalog_reference_key(input_label);

    insert into app_private.catalog_manufacturers(name, normalized_name)
    values (input_label, normalized_label)
    on conflict (normalized_name) do nothing;

    select m.id, m.name
      into reference_id, canonical_label
    from app_private.catalog_manufacturers m
    where m.normalized_name = normalized_label;

    insert into app_private.catalog_manufacturer_aliases(
      manufacturer_id,
      alias
    )
    values (reference_id, input_label)
    on conflict do nothing;

    new.manufacturer_id := reference_id;
    new.manufacturer := canonical_label;
  end if;

  input_label := nullif(btrim(new.dosage_form), '');

  if input_label is null and new.dosage_form_id is null then
    new.dosage_form := null;
    new.dosage_form_id := null;
  elsif input_label is null then
    select f.name
      into canonical_label
    from app_private.catalog_dosage_forms f
    where f.id = new.dosage_form_id;

    if canonical_label is null then
      raise exception 'unknown dosage-form reference'
        using errcode = '23503';
    end if;

    new.dosage_form := canonical_label;
  else
    normalized_label :=
      app_private.catalog_reference_key(input_label);

    insert into app_private.catalog_dosage_forms(name, normalized_name)
    values (input_label, normalized_label)
    on conflict (normalized_name) do nothing;

    select f.id, f.name
      into reference_id, canonical_label
    from app_private.catalog_dosage_forms f
    where f.normalized_name = normalized_label;

    insert into app_private.catalog_dosage_form_aliases(
      dosage_form_id,
      alias
    )
    values (reference_id, input_label)
    on conflict do nothing;

    new.dosage_form_id := reference_id;
    new.dosage_form := canonical_label;
  end if;

  return new;
end;
$$;

revoke all on function app_private.sync_product_references()
from public, anon, authenticated;

create trigger products_reference_sync
before insert or update of manufacturer, manufacturer_id, dosage_form, dosage_form_id
on public.products
for each row
execute function app_private.sync_product_references();

create or replace function public.catalog_reference_options(
  reference_kind text,
  search_text text default null,
  requested_limit integer default 200
)
returns table (
  id bigint,
  label text
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

  normalized_query :=
    nullif(app_private.catalog_search_normalize(coalesce(search_text, '')), '');
  bounded_limit := greatest(1, least(coalesce(requested_limit, 200), 500));

  if reference_kind = 'manufacturer' then
    return query
    select m.id, m.name
    from app_private.catalog_manufacturers m
    where normalized_query is null
       or m.normalized_name like normalized_query || '%'
       or strpos(m.normalized_name, normalized_query) > 0
    order by
      case
        when normalized_query is not null
         and m.normalized_name = normalized_query then 0
        when normalized_query is not null
         and m.normalized_name like normalized_query || '%' then 1
        else 2
      end,
      m.name,
      m.id
    limit bounded_limit;
    return;
  end if;

  if reference_kind = 'dosage_form' then
    return query
    select f.id, f.name
    from app_private.catalog_dosage_forms f
    where normalized_query is null
       or f.normalized_name like normalized_query || '%'
       or strpos(f.normalized_name, normalized_query) > 0
    order by
      case
        when normalized_query is not null
         and f.normalized_name = normalized_query then 0
        when normalized_query is not null
         and f.normalized_name like normalized_query || '%' then 1
        else 2
      end,
      f.name,
      f.id
    limit bounded_limit;
    return;
  end if;

  raise exception 'unsupported catalog reference kind'
    using errcode = '22023';
end;
$$;

revoke all on function public.catalog_reference_options(text, text, integer)
from public, anon;

grant execute on function public.catalog_reference_options(text, text, integer)
to authenticated;

-- Guard the structural backfill itself.
do $$
begin
  if exists (
    select 1
    from public.products
    where nullif(btrim(manufacturer), '') is not null
      and manufacturer_id is null
  ) then
    raise exception 'manufacturer reference backfill incomplete';
  end if;

  if exists (
    select 1
    from public.products
    where nullif(btrim(dosage_form), '') is not null
      and dosage_form_id is null
  ) then
    raise exception 'dosage-form reference backfill incomplete';
  end if;
end
$$;
