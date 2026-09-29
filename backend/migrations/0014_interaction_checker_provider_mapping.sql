-- Issue #98: map trusted Sherko Pharma ingredient identities to
-- Interaction Checker provider substances without changing the internal
-- composition-normalization registry.

create type app_private.ddi_provider_mapping_status as enum (
  'mapped',
  'ambiguous',
  'unmapped'
);

create type app_private.ddi_provider_mapping_method as enum (
  'exact',
  'salt_base',
  'provider_alias',
  'context',
  'manual',
  'none'
);

create table app_private.interaction_checker_ingredient_mappings (
  ingredient_id bigint primary key
    references app_private.catalog_ingredients(id) on delete cascade,
  status app_private.ddi_provider_mapping_status not null,
  provider_substance_id text,
  provider_substance_name text,
  provider_substance_kind text,
  mapping_method app_private.ddi_provider_mapping_method not null,
  confidence smallint not null,
  candidate_substance_ids text[] not null default array[]::text[],
  note text,
  provider_catalog_fetched_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint interaction_checker_mapping_confidence_range
    check (confidence between 0 and 100),
  constraint interaction_checker_mapping_mapped_shape
    check (
      (
        status = 'mapped'
        and nullif(btrim(provider_substance_id), '') is not null
        and nullif(btrim(provider_substance_name), '') is not null
        and nullif(btrim(provider_substance_kind), '') is not null
        and mapping_method <> 'none'
        and confidence >= 90
      )
      or (
        status <> 'mapped'
        and provider_substance_id is null
        and provider_substance_name is null
        and provider_substance_kind is null
      )
    ),
  constraint interaction_checker_mapping_unmapped_method
    check (
      status <> 'unmapped'
      or mapping_method = 'none'
    )
);

create table app_private.interaction_checker_component_overrides (
  product_id uuid not null,
  component_index smallint not null,
  ingredient_id bigint not null,
  status app_private.ddi_provider_mapping_status not null,
  provider_substance_id text,
  provider_substance_name text,
  provider_substance_kind text,
  mapping_method app_private.ddi_provider_mapping_method not null,
  confidence smallint not null,
  candidate_substance_ids text[] not null default array[]::text[],
  note text,
  provider_catalog_fetched_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (product_id, component_index),
  foreign key (product_id, component_index)
    references app_private.product_ingredients(product_id, component_index)
    on delete cascade,
  foreign key (ingredient_id)
    references app_private.catalog_ingredients(id)
    on delete cascade,
  constraint interaction_checker_override_confidence_range
    check (confidence between 0 and 100),
  constraint interaction_checker_override_mapped_shape
    check (
      (
        status = 'mapped'
        and nullif(btrim(provider_substance_id), '') is not null
        and nullif(btrim(provider_substance_name), '') is not null
        and nullif(btrim(provider_substance_kind), '') is not null
        and mapping_method <> 'none'
        and confidence >= 90
      )
      or (
        status <> 'mapped'
        and provider_substance_id is null
        and provider_substance_name is null
        and provider_substance_kind is null
      )
    ),
  constraint interaction_checker_override_unmapped_method
    check (
      status <> 'unmapped'
      or mapping_method = 'none'
    )
);

create index interaction_checker_mapping_status_idx
  on app_private.interaction_checker_ingredient_mappings(status);

create index interaction_checker_mapping_provider_id_idx
  on app_private.interaction_checker_ingredient_mappings(
    provider_substance_id,
    ingredient_id
  )
  where status = 'mapped';

create index interaction_checker_override_provider_id_idx
  on app_private.interaction_checker_component_overrides(
    provider_substance_id,
    product_id
  )
  where status = 'mapped';

revoke all on app_private.interaction_checker_ingredient_mappings
from public, anon, authenticated;

revoke all on app_private.interaction_checker_component_overrides
from public, anon, authenticated;

create or replace function app_private.interaction_checker_base_name(
  input_name text
)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select pg_catalog.regexp_replace(
    input_name,
    ' (hydrochloride|hcl|hydrobromide|hbr|maleate|fumarate|succinate|tartrate|mesylate|besylate|sulfate|sulphate|phosphate|nitrate|acetate|citrate|propionate|potassium|sodium|calcium|magnesium|trihydrate|monohydrate|dihydrate|hemihydrate|monosodium|disodium|arginine|furoate|acetonide|bromide|chloride|carbonate|oxide|hydroxide|gluconate|glycerophosphate|bicarbonate|trisilicate|pidolate|lactate|polymaltose|salts|na)$',
    '',
    'i'
  );
$$;

revoke all on function app_private.interaction_checker_base_name(text)
from public, anon, authenticated;

create or replace function app_private.reconcile_interaction_checker_mappings(
  provider_catalog jsonb,
  catalog_fetched_at timestamptz default now()
)
returns table (
  mapped_count integer,
  ambiguous_count integer,
  unmapped_count integer,
  component_override_count integer
)
language plpgsql
security definer
set search_path = ''
as $reconcile_interaction_checker_mappings$
declare
  provider_count integer;
begin
  if provider_catalog is null
     or pg_catalog.jsonb_typeof(provider_catalog -> 'results') <> 'array' then
    raise exception 'provider catalog must contain a results array'
      using errcode = '22023';
  end if;

  provider_count := pg_catalog.jsonb_array_length(
    provider_catalog -> 'results'
  );
  if provider_count < 1 then
    raise exception 'provider catalog must not be empty'
      using errcode = '22023';
  end if;

  -- Preserve explicitly manual decisions across catalog refreshes. Every other
  -- row is regenerated from the current provider snapshot and reviewed rules.
  insert into app_private.interaction_checker_ingredient_mappings(
    ingredient_id,
    status,
    provider_substance_id,
    provider_substance_name,
    provider_substance_kind,
    mapping_method,
    confidence,
    candidate_substance_ids,
    note,
    provider_catalog_fetched_at,
    updated_at
  )
  select
    i.id,
    'unmapped'::app_private.ddi_provider_mapping_status,
    null,
    null,
    null,
    'none'::app_private.ddi_provider_mapping_method,
    0,
    array[]::text[],
    'No reviewed Interaction Checker mapping in the current provider catalog.',
    catalog_fetched_at,
    pg_catalog.now()
  from app_private.catalog_ingredients i
  on conflict (ingredient_id) do update
  set
    status = excluded.status,
    provider_substance_id = excluded.provider_substance_id,
    provider_substance_name = excluded.provider_substance_name,
    provider_substance_kind = excluded.provider_substance_kind,
    mapping_method = excluded.mapping_method,
    confidence = excluded.confidence,
    candidate_substance_ids = excluded.candidate_substance_ids,
    note = excluded.note,
    provider_catalog_fetched_at = excluded.provider_catalog_fetched_at,
    updated_at = excluded.updated_at
  where
    app_private.interaction_checker_ingredient_mappings.mapping_method
      <> 'manual';

  delete from app_private.interaction_checker_component_overrides o
  where o.mapping_method <> 'manual';

  -- Exact provider ID/name/primary-name matches. Parenthetical provider
  -- qualifiers such as "(folate)" do not prevent an exact primary-name match.
  with provider as (
    select
      item ->> 'id' as provider_id,
      item ->> 'name' as provider_name,
      item ->> 'kind' as provider_kind,
      app_private.catalog_search_normalize(item ->> 'id') as id_key,
      app_private.catalog_search_normalize(item ->> 'name') as name_key,
      app_private.catalog_search_normalize(
        pg_catalog.regexp_replace(
          item ->> 'name',
          '[[:space:]]*\([^)]*\)[[:space:]]*$',
          '',
          'g'
        )
      ) as primary_name_key
    from pg_catalog.jsonb_array_elements(
      provider_catalog -> 'results'
    ) item
  ),
  candidates as (
    select
      i.id as ingredient_id,
      p.provider_id,
      min(p.provider_name) as provider_name,
      min(p.provider_kind) as provider_kind
    from app_private.catalog_ingredients i
    join provider p
      on i.normalized_name in (
        p.id_key,
        p.name_key,
        p.primary_name_key
      )
    group by i.id, p.provider_id
  ),
  unique_matches as (
    select
      ingredient_id,
      min(provider_id) as provider_id,
      min(provider_name) as provider_name,
      min(provider_kind) as provider_kind
    from candidates
    group by ingredient_id
    having count(*) = 1
  )
  update app_private.interaction_checker_ingredient_mappings m
  set
    status = 'mapped',
    provider_substance_id = u.provider_id,
    provider_substance_name = u.provider_name,
    provider_substance_kind = u.provider_kind,
    mapping_method = 'exact',
    confidence = 100,
    candidate_substance_ids = array[u.provider_id],
    note = 'Unique exact provider ID/name match.',
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from unique_matches u
  where m.ingredient_id = u.ingredient_id
    and m.mapping_method <> 'manual';

  -- Parenthetical aliases explicitly supplied in provider display names, e.g.
  -- Folic acid (folate), Turmeric (curcumin), Senna (sennosides).
  with provider as (
    select
      item ->> 'id' as provider_id,
      item ->> 'name' as provider_name,
      item ->> 'kind' as provider_kind,
      case
        when item ->> 'name' like '%(%'
          then pg_catalog.regexp_replace(
            item ->> 'name',
            '^.*\(([^)]*)\).*$',
            '\1'
          )
        else ''
      end as parenthetical
    from pg_catalog.jsonb_array_elements(
      provider_catalog -> 'results'
    ) item
  ),
  tokens as (
    select
      p.provider_id,
      p.provider_name,
      p.provider_kind,
      app_private.catalog_search_normalize(pg_catalog.btrim(t.token)) as token_key
    from provider p
    cross join lateral pg_catalog.regexp_split_to_table(
      p.parenthetical,
      '[,/]'
    ) t(token)
    where pg_catalog.btrim(t.token) <> ''
  ),
  unique_matches as (
    select
      i.id as ingredient_id,
      min(t.provider_id) as provider_id,
      min(t.provider_name) as provider_name,
      min(t.provider_kind) as provider_kind
    from app_private.catalog_ingredients i
    join tokens t on t.token_key = i.normalized_name
    join app_private.interaction_checker_ingredient_mappings m
      on m.ingredient_id = i.id
    where m.status = 'unmapped'
      and m.mapping_method <> 'manual'
    group by i.id
    having count(distinct t.provider_id) = 1
  )
  update app_private.interaction_checker_ingredient_mappings m
  set
    status = 'mapped',
    provider_substance_id = u.provider_id,
    provider_substance_name = u.provider_name,
    provider_substance_kind = u.provider_kind,
    mapping_method = 'provider_alias',
    confidence = 98,
    candidate_substance_ids = array[u.provider_id],
    note = 'Unique provider-supplied parenthetical alias match.',
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from unique_matches u
  where m.ingredient_id = u.ingredient_id
    and m.mapping_method <> 'manual';

  -- Conservative active-moiety/base-name matching for terminal salts/forms.
  with provider as (
    select
      item ->> 'id' as provider_id,
      item ->> 'name' as provider_name,
      item ->> 'kind' as provider_kind,
      app_private.catalog_search_normalize(item ->> 'id') as id_key,
      app_private.catalog_search_normalize(
        pg_catalog.regexp_replace(
          item ->> 'name',
          '[[:space:]]*\([^)]*\)[[:space:]]*$',
          '',
          'g'
        )
      ) as name_key
    from pg_catalog.jsonb_array_elements(
      provider_catalog -> 'results'
    ) item
  ),
  candidates as (
    select
      i.id as ingredient_id,
      p.provider_id,
      min(p.provider_name) as provider_name,
      min(p.provider_kind) as provider_kind
    from app_private.catalog_ingredients i
    join app_private.interaction_checker_ingredient_mappings m
      on m.ingredient_id = i.id
    join provider p
      on app_private.interaction_checker_base_name(i.normalized_name)
        in (p.id_key, p.name_key)
    where m.status = 'unmapped'
      and m.mapping_method <> 'manual'
      and app_private.interaction_checker_base_name(i.normalized_name)
        <> i.normalized_name
    group by i.id, p.provider_id
  ),
  unique_matches as (
    select
      ingredient_id,
      min(provider_id) as provider_id,
      min(provider_name) as provider_name,
      min(provider_kind) as provider_kind
    from candidates
    group by ingredient_id
    having count(*) = 1
  )
  update app_private.interaction_checker_ingredient_mappings m
  set
    status = 'mapped',
    provider_substance_id = u.provider_id,
    provider_substance_name = u.provider_name,
    provider_substance_kind = u.provider_kind,
    mapping_method = 'salt_base',
    confidence = 98,
    candidate_substance_ids = array[u.provider_id],
    note = 'Unique provider base substance after conservative terminal salt/form removal.',
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from unique_matches u
  where m.ingredient_id = u.ingredient_id
    and m.mapping_method <> 'manual';

  -- Reviewed lexical synonyms and spelling conventions. The provider ID must
  -- exist in the supplied snapshot or the rule is ignored.
  with rules(internal_key, provider_id, method, confidence, note) as (
    values
      ('paracetamol', 'acetaminophen', 'provider_alias', 100, 'International name to US provider name.'),
      ('acetylsalicylic acid', 'aspirin', 'provider_alias', 100, 'Established aspirin synonym.'),
      ('salbutamol', 'albuterol', 'provider_alias', 100, 'International name to US provider name.'),
      ('adrenaline', 'epinephrine', 'provider_alias', 100, 'International name to US provider name.'),
      ('glibenclamide', 'glyburide', 'provider_alias', 100, 'International name to US provider name.'),
      ('mesalazine', 'mesalamine', 'provider_alias', 100, 'International name to US provider name.'),
      ('meclozine', 'meclizine', 'provider_alias', 98, 'Established spelling synonym.'),
      ('chlortalidone', 'chlorthalidone', 'provider_alias', 98, 'Established spelling synonym.'),
      ('hydrochlorthiazide', 'hydrochlorothiazide', 'provider_alias', 98, 'Source spelling correction.'),
      ('caffine', 'caffeine', 'provider_alias', 98, 'Source spelling correction.'),
      ('melatonine', 'melatonin', 'provider_alias', 98, 'Source spelling correction.'),
      ('guaiphenesin', 'guaifenesin', 'provider_alias', 98, 'Established spelling synonym.'),
      ('phenoxymethylpenicillin', 'penicillin-v', 'provider_alias', 100, 'Phenoxymethylpenicillin is penicillin V.'),
      ('phenoxymethylpenicillin potassium', 'penicillin-v', 'provider_alias', 100, 'Phenoxymethylpenicillin potassium is penicillin V potassium.'),
      ('aminophylline', 'theophylline', 'provider_alias', 95, 'Aminophylline is the theophylline-ethylenediamine complex; provider DDI identity uses theophylline.'),
      ('miconazol', 'miconazole', 'provider_alias', 98, 'Source spelling correction.'),
      ('miconazol nitrate', 'miconazole', 'provider_alias', 98, 'Source spelling plus salt normalization.'),
      ('sodium valproate', 'valproic-acid', 'provider_alias', 95, 'Valproate active-moiety provider mapping.')
  ),
  provider as (
    select
      item ->> 'id' as provider_id,
      item ->> 'name' as provider_name,
      item ->> 'kind' as provider_kind
    from pg_catalog.jsonb_array_elements(
      provider_catalog -> 'results'
    ) item
  )
  update app_private.interaction_checker_ingredient_mappings m
  set
    status = 'mapped',
    provider_substance_id = p.provider_id,
    provider_substance_name = p.provider_name,
    provider_substance_kind = p.provider_kind,
    mapping_method = r.method::app_private.ddi_provider_mapping_method,
    confidence = r.confidence,
    candidate_substance_ids = array[p.provider_id],
    note = r.note,
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from rules r
  join app_private.catalog_ingredients i
    on i.normalized_name = r.internal_key
  join provider p on p.provider_id = r.provider_id
  where m.ingredient_id = i.id
    and m.mapping_method <> 'manual';

  -- Reviewed supplement/mineral families that the provider intentionally
  -- represents as broad vitamin/mineral/herbal substances.
  with rules(internal_key, provider_id, confidence, note) as (
    values
      ('b12', 'vitamin-b12', 100, 'Vitamin B12 abbreviation in vitamin formulations.'),
      ('vit b12', 'vitamin-b12', 100, 'Vitamin B12 abbreviation.'),
      ('vitamin b12', 'vitamin-b12', 100, 'Provider vitamin/mineral category.'),
      ('cyanocobalamin', 'vitamin-b12', 98, 'Provider groups B12 forms under Vitamin B12.'),
      ('methylcobalamin', 'vitamin-b12', 98, 'Provider groups B12 forms under Vitamin B12.'),
      ('d2', 'vitamin-d', 98, 'Vitamin D2 maps to provider Vitamin D category.'),
      ('d3', 'vitamin-d', 98, 'Vitamin D3 maps to provider Vitamin D category.'),
      ('vit d', 'vitamin-d', 98, 'Vitamin D abbreviation.'),
      ('vit d3', 'vitamin-d', 98, 'Vitamin D3 abbreviation.'),
      ('vitamin d3', 'vitamin-d', 98, 'Vitamin D3 maps to provider Vitamin D category.'),
      ('vitamin d3 cholecalciferol', 'vitamin-d', 98, 'Cholecalciferol maps to provider Vitamin D category.'),
      ('vitamin d2 ergocalciferol', 'vitamin-d', 98, 'Ergocalciferol maps to provider Vitamin D category.'),
      ('cholecalciferol', 'vitamin-d', 98, 'Provider groups cholecalciferol under Vitamin D.'),
      ('ergocalciferol', 'vitamin-d', 98, 'Provider groups ergocalciferol under Vitamin D.'),
      ('e', 'vitamin-e', 98, 'All current E-token uses are vitamin-formulation context.'),
      ('vit e', 'vitamin-e', 100, 'Vitamin E abbreviation.'),
      ('vitamin e', 'vitamin-e', 100, 'Provider vitamin/mineral category.'),
      ('tocopherol', 'vitamin-e', 95, 'Provider groups tocopherol under Vitamin E.'),
      ('vit k', 'vitamin-k', 100, 'Explicit Vitamin K abbreviation.'),
      ('vitamin k', 'vitamin-k', 100, 'Provider vitamin/mineral category.'),
      ('ca', 'calcium', 98, 'Calcium mineral abbreviation.'),
      ('calcium salts', 'calcium', 98, 'Provider calcium mineral category.'),
      ('calcium carbonate', 'calcium', 98, 'Provider calcium mineral category.'),
      ('calcium chloride', 'calcium', 98, 'Provider calcium mineral category.'),
      ('ca carbonate', 'calcium', 98, 'Calcium mineral abbreviation.'),
      ('ca chloride', 'calcium', 98, 'Calcium mineral abbreviation.'),
      ('ca salts', 'calcium', 98, 'Calcium mineral abbreviation.'),
      ('calcium gluconate', 'calcium', 95, 'Provider calcium mineral category.'),
      ('ca gluconate', 'calcium', 95, 'Provider calcium mineral category.'),
      ('calcium glycerophosphate', 'calcium', 95, 'Provider calcium mineral category.'),
      ('mg', 'magnesium', 98, 'Magnesium mineral abbreviation.'),
      ('mg hydroxide', 'magnesium', 98, 'Provider magnesium mineral category.'),
      ('magnesium hydroxide', 'magnesium', 98, 'Provider magnesium mineral category.'),
      ('magnesium carbonate', 'magnesium', 98, 'Provider magnesium mineral category.'),
      ('mg chloride', 'magnesium', 98, 'Magnesium mineral abbreviation.'),
      ('magnesium oxide', 'magnesium', 98, 'Provider magnesium mineral category.'),
      ('magnesium oxde', 'magnesium', 95, 'Source spelling correction to magnesium oxide.'),
      ('mg oxide', 'magnesium', 98, 'Magnesium mineral abbreviation.'),
      ('mg trisilicate', 'magnesium', 95, 'Provider magnesium mineral category.'),
      ('magnesium pidolate', 'magnesium', 95, 'Provider magnesium mineral category.'),
      ('mg lactate', 'magnesium', 95, 'Provider magnesium mineral category.'),
      ('mg glycerophosphate', 'magnesium', 95, 'Provider magnesium mineral category.'),
      ('fe', 'iron', 98, 'Iron mineral abbreviation.'),
      ('iron salts', 'iron', 98, 'Provider iron mineral category.'),
      ('iron polymaltose', 'iron', 95, 'Provider iron mineral category.'),
      ('iron sucrose', 'iron', 95, 'Provider iron mineral category.'),
      ('ferrous fumarate', 'iron', 95, 'Provider iron mineral category.'),
      ('ferrous sulphate', 'iron', 95, 'Provider iron mineral category.'),
      ('ferric ammonium citrate', 'iron', 95, 'Provider iron mineral category.'),
      ('ferric ammonuim citrate', 'iron', 95, 'Source spelling correction; provider iron mineral category.'),
      ('zn', 'zinc', 98, 'Zinc mineral abbreviation.'),
      ('zinc oxide', 'zinc', 95, 'Provider zinc mineral category.'),
      ('zinc sulfate', 'zinc', 95, 'Provider zinc mineral category.'),
      ('zinc sulphate', 'zinc', 95, 'Provider zinc mineral category.'),
      ('zinc acetate', 'zinc', 95, 'Provider zinc mineral category.'),
      ('zinc citrate', 'zinc', 95, 'Provider zinc mineral category.'),
      ('zinc gluconate', 'zinc', 95, 'Provider zinc mineral category.'),
      ('kcl', 'potassium-chloride', 100, 'Potassium chloride abbreviation.'),
      ('potassium cl', 'potassium-chloride', 98, 'Potassium chloride abbreviation.'),
      ('potassium citrate', 'potassium', 95, 'Provider potassium mineral category.'),
      ('potassium bicarbonate', 'potassium', 95, 'Provider potassium mineral category.'),
      ('potassium gluconate', 'potassium', 95, 'Provider potassium mineral category.'),
      ('gin', 'ginseng', 98, 'All current GIN-token uses are ginseng multivitamin context.'),
      ('ginseng ext', 'ginseng', 98, 'Ginseng extract abbreviation.'),
      ('ginseng extract', 'ginseng', 98, 'Provider ginseng supplement category.'),
      ('ginseng powder', 'ginseng', 98, 'Provider ginseng supplement category.')
  ),
  provider as (
    select
      item ->> 'id' as provider_id,
      item ->> 'name' as provider_name,
      item ->> 'kind' as provider_kind
    from pg_catalog.jsonb_array_elements(
      provider_catalog -> 'results'
    ) item
  )
  update app_private.interaction_checker_ingredient_mappings m
  set
    status = 'mapped',
    provider_substance_id = p.provider_id,
    provider_substance_name = p.provider_name,
    provider_substance_kind = p.provider_kind,
    mapping_method = 'context',
    confidence = r.confidence,
    candidate_substance_ids = array[p.provider_id],
    note = r.note,
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from rules r
  join app_private.catalog_ingredients i
    on i.normalized_name = r.internal_key
  join provider p on p.provider_id = r.provider_id
  where m.ingredient_id = i.id
    and m.mapping_method <> 'manual';

  -- Known local identities with no standalone substance in the current
  -- provider snapshot stay explicitly unmapped instead of being forced onto
  -- a clinically different provider substance.
  update app_private.interaction_checker_ingredient_mappings m
  set
    note = case
      when i.normalized_name in ('a', 'vit a', 'vitamin a')
        then 'Known Vitamin A context; current provider snapshot has no standalone Vitamin A substance.'
      when i.normalized_name in ('c', 'vit c', 'vitamin c', 'ascorbic acid')
        then 'Known Vitamin C/ascorbic acid context; current provider snapshot has no standalone Vitamin C substance.'
      when i.normalized_name in ('thiamine', 'vit b1')
        then 'Known Vitamin B1/thiamine context; current provider snapshot has no standalone Vitamin B1 substance.'
      when i.normalized_name in ('vit b2', 'riboflavin')
        then 'Known Vitamin B2/riboflavin context; current provider snapshot has no standalone Vitamin B2 substance.'
      when i.normalized_name in ('b6', 'vit b6', 'vitamin b6', 'pyridoxine')
        then 'Known Vitamin B6 context; current provider snapshot has no standalone Vitamin B6 substance.'
      when i.normalized_name in ('cu', 'copper')
        then 'Known copper mineral context; current provider snapshot has no standalone copper substance.'
      when i.normalized_name in ('mn', 'manganese')
        then 'Known manganese mineral context; current provider snapshot has no standalone manganese substance.'
      when i.normalized_name in ('p', 'phosphorus', 'phosphate')
        then 'Known phosphorus/phosphate context; current provider snapshot has no standalone phosphorus/phosphate substance.'
      else m.note
    end,
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from app_private.catalog_ingredients i
  where m.ingredient_id = i.id
    and m.status = 'unmapped'
    and i.normalized_name in (
      'a', 'vit a', 'vitamin a',
      'c', 'vit c', 'vitamin c', 'ascorbic acid',
      'thiamine', 'vit b1',
      'vit b2', 'riboflavin',
      'b6', 'vit b6', 'vitamin b6', 'pyridoxine',
      'cu', 'copper',
      'mn', 'manganese',
      'p', 'phosphorus', 'phosphate'
    )
    and m.mapping_method <> 'manual';

  -- Explicitly preserve ambiguous high-use abbreviations instead of forcing
  -- them into a provider identity.
  update app_private.interaction_checker_ingredient_mappings m
  set
    status = 'ambiguous',
    provider_substance_id = null,
    provider_substance_name = null,
    provider_substance_kind = null,
    mapping_method = 'context',
    confidence = 0,
    candidate_substance_ids = array['potassium', 'vitamin-k'],
    note = 'K is context-dependent in the source catalog (potassium vs vitamin K). Product-component overrides resolve reviewed current uses.',
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from app_private.catalog_ingredients i
  where m.ingredient_id = i.id
    and i.normalized_name = 'k'
    and m.mapping_method <> 'manual';

  update app_private.interaction_checker_ingredient_mappings m
  set
    status = 'ambiguous',
    provider_substance_id = null,
    provider_substance_name = null,
    provider_substance_kind = null,
    mapping_method = 'context',
    confidence = 0,
    candidate_substance_ids = array['niacin'],
    note = 'PP is Vitamin B3 in current multivitamin context, but the provider catalog exposes drug niacin and no distinct nicotinamide/niacinamide substance; do not conflate automatically.',
    provider_catalog_fetched_at = catalog_fetched_at,
    updated_at = pg_catalog.now()
  from app_private.catalog_ingredients i
  where m.ingredient_id = i.id
    and i.normalized_name in ('pp', 'vit b3', 'vitamin b3')
    and m.mapping_method <> 'manual';

  -- Product-component K overrides. The current source catalog uses the same
  -- lexical K identity for two medically different meanings.
  with provider as (
    select
      item ->> 'id' as provider_id,
      item ->> 'name' as provider_name,
      item ->> 'kind' as provider_kind
    from pg_catalog.jsonb_array_elements(
      provider_catalog -> 'results'
    ) item
  ),
  contexts as (
    select
      pi.product_id,
      pi.component_index,
      pi.ingredient_id,
      case
        when p.name_en ilike 'ADAVIT-SILVER%'
          then 'vitamin-k'
        when p.name_en ilike 'ASIA-TONIC%'
          or p.name_en ilike 'RUBAVIT-G%'
          then 'potassium'
        else null
      end as provider_id,
      case
        when p.name_en ilike 'ADAVIT-SILVER%'
          then 'K is in a multivitamin vitamin sequence; reviewed as vitamin K.'
        when p.name_en ilike 'ASIA-TONIC%'
          or p.name_en ilike 'RUBAVIT-G%'
          then 'K is in the mineral sequence FE+K+CU+MN+ZN+P; reviewed as potassium.'
        else null
      end as note
    from app_private.product_ingredients pi
    join app_private.catalog_ingredients i on i.id = pi.ingredient_id
    join public.products p on p.id = pi.product_id
    where i.normalized_name = 'k'
  )
  insert into app_private.interaction_checker_component_overrides(
    product_id,
    component_index,
    ingredient_id,
    status,
    provider_substance_id,
    provider_substance_name,
    provider_substance_kind,
    mapping_method,
    confidence,
    candidate_substance_ids,
    note,
    provider_catalog_fetched_at,
    updated_at
  )
  select
    c.product_id,
    c.component_index,
    c.ingredient_id,
    'mapped',
    p.provider_id,
    p.provider_name,
    p.provider_kind,
    'context',
    97,
    array[p.provider_id],
    c.note,
    catalog_fetched_at,
    pg_catalog.now()
  from contexts c
  join provider p on p.provider_id = c.provider_id
  where c.provider_id is not null
  on conflict (product_id, component_index) do update
  set
    ingredient_id = excluded.ingredient_id,
    status = excluded.status,
    provider_substance_id = excluded.provider_substance_id,
    provider_substance_name = excluded.provider_substance_name,
    provider_substance_kind = excluded.provider_substance_kind,
    mapping_method = excluded.mapping_method,
    confidence = excluded.confidence,
    candidate_substance_ids = excluded.candidate_substance_ids,
    note = excluded.note,
    provider_catalog_fetched_at = excluded.provider_catalog_fetched_at,
    updated_at = excluded.updated_at
  where
    app_private.interaction_checker_component_overrides.mapping_method
      <> 'manual';

  return query
  select
    count(*) filter (where m.status = 'mapped')::integer,
    count(*) filter (where m.status = 'ambiguous')::integer,
    count(*) filter (where m.status = 'unmapped')::integer,
    (
      select count(*)::integer
      from app_private.interaction_checker_component_overrides
      where status = 'mapped'
    )
  from app_private.interaction_checker_ingredient_mappings m;
end;
$reconcile_interaction_checker_mappings$;

revoke all on function app_private.reconcile_interaction_checker_mappings(
  jsonb,
  timestamptz
)
from public, anon, authenticated;

drop function public.catalog_ddi_ingredients(uuid[]);

create function public.catalog_ddi_ingredients(
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
  normalized_ingredient_name text,
  provider_mapping_status text,
  provider_substance_id text,
  provider_substance_name text,
  provider_substance_kind text,
  provider_mapping_method text
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
    end as normalized_ingredient_name,
    case
      when not c.is_trusted then null
      when o.product_id is not null then o.status::text
      when m.ingredient_id is not null then m.status::text
      else 'unmapped'
    end as provider_mapping_status,
    case
      when not c.is_trusted then null
      when o.product_id is not null then o.provider_substance_id
      else m.provider_substance_id
    end as provider_substance_id,
    case
      when not c.is_trusted then null
      when o.product_id is not null then o.provider_substance_name
      else m.provider_substance_name
    end as provider_substance_name,
    case
      when not c.is_trusted then null
      when o.product_id is not null then o.provider_substance_kind
      else m.provider_substance_kind
    end as provider_substance_kind,
    case
      when not c.is_trusted then null
      when o.product_id is not null then o.mapping_method::text
      when m.ingredient_id is not null then m.mapping_method::text
      else 'none'
    end as provider_mapping_method
  from coverage c
  left join app_private.product_ingredients pi
    on c.is_trusted
    and pi.product_id = c.product_id
  left join app_private.catalog_ingredients i
    on i.id = pi.ingredient_id
  left join app_private.interaction_checker_component_overrides o
    on o.product_id = pi.product_id
    and o.component_index = pi.component_index
    and o.ingredient_id = pi.ingredient_id
  left join app_private.interaction_checker_ingredient_mappings m
    on m.ingredient_id = pi.ingredient_id
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
  'Owner-only bounded DDI ingredient input mapping with Interaction Checker provider identity status.';
