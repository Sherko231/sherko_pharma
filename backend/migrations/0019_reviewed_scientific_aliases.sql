-- SP-041: curated, reviewed scientific aliases and legacy spellings.
--
-- This migration adds reviewed reference data and exact alias resolution only.
-- It does not backfill product mappings, rewrite raw catalog text, perform fuzzy
-- matching, change pharmaceutical equivalence, or alter DDI-provider mappings.

create or replace function app_private.guard_scientific_alias_canonical_collision()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  alias_key text;
begin
  alias_key := app_private.scientific_name_key(new.alias_text);

  if exists (
    select 1
    from app_private.scientific_ingredients i
    where i.normalized_preferred_name = alias_key
      and i.id <> new.scientific_ingredient_id
  ) then
    raise exception
      'reviewed scientific alias conflicts with another canonical scientific name'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_scientific_alias_canonical_collision()
from public, anon, authenticated;

create trigger scientific_ingredient_alias_canonical_collision_guard
before insert or update of alias_text, normalized_alias, scientific_ingredient_id
on app_private.scientific_ingredient_aliases
for each row
execute function app_private.guard_scientific_alias_canonical_collision();

create or replace function app_private.guard_scientific_canonical_alias_collision()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  canonical_key text;
begin
  canonical_key := app_private.scientific_name_key(new.preferred_name);

  if exists (
    select 1
    from app_private.scientific_ingredient_aliases a
    where a.normalized_alias = canonical_key
      and (
        new.id is null
        or a.scientific_ingredient_id <> new.id
      )
  ) then
    raise exception
      'canonical scientific name conflicts with a reviewed alias for another identity'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_scientific_canonical_alias_collision()
from public, anon, authenticated;

create trigger scientific_ingredient_canonical_alias_collision_guard
before insert or update of preferred_name, normalized_preferred_name
on app_private.scientific_ingredients
for each row
execute function app_private.guard_scientific_canonical_alias_collision();

create or replace function app_private.resolve_reviewed_scientific_alias(
  input_text text
)
returns table (
  scientific_ingredient_id bigint,
  preferred_name text,
  match_kind text,
  alias_text text,
  alias_kind app_private.scientific_ingredient_alias_kind,
  reference_source text,
  reference_version text,
  reviewed_at timestamptz,
  review_note text
)
language sql
stable
strict
parallel safe
set search_path = ''
as $$
  with key_input as (
    select app_private.scientific_name_key(input_text) as normalized_key
  ),
  matches as (
    select
      i.id as scientific_ingredient_id,
      i.preferred_name,
      1 as match_priority,
      'canonical'::text as match_kind,
      null::text as alias_text,
      null::app_private.scientific_ingredient_alias_kind as alias_kind,
      null::text as reference_source,
      null::text as reference_version,
      null::timestamptz as reviewed_at,
      null::text as review_note
    from key_input k
    join app_private.scientific_ingredients i
      on i.normalized_preferred_name = k.normalized_key

    union all

    select
      i.id as scientific_ingredient_id,
      i.preferred_name,
      2 as match_priority,
      'reviewed_alias'::text as match_kind,
      a.alias_text,
      a.alias_kind,
      a.reference_source,
      a.reference_version,
      a.reviewed_at,
      a.review_note
    from key_input k
    join app_private.scientific_ingredient_aliases a
      on a.normalized_alias = k.normalized_key
    join app_private.scientific_ingredients i
      on i.id = a.scientific_ingredient_id
  )
  select
    m.scientific_ingredient_id,
    m.preferred_name,
    m.match_kind,
    m.alias_text,
    m.alias_kind,
    m.reference_source,
    m.reference_version,
    m.reviewed_at,
    m.review_note
  from matches m
  order by m.match_priority
  limit 1
$$;

revoke all on function app_private.resolve_reviewed_scientific_alias(text)
from public, anon, authenticated;

-- Seed only reviewed global scientific identities and aliases. These rows do not
-- map any production SP-025 ingredient identity; SP-044 owns production backfill.
insert into app_private.scientific_ingredients(
  preferred_name,
  normalized_preferred_name,
  category
)
values
  (
    'Amoxicillin',
    app_private.scientific_name_key('Amoxicillin'),
    'medicinal_substance'
  ),
  (
    'Caffeine',
    app_private.scientific_name_key('Caffeine'),
    'medicinal_substance'
  ),
  (
    'Paracetamol',
    app_private.scientific_name_key('Paracetamol'),
    'medicinal_substance'
  );

insert into app_private.scientific_ingredient_references(
  scientific_ingredient_id,
  reference_system,
  reference_key,
  reference_name,
  reference_version,
  reviewed_at,
  review_note
)
select
  i.id,
  'pubchem',
  '33613',
  'Amoxicillin',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'PubChem CID 33613 lists Amoxicilline and Amoxycillin as synonyms and reports INN AMOXICILLIN.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Amoxicillin');

insert into app_private.scientific_ingredient_references(
  scientific_ingredient_id,
  reference_system,
  reference_key,
  reference_name,
  reference_version,
  reviewed_at,
  review_note
)
select
  i.id,
  'pubchem',
  '2519',
  'Caffeine',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'PubChem CID 2519 identifies caffeine; ChEBI CHEBI:27732 separately records the French term caféine used for the same compound.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Caffeine');

insert into app_private.scientific_ingredient_references(
  scientific_ingredient_id,
  reference_system,
  reference_key,
  reference_name,
  reference_version,
  reviewed_at,
  review_note
)
select
  i.id,
  'other',
  'CHEBI:27732',
  'caffeine',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'ChEBI CHEBI:27732 lists French caféine as a synonym/term for caffeine.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Caffeine');

insert into app_private.scientific_ingredient_references(
  scientific_ingredient_id,
  reference_system,
  reference_key,
  reference_name,
  reference_version,
  reviewed_at,
  review_note
)
select
  i.id,
  'pubchem',
  '1983',
  'Acetaminophen / Paracetamol',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'PubChem CID 1983 lists acetaminophen and paracetamol as synonyms and reports INN PARACETAMOL.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Paracetamol');

insert into app_private.scientific_ingredient_aliases(
  normalized_alias,
  scientific_ingredient_id,
  alias_text,
  alias_kind,
  reference_source,
  reference_version,
  reviewed_at,
  review_note
)
select
  app_private.scientific_name_key('Amoxicilline'),
  i.id,
  'Amoxicilline',
  'legacy_name',
  'PubChem CID 33613 / MeSH entry terms',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'Reviewed spelling variant of Amoxicillin; exact alias only, not fuzzy matching.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Amoxicillin');

insert into app_private.scientific_ingredient_aliases(
  normalized_alias,
  scientific_ingredient_id,
  alias_text,
  alias_kind,
  reference_source,
  reference_version,
  reviewed_at,
  review_note
)
select
  app_private.scientific_name_key('Amoxycillin'),
  i.id,
  'Amoxycillin',
  'synonym',
  'PubChem CID 33613 / MeSH entry terms',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'Reviewed established synonym of Amoxicillin.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Amoxicillin');

insert into app_private.scientific_ingredient_aliases(
  normalized_alias,
  scientific_ingredient_id,
  alias_text,
  alias_kind,
  reference_source,
  reference_version,
  reviewed_at,
  review_note
)
select
  app_private.scientific_name_key('caféine'),
  i.id,
  'caféine',
  'local_name',
  'ChEBI CHEBI:27732',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'Reviewed French term for Caffeine.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Caffeine');

insert into app_private.scientific_ingredient_aliases(
  normalized_alias,
  scientific_ingredient_id,
  alias_text,
  alias_kind,
  reference_source,
  reference_version,
  reviewed_at,
  review_note
)
select
  app_private.scientific_name_key('cafeine'),
  i.id,
  'cafeine',
  'legacy_name',
  'ChEBI CHEBI:27732; reviewed source orthography',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'Reviewed de-accented catalog spelling of ChEBI French caféine; exact alias only.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Caffeine');

insert into app_private.scientific_ingredient_aliases(
  normalized_alias,
  scientific_ingredient_id,
  alias_text,
  alias_kind,
  reference_source,
  reference_version,
  reviewed_at,
  review_note
)
select
  app_private.scientific_name_key('Acetaminophen'),
  i.id,
  'Acetaminophen',
  'common_name',
  'PubChem CID 1983 / MeSH; FDA GSRS INN field',
  'retrieved 2026-10-01',
  '2026-10-01T00:00:00Z'::timestamptz,
  'Reviewed common-name synonym of canonical INN Paracetamol.'
from app_private.scientific_ingredients i
where i.normalized_preferred_name = app_private.scientific_name_key('Paracetamol');
