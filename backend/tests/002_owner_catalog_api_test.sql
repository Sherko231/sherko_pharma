\set ON_ERROR_STOP on

begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111');

insert into public.products (
  name_en, name_ar, composition, manufacturer, strength, dosage_form,
  package_description, barcode, barcode2, selling_amount, currency, notes
) values
  ('Alpha % Literal', 'ألفا', 'acetyl_test', 'Maker A', '10 mg', 'tablet', 'box', '00123', 'ALT-001', 14500, 'SYP', 'owner test'),
  ('Beta Product', 'بيتا', 'underscore_test', 'Maker B', '20 mg', 'capsule', 'box', '00123', '00123', 20000, 'SYP', null);

-- Anonymous callers have no EXECUTE privilege on any catalog RPC and no direct table access.
do $$
begin
  if has_function_privilege('anon', 'public.catalog_search(text,integer)', 'EXECUTE')
    or has_function_privilege('anon', 'public.catalog_get(uuid)', 'EXECUTE')
    or has_function_privilege('anon', 'public.catalog_lookup_barcode(text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.catalog_create(text,text,text,text,text,text,text,text,text,bigint,text,text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.catalog_update(uuid,bigint,text,text,text,text,text,text,text,text,text,bigint,text,text)', 'EXECUTE')
  then
    raise exception 'anonymous catalog EXECUTE privilege unexpectedly exists';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.products'::regclass) then
    raise exception 'products RLS is not enabled';
  end if;
end
$$;

set local role anon;
set local "request.jwt.claim.sub" = '';

do $$ begin
  begin
    perform * from public.catalog_search('Alpha', 10);
    raise exception 'anonymous RPC unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    perform * from public.products;
    raise exception 'anonymous direct table read unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    insert into public.products (name_en, selling_amount, currency)
    values ('Anonymous write', 1, 'SYP');
    raise exception 'anonymous direct table write unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;

reset role;

-- Authenticated non-owner is denied by the server-side owner check and direct table access.
set local role authenticated;
set local "request.jwt.claim.sub" = '22222222-2222-2222-2222-222222222222';

do $$
declare
  existing_id uuid;
begin
  reset role;
  select id into existing_id from public.products order by id limit 1;
  set local role authenticated;
  set local "request.jwt.claim.sub" = '22222222-2222-2222-2222-222222222222';

  begin
    perform * from public.catalog_search('Alpha', 10);
    raise exception 'non-owner search unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    perform * from public.catalog_get(existing_id);
    raise exception 'non-owner detail unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    perform * from public.catalog_lookup_barcode('00123');
    raise exception 'non-owner barcode lookup unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    perform * from public.catalog_create('X',null,null,null,null,null,null,null,null,1,'SYP',null);
    raise exception 'non-owner create unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    perform * from public.catalog_update(
      existing_id, 1, 'X', null, null, null, null, null, null, null, null, 1, 'SYP', null
    );
    raise exception 'non-owner update unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    perform * from public.products;
    raise exception 'authenticated direct table read unexpectedly succeeded';
  exception when insufficient_privilege then null; end;

  begin
    insert into public.products (name_en, selling_amount, currency)
    values ('Authenticated write', 1, 'SYP');
    raise exception 'authenticated direct table write unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;

reset role;

-- Owner can use bounded functions but still cannot bypass them through direct table access.
set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

do $$ begin
  if (select count(*) from public.catalog_search('Alpha', 10)) <> 1 then
    raise exception 'owner English search failed';
  end if;
  if (select count(*) from public.catalog_search('ألفا', 10)) <> 1 then
    raise exception 'owner Arabic search failed';
  end if;
  if (select count(*) from public.catalog_search('acetyl_test', 10)) <> 1 then
    raise exception 'owner composition search failed';
  end if;

  -- Percent and underscore are literal characters, not caller-controlled wildcards.
  if (select count(*) from public.catalog_search('%', 10)) <> 1 then
    raise exception 'percent search was not literal';
  end if;
  if (select count(*) from public.catalog_search('_', 10)) <> 2 then
    raise exception 'underscore search was not literal';
  end if;

  -- Requested limit is clamped to the hard server maximum.
  if (select count(*) from public.catalog_search('Product', 5000)) > 50 then
    raise exception 'search exceeded hard limit';
  end if;

  -- Exact cross-field lookup returns distinct product rows, not one row per matched column.
  if (select count(*) from public.catalog_lookup_barcode('00123')) <> 2 then
    raise exception 'barcode lookup did not preserve ambiguity/distinct products';
  end if;

  begin
    perform * from public.products;
    raise exception 'owner direct table read unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;

-- Create only exposes canonical editable inputs; source provenance remains null and revision starts at 1.
do $$
declare
  created_id uuid;
  created_revision bigint;
begin
  select id, revision into created_id, created_revision
  from public.catalog_create(
    'Created Product', null, 'created composition', 'Maker C', '5 mg',
    'tablet', 'box', 'NEW-001', null, 99, 'USD', 'created'
  );

  if created_id is null or created_revision <> 1 then
    raise exception 'owner create failed';
  end if;

  reset role;
  if exists (
    select 1 from public.products
    where id = created_id
      and (
        source_dataset is not null or source_id is not null or source_item_id is not null
        or source_num is not null or source_purchase_amount is not null or source_payload is not null
      )
  ) then
    raise exception 'client create modified source provenance';
  end if;

  set local role authenticated;
  set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

  perform *
  from public.catalog_update(
    created_id, 1,
    'Created Product Updated', null, 'created composition', 'Maker C', '5 mg',
    'tablet', 'box', 'NEW-001', null, 100, 'USD', 'updated'
  );

  if (select revision from public.catalog_get(created_id)) <> 2 then
    raise exception 'revision did not advance exactly once through update RPC';
  end if;

  begin
    perform *
    from public.catalog_update(
      created_id, 1,
      'Stale overwrite', null, 'created composition', 'Maker C', '5 mg',
      'tablet', 'box', 'NEW-001', null, 101, 'USD', 'stale'
    );
    raise exception 'stale update unexpectedly succeeded';
  exception when serialization_failure then null; end;

  if (select name_en from public.catalog_get(created_id)) <> 'Created Product Updated' then
    raise exception 'stale update overwrote newer value';
  end if;
end
$$;

reset role;
rollback;
