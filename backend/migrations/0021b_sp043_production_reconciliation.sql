-- SP-044 production reconciliation for SP-043.
--
-- Production received SP-043 in several small, recorded migrations because the
-- hosted migration surface rejected the original large DDL payload. Fresh
-- environments already receive the same end-state from 0021. This migration is
-- intentionally assertion-only: it records and verifies that both paths have
-- converged before the SP-044 backfill runs.

do $sp043_production_reconciliation$
begin
  if to_regtype('app_private.complex_composition_node_kind') is null
     or to_regtype('app_private.complex_composition_structure_status') is null
     or to_regtype('app_private.complex_composition_identity_status') is null then
    raise exception 'SP-043 reconciliation: required enum types are missing';
  end if;

  if to_regprocedure('app_private.complex_composition_parser_version()') is null
     or to_regprocedure('app_private.scientific_parentheses_balanced(text)') is null
     or to_regprocedure('app_private.scientific_outer_parentheses_enclose(text)') is null
     or to_regprocedure('app_private.scientific_split_complex_top_level(text,boolean)') is null
     or to_regprocedure('app_private.scientific_comma_component_list_safe(text)') is null
     or to_regprocedure('app_private.scientific_parse_complex_leaf(text,integer[],integer[],text,text)') is null
     or to_regprocedure('app_private.scientific_parse_complex_children(text,integer[],text)') is null
     or to_regprocedure('app_private.scientific_parse_complex_composition(text)') is null
     or to_regprocedure('app_private.scientific_complex_composition_summary(text)') is null then
    raise exception 'SP-043 reconciliation: required parser function is missing';
  end if;

  if app_private.complex_composition_parser_version() <> 1 then
    raise exception 'SP-043 reconciliation: unexpected parser version %',
      app_private.complex_composition_parser_version();
  end if;

  if has_function_privilege(
       'anon',
       'app_private.scientific_parse_complex_composition(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'app_private.scientific_parse_complex_composition(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'app_private.scientific_complex_composition_summary(text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'app_private.scientific_complex_composition_summary(text)',
       'EXECUTE'
     ) then
    raise exception 'SP-043 reconciliation: normal client role can execute private parser';
  end if;
end;
$sp043_production_reconciliation$;