-- Issue #98 hardening: persist reviewed provider-mapping exclusions so
-- future reconciliations cannot recreate an explicitly rejected match.

create table app_private.interaction_checker_mapping_exclusions (
  ingredient_normalized_name text not null,
  provider_substance_id text not null,
  note text not null,
  created_at timestamptz not null default now(),
  primary key (ingredient_normalized_name, provider_substance_id),
  constraint interaction_checker_mapping_exclusion_name_nonblank
    check (btrim(ingredient_normalized_name) <> ''),
  constraint interaction_checker_mapping_exclusion_provider_nonblank
    check (btrim(provider_substance_id) <> ''),
  constraint interaction_checker_mapping_exclusion_note_nonblank
    check (btrim(note) <> '')
);

revoke all on app_private.interaction_checker_mapping_exclusions
from public, anon, authenticated;

insert into app_private.interaction_checker_mapping_exclusions(
  ingredient_normalized_name,
  provider_substance_id,
  note
)
values
  (
    'glucosamine',
    'glucosamine',
    'Provider substance is labeled "Glucosamine and chondroitin", which is broader than the internal glucosamine identity.'
  ),
  (
    'glucosamine sulfate',
    'glucosamine',
    'Provider substance is labeled "Glucosamine and chondroitin", which is broader than the internal glucosamine sulfate identity.'
  );

create function app_private.enforce_interaction_checker_mapping_exclusion()
returns trigger
language plpgsql
set search_path = ''
as $enforce_interaction_checker_mapping_exclusion$
declare
  exclusion_note text;
  excluded_provider_id text;
begin
  if new.provider_substance_id is null then
    return new;
  end if;

  select e.note
  into exclusion_note
  from app_private.interaction_checker_mapping_exclusions e
  join app_private.catalog_ingredients i
    on i.id = new.ingredient_id
  where e.ingredient_normalized_name = i.normalized_name
    and e.provider_substance_id = new.provider_substance_id
  limit 1;

  if exclusion_note is null then
    return new;
  end if;

  excluded_provider_id := new.provider_substance_id;
  new.status = 'unmapped';
  new.provider_substance_id = null;
  new.provider_substance_name = null;
  new.provider_substance_kind = null;
  new.mapping_method = 'manual';
  new.confidence = 100;
  new.candidate_substance_ids = array[excluded_provider_id]::text[];
  new.note = 'Manual exclusion: ' || exclusion_note;
  new.updated_at = now();

  return new;
end;
$enforce_interaction_checker_mapping_exclusion$;

revoke all on function
  app_private.enforce_interaction_checker_mapping_exclusion()
from public, anon, authenticated;

create trigger enforce_interaction_checker_mapping_exclusion
before insert or update
on app_private.interaction_checker_ingredient_mappings
for each row
execute function
  app_private.enforce_interaction_checker_mapping_exclusion();

-- Re-assert the current reviewed exclusions in case this migration is applied
-- to an environment where reconciliation already populated the mappings.
update app_private.interaction_checker_ingredient_mappings m
set
  status = 'unmapped',
  provider_substance_id = null,
  provider_substance_name = null,
  provider_substance_kind = null,
  mapping_method = 'manual',
  confidence = 100,
  candidate_substance_ids = array['glucosamine']::text[],
  note = 'Manual exclusion: ' || e.note,
  updated_at = now()
from app_private.catalog_ingredients i
join app_private.interaction_checker_mapping_exclusions e
  on e.ingredient_normalized_name = i.normalized_name
where m.ingredient_id = i.id
  and (
    m.provider_substance_id = e.provider_substance_id
    or (
      m.mapping_method = 'manual'
      and m.provider_substance_id is null
      and m.candidate_substance_ids @> array[e.provider_substance_id]::text[]
    )
  );
