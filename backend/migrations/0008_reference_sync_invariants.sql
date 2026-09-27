-- SP-024 review fix: make reference/text synchronization unambiguous.
-- App/RPC edits change the compatibility text, so a changed text value wins.
-- Administrative FK-only edits are also supported and refresh the text cache.

create or replace function app_private.sync_product_references()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  input_label text;
  normalized_label text;
  reference_id bigint;
  canonical_label text;
begin
  if tg_op = 'UPDATE'
     and new.manufacturer is distinct from old.manufacturer then
    input_label := nullif(btrim(new.manufacturer), '');

    if input_label is null then
      new.manufacturer := null;
      new.manufacturer_id := null;
    else
      normalized_label := app_private.catalog_reference_key(input_label);

      insert into app_private.catalog_manufacturers(name, normalized_name)
      values (input_label, normalized_label)
      on conflict (normalized_name) do nothing;

      select m.id, m.name
        into reference_id, canonical_label
      from app_private.catalog_manufacturers m
      where m.normalized_name = normalized_label;

      insert into app_private.catalog_manufacturer_aliases(
        manufacturer_id,
        alias
      )
      values (reference_id, input_label)
      on conflict do nothing;

      new.manufacturer_id := reference_id;
      new.manufacturer := canonical_label;
    end if;
  elsif tg_op = 'UPDATE'
        and new.manufacturer_id is distinct from old.manufacturer_id then
    if new.manufacturer_id is null then
      new.manufacturer := null;
    else
      select m.name
        into canonical_label
      from app_private.catalog_manufacturers m
      where m.id = new.manufacturer_id;

      if canonical_label is null then
        raise exception 'unknown manufacturer reference'
          using errcode = '23503';
      end if;

      new.manufacturer := canonical_label;
    end if;
  elsif tg_op = 'INSERT' then
    input_label := nullif(btrim(new.manufacturer), '');

    if input_label is not null then
      normalized_label := app_private.catalog_reference_key(input_label);

      insert into app_private.catalog_manufacturers(name, normalized_name)
      values (input_label, normalized_label)
      on conflict (normalized_name) do nothing;

      select m.id, m.name
        into reference_id, canonical_label
      from app_private.catalog_manufacturers m
      where m.normalized_name = normalized_label;

      insert into app_private.catalog_manufacturer_aliases(
        manufacturer_id,
        alias
      )
      values (reference_id, input_label)
      on conflict do nothing;

      new.manufacturer_id := reference_id;
      new.manufacturer := canonical_label;
    elsif new.manufacturer_id is not null then
      select m.name
        into canonical_label
      from app_private.catalog_manufacturers m
      where m.id = new.manufacturer_id;

      if canonical_label is null then
        raise exception 'unknown manufacturer reference'
          using errcode = '23503';
      end if;

      new.manufacturer := canonical_label;
    else
      new.manufacturer := null;
      new.manufacturer_id := null;
    end if;
  end if;

  if tg_op = 'UPDATE'
     and new.dosage_form is distinct from old.dosage_form then
    input_label := nullif(btrim(new.dosage_form), '');

    if input_label is null then
      new.dosage_form := null;
      new.dosage_form_id := null;
    else
      normalized_label := app_private.catalog_reference_key(input_label);

      insert into app_private.catalog_dosage_forms(name, normalized_name)
      values (input_label, normalized_label)
      on conflict (normalized_name) do nothing;

      select f.id, f.name
        into reference_id, canonical_label
      from app_private.catalog_dosage_forms f
      where f.normalized_name = normalized_label;

      insert into app_private.catalog_dosage_form_aliases(
        dosage_form_id,
        alias
      )
      values (reference_id, input_label)
      on conflict do nothing;

      new.dosage_form_id := reference_id;
      new.dosage_form := canonical_label;
    end if;
  elsif tg_op = 'UPDATE'
        and new.dosage_form_id is distinct from old.dosage_form_id then
    if new.dosage_form_id is null then
      new.dosage_form := null;
    else
      select f.name
        into canonical_label
      from app_private.catalog_dosage_forms f
      where f.id = new.dosage_form_id;

      if canonical_label is null then
        raise exception 'unknown dosage-form reference'
          using errcode = '23503';
      end if;

      new.dosage_form := canonical_label;
    end if;
  elsif tg_op = 'INSERT' then
    input_label := nullif(btrim(new.dosage_form), '');

    if input_label is not null then
      normalized_label := app_private.catalog_reference_key(input_label);

      insert into app_private.catalog_dosage_forms(name, normalized_name)
      values (input_label, normalized_label)
      on conflict (normalized_name) do nothing;

      select f.id, f.name
        into reference_id, canonical_label
      from app_private.catalog_dosage_forms f
      where f.normalized_name = normalized_label;

      insert into app_private.catalog_dosage_form_aliases(
        dosage_form_id,
        alias
      )
      values (reference_id, input_label)
      on conflict do nothing;

      new.dosage_form_id := reference_id;
      new.dosage_form := canonical_label;
    elsif new.dosage_form_id is not null then
      select f.name
        into canonical_label
      from app_private.catalog_dosage_forms f
      where f.id = new.dosage_form_id;

      if canonical_label is null then
        raise exception 'unknown dosage-form reference'
          using errcode = '23503';
      end if;

      new.dosage_form := canonical_label;
    else
      new.dosage_form := null;
      new.dosage_form_id := null;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function app_private.sync_product_references()
from public, anon, authenticated;
