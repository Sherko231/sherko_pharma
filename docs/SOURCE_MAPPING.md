# Corrected source CSV mapping

Status: SP-003 mapping contract for the owner-supplied corrected `sy-database(2).csv`. The CSV itself is private input and must not be committed.

## Inspected source fingerprint

- Rows: **23,750**
- Columns: **25**
- SHA-256: `2923fffd24e8aaee0cda7549458aec680f6ee67b50925b93ff540c2c755029a4`
- `Id` and `itemId`: unique, populated, and equal for all inspected rows.
- `num`: separately unique and differs from `Id` in most rows.
- `price`: integer text, range 0..75,993,500; 423 zero-priced anomalies.
- `barcode`: 8,260 blanks and seven duplicated nonempty values.
- `barcode2`: 22,495 blanks and one duplicated nonempty value.
- Across both barcode columns, 13 codes identify more than one distinct source row.
- Some nonempty barcode values contain a leading minus sign. Barcode storage remains text.
- All current source selling prices map to explicit `SYP` without conversion.

SP-005 must reject or explicitly account for a different fingerprint rather than assuming it is identical.

## Identity and provenance

`products.id` is a generated UUID independent from every source identifier and mutable catalog field. Imported rows preserve a versioned `source_dataset`, `source_id`, `source_item_id`, `source_num`, `source_purchase_amount`, and the complete original 25-column row in `source_payload` JSONB.

## Complete 25-column mapping

| Source column | Destination | Rule |
| --- | --- | --- |
| `Id` | `source_id` | Exact integer; also preserve raw text; never application identity |
| `name` | `name_en` | Preserve text |
| `tarkibah` | `composition` | Preserve text; canonical blank may become NULL |
| `shakielSaidalaani` | `dosage_form` | Preserve text |
| `maamaal` | `manufacturer` | Preserve text |
| `tarkiez` | `strength` | Preserve text; do not reinterpret units |
| `shakielOboaa` | `package_description` | Preserve text |
| `price` | `selling_amount` + `currency='SYP'` | Exact whole integer; no conversion/rounding; zero retained as anomaly |
| `barcode` | `barcode` | Blank -> NULL; nonblank copied exactly; no uniqueness/numeric coercion |
| `barcode2` | `barcode2` | Same as primary barcode; alternative identifier for same package |
| `notice` | source payload only | Preserve; semantics not invented |
| `itemId` | `source_item_id` | Exact integer, preserved separately |
| `purchasePrice` | `source_purchase_amount` | Provenance only; never substitute selling amount |
| `name_ar` | `name_ar` | Preserve Arabic text |
| `volume` | source payload only | Preserve; currently blank |
| `type` | source payload only | Preserve; do not invent enum |
| `source` | source payload only | Preserve; distinct from provenance dataset key |
| `expireDate` | source payload only | Preserve; no date semantics inferred |
| `num` | `source_num` | Exact integer, separate from Id/itemId |
| `isDirty` | source payload only | Preserve; not server revision state |
| `Indications` | source payload only | Preserve; UI/API exposure deferred |
| `Contraindications` | source payload only | Preserve; UI/API exposure deferred |
| `Pregnancy` | source payload only | Preserve; UI/API exposure deferred |
| `isRepeated` | source payload only | Preserve; no dedupe semantics inferred |
| `isForDelete` | source payload only | Preserve; never silently delete a row |

## Anomaly policy

Do not drop or deduplicate rows because prices are zero, barcodes are blank/duplicated, or source-only fields are empty. Canonical blank barcodes become NULL while the raw values remain in `source_payload`. Cross-product barcode collisions remain multiple candidates. Parse failures, overflow, fractional selling prices, unsupported source shape, or unusable names are explicit SP-005 import errors.

## Revision contract

Products start at `revision = 1`. The database trigger increments revision by exactly one on every accepted update and refreshes `updated_at`. SP-004 must update with both product id and expected revision; a zero-row update is a conflict, not last-writer-wins.
