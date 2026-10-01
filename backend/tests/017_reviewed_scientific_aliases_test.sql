\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

set local role authenticated;
set local "request.jwt.claim.sub" =
  '11111111-1111-1111-1111-111111111111';

select id from public.catalog_create_idempotent(
  '77000000-0000-4000-8000-000000000002',
  'SP041 Raw Alias Preservation',
  null,
  'amoxicilline',
  null,
  null,
  'Capsule',
  null,
  null,
  null,
  1000,
  'SYP',
  null
);

reset role;

do $reviewed_aliases$
declare
  r record;
  cleanup record;
  lexical_ingredient_id bigint;
  lexical_ingredient_name text;
  raw_component_before text;
  test_identity_id bigint;
begin
  select * into r
  from app_private.resolve_reviewed_scientific_alias('amoxicilline');

  if r.scientific_ingredient_id is null
     or r.preferred_name <> 'Amoxicillin'
     or r.match_kind <> 'reviewed_alias'
     or r.alias_text <> 'Amoxicilline'
     or r.alias_kind <> 'legacy_name'
     or nullif(btrim(r.reference_source), '') is null
     or r.reviewed_at is null then
    raise exception 'amoxicilline reviewed alias resolution failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.resolve_reviewed_scientific_alias('Amoxycillin');

  if r.preferred_name <> 'Amoxicillin'
     or r.match_kind <> 'reviewed_alias'
     or r.alias_kind <> 'synonym' then
    raise exception 'Amoxycillin reviewed synonym resolution failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.resolve_reviewed_scientific_alias('cafeine');

  if r.preferred_name <> 'Caffeine'
     or r.match_kind <> 'reviewed_alias'
     or r.alias_text <> 'cafeine'
     or r.alias_kind <> 'legacy_name'
     or position('ChEBI' in coalesce(r.reference_source, '')) = 0
     or r.reviewed_at is null then
    raise exception 'cafeine reviewed spelling resolution failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.resolve_reviewed_scientific_alias('caféine');

  if r.preferred_name <> 'Caffeine'
     or r.match_kind <> 'reviewed_alias'
     or r.alias_kind <> 'local_name' then
    raise exception 'caféine reviewed local-name resolution failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.resolve_reviewed_scientific_alias('acetaminophen');

  if r.preferred_name <> 'Paracetamol'
     or r.match_kind <> 'reviewed_alias'
     or r.alias_kind <> 'common_name'
     or position('PubChem CID 1983' in coalesce(r.reference_source, '')) = 0 then
    raise exception 'acetaminophen/paracetamol reviewed synonym failed: %', to_jsonb(r);
  end if;

  select * into r
  from app_private.resolve_reviewed_scientific_alias('Amoxicillin');

  if r.preferred_name <> 'Amoxicillin'
     or r.match_kind <> 'canonical'
     or r.alias_text is not null
     or r.reference_source is not null then
    raise exception 'canonical exact-name resolution failed: %', to_jsonb(r);
  end if;

  if exists (
    select 1
    from app_private.resolve_reviewed_scientific_alias('amoxicilin')
  ) then
    raise exception 'uncurated fuzzy near-match amoxicilin was auto-accepted';
  end if;

  if exists (
    select 1
    from app_private.resolve_reviewed_scientific_alias('VIT.B3')
  ) or exists (
    select 1
    from app_private.resolve_reviewed_scientific_alias('Vitamin B3')
  ) then
    raise exception 'ambiguous Vitamin B3 token was semantically collapsed';
  end if;

  select * into cleanup
  from app_private.scientific_cleanup_component_candidate('amoxicilline');

  if cleanup.candidate_text <> 'Amoxicilline'
     or cleanup.cleanup_status <> 'deterministic_candidate' then
    raise exception 'SP-040 cleanup candidate changed unexpectedly: %', to_jsonb(cleanup);
  end if;

  select * into r
  from app_private.resolve_reviewed_scientific_alias(cleanup.candidate_text);

  if r.preferred_name <> 'Amoxicillin'
     or r.match_kind <> 'reviewed_alias' then
    raise exception 'reviewed alias did not resolve SP-040 candidate: %', to_jsonb(r);
  end if;

  select pi.ingredient_id, i.name, pi.raw_component
    into lexical_ingredient_id, lexical_ingredient_name, raw_component_before
  from app_private.product_ingredients pi
  join app_private.catalog_ingredients i on i.id = pi.ingredient_id
  where pi.product_id = '77000000-0000-4000-8000-000000000002'::uuid
    and pi.component_index = 1;

  if raw_component_before <> 'amoxicilline' then
    raise exception 'synthetic raw spelling not preserved before alias resolution';
  end if;

  perform *
  from app_private.resolve_reviewed_scientific_alias(raw_component_before);

  if not exists (
    select 1
    from app_private.product_ingredients pi
    join app_private.catalog_ingredients i on i.id = pi.ingredient_id
    where pi.product_id = '77000000-0000-4000-8000-000000000002'::uuid
      and pi.component_index = 1
      and pi.ingredient_id = lexical_ingredient_id
      and pi.raw_component = raw_component_before
      and i.name = lexical_ingredient_name
  ) then
    raise exception 'reviewed alias resolution mutated SP-025 lexical state';
  end if;

  if exists (
    select 1
    from app_private.catalog_ingredient_scientific_mappings m
    where m.ingredient_id = lexical_ingredient_id
  ) then
    raise exception 'SP-041 resolver persisted a production-style scientific mapping';
  end if;

  begin
    insert into app_private.scientific_ingredients(
      preferred_name,
      normalized_preferred_name,
      category
    ) values (
      'Amoxicilline',
      app_private.scientific_name_key('Amoxicilline'),
      'medicinal_substance'
    );
    raise exception 'canonical name was allowed to collide with reviewed alias';
  exception
    when unique_violation then null;
  end;

  insert into app_private.scientific_ingredients(
    preferred_name,
    normalized_preferred_name,
    category
  ) values (
    'SP041 Collision Test Identity',
    app_private.scientific_name_key('SP041 Collision Test Identity'),
    'other'
  ) returning id into test_identity_id;

  begin
    insert into app_private.scientific_ingredient_aliases(
      normalized_alias,
      scientific_ingredient_id,
      alias_text,
      alias_kind,
      reference_source,
      reference_version,
      reviewed_at,
      review_note
    ) values (
      app_private.scientific_name_key('Caffeine'),
      test_identity_id,
      'Caffeine',
      'synonym',
      'synthetic collision fixture',
      'test',
      now(),
      'Must conflict with canonical Caffeine identity.'
    );
    raise exception 'reviewed alias was allowed to collide with canonical name';
  exception
    when unique_violation then null;
  end;

  begin
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
      'synonym',
      'synthetic collision fixture',
      'test',
      now(),
      'Must conflict with existing Amoxicilline -> Amoxicillin alias.'
    from app_private.scientific_ingredients i
    where i.normalized_preferred_name = app_private.scientific_name_key('Caffeine');
    raise exception 'same reviewed alias key was allowed to map to two identities';
  exception
    when unique_violation then null;
  end;

  if exists (
    select 1
    from app_private.scientific_ingredient_aliases a
    where nullif(btrim(a.reference_source), '') is null
       or a.reviewed_at is null
  ) then
    raise exception 'reviewed scientific alias lacks provenance/review timestamp';
  end if;
end
$reviewed_aliases$;

do $reviewed_alias_private_access$
begin
  if has_function_privilege(
    'anon',
    'app_private.resolve_reviewed_scientific_alias(text)',
    'EXECUTE'
  ) then
    raise exception 'anon can execute private reviewed alias resolver';
  end if;

  if has_function_privilege(
    'authenticated',
    'app_private.resolve_reviewed_scientific_alias(text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can execute private reviewed alias resolver';
  end if;

  if has_function_privilege(
    'anon',
    'app_private.guard_scientific_alias_canonical_collision()',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'app_private.guard_scientific_alias_canonical_collision()',
    'EXECUTE'
  ) then
    raise exception 'client role can execute private alias collision guard';
  end if;
end
$reviewed_alias_private_access$;

rollback;
