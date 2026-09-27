\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111')
on conflict (singleton) do update set user_id = excluded.user_id;

do $alternatives_api_test$
declare
  target_id uuid;
  exact_alpha_id uuid;
  exact_zulu_id uuid;
  different_strength_id uuid;
  different_form_id uuid;
  both_different_id uuid;
  unresolved_form_id uuid;
  other_ingredient_id uuid;
  untrusted_target_id uuid;
  created_id uuid;
  i integer;
begin
  if has_function_privilege(
    'anon',
    'public.catalog_alternatives(uuid,integer)',
    'EXECUTE'
  ) then
    raise exception 'anon can execute catalog_alternatives';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.catalog_alternatives(uuid,integer)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute catalog_alternatives';
  end if;

  set local role authenticated;
  set local "request.jwt.claim.sub" =
    '22222222-2222-2222-2222-222222222222';

  begin
    perform *
    from public.catalog_alternatives(
      '73000000-0000-4000-8000-000000000001',
      10
    );
    raise exception 'non-owner alternatives call unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;

  reset role;

  set local role authenticated;
  set local "request.jwt.claim.sub" =
    '11111111-1111-1111-1111-111111111111';

  select id into target_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000001',
    'SP028 Target',
    null,
    'SP028TESTACTIVE',
    null,
    '500 MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    1000,
    'SYP',
    null
  );

  select id into exact_alpha_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000002',
    'SP028 Exact Alpha',
    null,
    'SP028TESTACTIVE',
    'Company A',
    '500 MG/CTD TAB.',
    'Film Coated Tablet',
    null,
    '028000000002',
    null,
    2000,
    'SYP',
    null
  );

  select id into exact_zulu_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000003',
    'SP028 Exact Zulu',
    null,
    'SP028TESTACTIVE',
    'Company Z',
    '500 MG/CTD TAB.',
    'Coated Tablet',
    null,
    '028000000003',
    null,
    3000,
    'SYP',
    null
  );

  select id into different_strength_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000004',
    'SP028 Different Strength',
    null,
    'SP028TESTACTIVE',
    null,
    '650 MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    4000,
    'SYP',
    null
  );

  select id into different_form_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000005',
    'SP028 Different Form',
    null,
    'SP028TESTACTIVE',
    null,
    '500 MG/CAP.',
    'Capsule',
    null,
    null,
    null,
    5000,
    'SYP',
    null
  );

  select id into both_different_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000006',
    'SP028 Both Different',
    null,
    'SP028TESTACTIVE',
    null,
    '650 MG/CAP.',
    'Capsule',
    null,
    null,
    null,
    6000,
    'SYP',
    null
  );

  select id into unresolved_form_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000007',
    'SP028 Unresolved Form',
    null,
    'SP028TESTACTIVE',
    null,
    '500 MG',
    'Unclassified Hybrid Device',
    null,
    null,
    null,
    7000,
    'SYP',
    null
  );

  select id into other_ingredient_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000008',
    'SP028 Other Ingredient',
    null,
    'SP028OTHERACTIVE',
    null,
    '500 MG/CTD TAB.',
    'Tablet',
    null,
    null,
    null,
    8000,
    'SYP',
    null
  );

  select id into untrusted_target_id
  from public.catalog_create_idempotent(
    '73000000-0000-4000-8000-000000000009',
    'SP028 Untrusted Target',
    null,
    'SP028UNTRUSTEDACTIVE',
    null,
    '500 MG',
    'Unknown Device Form',
    null,
    null,
    null,
    9000,
    'SYP',
    null
  );

  if (
    select count(*)
    from public.catalog_alternatives(target_id, 10)
    where relationship_group = 'exact'
  ) <> 2 then
    raise exception 'exact alternatives group is incorrect';
  end if;

  if (
    select count(*)
    from public.catalog_alternatives(target_id, 10)
    where relationship_group = 'same_ingredients_different_strength'
  ) <> 1 then
    raise exception 'different-strength alternatives group is incorrect';
  end if;

  if (
    select count(*)
    from public.catalog_alternatives(target_id, 10)
    where relationship_group = 'same_ingredients_different_form'
  ) <> 1 then
    raise exception 'different-form alternatives group is incorrect';
  end if;

  if not exists (
    select 1
    from public.catalog_alternatives(target_id, 10)
    where relationship_group = 'exact'
      and id = exact_alpha_id
      and group_position = 1
      and selling_amount = 2000
      and currency = 'SYP'
      and barcode = '028000000002'
  ) then
    raise exception 'exact result shape/order did not preserve catalog values';
  end if;

  if not exists (
    select 1
    from public.catalog_alternatives(target_id, 10)
    where relationship_group = 'exact'
      and id = exact_zulu_id
      and group_position = 2
  ) then
    raise exception 'exact deterministic ordering failed';
  end if;

  if not exists (
    select 1
    from public.catalog_alternatives(target_id, 10)
    where relationship_group = 'same_ingredients_different_strength'
      and id = different_strength_id
  ) then
    raise exception 'different-strength candidate was not returned';
  end if;

  if not exists (
    select 1
    from public.catalog_alternatives(target_id, 10)
    where relationship_group = 'same_ingredients_different_form'
      and id = different_form_id
  ) then
    raise exception 'different-form candidate was not returned';
  end if;

  if exists (
    select 1
    from public.catalog_alternatives(target_id, 10)
    where id in (
      target_id,
      both_different_id,
      unresolved_form_id,
      other_ingredient_id
    )
  ) then
    raise exception 'excluded candidate leaked into alternatives results';
  end if;

  if (
    select count(*)
    from public.catalog_alternatives(target_id, 10)
  ) <> (
    select count(distinct id)
    from public.catalog_alternatives(target_id, 10)
  ) then
    raise exception 'candidate appeared in more than one relationship group';
  end if;

  if (
    select count(*)
    from public.catalog_alternatives(target_id, 1)
    group by relationship_group
    having count(*) > 1
    limit 1
  ) is not null then
    raise exception 'requested per-group limit was not enforced';
  end if;

  if exists (
    select 1
    from public.catalog_alternatives(untrusted_target_id, 10)
  ) then
    raise exception 'untrusted target produced guessed alternatives';
  end if;

  begin
    perform *
    from public.catalog_alternatives(
      '73000000-0000-4000-8000-999999999999',
      10
    );
    raise exception 'missing target did not raise not-found';
  exception
    when no_data_found then null;
  end;

  -- Add enough exact candidates to prove the hard server cap of 25 per group.
  for i in 1..30 loop
    select id into created_id
    from public.catalog_create_idempotent(
      (
        '73999999-0000-4000-8000-' ||
        lpad(i::text, 12, '0')
      )::uuid,
      'SP028 Bulk Exact ' || lpad(i::text, 2, '0'),
      null,
      'SP028TESTACTIVE',
      null,
      '500 MG/CTD TAB.',
      'Tablet',
      null,
      null,
      null,
      10000 + i,
      'SYP',
      null
    );
  end loop;

  if (
    select count(*)
    from public.catalog_alternatives(target_id, 5000)
    where relationship_group = 'exact'
  ) <> 25 then
    raise exception 'hard per-group limit was not clamped to 25';
  end if;

  reset role;
end
$alternatives_api_test$;

rollback;
