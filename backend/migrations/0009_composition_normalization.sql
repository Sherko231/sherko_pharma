-- SP-025: derive conservative ingredient identities from raw composition text.
-- The raw public.products.composition value remains authoritative display/source text.
-- This migration deliberately avoids semantic/fuzzy synonym merging.

create type app_private.composition_normalization_status as enum (
  'auto_verified',
  'high_confidence',
  'needs_review',
  'unresolved'
);

create type app_private.catalog_ingredient_alias_kind as enum (
  'lexical',
  'verified_synonym'
);

create table app_private.catalog_ingredients (
  id bigint generated always as identity primary key,
  name text not null,
  normalized_name text not null unique,
  created_at timestamptz not null default now(),
  constraint catalog_ingredients_name_nonblank
    check (btrim(name) <> ''),
  constraint catalog_ingredients_normalized_name_nonblank
    check (btrim(normalized_name) <> ''),
  constraint catalog_ingredients_normalized_name_matches
    check (
      normalized_name = app_private.catalog_search_normalize(name)
    )
);

-- One normalized alias key resolves to one ingredient identity. Initial aliases
-- are lexical-only; verified semantic synonyms can be curated later without
-- changing product raw composition text.
create table app_private.catalog_ingredient_aliases (
  normalized_alias text primary key,
  ingredient_id bigint not null
    references app_private.catalog_ingredients(id) on delete cascade,
  alias_kind app_private.catalog_ingredient_alias_kind not null
    default 'lexical',
  preferred_spelling text not null,
  created_at timestamptz not null default now(),
  constraint catalog_ingredient_aliases_nonblank
    check (
      btrim(normalized_alias) <> ''
      and btrim(preferred_spelling) <> ''
    ),
  constraint catalog_ingredient_aliases_normalized_matches
    check (
      normalized_alias =
        app_private.catalog_search_normalize(preferred_spelling)
    )
);

-- Preserve observed spelling/case variants without making them separate
-- ingredient identities.
create table app_private.catalog_ingredient_alias_spellings (
  normalized_alias text not null
    references app_private.catalog_ingredient_aliases(normalized_alias)
    on delete cascade,
  spelling text not null,
  primary key (normalized_alias, spelling),
  constraint catalog_ingredient_alias_spellings_nonblank
    check (btrim(spelling) <> ''),
  constraint catalog_ingredient_alias_spellings_normalized_matches
    check (
      normalized_alias =
        app_private.catalog_search_normalize(spelling)
    )
);

create table app_private.product_ingredients (
  product_id uuid not null
    references public.products(id) on delete cascade,
  component_index smallint not null,
  ingredient_id bigint not null
    references app_private.catalog_ingredients(id),
  raw_component text not null,
  normalized_component text not null,
  primary key (product_id, component_index),
  constraint product_ingredients_component_index_positive
    check (component_index > 0),
  constraint product_ingredients_raw_component_nonblank
    check (btrim(raw_component) <> ''),
  constraint product_ingredients_normalized_component_nonblank
    check (btrim(normalized_component) <> '')
);

create table app_private.product_composition_normalization (
  product_id uuid primary key
    references public.products(id) on delete cascade,
  source_composition text,
  ingredient_set_key text,
  status app_private.composition_normalization_status not null,
  component_count integer not null,
  resolved_component_count integer not null,
  parser_version smallint not null default 1,
  normalized_at timestamptz not null default now(),
  constraint product_composition_component_count_valid
    check (
      component_count >= 0
      and resolved_component_count >= 0
      and resolved_component_count <= component_count
    ),
  constraint product_composition_parser_version_positive
    check (parser_version > 0),
  constraint product_composition_unresolved_key_guard
    check (
      status <> 'unresolved'
      or ingredient_set_key is null
    )
);

create index catalog_ingredient_aliases_ingredient_id_idx
  on app_private.catalog_ingredient_aliases(ingredient_id);

create index product_ingredients_ingredient_id_idx
  on app_private.product_ingredients(ingredient_id, product_id);

create index product_composition_set_key_idx
  on app_private.product_composition_normalization(ingredient_set_key)
  where ingredient_set_key is not null;

create index product_composition_status_idx
  on app_private.product_composition_normalization(status);

revoke all on app_private.catalog_ingredients
from public, anon, authenticated;
revoke all on app_private.catalog_ingredient_aliases
from public, anon, authenticated;
revoke all on app_private.catalog_ingredient_alias_spellings
from public, anon, authenticated;
revoke all on app_private.product_ingredients
from public, anon, authenticated;
revoke all on app_private.product_composition_normalization
from public, anon, authenticated;

-- Pick a deterministic canonical display spelling for every lexical component
-- key: the most common observed spelling wins, then lexical order.
with parsed as (
  select
    btrim(parts.raw_component) as raw_component,
    app_private.catalog_search_normalize(
      btrim(parts.raw_component)
    ) as normalized_component
  from public.products p
  cross join lateral regexp_split_to_table(
    p.composition,
    '[+]'
  ) as parts(raw_component)
  where nullif(btrim(p.composition), '') is not null
    and nullif(btrim(parts.raw_component), '') is not null
),
counted as (
  select
    normalized_component,
    raw_component,
    count(*) as usage_count
  from parsed
  where nullif(normalized_component, '') is not null
  group by normalized_component, raw_component
),
ranked as (
  select
    normalized_component,
    raw_component,
    row_number() over (
      partition by normalized_component
      order by usage_count desc, raw_component
    ) as preference
  from counted
)
insert into app_private.catalog_ingredients(name, normalized_name)
select raw_component, normalized_component
from ranked
where preference = 1
order by normalized_component;

insert into app_private.catalog_ingredient_aliases(
  normalized_alias,
  ingredient_id,
  alias_kind,
  preferred_spelling
)
select
  i.normalized_name,
  i.id,
  'lexical'::app_private.catalog_ingredient_alias_kind,
  i.name
from app_private.catalog_ingredients i;

with parsed as (
  select distinct
    app_private.catalog_search_normalize(
      btrim(parts.raw_component)
    ) as normalized_component,
    btrim(parts.raw_component) as raw_component
  from public.products p
  cross join lateral regexp_split_to_table(
    p.composition,
    '[+]'
  ) as parts(raw_component)
  where nullif(btrim(p.composition), '') is not null
    and nullif(btrim(parts.raw_component), '') is not null
)
insert into app_private.catalog_ingredient_alias_spellings(
  normalized_alias,
  spelling
)
select normalized_component, raw_component
from parsed
where nullif(normalized_component, '') is not null
on conflict do nothing;

create or replace function app_private.resolve_catalog_ingredient(
  input_text text
)
returns table (
  ingredient_id bigint,
  normalized_alias text,
  alias_kind app_private.catalog_ingredient_alias_kind
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  raw_label text;
  alias_key text;
  resolved_id bigint;
  resolved_kind app_private.catalog_ingredient_alias_kind;
begin
  raw_label := nullif(btrim(input_text), '');
  if raw_label is null then
    raise exception 'ingredient label must not be blank'
      using errcode = '22023';
  end if;

  alias_key := nullif(
    app_private.catalog_search_normalize(raw_label),
    ''
  );
  if alias_key is null then
    raise exception 'ingredient label does not contain a resolvable identity'
      using errcode = '22023';
  end if;

  select a.ingredient_id, a.alias_kind
    into resolved_id, resolved_kind
  from app_private.catalog_ingredient_aliases a
  where a.normalized_alias = alias_key;

  if resolved_id is null then
    select i.id
      into resolved_id
    from app_private.catalog_ingredients i
    where i.normalized_name = alias_key;

    if resolved_id is null then
      insert into app_private.catalog_ingredients(name, normalized_name)
      values (raw_label, alias_key)
      on conflict (normalized_name) do nothing;

      select i.id
        into resolved_id
      from app_private.catalog_ingredients i
      where i.normalized_name = alias_key;
    end if;

    insert into app_private.catalog_ingredient_aliases(
      normalized_alias,
      ingredient_id,
      alias_kind,
      preferred_spelling
    )
    values (
      alias_key,
      resolved_id,
      'lexical',
      raw_label
    )
    on conflict (normalized_alias) do nothing;

    select a.ingredient_id, a.alias_kind
      into resolved_id, resolved_kind
    from app_private.catalog_ingredient_aliases a
    where a.normalized_alias = alias_key;
  end if;

  insert into app_private.catalog_ingredient_alias_spellings(
    normalized_alias,
    spelling
  )
  values (alias_key, raw_label)
  on conflict do nothing;

  return query
  select resolved_id, alias_key, resolved_kind;
end;
$$;

revoke all on function app_private.resolve_catalog_ingredient(text)
from public, anon, authenticated;

create or replace function app_private.refresh_product_composition_normalization(
  target_product_id uuid,
  input_composition text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  component record;
  raw_component text;
  normalized_component text;
  resolved_id bigint;
  resolved_alias text;
  resolved_kind app_private.catalog_ingredient_alias_kind;
  normalization_status app_private.composition_normalization_status :=
    'auto_verified';
  component_count_value integer := 0;
  resolved_count_value integer := 0;
  seen_components text[] := array[]::text[];
  semantic_alias_used boolean := false;
  set_key text;
begin
  delete from app_private.product_ingredients
  where product_id = target_product_id;

  delete from app_private.product_composition_normalization
  where product_id = target_product_id;

  if nullif(btrim(input_composition), '') is null then
    insert into app_private.product_composition_normalization(
      product_id,
      source_composition,
      ingredient_set_key,
      status,
      component_count,
      resolved_component_count
    )
    values (
      target_product_id,
      input_composition,
      null,
      'unresolved',
      0,
      0
    );
    return;
  end if;

  for component in
    select part, ordinal
    from regexp_split_to_table(input_composition, '[+]')
         with ordinality as parsed(part, ordinal)
    order by ordinal
  loop
    component_count_value := component_count_value + 1;
    raw_component := btrim(component.part);
    normalized_component := nullif(
      app_private.catalog_search_normalize(raw_component),
      ''
    );

    if raw_component = '' or normalized_component is null then
      normalization_status := 'unresolved';
      continue;
    end if;

    if normalized_component = any(seen_components)
       and normalization_status <> 'unresolved' then
      normalization_status := 'needs_review';
    end if;
    seen_components := array_append(
      seen_components,
      normalized_component
    );

    -- These patterns frequently encode synonyms, ratios, strengths, complexes,
    -- or other semantics that SP-025 is not allowed to guess.
    if (
      raw_component ~ '[()/,;:&=|]'
      or position('[' in raw_component) > 0
      or position(']' in raw_component) > 0
      or position('{' in raw_component) > 0
      or position('}' in raw_component) > 0
      or raw_component ~* (
        '(^|[^[:alnum:]])[0-9]+([.,][0-9]+)?' ||
        '[[:space:]]*(mg|mcg|ug|µg|g|ml|iu|%)' ||
        '($|[^[:alnum:]])'
      )
    ) and normalization_status <> 'unresolved' then
      normalization_status := 'needs_review';
    end if;

    select
      r.ingredient_id,
      r.normalized_alias,
      r.alias_kind
      into resolved_id, resolved_alias, resolved_kind
    from app_private.resolve_catalog_ingredient(raw_component) r;

    insert into app_private.product_ingredients(
      product_id,
      component_index,
      ingredient_id,
      raw_component,
      normalized_component
    )
    values (
      target_product_id,
      component.ordinal::smallint,
      resolved_id,
      raw_component,
      resolved_alias
    );

    resolved_count_value := resolved_count_value + 1;
    if resolved_kind = 'verified_synonym' then
      semantic_alias_used := true;
    end if;
  end loop;

  if component_count_value = 0
     or resolved_count_value <> component_count_value then
    normalization_status := 'unresolved';
  elsif normalization_status = 'auto_verified'
        and semantic_alias_used then
    normalization_status := 'high_confidence';
  end if;

  if normalization_status <> 'unresolved' then
    select string_agg(
      char_length(i.normalized_name)::text ||
        ':' || i.normalized_name,
      '|'
      order by i.normalized_name, pi.component_index
    )
      into set_key
    from app_private.product_ingredients pi
    join app_private.catalog_ingredients i
      on i.id = pi.ingredient_id
    where pi.product_id = target_product_id;
  else
    set_key := null;
  end if;

  insert into app_private.product_composition_normalization(
    product_id,
    source_composition,
    ingredient_set_key,
    status,
    component_count,
    resolved_component_count
  )
  values (
    target_product_id,
    input_composition,
    set_key,
    normalization_status,
    component_count_value,
    resolved_count_value
  );
end;
$$;

revoke all on function app_private.refresh_product_composition_normalization(
  uuid,
  text
)
from public, anon, authenticated;

create or replace function app_private.sync_product_composition_normalization()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
begin
  perform app_private.refresh_product_composition_normalization(
    new.id,
    new.composition
  );
  return new;
end;
$$;

revoke all on function app_private.sync_product_composition_normalization()
from public, anon, authenticated;

create trigger products_composition_normalization_sync
after insert or update of composition
on public.products
for each row
execute function app_private.sync_product_composition_normalization();

-- Record the values that SP-025 is not allowed to mutate while it backfills the
-- derived normalization layer.
create temporary table sp025_product_state_before
on commit drop
as
select id, composition, revision, updated_at
from public.products;

do $$
declare
  product_row record;
begin
  for product_row in
    select id, composition
    from public.products
    order by id
  loop
    perform app_private.refresh_product_composition_normalization(
      product_row.id,
      product_row.composition
    );
  end loop;
end
$$;

do $$
begin
  if (
    select count(*)
    from app_private.product_composition_normalization
  ) <> (
    select count(*)
    from public.products
  ) then
    raise exception 'composition normalization backfill row count mismatch';
  end if;

  if exists (
    select 1
    from public.products p
    join sp025_product_state_before b using (id)
    where p.composition is distinct from b.composition
       or p.revision is distinct from b.revision
       or p.updated_at is distinct from b.updated_at
  ) then
    raise exception 'composition normalization mutated product source/revision state';
  end if;

  if exists (
    select 1
    from public.products p
    join app_private.product_composition_normalization n
      on n.product_id = p.id
    where n.source_composition is distinct from p.composition
  ) then
    raise exception 'composition normalization source snapshot is out of sync';
  end if;

  if exists (
    select 1
    from app_private.product_ingredients pi
    left join app_private.product_composition_normalization n
      on n.product_id = pi.product_id
    where n.product_id is null
  ) then
    raise exception 'ingredient link exists without normalization summary';
  end if;
end
$$;
