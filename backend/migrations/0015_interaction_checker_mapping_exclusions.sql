-- Issue #98 follow-up hardening: do not map a narrower internal
-- glucosamine identity to the provider's broader "Glucosamine and
-- chondroitin" substance.

alter table app_private.interaction_checker_ingredient_mappings
  drop constraint interaction_checker_mapping_unmapped_method;

alter table app_private.interaction_checker_ingredient_mappings
  add constraint interaction_checker_mapping_unmapped_method
  check (
    status <> 'unmapped'
    or mapping_method in ('none', 'manual')
  );

update app_private.interaction_checker_ingredient_mappings m
set
  status = 'unmapped',
  provider_substance_id = null,
  provider_substance_name = null,
  provider_substance_kind = null,
  mapping_method = 'manual',
  confidence = 100,
  candidate_substance_ids = array['glucosamine']::text[],
  note = 'Manual exclusion: provider substance glucosamine is labeled "Glucosamine and chondroitin", which is broader than this internal glucosamine identity.',
  updated_at = now()
from app_private.catalog_ingredients i
where m.ingredient_id = i.id
  and i.normalized_name in ('glucosamine', 'glucosamine sulfate')
  and m.provider_substance_id = 'glucosamine';
