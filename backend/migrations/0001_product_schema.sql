-- SP-003: initial versioned product schema.
-- Production deployment and authorization are deliberately deferred to later tasks.

create extension if not exists pgcrypto;

create table public.products (
  id uuid primary key default gen_random_uuid(),
  name_en text,
  name_ar text,
  composition text,
  manufacturer text,
  strength text,
  dosage_form text,
  package_description text,
  barcode text,
  barcode2 text,
  selling_amount bigint not null,
  currency text not null,
  notes text,
  revision bigint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  source_dataset text,
  source_id bigint,
  source_item_id bigint,
  source_num bigint,
  source_purchase_amount bigint,
  source_payload jsonb,
  constraint products_name_required check (
    btrim(coalesce(name_en, '')) <> '' or btrim(coalesce(name_ar, '')) <> ''
  ),
  constraint products_currency_supported check (currency in ('SYP', 'USD')),
  constraint products_selling_amount_valid check (
    selling_amount > 0 or (selling_amount = 0 and source_dataset is not null)
  ),
  constraint products_revision_positive check (revision >= 1),
  constraint products_barcode_not_empty check (barcode is null or length(barcode) > 0),
  constraint products_barcode2_not_empty check (barcode2 is null or length(barcode2) > 0),
  constraint products_source_metadata_complete check (
    (
      source_dataset is null and source_id is null and source_item_id is null
      and source_num is null and source_purchase_amount is null and source_payload is null
    )
    or
    (
      source_dataset is not null and source_id is not null and source_item_id is not null
      and source_num is not null and source_payload is not null
    )
  ),
  constraint products_source_row_unique unique (source_dataset, source_id)
);

create index products_barcode_idx on public.products (barcode) where barcode is not null;
create index products_barcode2_idx on public.products (barcode2) where barcode2 is not null;

create or replace function public.set_product_revision()
returns trigger
language plpgsql
as $$
begin
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;

create trigger products_set_revision
before update on public.products
for each row execute function public.set_product_revision();
