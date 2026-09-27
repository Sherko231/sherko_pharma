-- SP-027: conservatively model strict pharmaceutical equivalence.
-- This derived layer never rewrites authoritative catalog fields. A strict key
-- exists only when trusted ingredient-strength normalization and a complete,
-- trusted dosage-form/route/release profile are all available.

create type app_private.pharmaceutical_equivalence_status as enum (
  'auto_verified',
  'high_confidence',
  'needs_review',
  'unresolved'
);

create type app_private.pharmaceutical_route_class as enum (
  'oral',
  'sublingual',
  'oromucosal',
  'ophthalmic',
  'otic',
  'nasal',
  'cutaneous',
  'vaginal',
  'rectal',
  'inhalation',
  'parenteral_unspecified'
);

create type app_private.pharmaceutical_release_class as enum (
  'immediate_release',
  'extended_release',
  'delayed_release',
  'not_applicable'
);

create table app_private.catalog_dosage_form_equivalence_profiles (
  dosage_form_id bigint primary key
    references app_private.catalog_dosage_forms(id) on delete cascade,
  source_name text not null,
  source_normalized_name text not null,
  form_class_key text,
  route_class app_private.pharmaceutical_route_class,
  release_class app_private.pharmaceutical_release_class,
  status app_private.pharmaceutical_equivalence_status not null,
  reason_code text not null,
  classifier_version smallint not null default 1,
  classified_at timestamptz not null default now(),
  constraint dosage_form_equivalence_source_name_nonblank
    check (btrim(source_name) <> ''),
  constraint dosage_form_equivalence_source_key_nonblank
    check (btrim(source_normalized_name) <> ''),
  constraint dosage_form_equivalence_reason_nonblank
    check (btrim(reason_code) <> ''),
  constraint dosage_form_equivalence_classifier_version_positive
    check (classifier_version > 0),
  constraint dosage_form_equivalence_trusted_dimensions
    check (
      status not in ('auto_verified', 'high_confidence')
      or (
        form_class_key is not null
        and btrim(form_class_key) <> ''
        and route_class is not null
        and release_class is not null
      )
    )
);

create table app_private.product_pharmaceutical_equivalence (
  product_id uuid primary key
    references public.products(id) on delete cascade,
  source_dosage_form text,
  dosage_form_id bigint
    references app_private.catalog_dosage_forms(id),
  composition_status app_private.composition_normalization_status,
  strength_status app_private.strength_normalization_status,
  dosage_form_status app_private.pharmaceutical_equivalence_status,
  ingredient_strength_set_key text,
  form_class_key text,
  route_class app_private.pharmaceutical_route_class,
  release_class app_private.pharmaceutical_release_class,
  status app_private.pharmaceutical_equivalence_status not null,
  reason_code text not null,
  strict_equivalence_key text,
  classifier_version smallint not null default 1,
  normalized_at timestamptz not null default now(),
  constraint product_equivalence_reason_nonblank
    check (btrim(reason_code) <> ''),
  constraint product_equivalence_classifier_version_positive
    check (classifier_version > 0),
  constraint product_equivalence_trusted_key_guard
    check (
      (
        status in ('auto_verified', 'high_confidence')
        and strict_equivalence_key is not null
        and btrim(strict_equivalence_key) <> ''
        and ingredient_strength_set_key is not null
        and composition_status in ('auto_verified', 'high_confidence')
        and strength_status in ('auto_verified', 'high_confidence')
        and dosage_form_status in ('auto_verified', 'high_confidence')
        and form_class_key is not null
        and route_class is not null
        and release_class is not null
      )
      or
      (
        status in ('needs_review', 'unresolved')
        and strict_equivalence_key is null
      )
    )
);

create index dosage_form_equivalence_status_idx
  on app_private.catalog_dosage_form_equivalence_profiles(status);

create index product_pharmaceutical_equivalence_key_idx
  on app_private.product_pharmaceutical_equivalence(strict_equivalence_key)
  where strict_equivalence_key is not null;

create index product_pharmaceutical_equivalence_status_idx
  on app_private.product_pharmaceutical_equivalence(status);

create index product_pharmaceutical_equivalence_form_idx
  on app_private.product_pharmaceutical_equivalence(
    form_class_key,
    route_class,
    release_class
  )
  where strict_equivalence_key is not null;

revoke all on app_private.catalog_dosage_form_equivalence_profiles
from public, anon, authenticated;
revoke all on app_private.product_pharmaceutical_equivalence
from public, anon, authenticated;

create or replace function app_private.catalog_classify_dosage_form(
  input_name text
)
returns table (
  normalized_name text,
  form_class_key text,
  route_class app_private.pharmaceutical_route_class,
  release_class app_private.pharmaceutical_release_class,
  status app_private.pharmaceutical_equivalence_status,
  reason_code text
)
language plpgsql
immutable
set search_path = ''
as $dosage_form_classifier$
declare
  extended_marker boolean := false;
  delayed_marker boolean := false;
  has_eye boolean := false;
  has_ear boolean := false;
  has_nasal boolean := false;
  has_vaginal boolean := false;
  has_rectal boolean := false;
  has_inhalation boolean := false;
  has_injection boolean := false;
  has_sublingual boolean := false;
  specific_route_count integer := 0;
begin
  normalized_name := app_private.catalog_reference_key(input_name);

  if normalized_name is null or normalized_name = '' then
    status := 'unresolved';
    reason_code := 'missing_dosage_form';
    return next;
    return;
  end if;

  extended_marker :=
    normalized_name ~ '(مديد|ممتد).*(تحرر)'
    or normalized_name ~ '(^| )(extended release|sustained release|prolonged release|modified release|controlled release|xr|sr|er|cr|mr)( |$)';

  delayed_marker :=
    normalized_name ~ '(متاخر).*(تحرر)'
    or normalized_name ~ 'معوي'
    or normalized_name ~ '(^| )(delayed release|enteric|gastro resistant)( |$)';

  if extended_marker and delayed_marker then
    status := 'needs_review';
    reason_code := 'conflicting_release_markers';
    return next;
    return;
  end if;

  has_eye := normalized_name ~ '(عيني|ophthalmic|(^| )eye( |$))';
  has_ear := normalized_name ~ '(اذن|otic|(^| )ear( |$))';
  has_nasal := normalized_name ~ '(انفي|انف|nasal)';
  has_vaginal := normalized_name ~ '(مهبل|vaginal)';
  has_rectal := normalized_name ~ '(شرجي|rectal)'
    or normalized_name in ('تحاميل', 'suppository', 'suppositories');
  has_inhalation := normalized_name ~ '(استنشاق|inhal)';
  has_injection := normalized_name ~ '(للحقن|(^| )حقن( |$)|injection|injectable)'
    or normalized_name in ('فيال', 'امبول', 'vial', 'ampoule', 'ampule');
  has_sublingual := normalized_name ~ '(تحت اللسان|sublingual)';

  specific_route_count :=
    (case when has_eye then 1 else 0 end)
    + (case when has_ear then 1 else 0 end)
    + (case when has_nasal then 1 else 0 end)
    + (case when has_vaginal then 1 else 0 end)
    + (case when has_rectal then 1 else 0 end)
    + (case when has_inhalation then 1 else 0 end)
    + (case when has_injection then 1 else 0 end)
    + (case when has_sublingual then 1 else 0 end);

  if specific_route_count > 1 then
    status := 'needs_review';
    reason_code := 'multiple_route_markers';
    return next;
    return;
  end if;

  if has_injection then
    route_class := 'parenteral_unspecified';
    release_class := 'not_applicable';

    if normalized_name ~ '(بودرة|powder)' then
      form_class_key := 'parenteral_powder';
    elsif normalized_name ~ '(معلق|suspension)' then
      form_class_key := 'parenteral_suspension';
    elsif normalized_name ~ '(محلول|solution)' then
      form_class_key := 'parenteral_solution';
    else
      form_class_key := 'parenteral_dosage_form';
    end if;

    status := 'needs_review';
    reason_code := 'specific_parenteral_route_missing';
    return next;
    return;
  end if;

  if has_eye then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    elsif normalized_name ~ '(قطرة|drop)' then
      form_class_key := 'ophthalmic_drop';
      route_class := 'ophthalmic';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_ophthalmic_drop';
    elsif normalized_name ~ '(مرهم|ointment)' then
      form_class_key := 'ophthalmic_ointment';
      route_class := 'ophthalmic';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_ophthalmic_ointment';
    else
      route_class := 'ophthalmic';
      status := 'needs_review';
      reason_code := 'ophthalmic_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if has_ear then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    elsif normalized_name ~ '(قطرة|drop)' then
      form_class_key := 'otic_drop';
      route_class := 'otic';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_otic_drop';
    else
      route_class := 'otic';
      status := 'needs_review';
      reason_code := 'otic_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if has_nasal then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    elsif normalized_name ~ '(بخاخ|spray)' then
      form_class_key := 'nasal_spray';
      route_class := 'nasal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_nasal_spray';
    elsif normalized_name ~ '(قطرة|drop)' then
      form_class_key := 'nasal_drop';
      route_class := 'nasal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_nasal_drop';
    else
      route_class := 'nasal';
      status := 'needs_review';
      reason_code := 'nasal_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if has_vaginal then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    elsif normalized_name ~ '(بيوض|ovule|pessary)' then
      form_class_key := 'vaginal_ovule';
      route_class := 'vaginal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_vaginal_ovule';
    elsif normalized_name ~ '(اقراص|tablet)' then
      form_class_key := 'vaginal_tablet';
      route_class := 'vaginal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_vaginal_tablet';
    elsif normalized_name ~ '(كريم|cream)' then
      form_class_key := 'vaginal_cream';
      route_class := 'vaginal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_vaginal_cream';
    elsif normalized_name ~ '(^| )(جل|gel)( |$)' then
      form_class_key := 'vaginal_gel';
      route_class := 'vaginal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_vaginal_gel';
    elsif normalized_name ~ '(غسول|wash|douche)' then
      form_class_key := 'vaginal_wash';
      route_class := 'vaginal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_vaginal_wash';
    else
      route_class := 'vaginal';
      status := 'needs_review';
      reason_code := 'vaginal_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if has_rectal then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    elsif normalized_name ~ '(تحاميل|suppositor)' then
      form_class_key := 'rectal_suppository';
      route_class := 'rectal';
      release_class := 'not_applicable';
      status := case
        when normalized_name in ('تحاميل', 'suppository', 'suppositories')
          then 'high_confidence'
        else 'auto_verified'
      end;
      reason_code := case
        when status = 'high_confidence'
          then 'conventional_suppository_route'
        else 'explicit_rectal_suppository'
      end;
    elsif normalized_name ~ '(كريم|cream)' then
      form_class_key := 'rectal_cream';
      route_class := 'rectal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_rectal_cream';
    elsif normalized_name ~ '(مرهم|ointment)' then
      form_class_key := 'rectal_ointment';
      route_class := 'rectal';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_rectal_ointment';
    else
      route_class := 'rectal';
      status := 'needs_review';
      reason_code := 'rectal_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if has_inhalation then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    elsif normalized_name ~ '(محلول|solution)' then
      form_class_key := 'inhalation_solution';
      route_class := 'inhalation';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_inhalation_solution';
    elsif normalized_name ~ '(محافظ|كبسول|capsule)' then
      form_class_key := 'inhalation_capsule';
      route_class := 'inhalation';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_inhalation_capsule';
    elsif normalized_name ~ '(بخاخ|inhaler|metered dose)' then
      form_class_key := 'inhalation_metered_dose';
      route_class := 'inhalation';
      release_class := 'not_applicable';
      status := 'auto_verified';
      reason_code := 'explicit_inhalation_device_form';
    else
      route_class := 'inhalation';
      status := 'needs_review';
      reason_code := 'inhalation_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if has_sublingual then
    if normalized_name ~ '(اقراص|tablet)' and not extended_marker and not delayed_marker then
      form_class_key := 'sublingual_tablet';
      route_class := 'sublingual';
      release_class := 'immediate_release';
      status := 'auto_verified';
      reason_code := 'explicit_sublingual_tablet';
    else
      route_class := 'sublingual';
      status := 'needs_review';
      reason_code := 'sublingual_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(متفتتة فمويا|orodispers|orally disintegr)' then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    else
      form_class_key := 'orodispersible_tablet';
      route_class := 'oral';
      release_class := 'immediate_release';
      status := 'auto_verified';
      reason_code := 'explicit_orodispersible_tablet';
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(للمضغ|chewable)' then
    if normalized_name ~ '(اقراص|tablet)' and not extended_marker and not delayed_marker then
      form_class_key := 'chewable_tablet';
      route_class := 'oral';
      release_class := 'immediate_release';
      status := 'auto_verified';
      reason_code := 'explicit_chewable_tablet';
    else
      status := 'needs_review';
      reason_code := 'chewable_form_unclassified';
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(اقراص فوارة|effervescent tablet)' then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    else
      form_class_key := 'effervescent_tablet';
      route_class := 'oral';
      release_class := 'immediate_release';
      status := 'auto_verified';
      reason_code := 'explicit_effervescent_tablet';
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(قابلة للاسالة|dispersible tablet|soluble tablet)' then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    else
      form_class_key := 'dispersible_tablet';
      route_class := 'oral';
      release_class := 'immediate_release';
      status := 'auto_verified';
      reason_code := 'explicit_dispersible_tablet';
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(ثنائية الطبقة|bilayer)' and normalized_name ~ '(اقراص|tablet)' then
    form_class_key := 'bilayer_tablet';
    route_class := 'oral';
    release_class := case
      when extended_marker then 'extended_release'
      when delayed_marker then 'delayed_release'
      else 'immediate_release'
    end;
    status := 'high_confidence';
    reason_code := 'explicit_bilayer_tablet';
    return next;
    return;
  end if;

  if normalized_name ~ '(تحضير معلق فموي|for oral suspension)' then
    form_class_key := 'tablet_for_oral_suspension';
    route_class := 'oral';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_tablet_for_oral_suspension';
    return next;
    return;
  end if;

  if normalized_name ~ '(اقراص مص|lozenge)' then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    else
      form_class_key := 'lozenge';
      route_class := 'oromucosal';
      release_class := 'immediate_release';
      status := 'auto_verified';
      reason_code := 'explicit_lozenge';
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(غسول فموي|mouthwash|oral rinse)' then
    form_class_key := 'oromucosal_rinse';
    route_class := 'oromucosal';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_oromucosal_rinse';
    return next;
    return;
  end if;

  if normalized_name ~ '(جل فموي|oral gel)' then
    form_class_key := 'oromucosal_gel';
    route_class := 'oromucosal';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_oromucosal_gel';
    return next;
    return;
  end if;

  if normalized_name ~ '(معجون فموي|oral paste)' then
    form_class_key := 'oromucosal_paste';
    route_class := 'oromucosal';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_oromucosal_paste';
    return next;
    return;
  end if;

  if normalized_name ~ '(نقط فموية|قطرة فموية|oral drop)' then
    form_class_key := 'oral_drops';
    route_class := 'oral';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_oral_drops';
    return next;
    return;
  end if;

  if normalized_name ~ '(معلق فموي|oral suspension)' then
    form_class_key := 'oral_suspension';
    route_class := 'oral';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_oral_suspension';
    return next;
    return;
  end if;

  if normalized_name ~ '(معلق جاف|powder for oral suspension|dry suspension)' then
    form_class_key := 'powder_for_oral_suspension';
    route_class := 'oral';
    release_class := 'not_applicable';
    status := 'high_confidence';
    reason_code := 'conventional_dry_suspension_route';
    return next;
    return;
  end if;

  if normalized_name ~ '(محلول فموي|oral solution)' then
    form_class_key := 'oral_solution';
    route_class := 'oral';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_oral_solution';
    return next;
    return;
  end if;

  if normalized_name in ('شراب', 'syrup', 'syrups') then
    form_class_key := 'oral_syrup';
    route_class := 'oral';
    release_class := 'not_applicable';
    status := 'high_confidence';
    reason_code := 'conventional_syrup_route';
    return next;
    return;
  end if;

  if normalized_name ~ '(محافظ.*جيلاتينية طرية|soft capsule|soft capsules|softgel|softgels)' then
    form_class_key := 'oral_soft_capsule';
    route_class := 'oral';
    release_class := case
      when extended_marker then 'extended_release'
      when delayed_marker then 'delayed_release'
      else 'immediate_release'
    end;
    status := 'high_confidence';
    reason_code := case
      when extended_marker then 'soft_capsule_explicit_extended_release'
      when delayed_marker then 'soft_capsule_explicit_delayed_release'
      else 'conventional_soft_capsule_route'
    end;
    return next;
    return;
  end if;

  if normalized_name ~ '(^محافظ$|^كبسول$|^capsule$|^capsules$|^hard capsule$|^hard capsules$)'
     or (
       normalized_name ~ '(محافظ|كبسول|capsule)'
       and (extended_marker or delayed_marker)
     ) then
    form_class_key := 'oral_capsule';
    route_class := 'oral';
    release_class := case
      when extended_marker then 'extended_release'
      when delayed_marker then 'delayed_release'
      else 'immediate_release'
    end;
    status := 'high_confidence';
    reason_code := case
      when extended_marker then 'capsule_explicit_extended_release'
      when delayed_marker then 'capsule_explicit_delayed_release'
      else 'conventional_capsule_route'
    end;
    return next;
    return;
  end if;

  if normalized_name = any(array[
      'اقراص',
      'اقراص ملبسة',
      'اقراص ملبسة بالفيلم',
      'اقراص سكرية',
      'مضغوطات',
      'مضغوطات ملبسة بالفلم',
      'tablet',
      'tablets',
      'coated tablet',
      'coated tablets',
      'film coated tablet',
      'film coated tablets'
    ])
     or (
       normalized_name ~ '(اقراص|مضغوطات|tablet)'
       and (extended_marker or delayed_marker)
     ) then
    form_class_key := 'oral_tablet';
    route_class := 'oral';
    release_class := case
      when extended_marker then 'extended_release'
      when delayed_marker then 'delayed_release'
      else 'immediate_release'
    end;
    status := 'high_confidence';
    reason_code := case
      when extended_marker then 'tablet_explicit_extended_release'
      when delayed_marker then 'tablet_explicit_delayed_release'
      else 'conventional_tablet_route'
    end;
    return next;
    return;
  end if;

  if normalized_name ~ '(كريم جلدي|cutaneous cream|topical cream)'
     or normalized_name = 'كريم' then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    else
      form_class_key := 'cutaneous_cream';
      route_class := 'cutaneous';
      release_class := 'not_applicable';
      status := case
        when normalized_name = 'كريم' then 'high_confidence'
        else 'auto_verified'
      end;
      reason_code := case
        when status = 'high_confidence'
          then 'conventional_cream_route'
        else 'explicit_cutaneous_cream'
      end;
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(مرهم جلدي|cutaneous ointment|topical ointment)'
     or normalized_name = 'مرهم' then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    else
      form_class_key := 'cutaneous_ointment';
      route_class := 'cutaneous';
      release_class := 'not_applicable';
      status := case
        when normalized_name = 'مرهم' then 'high_confidence'
        else 'auto_verified'
      end;
      reason_code := case
        when status = 'high_confidence'
          then 'conventional_ointment_route'
        else 'explicit_cutaneous_ointment'
      end;
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(جل جلدي|cutaneous gel|topical gel)'
     or normalized_name = 'جل' then
    if extended_marker or delayed_marker then
      status := 'needs_review';
      reason_code := 'unexpected_release_marker_for_form';
    else
      form_class_key := 'cutaneous_gel';
      route_class := 'cutaneous';
      release_class := 'not_applicable';
      status := case
        when normalized_name = 'جل' then 'high_confidence'
        else 'auto_verified'
      end;
      reason_code := case
        when status = 'high_confidence'
          then 'conventional_gel_route'
        else 'explicit_cutaneous_gel'
      end;
    end if;
    return next;
    return;
  end if;

  if normalized_name ~ '(cutaneous lotion|topical lotion)'
     or normalized_name = 'لوشن' then
    form_class_key := 'cutaneous_lotion';
    route_class := 'cutaneous';
    release_class := 'not_applicable';
    status := case
      when normalized_name = 'لوشن' then 'high_confidence'
      else 'auto_verified'
    end;
    reason_code := case
      when status = 'high_confidence'
        then 'conventional_lotion_route'
      else 'explicit_cutaneous_lotion'
    end;
    return next;
    return;
  end if;

  if normalized_name ~ '(بخاخ جلدي|cutaneous spray|topical spray)' then
    form_class_key := 'cutaneous_spray';
    route_class := 'cutaneous';
    release_class := 'not_applicable';
    status := 'auto_verified';
    reason_code := 'explicit_cutaneous_spray';
    return next;
    return;
  end if;

  status := 'unresolved';
  reason_code := 'unclassified_dosage_form';
  return next;
end;
$dosage_form_classifier$;

revoke all on function app_private.catalog_classify_dosage_form(text)
from public, anon, authenticated;

create or replace function app_private.refresh_catalog_dosage_form_equivalence_profile(
  target_dosage_form_id bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $refresh_dosage_form_profile$
declare
  source_row record;
  classified_row record;
begin
  select f.id, f.name, f.normalized_name
    into source_row
  from app_private.catalog_dosage_forms f
  where f.id = target_dosage_form_id;

  if not found then
    delete from app_private.catalog_dosage_form_equivalence_profiles
    where dosage_form_id = target_dosage_form_id;
    return;
  end if;

  select *
    into classified_row
  from app_private.catalog_classify_dosage_form(source_row.name);

  insert into app_private.catalog_dosage_form_equivalence_profiles(
    dosage_form_id,
    source_name,
    source_normalized_name,
    form_class_key,
    route_class,
    release_class,
    status,
    reason_code,
    classifier_version,
    classified_at
  )
  values (
    source_row.id,
    source_row.name,
    source_row.normalized_name,
    classified_row.form_class_key,
    classified_row.route_class,
    classified_row.release_class,
    classified_row.status,
    classified_row.reason_code,
    1,
    now()
  )
  on conflict (dosage_form_id) do update
  set
    source_name = excluded.source_name,
    source_normalized_name = excluded.source_normalized_name,
    form_class_key = excluded.form_class_key,
    route_class = excluded.route_class,
    release_class = excluded.release_class,
    status = excluded.status,
    reason_code = excluded.reason_code,
    classifier_version = excluded.classifier_version,
    classified_at = excluded.classified_at;
end;
$refresh_dosage_form_profile$;

revoke all on function app_private.refresh_catalog_dosage_form_equivalence_profile(bigint)
from public, anon, authenticated;

create or replace function app_private.refresh_product_pharmaceutical_equivalence(
  target_product_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $refresh_product_equivalence$
declare
  product_row record;
  composition_status_value app_private.composition_normalization_status;
  strength_status_value app_private.strength_normalization_status;
  ingredient_strength_key text;
  profile_source_name text;
  profile_status_value app_private.pharmaceutical_equivalence_status;
  profile_form_class text;
  profile_route app_private.pharmaceutical_route_class;
  profile_release app_private.pharmaceutical_release_class;
  profile_reason text;
  final_status app_private.pharmaceutical_equivalence_status;
  final_reason text;
  strict_key text;
begin
  delete from app_private.product_pharmaceutical_equivalence
  where product_id = target_product_id;

  select p.id, p.dosage_form, p.dosage_form_id
    into product_row
  from public.products p
  where p.id = target_product_id;

  if not found then
    return;
  end if;

  if product_row.dosage_form_id is not null then
    select
      p.source_name,
      p.status,
      p.form_class_key,
      p.route_class,
      p.release_class,
      p.reason_code
      into
        profile_source_name,
        profile_status_value,
        profile_form_class,
        profile_route,
        profile_release,
        profile_reason
    from app_private.catalog_dosage_form_equivalence_profiles p
    where p.dosage_form_id = product_row.dosage_form_id;

    if not found
       or profile_source_name is distinct from product_row.dosage_form then
      perform app_private.refresh_catalog_dosage_form_equivalence_profile(
        product_row.dosage_form_id
      );

      select
        p.source_name,
        p.status,
        p.form_class_key,
        p.route_class,
        p.release_class,
        p.reason_code
        into
          profile_source_name,
          profile_status_value,
          profile_form_class,
          profile_route,
          profile_release,
          profile_reason
      from app_private.catalog_dosage_form_equivalence_profiles p
      where p.dosage_form_id = product_row.dosage_form_id;
    end if;
  end if;

  select c.status
    into composition_status_value
  from app_private.product_composition_normalization c
  where c.product_id = target_product_id;

  select s.status, s.ingredient_strength_set_key
    into strength_status_value, ingredient_strength_key
  from app_private.product_strength_normalization s
  where s.product_id = target_product_id;

  if composition_status_value is null then
    final_status := 'unresolved';
    final_reason := 'missing_composition_normalization';
  elsif composition_status_value = 'unresolved' then
    final_status := 'unresolved';
    final_reason := 'composition_unresolved';
  elsif composition_status_value = 'needs_review' then
    final_status := 'needs_review';
    final_reason := 'composition_needs_review';
  elsif strength_status_value is null then
    final_status := 'unresolved';
    final_reason := 'missing_strength_normalization';
  elsif strength_status_value = 'unresolved' then
    final_status := 'unresolved';
    final_reason := 'strength_unresolved';
  elsif strength_status_value = 'needs_review'
        or ingredient_strength_key is null then
    final_status := 'needs_review';
    final_reason := 'strength_needs_review';
  elsif product_row.dosage_form_id is null then
    final_status := 'unresolved';
    final_reason := 'missing_dosage_form';
  elsif profile_status_value is null then
    final_status := 'unresolved';
    final_reason := 'missing_dosage_form_profile';
  elsif profile_status_value = 'unresolved' then
    final_status := 'unresolved';
    final_reason := coalesce(profile_reason, 'unclassified_dosage_form');
  elsif profile_status_value = 'needs_review' then
    final_status := 'needs_review';
    final_reason := profile_reason;
  else
    final_status := case
      when composition_status_value = 'high_confidence'
        or strength_status_value = 'high_confidence'
        or profile_status_value = 'high_confidence'
        then 'high_confidence'
      else 'auto_verified'
    end;

    final_reason := case
      when final_status = 'high_confidence'
        then 'trusted_dimensions_with_high_confidence_input'
      else 'all_dimensions_auto_verified'
    end;

    strict_key :=
      char_length(ingredient_strength_key)::text || ':' ||
      ingredient_strength_key ||
      '|form=' ||
      char_length(profile_form_class)::text || ':' ||
      profile_form_class ||
      '|route=' || profile_route::text ||
      '|release=' || profile_release::text;
  end if;

  insert into app_private.product_pharmaceutical_equivalence(
    product_id,
    source_dosage_form,
    dosage_form_id,
    composition_status,
    strength_status,
    dosage_form_status,
    ingredient_strength_set_key,
    form_class_key,
    route_class,
    release_class,
    status,
    reason_code,
    strict_equivalence_key,
    classifier_version
  )
  values (
    target_product_id,
    product_row.dosage_form,
    product_row.dosage_form_id,
    composition_status_value,
    strength_status_value,
    profile_status_value,
    ingredient_strength_key,
    profile_form_class,
    profile_route,
    profile_release,
    final_status,
    final_reason,
    case
      when final_status in ('auto_verified', 'high_confidence')
        then strict_key
      else null
    end,
    1
  );
end;
$refresh_product_equivalence$;

revoke all on function app_private.refresh_product_pharmaceutical_equivalence(uuid)
from public, anon, authenticated;

-- Extend the dependency chain. Composition refreshes ingredient identities,
-- then strength pairing, then pharmaceutical equivalence.
create or replace function app_private.sync_product_composition_normalization()
returns trigger
language plpgsql
security definer
set search_path = ''
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

  perform app_private.refresh_product_pharmaceutical_equivalence(new.id);

  return new;
end;
$$;

revoke all on function app_private.sync_product_composition_normalization()
from public, anon, authenticated;

create or replace function app_private.sync_product_strength_normalization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
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

  perform app_private.refresh_product_pharmaceutical_equivalence(new.id);

  return new;
end;
$$;

revoke all on function app_private.sync_product_strength_normalization()
from public, anon, authenticated;

create or replace function app_private.sync_product_pharmaceutical_equivalence_on_form()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Composition/strength changes own their dependency chains and refresh SP-027
  -- after upstream normalization has completed.
  if new.composition is distinct from old.composition
     or new.strength is distinct from old.strength then
    return new;
  end if;

  if new.dosage_form is not distinct from old.dosage_form
     and new.dosage_form_id is not distinct from old.dosage_form_id then
    return new;
  end if;

  perform app_private.refresh_product_pharmaceutical_equivalence(new.id);
  return new;
end;
$$;

revoke all on function app_private.sync_product_pharmaceutical_equivalence_on_form()
from public, anon, authenticated;

create trigger products_pharmaceutical_equivalence_form_sync
after update of dosage_form, dosage_form_id
on public.products
for each row
execute function app_private.sync_product_pharmaceutical_equivalence_on_form();

-- Structural backfill must not mutate authoritative product values or revisions.
create temporary table sp027_product_state_before
on commit drop
as
select
  id,
  composition,
  strength,
  dosage_form,
  dosage_form_id,
  revision,
  updated_at
from public.products;

do $sp027_profile_backfill$
declare
  form_row record;
begin
  for form_row in
    select id
    from app_private.catalog_dosage_forms
    order by id
  loop
    perform app_private.refresh_catalog_dosage_form_equivalence_profile(
      form_row.id
    );
  end loop;
end
$sp027_profile_backfill$;

do $sp027_product_backfill$
declare
  product_row record;
begin
  for product_row in
    select id
    from public.products
    order by id
  loop
    perform app_private.refresh_product_pharmaceutical_equivalence(
      product_row.id
    );
  end loop;
end
$sp027_product_backfill$;

do $sp027_backfill_guards$
begin
  if (
    select count(*)
    from app_private.catalog_dosage_form_equivalence_profiles
  ) <> (
    select count(*)
    from app_private.catalog_dosage_forms
  ) then
    raise exception 'dosage-form equivalence profile backfill row count mismatch';
  end if;

  if (
    select count(*)
    from app_private.product_pharmaceutical_equivalence
  ) <> (
    select count(*)
    from public.products
  ) then
    raise exception 'product pharmaceutical equivalence backfill row count mismatch';
  end if;

  if exists (
    select 1
    from public.products p
    join sp027_product_state_before b using (id)
    where p.composition is distinct from b.composition
       or p.strength is distinct from b.strength
       or p.dosage_form is distinct from b.dosage_form
       or p.dosage_form_id is distinct from b.dosage_form_id
       or p.revision is distinct from b.revision
       or p.updated_at is distinct from b.updated_at
  ) then
    raise exception 'pharmaceutical equivalence backfill mutated product source/revision state';
  end if;

  if exists (
    select 1
    from app_private.product_pharmaceutical_equivalence e
    where e.status in ('auto_verified', 'high_confidence')
      and (
        e.strict_equivalence_key is null
        or e.ingredient_strength_set_key is null
        or e.form_class_key is null
        or e.route_class is null
        or e.release_class is null
      )
  ) then
    raise exception 'trusted pharmaceutical equivalence row is incomplete';
  end if;

  if exists (
    select 1
    from app_private.product_pharmaceutical_equivalence e
    where e.status in ('needs_review', 'unresolved')
      and e.strict_equivalence_key is not null
  ) then
    raise exception 'untrusted pharmaceutical equivalence row retained strict key';
  end if;

  if exists (
    select 1
    from app_private.product_pharmaceutical_equivalence e
    join app_private.catalog_dosage_form_equivalence_profiles f
      on f.dosage_form_id = e.dosage_form_id
    where e.strict_equivalence_key is not null
      and f.status not in ('auto_verified', 'high_confidence')
  ) then
    raise exception 'strict pharmaceutical equivalence used untrusted dosage-form profile';
  end if;
end
$sp027_backfill_guards$;
