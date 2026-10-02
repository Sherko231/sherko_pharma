-- SP-044 production reconciliation marker.
--
-- Production deployed the SP-044 schema/functions/backfill as several smaller
-- recorded migrations because the hosted migration surface rejected the
-- original large payload. Fresh environments still reach the same end-state
-- through 0022. This migration is assertion-only and records convergence.

do $sp044_production_reconciliation$
begin
  if to_regprocedure('app_private.scientific_canonicalization_version()') is null
     or to_regprocedure('app_private.refresh_catalog_ingredient_scientific_mapping(bigint)') is null
     or to_regprocedure('app_private.refresh_product_scientific_canonicalization(uuid,text,text)') is null
     or to_regprocedure('app_private.refresh_all_scientific_canonicalization()') is null
     or to_regprocedure('app_private.sync_product_scientific_canonicalization()') is null then
    raise exception 'SP-044 reconciliation: required function is missing';
  end if;

  if to_regclass('app_private.scientific_canonicalization_versions') is null
     or to_regclass('app_private.product_scientific_canonicalization_nodes') is null
     or to_regclass('app_private.product_scientific_canonicalization') is null then
    raise exception 'SP-044 reconciliation: required derived table is missing';
  end if;

  if app_private.scientific_canonicalization_version() <> 1 then
    raise exception 'SP-044 reconciliation: unexpected canonicalization version %',
      app_private.scientific_canonicalization_version();
  end if;

  if (select count(*) from app_private.catalog_ingredient_scientific_mappings)
       <> (select count(*) from app_private.catalog_ingredients) then
    raise exception 'SP-044 reconciliation: lexical scientific mapping coverage is incomplete';
  end if;

  if (select count(*) from app_private.product_scientific_canonicalization)
       <> (select count(*) from public.products) then
    raise exception 'SP-044 reconciliation: product canonicalization coverage is incomplete';
  end if;

  if exists (
    select 1
    from public.products p
    join app_private.product_scientific_canonicalization s on s.product_id = p.id
    where s.source_composition is distinct from p.composition
       or s.source_strength is distinct from p.strength
       or s.source_fingerprint is distinct from
          app_private.scientific_canonicalization_source_fingerprint(p.composition, p.strength)
  ) then
    raise exception 'SP-044 reconciliation: product source snapshot is stale';
  end if;

  if has_function_privilege(
       'anon',
       'app_private.refresh_all_scientific_canonicalization()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'app_private.refresh_all_scientific_canonicalization()',
       'EXECUTE'
     )
     or has_table_privilege(
       'anon',
       'app_private.product_scientific_canonicalization',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'app_private.product_scientific_canonicalization_nodes',
       'SELECT'
     ) then
    raise exception 'SP-044 reconciliation: normal client role can access private canonicalization state';
  end if;
end;
$sp044_production_reconciliation$;