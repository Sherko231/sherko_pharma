#!/usr/bin/env python3
"""Audit reviewed Sherko scientific identities against an operator SDIF database.

The audit is read-only and conservative. Reviewed ATC metadata can establish
provider lookup compatibility when SDIF resolves it unambiguously. Exact
substance-name equality is only a review candidate and is never auto-trusted.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from sdif_contract import SdifContractError, validate_sdif_database

EXPORT_SCHEMA_VERSION = 1
STATUS_REVIEWED_ATC_MATCH = 'reviewed_atc_match'
STATUS_REVIEWED_ATC_AMBIGUOUS = 'reviewed_atc_ambiguous'
STATUS_EXACT_NAME_CANDIDATE = 'exact_name_candidate'
STATUS_AMBIGUOUS_NAME_CANDIDATE = 'ambiguous_name_candidate'
STATUS_UNMAPPED = 'unmapped'
STATUSES = (
    STATUS_REVIEWED_ATC_MATCH,
    STATUS_REVIEWED_ATC_AMBIGUOUS,
    STATUS_EXACT_NAME_CANDIDATE,
    STATUS_AMBIGUOUS_NAME_CANDIDATE,
    STATUS_UNMAPPED,
)


class SdifMappingAuditError(RuntimeError):
    pass


@dataclass(frozen=True)
class SherkoScientificIdentity:
    scientific_ingredient_id: int
    preferred_name: str
    reviewed_atc_codes: tuple[str, ...]


@dataclass(frozen=True)
class MappingAuditResult:
    scientific_ingredient_id: int
    preferred_name: str
    status: str
    reviewed_atc_codes: tuple[str, ...]
    provider_atc_codes: tuple[str, ...]
    provider_substances: tuple[str, ...]
    reason_codes: tuple[str, ...]


@dataclass(frozen=True)
class MappingAuditReport:
    results: tuple[MappingAuditResult, ...]

    @property
    def counts(self) -> dict[str, int]:
        counter = Counter(result.status for result in self.results)
        return {status: counter.get(status, 0) for status in STATUSES}

    def aggregate_dict(self) -> dict[str, object]:
        counts = self.counts
        total = len(self.results)
        atc_backed = counts[STATUS_REVIEWED_ATC_MATCH]
        return {
            'total_identities': total,
            'reviewed_atc_backed_mappings': atc_backed,
            'reviewed_atc_backed_coverage_percent': (
                round((100.0 * atc_backed / total), 2) if total else 0.0
            ),
            'counts': counts,
        }

    def as_dict(self) -> dict[str, object]:
        return {
            **self.aggregate_dict(),
            'results': [
                {
                    'scientific_ingredient_id': result.scientific_ingredient_id,
                    'preferred_name': result.preferred_name,
                    'status': result.status,
                    'reviewed_atc_codes': list(result.reviewed_atc_codes),
                    'provider_atc_codes': list(result.provider_atc_codes),
                    'provider_substances': list(result.provider_substances),
                    'reason_codes': list(result.reason_codes),
                }
                for result in self.results
            ],
        }


def scientific_name_key(value: str) -> str:
    normalized = unicodedata.normalize('NFKC', value).strip().casefold()
    return ' '.join(normalized.split())


def _validate_atc_code(value: object) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SdifMappingAuditError('reviewed_atc_codes must contain nonblank strings')
    canonical = value.strip().upper()
    if canonical != value.strip():
        raise SdifMappingAuditError(
            f'reviewed ATC code must already be canonical uppercase: {value!r}'
        )
    return canonical


def load_identity_export(path: str | Path) -> tuple[SherkoScientificIdentity, ...]:
    try:
        raw = json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise SdifMappingAuditError(
            f'Unable to read scientific identity export: {error}'
        ) from error
    if not isinstance(raw, dict) or raw.get('schema_version') != EXPORT_SCHEMA_VERSION:
        raise SdifMappingAuditError(
            f'Expected export schema_version {EXPORT_SCHEMA_VERSION}'
        )
    identities = raw.get('identities')
    if not isinstance(identities, list):
        raise SdifMappingAuditError('Export identities must be a list')
    parsed = []
    seen_ids = set()
    for index, item in enumerate(identities):
        if not isinstance(item, dict):
            raise SdifMappingAuditError(f'Identity at index {index} must be an object')
        identity_id = item.get('scientific_ingredient_id')
        preferred_name = item.get('preferred_name')
        reviewed_atc_codes = item.get('reviewed_atc_codes', [])
        if (
            not isinstance(identity_id, int)
            or isinstance(identity_id, bool)
            or identity_id <= 0
        ):
            raise SdifMappingAuditError(
                f'Identity at index {index} has invalid scientific_ingredient_id'
            )
        if identity_id in seen_ids:
            raise SdifMappingAuditError(
                f'Duplicate scientific_ingredient_id: {identity_id}'
            )
        if not isinstance(preferred_name, str) or not preferred_name.strip():
            raise SdifMappingAuditError(
                f'Identity {identity_id} has blank preferred_name'
            )
        if not isinstance(reviewed_atc_codes, list):
            raise SdifMappingAuditError(
                f'Identity {identity_id} reviewed_atc_codes must be a list'
            )
        atc_codes = tuple(
            dict.fromkeys(_validate_atc_code(code) for code in reviewed_atc_codes)
        )
        parsed.append(
            SherkoScientificIdentity(
                identity_id,
                preferred_name.strip(),
                atc_codes,
            )
        )
        seen_ids.add(identity_id)
    return tuple(parsed)


def _open_read_only(path: Path) -> sqlite3.Connection:
    return sqlite3.connect(f'{path.resolve().as_uri()}?mode=ro', uri=True)


def _parse_substances(raw: str | None) -> tuple[str, ...]:
    if raw is None:
        return ()
    return tuple(part.strip() for part in raw.split(', ') if part.strip())


def _substance_set_key(raw: str | None) -> tuple[str, ...]:
    return tuple(
        sorted({scientific_name_key(value) for value in _parse_substances(raw)})
    )


def _provider_indexes(connection: sqlite3.Connection):
    atc_sets: dict[str, set[tuple[str, ...]]] = defaultdict(set)
    atc_display_substances: dict[str, set[str]] = defaultdict(set)
    for atc_code, active_substances in connection.execute(
        "select coalesce(atc_code, ''), coalesce(active_substances, '') from drugs"
    ):
        atc = str(atc_code).strip().upper()
        if not atc:
            continue
        substance_set = _substance_set_key(str(active_substances))
        if substance_set:
            atc_sets[atc].add(substance_set)
            atc_display_substances[atc].update(
                _parse_substances(str(active_substances))
            )

    name_atcs: dict[str, set[str]] = defaultdict(set)
    name_display: dict[str, set[str]] = defaultdict(set)
    rows = connection.execute(
        "select sbm.substance, coalesce(d.atc_code, '') "
        "from substance_brand_map sbm "
        "left join drugs d on d.brand_name = sbm.brand_name"
    )
    for substance, atc_code in rows:
        if substance is None:
            continue
        display = str(substance).strip()
        if not display:
            continue
        key = scientific_name_key(display)
        name_display[key].add(display)
        atc = str(atc_code).strip().upper()
        if atc:
            name_atcs[key].add(atc)
    return atc_sets, atc_display_substances, name_atcs, name_display


def audit_identity_mapping(
    database_path: str | Path,
    identities: Iterable[SherkoScientificIdentity],
) -> MappingAuditReport:
    try:
        validate_sdif_database(database_path)
    except SdifContractError as error:
        raise SdifMappingAuditError(
            f'SDIF contract validation failed: {error}'
        ) from error

    path = Path(database_path)
    connection = _open_read_only(path)
    try:
        atc_sets, atc_display, name_atcs, name_display = _provider_indexes(connection)
    except sqlite3.DatabaseError as error:
        raise SdifMappingAuditError(
            f'Unable to audit SDIF database: {error}'
        ) from error
    finally:
        connection.close()

    results = []
    for identity in identities:
        matched_atc_codes = tuple(
            code for code in identity.reviewed_atc_codes if code in atc_sets
        )
        if matched_atc_codes:
            distinct_sets = {
                subset
                for code in matched_atc_codes
                for subset in atc_sets[code]
            }
            provider_substances = tuple(
                sorted(
                    {
                        substance
                        for code in matched_atc_codes
                        for substance in atc_display[code]
                    }
                )
            )
            missing_reviewed_atc_codes = tuple(
                code for code in identity.reviewed_atc_codes if code not in atc_sets
            )
            single_provider_substance = (
                len(distinct_sets) == 1
                and all(len(subset) == 1 for subset in distinct_sets)
            )
            if single_provider_substance:
                status = STATUS_REVIEWED_ATC_MATCH
                reason_list = ['reviewed_atc_provider_match']
                if missing_reviewed_atc_codes:
                    reason_list.append('some_reviewed_atc_codes_not_found')
                reasons = tuple(reason_list)
            else:
                status = STATUS_REVIEWED_ATC_AMBIGUOUS
                reason_list = ['reviewed_atc_provider_conflict_or_combination']
                if missing_reviewed_atc_codes:
                    reason_list.append('some_reviewed_atc_codes_not_found')
                reasons = tuple(reason_list)
            results.append(
                MappingAuditResult(
                    identity.scientific_ingredient_id,
                    identity.preferred_name,
                    status,
                    identity.reviewed_atc_codes,
                    tuple(sorted(matched_atc_codes)),
                    provider_substances,
                    reasons,
                )
            )
            continue

        name_key = scientific_name_key(identity.preferred_name)
        matched_names = name_display.get(name_key, set())
        matched_name_atcs = tuple(sorted(name_atcs.get(name_key, set())))
        if matched_names:
            reasons = []
            if identity.reviewed_atc_codes:
                reasons.append('reviewed_atc_not_found')
            if len(matched_name_atcs) <= 1:
                status = STATUS_EXACT_NAME_CANDIDATE
                reasons.append('exact_provider_substance_name_requires_review')
            else:
                status = STATUS_AMBIGUOUS_NAME_CANDIDATE
                reasons.append(
                    'exact_provider_substance_name_spans_multiple_atc_codes'
                )
            results.append(
                MappingAuditResult(
                    identity.scientific_ingredient_id,
                    identity.preferred_name,
                    status,
                    identity.reviewed_atc_codes,
                    matched_name_atcs,
                    tuple(sorted(matched_names)),
                    tuple(reasons),
                )
            )
            continue

        reasons = (
            ('reviewed_atc_not_found', 'no_exact_provider_substance_name')
            if identity.reviewed_atc_codes
            else ('no_reviewed_atc_or_exact_provider_substance_name',)
        )
        results.append(
            MappingAuditResult(
                identity.scientific_ingredient_id,
                identity.preferred_name,
                STATUS_UNMAPPED,
                identity.reviewed_atc_codes,
                (),
                (),
                reasons,
            )
        )

    return MappingAuditReport(tuple(results))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            'Audit reviewed Sherko scientific identities against an '
            'operator-supplied SDIF database.'
        )
    )
    parser.add_argument('database', help='Path to validated SDIF interactions.db')
    parser.add_argument(
        'identity_export',
        help='Path to Sherko scientific identity JSON export',
    )
    parser.add_argument('--json', action='store_true', help='Print machine-readable output.')
    parser.add_argument(
        '--aggregate-only',
        action='store_true',
        help='Omit per-identity/provider details and print only coverage counts.',
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        identities = load_identity_export(args.identity_export)
        report = audit_identity_mapping(args.database, identities)
    except SdifMappingAuditError as error:
        print(f'SDIF mapping audit failed: {error}', file=sys.stderr)
        return 2

    payload = report.aggregate_dict() if args.aggregate_only else report.as_dict()
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False))
    else:
        counts = report.counts
        print(f"SDIF mapping audit: {len(report.results)} scientific identities")
        print(f"  reviewed ATC matches: {counts[STATUS_REVIEWED_ATC_MATCH]}")
        print(f"  reviewed ATC ambiguous: {counts[STATUS_REVIEWED_ATC_AMBIGUOUS]}")
        print(f"  exact-name review candidates: {counts[STATUS_EXACT_NAME_CANDIDATE]}")
        print(
            '  ambiguous-name candidates: '
            f"{counts[STATUS_AMBIGUOUS_NAME_CANDIDATE]}"
        )
        print(f"  unmapped: {counts[STATUS_UNMAPPED]}")
        if not args.aggregate_only:
            for result in report.results:
                print(
                    f"  - {result.scientific_ingredient_id} "
                    f"{result.preferred_name}: {result.status}"
                )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
