-- SP-026: conservatively normalize ingredient strengths derived from raw product text.
-- Raw public.products.strength remains authoritative display/source text.
-- This layer pairs strengths to SP-025 ingredient identities only when syntax and
-- component counts make that mapping deterministic.

create type app_private.strength_normalization_status as enum (
  'auto_verified',
  'high_confidence',
  'needs_review',
  'unresolved'
);

alter table app_private.product_ingredients
  add constraint product_ingredients_identity_unique
  unique (product_id, component_index, ingredient_id);

create table app_private.product_ingredient_strengths (
  product_id uuid not null,
  component_index smallint not null,
  ingredient_id bigint not null,
  raw_strength_component text not null,
  normalized_amount numeric not null,
  normalized_unit text not null,
  per_amount numeric,
  per_unit text,
  normalized_strength_key text not null,
  primary key (product_id, component_index),
  constraint product_ingredient_strengths_ingredient_fk
    foreign key (product_id, component_index, ingredient_id)
    references app_private.product_ingredients(
      product_id,
      component_index,
      ingredient_id
    )
    on delete cascade,
  constraint product_ingredient_strengths_raw_nonblank
    check (btrim(raw_strength_component) <> ''),
  constraint product_ingredient_strengths_amount_positive
    check (normalized_amount > 0),
  constraint product_ingredient_strengths_unit_supported
    check (
      normalized_unit in (
        'mg',
        'iu',
        'u',
        'meq',
        'mmol',
        'percent'
      )
    ),
  constraint product_ingredient_strengths_per_pair
    check (
      (per_amount is null and per_unit is null)
      or
      (
        per_amount > 0
        and per_unit in ('mg', 'ml')
      )
    ),
  constraint product_ingredient_strengths_key_nonblank
    check (btrim(normalized_strength_key) <> '')
);

create table app_private.product_strength_normalization (
  product_id uuid primary key
    references public.products(id) on delete cascade,
  source_strength text,
  status app_private.strength_normalization_status not null,
  reason_code text not null,
  component_count integer not null,
  parsed_component_count integer not null,
  linked_component_count integer not null,
  ingredient_strength_set_key text,
  parser_version smallint not null default 1,
  normalized_at timestamptz not null default now(),
  constraint product_strength_counts_valid
    check (
      component_count >= 0
      and parsed_component_count >= 0
      and linked_component_count >= 0
      and parsed_component_count <= component_count
      and linked_component_count <= parsed_component_count
    ),
  constraint product_strength_parser_version_positive
    check (parser_version > 0),
  constraint product_strength_reason_nonblank
    check (btrim(reason_code) <> ''),
  constraint product_strength_trusted_key_guard
    check (
      (
        status in ('auto_verified', 'high_confidence')
        and ingredient_strength_set_key is not null
        and linked_component_count = component_count
        and parsed_component_count = component_count
      )
      or
      (
        status in ('needs_review', 'unresolved')
        and ingredient_strength_set_key is null
      )
    )
);

create index product_ingredient_strengths_ingredient_idx
  on app_private.product_ingredient_strengths(
    ingredient_id,
    normalized_strength_key,
    product_id
  );

create index product_strength_set_key_idx
  on app_private.product_strength_normalization(
    ingredient_strength_set_key
  )
  where ingredient_strength_set_key is not null;

create index product_strength_status_idx
  on app_private.product_strength_normalization(status);

revoke all on app_private.product_ingredient_strengths
from public, anon, authenticated;
revoke all on app_private.product_strength_normalization
from public, anon, authenticated;

create or replace function app_private.catalog_strength_clean(
  input_text text
)
returns text
language sql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
  select replace(
    replace(
      replace(
        replace(
          replace(
            regexp_replace(
              translate(
                upper(normalize(input_text, NFKC)),
                '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
                '01234567890123456789'
              ),
              '[[:space:]]+',
              '',
              'g'
            ),
            '٫',
            '.'
          ),
          '٬',
          ''
        ),
        '٪',
        '%'
      ),
      'ΜG',
      'MCG'
    ),
    'مل',
    'ML'
  )
$$;

revoke all on function app_private.catalog_strength_clean(text)
from public, anon, authenticated;

create or replace function app_private.catalog_numeric_key(
  input_value numeric
)
returns text
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog
as $$
declare
  rendered text;
begin
  if input_value = trunc(input_value) then
    return trunc(input_value)::text;
  end if;

  rendered := input_value::text;
  rendered := regexp_replace(rendered, '0+$', '');
  rendered := regexp_replace(rendered, '[.]$', '');
  return rendered;
end;
$$;

revoke all on function app_private.catalog_numeric_key(numeric)
from public, anon, authenticated;

create or replace function app_private.catalog_parse_strength_measure(
  input_text text
)
returns table (
  normalized_amount numeric,
  normalized_unit text
)
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog, app_private
as $$
declare
  cleaned text;
  matched text[];
  amount_value numeric;
  unit_value text;
begin
  cleaned := regexp_replace(
    app_private.catalog_strength_clean(input_text),
    '[.]+$',
    ''
  );

  matched := regexp_match(
    cleaned,
    '^([0-9]+([.][0-9]+)?)(MCG|UG|MG|KG|G|IU|I[.]?U[.]?|UI|U[.]?I[.]?|U|MEQ|MMOL|%)$'
  );

  if matched is null then
    return;
  end if;

  amount_value := matched[1]::numeric;
  if amount_value <= 0 then
    return;
  end if;

  unit_value := matched[3];

  if unit_value = 'KG' then
    normalized_amount := amount_value * 1000000;
    normalized_unit := 'mg';
  elsif unit_value = 'G' then
    normalized_amount := amount_value * 1000;
    normalized_unit := 'mg';
  elsif unit_value = 'MG' then
    normalized_amount := amount_value;
    normalized_unit := 'mg';
  elsif unit_value in ('MCG', 'UG') then
    normalized_amount := amount_value / 1000;
    normalized_unit := 'mg';
  elsif unit_value in (
    'IU',
    'I.U',
    'I.U.',
    'UI',
    'U.I',
    'U.I.'
  ) then
    normalized_amount := amount_value;
    normalized_unit := 'iu';
  elsif unit_value = 'U' then
    normalized_amount := amount_value;
    normalized_unit := 'u';
  elsif unit_value = 'MEQ' then
    normalized_amount := amount_value;
    normalized_unit := 'meq';
  elsif unit_value = 'MMOL' then
    normalized_amount := amount_value;
    normalized_unit := 'mmol';
  elsif unit_value = '%' then
    normalized_amount := amount_value;
    normalized_unit := 'percent';
  else
    return;
  end if;

  return next;
end;
$$;

revoke all on function app_private.catalog_parse_strength_measure(text)
from public, anon, authenticated;

create or replace function app_private.catalog_parse_strength_denominator(
  input_text text
)
returns table (
  normalized_per_amount numeric,
  normalized_per_unit text
)
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog, app_private
as $$
declare
  cleaned text;
  matched text[];
  amount_value numeric;
  unit_value text;
begin
  cleaned := app_private.catalog_strength_clean(input_text);
  cleaned := regexp_replace(cleaned, '^/+', '');
  cleaned := regexp_replace(cleaned, '[.]+$', '');

  matched := regexp_match(
    cleaned,
    '^([0-9]+([.][0-9]+)?)?(MCG|UG|MG|KG|G|ML|L)$'
  );

  if matched is null then
    return;
  end if;

  amount_value := coalesce(nullif(matched[1], '')::numeric, 1);
  if amount_value <= 0 then
    return;
  end if;

  unit_value := matched[3];

  if unit_value = 'L' then
    normalized_per_amount := amount_value * 1000;
    normalized_per_unit := 'ml';
  elsif unit_value = 'ML' then
    normalized_per_amount := amount_value;
    normalized_per_unit := 'ml';
  elsif unit_value = 'KG' then
    normalized_per_amount := amount_value * 1000000;
    normalized_per_unit := 'mg';
  elsif unit_value = 'G' then
    normalized_per_amount := amount_value * 1000;
    normalized_per_unit := 'mg';
  elsif unit_value = 'MG' then
    normalized_per_amount := amount_value;
    normalized_per_unit := 'mg';
  elsif unit_value in ('MCG', 'UG') then
    normalized_per_amount := amount_value / 1000;
    normalized_per_unit := 'mg';
  else
    return;
  end if;

  return next;
end;
$$;

revoke all on function app_private.catalog_parse_strength_denominator(text)
from public, anon, authenticated;

create or replace function app_private.catalog_strength_is_presentation_suffix(
  input_text text
)
returns boolean
language plpgsql
immutable
strict
parallel safe
set search_path = pg_catalog, app_private
as $$
declare
  suffix_key text;
begin
  suffix_key := regexp_replace(
    app_private.catalog_strength_clean(input_text),
    '[^A-Z0-9]+',
    '',
    'g'
  );

  return suffix_key = any(array[
    'TAB',
    'CTDTAB',
    'CAP',
    'CAPS',
    'VIAL',
    'AMP',
    'SUPP',
    'OVULE',
    'OVULES',
    'SACHET',
    'DOSE',
    'CHEWTAB',
    'EFFTAB',
    'LOZENGE',
    'SGCAP',
    'SOFTCAP',
    'SOFTGCAP',
    'ENTERICTAB',
    'ENTERICCTDTAB',
    'DELAYEDRELEASETAB',
    'DELAYEDRELEASECAP',
    'EXTENDEDRELEASETAB',
    'EXTENDEDRTAB',
    'EXTENDEDRELEASECAP',
    'PROLONGEDRELEASETAB',
    'PROLONGEDRELEASECAP',
    'SUSTAINEDRELEASETAB',
    'SUSTAINEDRELEASECAP',
    'SRTAB',
    'SRCAP',
    'XRTAB',
    'XRCTDTAB',
    'DRCAP',
    'VAGTAB',
    'DISINTEGRATINGTAB',
    'DISPERSIBLETAB',
    'PLASTICAMP',
    'ORALVIAL',
    'LIQUIDVIAL'
  ]);
end;
$$;

revoke all on function app_private.catalog_strength_is_presentation_suffix(text)
from public, anon, authenticated;

create or replace function app_private.refresh_product_strength_normalization(
  target_product_id uuid,
  input_strength text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  composition_status app_private.composition_normalization_status;
  ingredient_count integer := 0;
  raw_parts text[];
  parse_parts text[];
  component_count_value integer := 0;
  parsed_count_value integer := 0;
  linked_count_value integer := 0;
  last_index integer;
  last_clean text;
  last_match text[];
  shared_tail text;
  shared_per_amount numeric;
  shared_per_unit text;
  shared_denominator boolean := false;
  shared_presentation boolean := false;
  unsafe_syntax boolean := false;
  amounts numeric[] := array[]::numeric[];
  units text[] := array[]::text[];
  measure_amount numeric;
  measure_unit text;
  component_index_value integer;
  ingredient_row record;
  strength_key text;
  set_key text;
  final_status app_private.strength_normalization_status;
  final_reason text;
begin
  delete from app_private.product_ingredient_strengths
  where product_id = target_product_id;

  delete from app_private.product_strength_normalization
  where product_id = target_product_id;

  if nullif(btrim(input_strength), '') is null then
    insert into app_private.product_strength_normalization(
      product_id,
      source_strength,
      status,
      reason_code,
      component_count,
      parsed_component_count,
      linked_component_count,
      ingredient_strength_set_key
    )
    values (
      target_product_id,
      input_strength,
      'unresolved',
      'missing_strength',
      0,
      0,
      0,
      null
    );
    return;
  end if;

  raw_parts := regexp_split_to_array(input_strength, '[+]');
  component_count_value := coalesce(array_length(raw_parts, 1), 0);

  select n.status
    into composition_status
  from app_private.product_composition_normalization n
  where n.product_id = target_product_id;

  select count(*)
    into ingredient_count
  from app_private.product_ingredients pi
  where pi.product_id = target_product_id;

  if composition_status is null or ingredient_count = 0 then
    insert into app_private.product_strength_normalization(
      product_id,
      source_strength,
      status,
      reason_code,
      component_count,
      parsed_component_count,
      linked_component_count,
      ingredient_strength_set_key
    )
    values (
      target_product_id,
      input_strength,
      'unresolved',
      'missing_ingredients',
      component_count_value,
      0,
      0,
      null
    );
    return;
  end if;

  if composition_status = 'unresolved' then
    insert into app_private.product_strength_normalization(
      product_id,
      source_strength,
      status,
      reason_code,
      component_count,
      parsed_component_count,
      linked_component_count,
      ingredient_strength_set_key
    )
    values (
      target_product_id,
      input_strength,
      'unresolved',
      'composition_unresolved',
      component_count_value,
      0,
      0,
      null
    );
    return;
  end if;

  if composition_status = 'needs_review' then
    insert into app_private.product_strength_normalization(
      product_id,
      source_strength,
      status,
      reason_code,
      component_count,
      parsed_component_count,
      linked_component_count,
      ingredient_strength_set_key
    )
    values (
      target_product_id,
      input_strength,
      'needs_review',
      'composition_needs_review',
      component_count_value,
      0,
      0,
      null
    );
    return;
  end if;

  if component_count_value = 0 then
    insert into app_private.product_strength_normalization(
      product_id,
      source_strength,
      status,
      reason_code,
      component_count,
      parsed_component_count,
      linked_component_count,
      ingredient_strength_set_key
    )
    values (
      target_product_id,
      input_strength,
      'unresolved',
      'unsupported_strength_syntax',
      0,
      0,
      0,
      null
    );
    return;
  end if;

  parse_parts := raw_parts;
  last_index := component_count_value;
  last_clean := regexp_replace(
    app_private.catalog_strength_clean(raw_parts[last_index]),
    '[.]+$',
    ''
  );

  last_match := regexp_match(
    last_clean,
    '^([0-9]+([.][0-9]+)?)(MCG|UG|MG|KG|G|IU|I[.]?U[.]?|UI|U[.]?I[.]?|U|MEQ|MMOL|%)(.*)$'
  );

  if last_match is null then
    unsafe_syntax := true;
  else
    shared_tail := coalesce(last_match[4], '');
    parse_parts[last_index] := last_match[1] || last_match[3];

    if shared_tail <> '' then
      if left(shared_tail, 1) <> '/' then
        unsafe_syntax := true;
      else
        select
          d.normalized_per_amount,
          d.normalized_per_unit
          into shared_per_amount, shared_per_unit
        from app_private.catalog_parse_strength_denominator(shared_tail) d;

        if shared_per_unit is not null then
          shared_denominator := true;
        elsif app_private.catalog_strength_is_presentation_suffix(shared_tail) then
          shared_presentation := true;
        else
          unsafe_syntax := true;
        end if;
      end if;
    end if;
  end if;

  for component_index_value in 1..component_count_value loop
    if nullif(btrim(raw_parts[component_index_value]), '') is null then
      unsafe_syntax := true;
      continue;
    end if;

    measure_amount := null;
    measure_unit := null;

    select
      m.normalized_amount,
      m.normalized_unit
      into measure_amount, measure_unit
    from app_private.catalog_parse_strength_measure(
      parse_parts[component_index_value]
    ) m;

    if measure_unit is null then
      unsafe_syntax := true;
      continue;
    end if;

    parsed_count_value := parsed_count_value + 1;
    amounts := array_append(amounts, measure_amount);
    units := array_append(units, measure_unit);
  end loop;

  if parsed_count_value = 0 then
    final_status := 'unresolved';
    final_reason := 'unsupported_strength_syntax';
  elsif unsafe_syntax or parsed_count_value <> component_count_value then
    final_status := 'needs_review';
    final_reason := 'partial_or_unsupported_strength_syntax';
  elsif component_count_value <> ingredient_count then
    final_status := 'needs_review';
    final_reason := 'component_count_mismatch';
  else
    if shared_denominator and component_count_value > 1 then
      final_status := 'high_confidence';
      final_reason := 'shared_quantitative_denominator';
    elsif composition_status = 'high_confidence' then
      final_status := 'high_confidence';
      final_reason := 'verified_ingredient_alias';
    else
      final_status := 'auto_verified';
      final_reason := case
        when shared_presentation then 'recognized_presentation_suffix'
        when shared_denominator then 'quantitative_denominator'
        else 'exact_component_mapping'
      end;
    end if;

    for ingredient_row in
      select
        pi.component_index,
        pi.ingredient_id,
        i.normalized_name
      from app_private.product_ingredients pi
      join app_private.catalog_ingredients i
        on i.id = pi.ingredient_id
      where pi.product_id = target_product_id
      order by pi.component_index
    loop
      component_index_value := ingredient_row.component_index;

      if shared_denominator then
        strength_key :=
          units[component_index_value] || '/' || shared_per_unit || ':' ||
          app_private.catalog_numeric_key(
            amounts[component_index_value] / shared_per_amount
          );
      else
        strength_key :=
          units[component_index_value] || ':' ||
          app_private.catalog_numeric_key(
            amounts[component_index_value]
          );
      end if;

      insert into app_private.product_ingredient_strengths(
        product_id,
        component_index,
        ingredient_id,
        raw_strength_component,
        normalized_amount,
        normalized_unit,
        per_amount,
        per_unit,
        normalized_strength_key
      )
      values (
        target_product_id,
        component_index_value::smallint,
        ingredient_row.ingredient_id,
        btrim(raw_parts[component_index_value]),
        amounts[component_index_value],
        units[component_index_value],
        case when shared_denominator then shared_per_amount else null end,
        case when shared_denominator then shared_per_unit else null end,
        strength_key
      );

      linked_count_value := linked_count_value + 1;
    end loop;

    select string_agg(
      char_length(i.normalized_name)::text ||
        ':' || i.normalized_name ||
        '=' ||
        char_length(s.normalized_strength_key)::text ||
        ':' || s.normalized_strength_key,
      '|'
      order by
        i.normalized_name,
        s.normalized_strength_key,
        s.component_index
    )
      into set_key
    from app_private.product_ingredient_strengths s
    join app_private.catalog_ingredients i
      on i.id = s.ingredient_id
    where s.product_id = target_product_id;
  end if;

  insert into app_private.product_strength_normalization(
    product_id,
    source_strength,
    status,
    reason_code,
    component_count,
    parsed_component_count,
    linked_component_count,
    ingredient_strength_set_key
  )
  values (
    target_product_id,
    input_strength,
    final_status,
    final_reason,
    component_count_value,
    parsed_count_value,
    linked_count_value,
    case
      when final_status in ('auto_verified', 'high_confidence')
        then set_key
      else null
    end
  );
end;
$$;

revoke all on function app_private.refresh_product_strength_normalization(
  uuid,
  text
)
from public, anon, authenticated;

-- Composition changes own the sequencing because strength pairing depends on
-- the SP-025 ingredient links. Replacing this function keeps the existing
-- trigger name/event contract while refreshing strength only after ingredients.
create or replace function app_private.sync_product_composition_normalization()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
begin
  if tg_op = 'UPDATE'
     and new.composition is not distinct from old.composition then
    return new;
  end if;

  perform app_private.refresh_product_composition_normalization(
    new.id,
    new.composition
  );

  perform app_private.refresh_product_strength_normalization(
    new.id,
    new.strength
  );

  return new;
end;
$$;

revoke all on function app_private.sync_product_composition_normalization()
from public, anon, authenticated;

create or replace function app_private.sync_product_strength_normalization()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
begin
  -- If composition changed in the same UPDATE, the SP-025 composition trigger
  -- refreshes ingredient identities first and then refreshes strength.
  if new.composition is distinct from old.composition then
    return new;
  end if;

  if new.strength is not distinct from old.strength then
    return new;
  end if;

  perform app_private.refresh_product_strength_normalization(
    new.id,
    new.strength
  );

  return new;
end;
$$;

revoke all on function app_private.sync_product_strength_normalization()
from public, anon, authenticated;

create trigger products_strength_normalization_sync
after update of strength
on public.products
for each row
execute function app_private.sync_product_strength_normalization();

-- Structural backfill must not alter authoritative product data or revision
-- state. It only fills the private derived normalization layer.
create temporary table sp026_product_state_before
on commit drop
as
select id, composition, strength, revision, updated_at
from public.products;

do $$
declare
  product_row record;
begin
  for product_row in
    select id, strength
    from public.products
    order by id
  loop
    perform app_private.refresh_product_strength_normalization(
      product_row.id,
      product_row.strength
    );
  end loop;
end
$$;

do $$
begin
  if (
    select count(*)
    from app_private.product_strength_normalization
  ) <> (
    select count(*)
    from public.products
  ) then
    raise exception 'strength normalization backfill row count mismatch';
  end if;

  if exists (
    select 1
    from public.products p
    join sp026_product_state_before b using (id)
    where p.composition is distinct from b.composition
       or p.strength is distinct from b.strength
       or p.revision is distinct from b.revision
       or p.updated_at is distinct from b.updated_at
  ) then
    raise exception 'strength normalization mutated product source/revision state';
  end if;

  if exists (
    select 1
    from public.products p
    join app_private.product_strength_normalization n
      on n.product_id = p.id
    where n.source_strength is distinct from p.strength
  ) then
    raise exception 'strength normalization source snapshot is out of sync';
  end if;

  if exists (
    select 1
    from app_private.product_ingredient_strengths s
    join app_private.product_strength_normalization n
      on n.product_id = s.product_id
    where n.status not in ('auto_verified', 'high_confidence')
  ) then
    raise exception 'untrusted strength normalization retained linked strengths';
  end if;
end
$$;
