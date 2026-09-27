-- SP-023: indexed, normalized, typo-tolerant manual catalog search.
-- Keeps the existing owner-only catalog_search RPC signature and return shape.

create extension if not exists pg_trgm with schema extensions;

create or replace function app_private.catalog_search_normalize(input_text text)
returns text
language sql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
  select btrim(
    regexp_replace(
      regexp_replace(
        translate(
          lower(normalize(input_text, NFKC)),
          'آأإٱؤئىيک٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
          'ااااويييك01234567890123456789'
        ),
        '[ًٌٍَُِّْٰـ]',
        '',
        'g'
      ),
      '[^[:alnum:]]+',
      ' ',
      'g'
    )
  )
$$;

revoke all on function app_private.catalog_search_normalize(text)
from public, anon, authenticated;

alter table public.products
  add column search_name_en text
    generated always as (
      coalesce(app_private.catalog_search_normalize(name_en), '')
    ) stored,
  add column search_name_ar text
    generated always as (
      coalesce(app_private.catalog_search_normalize(name_ar), '')
    ) stored,
  add column search_composition text
    generated always as (
      coalesce(app_private.catalog_search_normalize(composition), '')
    ) stored,
  add column search_secondary text
    generated always as (
      app_private.catalog_search_normalize(
        coalesce(manufacturer, '') || ' ' ||
        coalesce(strength, '') || ' ' ||
        coalesce(dosage_form, '') || ' ' ||
        coalesce(package_description, '')
      )
    ) stored,
  add column search_document text
    generated always as (
      app_private.catalog_search_normalize(
        coalesce(name_en, '') || ' ' ||
        coalesce(strength, '') || ' ' ||
        coalesce(composition, '') || ' ' ||
        coalesce(name_ar, '') || ' ' ||
        coalesce(strength, '') || ' ' ||
        coalesce(composition, '') || ' ' ||
        coalesce(manufacturer, '') || ' ' ||
        coalesce(dosage_form, '') || ' ' ||
        coalesce(package_description, '')
      )
    ) stored,
  add column search_fts tsvector
    generated always as (
      setweight(
        to_tsvector(
          'simple'::regconfig,
          coalesce(app_private.catalog_search_normalize(name_en), '')
        ),
        'A'
      ) ||
      setweight(
        to_tsvector(
          'simple'::regconfig,
          coalesce(app_private.catalog_search_normalize(name_ar), '')
        ),
        'A'
      ) ||
      setweight(
        to_tsvector(
          'simple'::regconfig,
          coalesce(app_private.catalog_search_normalize(composition), '')
        ),
        'B'
      ) ||
      setweight(
        to_tsvector(
          'simple'::regconfig,
          app_private.catalog_search_normalize(
            coalesce(strength, '') || ' ' || coalesce(manufacturer, '')
          )
        ),
        'C'
      ) ||
      setweight(
        to_tsvector(
          'simple'::regconfig,
          app_private.catalog_search_normalize(
            coalesce(dosage_form, '') || ' ' ||
            coalesce(package_description, '')
          )
        ),
        'D'
      )
    ) stored;

create index products_search_name_en_prefix_idx
  on public.products (search_name_en text_pattern_ops)
  where search_name_en <> '';

create index products_search_name_ar_prefix_idx
  on public.products (search_name_ar text_pattern_ops)
  where search_name_ar <> '';

create index products_search_document_trgm_idx
  on public.products using gin (search_document extensions.gin_trgm_ops);

create index products_search_fts_idx
  on public.products using gin (search_fts);

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

  -- Preserve literal punctuation-only searches from the existing API contract.
  if normalized_query = '' then
    return query
    select
      p.id, p.name_en, p.name_ar, p.composition, p.manufacturer, p.strength,
      p.dosage_form, p.package_description, p.barcode, p.barcode2,
      p.selling_amount, p.currency, p.notes, p.revision, p.updated_at
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
  with candidates as (
    select
      p.*,
      (p.barcode = raw_query or p.barcode2 = raw_query) as barcode_exact,
      (p.search_name_en = normalized_query or
       p.search_name_ar = normalized_query) as name_exact,
      (p.search_name_en like normalized_query || '%' or
       p.search_name_ar like normalized_query || '%') as name_prefix,
      (p.search_composition = normalized_query) as composition_exact,
      (p.search_composition like normalized_query || '%') as composition_prefix,
      (p.search_name_en like '%' || normalized_query || '%' or
       p.search_name_ar like '%' || normalized_query || '%') as name_substring,
      (p.search_composition like '%' || normalized_query || '%') as composition_substring,
      (
        query_length >= 3
        and prefix_query is not null
        and p.search_fts @@ prefix_query
      ) as prefix_fts_match,
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
        then extensions.word_similarity(
          normalized_query,
          p.search_composition
        )
        else 0
      end as composition_similarity,
      case
        when query_length >= 3
        then extensions.word_similarity(
          normalized_query,
          p.search_secondary
        )
        else 0
      end as secondary_similarity
    from public.products p
    where
      p.barcode = raw_query
      or p.barcode2 = raw_query
      or p.search_name_en = normalized_query
      or p.search_name_ar = normalized_query
      or p.search_composition = normalized_query
      or p.search_name_en like normalized_query || '%'
      or p.search_name_ar like normalized_query || '%'
      or (
        query_length >= 3
        and prefix_query is not null
        and p.search_fts @@ prefix_query
      )
      or (
        query_length >= 3
        and p.search_document like '%' || normalized_query || '%'
      )
      or (
        query_length >= 3
        and normalized_query OPERATOR(extensions.<%) p.search_document
      )
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
    r.selling_amount, r.currency, r.notes, r.revision, r.updated_at
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

revoke all on function public.catalog_search(text, integer)
from public, anon;

grant execute on function public.catalog_search(text, integer)
to authenticated;
