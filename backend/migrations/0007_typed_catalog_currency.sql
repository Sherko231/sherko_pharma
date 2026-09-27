-- SP-024: make the stable currency domain a database enum while preserving
-- the existing RPC contract as text for current clients.

create type app_private.catalog_currency as enum ('SYP', 'USD');

alter table public.products
  drop constraint products_currency_supported;

alter table public.products
  alter column currency type app_private.catalog_currency
  using currency::app_private.catalog_currency;

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
    p.selling_amount, p.currency::text, p.notes, p.revision, p.updated_at
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
    p.selling_amount, p.currency::text, p.notes, p.revision, p.updated_at
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
    product_currency::app_private.catalog_currency,
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
    currency = product_currency::app_private.catalog_currency,
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
  typed_currency app_private.catalog_currency;
begin
  perform app_private.require_owner();
  typed_currency := product_currency::app_private.catalog_currency;

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
    typed_currency,
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
      and p.currency = typed_currency
      and p.notes is not distinct from nullif(product_notes, '')
  ) then
    return query select * from public.catalog_get(product_id);
    return;
  end if;

  raise exception 'product create request conflicts with existing identity'
    using errcode = '40001';
end;
$$;

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
set search_path = pg_catalog, public, app_private, extensions
as $$
declare
  raw_query text;
  normalized_query text;
  bounded_limit integer;
  query_length integer;
  prefix_query_text text;
  prefix_query tsquery;
  fuzzy_threshold text;
begin
  perform app_private.require_owner();

  raw_query := btrim(coalesce(search_text, ''));
  if raw_query = '' then
    return;
  end if;

  bounded_limit := greatest(1, least(coalesce(requested_limit, 25), 50));
  normalized_query := app_private.catalog_search_normalize(raw_query);

  if normalized_query = '' then
    return query
    select
      p.id, p.name_en, p.name_ar, p.composition, p.manufacturer, p.strength,
      p.dosage_form, p.package_description, p.barcode, p.barcode2,
      p.selling_amount, p.currency::text, p.notes, p.revision, p.updated_at
    from public.products p
    where
      strpos(lower(coalesce(p.name_en, '')), lower(raw_query)) > 0
      or strpos(lower(coalesce(p.name_ar, '')), lower(raw_query)) > 0
      or strpos(lower(coalesce(p.composition, '')), lower(raw_query)) > 0
    order by
      case when lower(coalesce(p.name_en, '')) = lower(raw_query) then 0 else 1 end,
      p.name_en nulls last,
      p.name_ar nulls last,
      p.id
    limit bounded_limit;
    return;
  end if;

  query_length := char_length(normalized_query);

  select string_agg(token || ':*', ' & ' order by ordinal)
  into prefix_query_text
  from regexp_split_to_table(normalized_query, '[[:space:]]+')
       with ordinality as terms(token, ordinal)
  where token <> '';

  if prefix_query_text is not null then
    prefix_query := to_tsquery('simple'::regconfig, prefix_query_text);
  end if;

  if query_length <= 3 then
    fuzzy_threshold := '0.48';
  elsif query_length <= 5 then
    fuzzy_threshold := '0.38';
  else
    fuzzy_threshold := '0.30';
  end if;
  perform set_config('pg_trgm.word_similarity_threshold', fuzzy_threshold, true);

  return query
  with candidate_ids as materialized (
    select p.id from public.products p where p.barcode = raw_query
    union
    select p.id from public.products p where p.barcode2 = raw_query
    union
    select p.id from public.products p where p.search_name_en = normalized_query
    union
    select p.id from public.products p where p.search_name_ar = normalized_query
    union
    select p.id from public.products p where p.search_name_en like normalized_query || '%'
    union
    select p.id from public.products p where p.search_name_ar like normalized_query || '%'
    union
    select p.id
    from public.products p
    where query_length >= 3
      and prefix_query is not null
      and p.search_fts @@ prefix_query
    union
    select p.id
    from public.products p
    where query_length >= 3
      and p.search_document like '%' || normalized_query || '%'
    union
    select p.id
    from public.products p
    where query_length >= 3
      and normalized_query OPERATOR(extensions.<%) p.search_document
  ),
  candidates as (
    select
      p.*,
      (p.barcode = raw_query or p.barcode2 = raw_query) as barcode_exact,
      (p.search_name_en = normalized_query or p.search_name_ar = normalized_query) as name_exact,
      (p.search_name_en like normalized_query || '%' or
       p.search_name_ar like normalized_query || '%') as name_prefix,
      (p.search_composition = normalized_query) as composition_exact,
      (p.search_composition like normalized_query || '%') as composition_prefix,
      (p.search_name_en like '%' || normalized_query || '%' or
       p.search_name_ar like '%' || normalized_query || '%') as name_substring,
      (p.search_composition like '%' || normalized_query || '%') as composition_substring,
      (query_length >= 3 and prefix_query is not null and p.search_fts @@ prefix_query) as prefix_fts_match,
      case
        when query_length >= 3 and prefix_query is not null
        then ts_rank_cd(p.search_fts, prefix_query, 32)
        else 0
      end as prefix_fts_rank,
      case
        when query_length >= 3 then greatest(
          extensions.word_similarity(normalized_query, p.search_name_en),
          extensions.word_similarity(normalized_query, p.search_name_ar)
        )
        else 0
      end as name_similarity,
      case
        when query_length >= 3
        then extensions.word_similarity(normalized_query, p.search_composition)
        else 0
      end as composition_similarity,
      case
        when query_length >= 3
        then extensions.word_similarity(normalized_query, p.search_secondary)
        else 0
      end as secondary_similarity
    from candidate_ids ids
    join public.products p on p.id = ids.id
  ),
  ranked as (
    select
      c.*,
      (
        case when c.barcode_exact then 100000 else 0 end +
        case when c.name_exact then 50000 else 0 end +
        case when c.name_prefix then 30000 else 0 end +
        case when c.composition_exact then 22000 else 0 end +
        case when c.prefix_fts_match then 18000 else 0 end +
        case when c.composition_prefix then 15000 else 0 end +
        case when c.name_substring then 12000 else 0 end +
        case when c.composition_substring then 8000 else 0 end +
        round(c.prefix_fts_rank * 8000)::integer +
        round(c.name_similarity * 6000)::integer +
        round(c.composition_similarity * 4000)::integer +
        round(c.secondary_similarity * 2000)::integer
      ) as relevance
    from candidates c
  )
  select
    r.id, r.name_en, r.name_ar, r.composition, r.manufacturer, r.strength,
    r.dosage_form, r.package_description, r.barcode, r.barcode2,
    r.selling_amount, r.currency::text, r.notes, r.revision, r.updated_at
  from ranked r
  order by
    r.relevance desc,
    least(
      nullif(char_length(r.search_name_en), 0),
      nullif(char_length(r.search_name_ar), 0)
    ) nulls last,
    r.name_en nulls last,
    r.name_ar nulls last,
    r.id
  limit bounded_limit;
end;
$$;
