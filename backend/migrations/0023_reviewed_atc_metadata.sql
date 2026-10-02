-- SDIF-003: curate bounded reviewed ATC classification metadata for the three
-- currently verified Sherko scientific identities. ATC is classification
-- metadata only; these rows apply to the plain substance and do not classify
-- every combination/product/route containing that substance.

do $sdif003$
declare
  target record;
  target_identity_id bigint;
  identity_count integer;
  verified_mapping_count integer;
  conflicting_name text;
begin
  for target in
    select *
    from (values
      (
        'Amoxicillin'::text,
        'J01CA04'::text,
        'amoxicillin'::text,
        'https://atcddd.fhi.no/atc_ddd_index/?code=J01CA04&showdescription=no'::text
      ),
      (
        'Caffeine'::text,
        'N06BC01'::text,
        'caffeine'::text,
        'https://atcddd.fhi.no/atc_ddd_index/?code=N06BC01&showdescription=no'::text
      ),
      (
        'Paracetamol'::text,
        'N02BE01'::text,
        'paracetamol'::text,
        'https://atcddd.fhi.no/atc_ddd_index/?code=N02BE01&showdescription=no'::text
      )
    ) as curated(preferred_name, atc_code, atc_name, source_url)
  loop
    select count(*), min(id)
      into identity_count, target_identity_id
    from app_private.scientific_ingredients
    where normalized_preferred_name =
      app_private.scientific_name_key(target.preferred_name);

    if identity_count <> 1 then
      raise exception
        'SDIF-003 expected exactly one scientific identity for %, found %',
        target.preferred_name,
        identity_count
        using errcode = '23514';
    end if;

    select count(*)
      into verified_mapping_count
    from app_private.catalog_ingredient_scientific_mappings
    where scientific_ingredient_id = target_identity_id
      and status = 'verified';

    if verified_mapping_count = 0 then
      raise exception
        'SDIF-003 scientific identity % is not referenced by a verified lexical mapping',
        target.preferred_name
        using errcode = '23514';
    end if;

    select atc_name
      into conflicting_name
    from app_private.scientific_ingredient_atc_codes
    where scientific_ingredient_id = target_identity_id
      and atc_code = target.atc_code
      and atc_name is distinct from target.atc_name;

    if found then
      raise exception
        'SDIF-003 existing ATC row conflicts for % / %: existing name %',
        target.preferred_name,
        target.atc_code,
        conflicting_name
        using errcode = '23514';
    end if;

    insert into app_private.scientific_ingredient_atc_codes(
      scientific_ingredient_id,
      atc_code,
      atc_name,
      reference_version,
      reviewed_at,
      review_note
    )
    values (
      target_identity_id,
      target.atc_code,
      target.atc_name,
      'WHO ATC/DDD Index; page last updated 2026-01-20',
      timestamptz '2026-10-02 00:00:00+00',
      'Reviewed 2026-10-02 against the official WHO Collaborating Centre for Drug Statistics Methodology ATC/DDD Index. Plain-substance classification metadata only; do not generalize to combination/product-specific ATC or use ATC as scientific identity truth. Source: ' || target.source_url
    )
    on conflict (scientific_ingredient_id, atc_code) do update
    set
      atc_name = excluded.atc_name,
      reference_version = excluded.reference_version,
      reviewed_at = excluded.reviewed_at,
      review_note = excluded.review_note
    where (
      app_private.scientific_ingredient_atc_codes.atc_name,
      app_private.scientific_ingredient_atc_codes.reference_version,
      app_private.scientific_ingredient_atc_codes.reviewed_at,
      app_private.scientific_ingredient_atc_codes.review_note
    ) is distinct from (
      excluded.atc_name,
      excluded.reference_version,
      excluded.reviewed_at,
      excluded.review_note
    );
  end loop;

  if (
    select count(*)
    from app_private.scientific_ingredient_atc_codes a
    join app_private.scientific_ingredients s
      on s.id = a.scientific_ingredient_id
    where (s.normalized_preferred_name, a.atc_code) in (
      (app_private.scientific_name_key('Amoxicillin'), 'J01CA04'),
      (app_private.scientific_name_key('Caffeine'), 'N06BC01'),
      (app_private.scientific_name_key('Paracetamol'), 'N02BE01')
    )
  ) <> 3 then
    raise exception 'SDIF-003 expected all three reviewed ATC rows after curation'
      using errcode = '23514';
  end if;
end;
$sdif003$;
