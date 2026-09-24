\set ON_ERROR_STOP on
begin;

insert into public.products (
  name_en, selling_amount, currency, barcode,
  source_dataset, source_id, source_item_id, source_num, source_purchase_amount, source_payload
) values
('Synthetic A',14500,'SYP','00123','synthetic-v1',1,1,101,12000,'{"Id":"1","barcode":"00123","price":"14500","purchasePrice":"12000"}'::jsonb),
('Synthetic B',20000,'SYP','00123','synthetic-v1',2,2,102,17000,'{"Id":"2","barcode":"00123","price":"20000","purchasePrice":"17000"}'::jsonb);

do $$ begin
  if (select count(*) from public.products where barcode='00123') <> 2 then
    raise exception 'duplicate barcode candidates were not preserved';
  end if;
end $$;

insert into public.products (
  name_ar,selling_amount,currency,barcode2,source_dataset,source_id,source_item_id,source_num,source_payload
) values ('تركيب اختباري',1,'SYP','-1002','synthetic-v1',3,3,103,'{"barcode2":"-1002"}'::jsonb);

do $$ begin
  if not exists(select 1 from public.products where barcode='00123' and length(barcode)=5) then
    raise exception 'leading-zero barcode was altered';
  end if;
  if not exists(select 1 from public.products where barcode2='-1002') then
    raise exception 'non-digit barcode text was altered';
  end if;
end $$;

insert into public.products (
  name_en,selling_amount,currency,source_dataset,source_id,source_item_id,source_num,source_purchase_amount,source_payload
) values ('Zero Source Price',0,'SYP','synthetic-v1',4,4,104,800,'{"price":"0","purchasePrice":"800"}'::jsonb);

do $$ begin
  begin
    insert into public.products(name_en,selling_amount,currency) values('Invalid manual zero',0,'SYP');
    raise exception 'manual zero price unexpectedly passed';
  exception when check_violation then null; end;
  begin
    insert into public.products(name_en,name_ar,selling_amount,currency) values('   ','',1,'SYP');
    raise exception 'blank names unexpectedly passed';
  exception when check_violation then null; end;
  begin
    insert into public.products(name_en,selling_amount,currency) values('Invalid currency',1,'EUR');
    raise exception 'unsupported currency unexpectedly passed';
  exception when check_violation then null; end;
  begin
    insert into public.products(name_en,selling_amount,currency) values('Negative price',-1,'SYP');
    raise exception 'negative selling amount unexpectedly passed';
  exception when check_violation then null; end;
end $$;

do $$ declare product_id uuid; begin
  select id into product_id from public.products where source_dataset='synthetic-v1' and source_id=1;
  if product_id is null then raise exception 'generated application identity missing'; end if;
end $$;

do $$ begin
  if (select source_payload->>'purchasePrice' from public.products where source_dataset='synthetic-v1' and source_id=1) <> '12000' then
    raise exception 'source payload was not preserved';
  end if;
end $$;

do $$ declare before_revision bigint; after_revision bigint; begin
  select revision into before_revision from public.products where source_dataset='synthetic-v1' and source_id=1;
  update public.products set notes='updated' where source_dataset='synthetic-v1' and source_id=1;
  select revision into after_revision from public.products where source_dataset='synthetic-v1' and source_id=1;
  if before_revision<>1 or after_revision<>2 then
    raise exception 'revision did not advance exactly once: % -> %',before_revision,after_revision;
  end if;
end $$;

rollback;
