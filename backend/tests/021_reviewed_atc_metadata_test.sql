-- SDIF-003 regression checks for reviewed ATC metadata.
-- Run after migrations through 0023. This test is read-only.

do $test$
declare
  target_rows integer;
  verified_mappings integer;
  verified_identities integer;
  bad_rows integer;
begin
  select count(*)
    into target_rows
  from app_private.scientific_ingredient_atc_codes a
  join app_private.scientific_ingredients s
    on s.id = a.scientific_ingredient_id
  where (s.normalized_preferred_name, a.atc_code, a.atc_name) in (
    (app_private.scientific_name_key('Amoxicillin'), 'J01CA04', 'amoxicillin'),
    (app_private.scientific_name_key('Caffeine'), 'N06BC01', 'caffeine'),
    (app_private.scientific_name_key('Paracetamol'), 'N02BE01', 'paracetamol')
  );

  if target_rows <> 3 then
    raise exception 'expected 3 reviewed SDIF-003 ATC rows, found %', target_rows;
  end if;

  select count(*)
    into bad_rows
  from app_private.scientific_ingredient_atc_codes a
  join app_private.scientific_ingredients s
    on s.id = a.scientific_ingredient_id
  where s.normalized_preferred_name in (
      app_private.scientific_name_key('Amoxicillin'),
      app_private.scientific_name_key('Caffeine'),
      app_private.scientific_name_key('Paracetamol')
    )
    and (
      a.reference_version <> 'WHO ATC/DDD Index; page last updated 2026-01-20'
      or a.reviewed_at <> timestamptz '2026-10-02 00:00:00+00'
      or a.review_note not like '%Plain-substance classification metadata only%'
      or a.review_note not like '%do not generalize to combination/product-specific ATC%'
    );

  if bad_rows <> 0 then
    raise exception 'SDIF-003 ATC provenance/scope regression: % row(s)', bad_rows;
  end if;

  select count(*) filter (where status = 'verified'),
         count(distinct scientific_ingredient_id) filter (where status = 'verified')
    into verified_mappings, verified_identities
  from app_private.catalog_ingredient_scientific_mappings;

  if verified_mappings <> 4 or verified_identities <> 3 then
    raise exception
      'SDIF-003 must not alter verified scientific mappings: mappings %, identities %',
      verified_mappings,
      verified_identities;
  end if;
end;
$test$;
