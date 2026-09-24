\set ON_ERROR_STOP on

begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111');

do $$
begin
  if has_function_privilege(
    'anon',
    'public.catalog_create_idempotent(uuid,text,text,text,text,text,text,text,text,text,bigint,text,text)',
    'EXECUTE'
  ) then
    raise exception 'anonymous idempotent create EXECUTE privilege unexpectedly exists';
  end if;
end
$$;

set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-2222-2222-222222222222';

do $$
begin
  begin
    perform * from public.catalog_create_idempotent(
      '33333333-3333-4333-8333-333333333333',
      'Denied Product', null, null, null, null, null, null, null, null,
      1, 'SYP', null
    );
    raise exception 'non-owner idempotent create unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end
$$;

reset role;

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

do $$
declare
  created_id uuid;
  replay_id uuid;
begin
  select id into created_id
  from public.catalog_create_idempotent(
    '44444444-4444-4444-8444-444444444444',
    'Idempotent Product', 'منتج', 'active ingredient', 'Maker', '25 mg',
    'tablet', 'box', '000123', 'ALT-X', 2500, 'SYP', 'note'
  );

  select id into replay_id
  from public.catalog_create_idempotent(
    '44444444-4444-4444-8444-444444444444',
    'Idempotent Product', 'منتج', 'active ingredient', 'Maker', '25 mg',
    'tablet', 'box', '000123', 'ALT-X', 2500, 'SYP', 'note'
  );

  if created_id <> '44444444-4444-4444-8444-444444444444'::uuid
     or replay_id <> created_id then
    raise exception 'idempotent create did not return the stable requested identity';
  end if;

  reset role;

  if (select count(*) from public.products where id = created_id) <> 1 then
    raise exception 'idempotent replay created a duplicate row';
  end if;

  if exists (
    select 1
    from public.products
    where id = created_id
      and (
        source_dataset is not null
        or source_id is not null
        or source_item_id is not null
        or source_num is not null
        or source_purchase_amount is not null
        or source_payload is not null
      )
  ) then
    raise exception 'idempotent manual create modified source provenance';
  end if;

  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  begin
    perform * from public.catalog_create_idempotent(
      created_id,
      'Different Product', 'منتج', 'active ingredient', 'Maker', '25 mg',
      'tablet', 'box', '000123', 'ALT-X', 2500, 'SYP', 'note'
    );
    raise exception 'mismatched idempotent replay unexpectedly succeeded';
  exception when serialization_failure then null; end;

  if (select name_en from public.catalog_get(created_id)) <> 'Idempotent Product' then
    raise exception 'mismatched replay changed the existing row';
  end if;
end
$$;

reset role;
rollback;
