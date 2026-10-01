-- SP-039: add a private scientific canonical ingredient identity layer above
-- the stable SP-025 lexical ingredient registry. This migration defines schema
-- only. It does not backfill or rewrite production/source catalog data.

create type app_private.scientific_ingredient_category as enum (
  'medicinal_substance',
  'vitamin',
  'mineral',
  'botanical',
  'biologic',
  'probiotic',
  'mixture',
  'other'
);

create type app_private.scientific_ingredient_parent_relation as enum (
  'salt_of',
  'ester_of',
  'hydrate_of',
  'solvate_of',
  'derivative_of',
  'component_of',
  'other'
);

create type app_private.scientific_ingredient_mapping_status as enum (
  'verified',
  'candidate',
  'needs_review',
  'unresolved'
);

create type app_private.scientific_ingredient_mapping_method as enum (
  'exact_reference',
  'reviewed_alias',
  'deterministic_cleanup',
  'context',
  'manual',
  'none'
);

create type app_private.scientific_ingredient_alias_kind as enum (
  'inn',
  'synonym',
  'common_name',
  'legacy_name',
  'local_name',
  'other'
);

create type app_private.scientific_ingredient_reference_system as enum (
  'who_inn',
  'fda_unii',
  'rxnorm',
  'pubchem',
  'other'
);

-- Scientific identity equality must not reuse the broad catalog-search key:
-- punctuation can carry chemical meaning. This key normalizes Unicode, case,
-- surrounding whitespace, and repeated whitespace while preserving punctuation.
create or replace function app_private.scientific_name_key(input_text text)
returns text
language sql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
  select lower(
    regexp_replace(
      btrim(normalize(input_text, NFKC)),
      '[[:space:]]+',
      ' ',
      'g'
    )
  )
$$;

revoke all on function app_private.scientific_name_key(text)
from public, anon, authenticated;

create table app_private.scientific_ingredients (
  id bigint generated always as identity primary key,
  preferred_name text not null,
  normalized_preferred_name text not null unique,
  category app_private.scientific_ingredient_category not null,
  parent_scientific_ingredient_id bigint
    references app_private.scientific_ingredients(id) on delete restrict,
  parent_relation app_private.scientific_ingredient_parent_relation,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scientific_ingredients_preferred_name_nonblank
    check (btrim(preferred_name) <> ''),
  constraint scientific_ingredients_normalized_name_nonblank
    check (btrim(normalized_preferred_name) <> ''),
  constraint scientific_ingredients_normalized_name_matches
    check (
      normalized_preferred_name =
        app_private.scientific_name_key(preferred_name)
    ),
  constraint scientific_ingredients_parent_shape
    check (
      (parent_scientific_ingredient_id is null and parent_relation is null)
      or
      (parent_scientific_ingredient_id is not null and parent_relation is not null)
    ),
  constraint scientific_ingredients_no_direct_self_parent
    check (
      parent_scientific_ingredient_id is null
      or parent_scientific_ingredient_id <> id
    )
);

-- Prevent longer parent/base cycles such as A -> B -> A. Direct self-parenting is
-- also rejected by the table CHECK so the invariant remains visible in schema.
create or replace function app_private.guard_scientific_ingredient_parent_cycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.parent_scientific_ingredient_id is null then
    return new;
  end if;

  if exists (
    with recursive lineage(id) as (
      select new.parent_scientific_ingredient_id
      union
      select parent.parent_scientific_ingredient_id
      from app_private.scientific_ingredients parent
      join lineage current_lineage on parent.id = current_lineage.id
      where parent.parent_scientific_ingredient_id is not null
    )
    select 1
    from lineage
    where id = new.id
  ) then
    raise exception 'scientific ingredient parent relationship would create a cycle'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_scientific_ingredient_parent_cycle()
from public, anon, authenticated;

create trigger scientific_ingredients_parent_cycle_guard
before insert or update of parent_scientific_ingredient_id
on app_private.scientific_ingredients
for each row
execute function app_private.guard_scientific_ingredient_parent_cycle();

create table app_private.scientific_ingredient_references (
  scientific_ingredient_id bigint not null
    references app_private.scientific_ingredients(id) on delete cascade,
  reference_system app_private.scientific_ingredient_reference_system not null,
  reference_key text not null,
  reference_name text,
  reference_version text,
  reviewed_at timestamptz not null,
  review_note text,
  primary key (
    scientific_ingredient_id,
    reference_system,
    reference_key
  ),
  constraint scientific_ingredient_references_key_nonblank
    check (btrim(reference_key) <> ''),
  constraint scientific_ingredient_references_name_nonblank
    check (
      reference_name is null
      or btrim(reference_name) <> ''
    ),
  constraint scientific_ingredient_references_system_key_unique
    unique (reference_system, reference_key)
);

create table app_private.scientific_ingredient_atc_codes (
  scientific_ingredient_id bigint not null
    references app_private.scientific_ingredients(id) on delete cascade,
  atc_code text not null,
  atc_name text,
  reference_version text,
  reviewed_at timestamptz not null,
  review_note text,
  primary key (scientific_ingredient_id, atc_code),
  constraint scientific_ingredient_atc_code_nonblank
    check (btrim(atc_code) <> ''),
  constraint scientific_ingredient_atc_code_canonical
    check (atc_code = upper(btrim(atc_code))),
  constraint scientific_ingredient_atc_name_nonblank
    check (
      atc_name is null
      or btrim(atc_name) <> ''
    )
);

create table app_private.scientific_ingredient_aliases (
  normalized_alias text primary key,
  scientific_ingredient_id bigint not null
    references app_private.scientific_ingredients(id) on delete cascade,
  alias_text text not null,
  alias_kind app_private.scientific_ingredient_alias_kind not null,
  reference_source text not null,
  reference_version text,
  reviewed_at timestamptz not null,
  review_note text,
  created_at timestamptz not null default now(),
  constraint scientific_ingredient_alias_text_nonblank
    check (btrim(alias_text) <> ''),
  constraint scientific_ingredient_alias_normalized_nonblank
    check (btrim(normalized_alias) <> ''),
  constraint scientific_ingredient_alias_normalized_matches
    check (
      normalized_alias = app_private.scientific_name_key(alias_text)
    ),
  constraint scientific_ingredient_alias_source_nonblank
    check (btrim(reference_source) <> '')
);

create table app_private.catalog_ingredient_scientific_mappings (
  ingredient_id bigint primary key
    references app_private.catalog_ingredients(id) on delete cascade,
  scientific_ingredient_id bigint
    references app_private.scientific_ingredients(id) on delete restrict,
  status app_private.scientific_ingredient_mapping_status not null,
  mapping_method app_private.scientific_ingredient_mapping_method not null,
  confidence smallint not null,
  reference_source text,
  reference_version text,
  reviewed_at timestamptz,
  review_note text,
  updated_at timestamptz not null default now(),
  constraint catalog_ingredient_scientific_mapping_confidence_range
    check (confidence between 0 and 100),
  constraint catalog_ingredient_scientific_mapping_source_shape
    check (
      mapping_method = 'none'
      or nullif(btrim(reference_source), '') is not null
    ),
  constraint catalog_ingredient_scientific_mapping_review_note_shape
    check (
      status not in ('needs_review', 'unresolved')
      or nullif(btrim(review_note), '') is not null
    ),
  constraint catalog_ingredient_scientific_mapping_status_shape
    check (
      (
        status = 'verified'
        and scientific_ingredient_id is not null
        and mapping_method <> 'none'
        and confidence = 100
        and nullif(btrim(reference_source), '') is not null
        and reviewed_at is not null
      )
      or (
        status = 'candidate'
        and scientific_ingredient_id is not null
        and mapping_method <> 'none'
        and confidence between 1 and 99
        and reviewed_at is null
      )
      or (
        status = 'needs_review'
        and scientific_ingredient_id is null
        and confidence between 0 and 99
      )
      or (
        status = 'unresolved'
        and scientific_ingredient_id is null
        and mapping_method = 'none'
        and confidence = 0
      )
    ),
  constraint catalog_ingredient_scientific_mapping_ingredient_status_unique
    unique (ingredient_id, status)
);

-- A needs-review mapping can retain multiple explicit candidate identities
-- without choosing one as scientific truth. The composite FK guarantees these
-- rows can exist only while the parent mapping remains needs_review.
create table app_private.catalog_ingredient_scientific_review_candidates (
  ingredient_id bigint not null,
  mapping_status app_private.scientific_ingredient_mapping_status not null
    default 'needs_review',
  scientific_ingredient_id bigint not null
    references app_private.scientific_ingredients(id) on delete restrict,
  mapping_method app_private.scientific_ingredient_mapping_method not null,
  confidence smallint not null,
  reference_source text not null,
  reference_version text,
  candidate_note text,
  generated_at timestamptz not null default now(),
  primary key (ingredient_id, scientific_ingredient_id),
  foreign key (ingredient_id, mapping_status)
    references app_private.catalog_ingredient_scientific_mappings(
      ingredient_id,
      status
    )
    on delete cascade,
  constraint catalog_ingredient_scientific_candidate_status
    check (mapping_status = 'needs_review'),
  constraint catalog_ingredient_scientific_candidate_method
    check (mapping_method <> 'none'),
  constraint catalog_ingredient_scientific_candidate_confidence
    check (confidence between 1 and 99),
  constraint catalog_ingredient_scientific_candidate_source_nonblank
    check (btrim(reference_source) <> '')
);

create index scientific_ingredients_parent_idx
  on app_private.scientific_ingredients(parent_scientific_ingredient_id)
  where parent_scientific_ingredient_id is not null;

create index scientific_ingredient_references_identity_idx
  on app_private.scientific_ingredient_references(scientific_ingredient_id);

create index scientific_ingredient_atc_identity_idx
  on app_private.scientific_ingredient_atc_codes(scientific_ingredient_id);

create index scientific_ingredient_alias_identity_idx
  on app_private.scientific_ingredient_aliases(scientific_ingredient_id);

create index catalog_ingredient_scientific_mapping_status_idx
  on app_private.catalog_ingredient_scientific_mappings(status);

create index catalog_ingredient_scientific_mapping_identity_idx
  on app_private.catalog_ingredient_scientific_mappings(
    scientific_ingredient_id,
    ingredient_id
  )
  where scientific_ingredient_id is not null;

create index catalog_ingredient_scientific_candidate_identity_idx
  on app_private.catalog_ingredient_scientific_review_candidates(
    scientific_ingredient_id,
    ingredient_id
  );

-- These are curation tables, not client API tables. Keep direct access denied
-- even if app_private becomes exposed accidentally in a future configuration.
alter table app_private.scientific_ingredients enable row level security;
alter table app_private.scientific_ingredient_references enable row level security;
alter table app_private.scientific_ingredient_atc_codes enable row level security;
alter table app_private.scientific_ingredient_aliases enable row level security;
alter table app_private.catalog_ingredient_scientific_mappings
  enable row level security;
alter table app_private.catalog_ingredient_scientific_review_candidates
  enable row level security;

revoke all on app_private.scientific_ingredients
from public, anon, authenticated;
revoke all on app_private.scientific_ingredient_references
from public, anon, authenticated;
revoke all on app_private.scientific_ingredient_atc_codes
from public, anon, authenticated;
revoke all on app_private.scientific_ingredient_aliases
from public, anon, authenticated;
revoke all on app_private.catalog_ingredient_scientific_mappings
from public, anon, authenticated;
revoke all on app_private.catalog_ingredient_scientific_review_candidates
from public, anon, authenticated;
revoke all on sequence app_private.scientific_ingredients_id_seq
from public, anon, authenticated;
