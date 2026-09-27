\set ON_ERROR_STOP on
begin;

insert into app_private.owner_account (singleton, user_id)
values (true, '11111111-1111-1111-1111-111111111111');

insert into public.products (
  name_en, name_ar, composition, manufacturer, strength, dosage_form,
  package_description, barcode, barcode2, selling_amount, currency
) values
  (
    'AMOKSIKLAV-1000 CTD TAB.',
    'أموكسيكلاف ١٠٠٠',
    'AMOXICILLIN+CLAVULANIC ACID',
    'Bahri Pharma',
    '875MG+125MG/CTD TAB.',
    'tablet',
    '14 tablets',
    '000111',
    null,
    1000,
    'SYP'
  ),
  (
    'AMOXICILLIN-500 CAP.',
    'أموكسيسيلين ٥٠٠',
    'AMOXICILLIN',
    'Alpha Pharma',
    '500 MG/CAP.',
    'capsule',
    '20 capsules',
    '000222',
    null,
    500,
    'SYP'
  ),
  (
    'METFORMIN XR 850',
    'ميتفورمين ممتد ٨٥٠',
    'METFORMIN',
    'Smart Pharma',
    '850 MG',
    'tablet',
    '30 tablets',
    '000333',
    'ALT-333',
    850,
    'SYP'
  );

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-1111-1111-1111-111111111111';

do $$
declare
  first_name text;
  result_count integer;
begin
  select name_en into first_name
  from public.catalog_search('اموكسيكلاف 1000', 10)
  limit 1;
  if first_name <> 'AMOKSIKLAV-1000 CTD TAB.' then
    raise exception 'Arabic alef/digit normalization did not rank expected product first: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('أَمُوكْسِيكْلَاف ١٠٠٠', 10)
  limit 1;
  if first_name <> 'AMOKSIKLAV-1000 CTD TAB.' then
    raise exception 'Arabic diacritic normalization failed: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('amoksiklav 1000', 10)
  limit 1;
  if first_name <> 'AMOKSIKLAV-1000 CTD TAB.' then
    raise exception 'punctuation-insensitive multi-token prefix search failed: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('amoksiklaf', 10)
  limit 1;
  if first_name <> 'AMOKSIKLAV-1000 CTD TAB.' then
    raise exception 'brand typo tolerance failed: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('amoxcillin', 10)
  limit 1;
  if first_name <> 'AMOXICILLIN-500 CAP.' then
    raise exception 'composition/name typo ranking failed: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('metfor 850', 10)
  limit 1;
  if first_name <> 'METFORMIN XR 850' then
    raise exception 'cross-field prefix search failed: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('850 metfor', 10)
  limit 1;
  if first_name <> 'METFORMIN XR 850' then
    raise exception 'word-order-independent prefix search failed: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('smart 850', 10)
  limit 1;
  if first_name <> 'METFORMIN XR 850' then
    raise exception 'secondary manufacturer/strength search failed: %', first_name;
  end if;

  select name_en into first_name
  from public.catalog_search('000222', 10)
  limit 1;
  if first_name <> 'AMOXICILLIN-500 CAP.' then
    raise exception 'exact typed barcode did not rank first: %', first_name;
  end if;

  select count(*) into result_count
  from public.catalog_search('am', 10);
  if result_count <> 2 then
    raise exception 'short query should stay conservative and match name prefixes only: %', result_count;
  end if;
end
$$;

reset role;
rollback;
