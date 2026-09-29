enum InteractionSeverity {
  major,
  moderate,
  minor,
  none,
  unknown,
}

enum InteractionSubstanceKind {
  drug,
  other,
}

enum InteractionEvidenceSeverity {
  major,
  moderate,
  minor,
  none,
}

enum InteractionEvidenceSection {
  boxedWarning,
  contraindications,
  warningsAndCautions,
  warnings,
  drugInteractions,
  precautions,
  overlay,
}

enum InteractionMatchKind {
  name,
  classMatch,
  overlay,
}

enum InteractionSourceType {
  fdaLabel,
  curated,
}

class InteractionSubstance {
  const InteractionSubstance({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    this.group,
  });

  factory InteractionSubstance.fromJson(Map<String, dynamic> json) {
    return InteractionSubstance(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      kind: _parseSubstanceKind(_requiredString(json, 'kind')),
      url: _requiredUri(json, 'url'),
      group: _optionalString(json, 'group'),
    );
  }

  final String id;
  final String name;
  final InteractionSubstanceKind kind;
  final Uri url;
  final String? group;
}

class ResolvedInteractionItem {
  const ResolvedInteractionItem({
    required this.substance,
    required this.query,
    this.matchedOn,
  });

  factory ResolvedInteractionItem.fromJson(Map<String, dynamic> json) {
    return ResolvedInteractionItem(
      substance: InteractionSubstance.fromJson(json),
      query: _requiredString(json, 'query'),
      matchedOn: _optionalString(json, 'matchedOn'),
    );
  }

  final InteractionSubstance substance;
  final String query;
  final String? matchedOn;
}

class UnresolvedInteractionItem {
  const UnresolvedInteractionItem({
    required this.query,
    required this.suggestions,
  });

  factory UnresolvedInteractionItem.fromJson(Map<String, dynamic> json) {
    final suggestions = _requiredList(json, 'suggestions');
    return UnresolvedInteractionItem(
      query: _requiredString(json, 'query'),
      suggestions: suggestions
          .map(
            (value) => InteractionSubstance.fromJson(
              _valueAsMap(value, 'unresolved.suggestions'),
            ),
          )
          .toList(growable: false),
    );
  }

  final String query;
  final List<InteractionSubstance> suggestions;
}

class InteractionEvidenceSource {
  const InteractionEvidenceSource({
    required this.type,
    required this.name,
    required this.url,
    this.effectiveDate,
  });

  factory InteractionEvidenceSource.fromJson(Map<String, dynamic> json) {
    return InteractionEvidenceSource(
      type: _parseSourceType(_requiredString(json, 'type')),
      name: _requiredString(json, 'name'),
      url: _requiredUri(json, 'url'),
      effectiveDate: _optionalDate(json, 'effectiveDate'),
    );
  }

  final InteractionSourceType type;
  final String name;
  final Uri url;
  final DateTime? effectiveDate;
}

class InteractionEvidence {
  const InteractionEvidence({
    required this.from,
    required this.about,
    required this.section,
    required this.sectionLabel,
    required this.severity,
    required this.quote,
    required this.matchedTerm,
    required this.matchKind,
    required this.source,
  });

  factory InteractionEvidence.fromJson(Map<String, dynamic> json) {
    return InteractionEvidence(
      from: _requiredString(json, 'from'),
      about: _requiredString(json, 'about'),
      section: _parseEvidenceSection(_requiredString(json, 'section')),
      sectionLabel: _requiredString(json, 'sectionLabel'),
      severity: _parseEvidenceSeverity(_requiredString(json, 'severity')),
      quote: _requiredString(json, 'quote'),
      matchedTerm: _requiredString(json, 'matchedTerm'),
      matchKind: _parseMatchKind(_requiredString(json, 'matchKind')),
      source: InteractionEvidenceSource.fromJson(
        _requiredMap(json, 'source'),
      ),
    );
  }

  final String from;
  final String about;
  final InteractionEvidenceSection section;
  final String sectionLabel;
  final InteractionEvidenceSeverity severity;
  final String quote;
  final String matchedTerm;
  final InteractionMatchKind matchKind;
  final InteractionEvidenceSource source;
}

class InteractionPair {
  const InteractionPair({
    required this.a,
    required this.b,
    required this.severity,
    required this.severityLabel,
    required this.url,
    required this.evidence,
    this.page,
  });

  factory InteractionPair.fromJson(Map<String, dynamic> json) {
    final evidence = _requiredList(json, 'evidence');
    return InteractionPair(
      a: InteractionSubstance.fromJson(_requiredMap(json, 'a')),
      b: InteractionSubstance.fromJson(_requiredMap(json, 'b')),
      severity: _parsePairSeverity(_requiredString(json, 'severity')),
      severityLabel: _requiredString(json, 'severityLabel'),
      url: _requiredUri(json, 'url'),
      page: _optionalUri(json, 'page'),
      evidence: evidence
          .map(
            (value) => InteractionEvidence.fromJson(
              _valueAsMap(value, 'pair.evidence'),
            ),
          )
          .toList(growable: false),
    );
  }

  final InteractionSubstance a;
  final InteractionSubstance b;
  final InteractionSeverity severity;
  final String severityLabel;
  final Uri url;
  final Uri? page;
  final List<InteractionEvidence> evidence;
}

class InteractionCheckData {
  const InteractionCheckData({
    this.labelExportDate,
    this.generatedAt,
  });

  factory InteractionCheckData.fromJson(Map<String, dynamic> json) {
    return InteractionCheckData(
      labelExportDate: _optionalDate(json, 'labelExportDate'),
      generatedAt: _optionalDate(json, 'generatedAt'),
    );
  }

  final DateTime? labelExportDate;
  final DateTime? generatedAt;
}

class InteractionAttribution {
  const InteractionAttribution({
    this.text,
    this.url,
    this.license,
  });

  factory InteractionAttribution.fromJson(Map<String, dynamic> json) {
    return InteractionAttribution(
      text: _optionalString(json, 'text'),
      url: _optionalUri(json, 'url'),
      license: _optionalString(json, 'license'),
    );
  }

  final String? text;
  final Uri? url;
  final String? license;
}

class InteractionCheckResult {
  const InteractionCheckResult({
    required this.items,
    required this.unresolved,
    required this.pairs,
    required this.summary,
    required this.data,
    required this.disclaimer,
    required this.attribution,
  });

  factory InteractionCheckResult.fromJson(Map<String, dynamic> json) {
    final items = _requiredList(json, 'items');
    final unresolved = _requiredList(json, 'unresolved');
    final pairs = _requiredList(json, 'pairs');
    final summaryJson = _requiredMap(json, 'summary');

    final summary = <InteractionSeverity, int>{};
    for (final severity in InteractionSeverity.values) {
      final key = severity.name;
      if (!summaryJson.containsKey(key)) {
        continue;
      }
      final count = summaryJson[key];
      if (count is! int || count < 0) {
        throw InteractionModelFormatException(
          'summary.$key must be a non-negative integer',
        );
      }
      summary[severity] = count;
    }

    return InteractionCheckResult(
      items: items
          .map(
            (value) => ResolvedInteractionItem.fromJson(
              _valueAsMap(value, 'items'),
            ),
          )
          .toList(growable: false),
      unresolved: unresolved
          .map(
            (value) => UnresolvedInteractionItem.fromJson(
              _valueAsMap(value, 'unresolved'),
            ),
          )
          .toList(growable: false),
      pairs: pairs
          .map(
            (value) => InteractionPair.fromJson(
              _valueAsMap(value, 'pairs'),
            ),
          )
          .toList(growable: false),
      summary: Map.unmodifiable(summary),
      data: InteractionCheckData.fromJson(_requiredMap(json, 'data')),
      disclaimer: _requiredString(json, 'disclaimer'),
      attribution: InteractionAttribution.fromJson(
        _requiredMap(json, 'attribution'),
      ),
    );
  }

  final List<ResolvedInteractionItem> items;
  final List<UnresolvedInteractionItem> unresolved;
  final List<InteractionPair> pairs;
  final Map<InteractionSeverity, int> summary;
  final InteractionCheckData data;
  final String disclaimer;
  final InteractionAttribution attribution;
}

class InteractionModelFormatException implements Exception {
  const InteractionModelFormatException(this.message);

  final String message;

  @override
  String toString() => 'InteractionModelFormatException: $message';
}

class InteractionUnsupportedValueException implements Exception {
  const InteractionUnsupportedValueException({
    required this.field,
    required this.value,
  });

  final String field;
  final String value;

  @override
  String toString() => 'Unsupported $field value: $value';
}

InteractionSeverity _parsePairSeverity(String value) {
  return switch (value) {
    'major' => InteractionSeverity.major,
    'moderate' => InteractionSeverity.moderate,
    'minor' => InteractionSeverity.minor,
    'none' => InteractionSeverity.none,
    'unknown' => InteractionSeverity.unknown,
    _ => throw InteractionUnsupportedValueException(
        field: 'pair.severity',
        value: value,
      ),
  };
}

InteractionEvidenceSeverity _parseEvidenceSeverity(String value) {
  return switch (value) {
    'major' => InteractionEvidenceSeverity.major,
    'moderate' => InteractionEvidenceSeverity.moderate,
    'minor' => InteractionEvidenceSeverity.minor,
    'none' => InteractionEvidenceSeverity.none,
    _ => throw InteractionUnsupportedValueException(
        field: 'evidence.severity',
        value: value,
      ),
  };
}

InteractionSubstanceKind _parseSubstanceKind(String value) {
  return switch (value) {
    'drug' => InteractionSubstanceKind.drug,
    'other' => InteractionSubstanceKind.other,
    _ => throw InteractionUnsupportedValueException(
        field: 'substance.kind',
        value: value,
      ),
  };
}

InteractionEvidenceSection _parseEvidenceSection(String value) {
  return switch (value) {
    'boxed_warning' => InteractionEvidenceSection.boxedWarning,
    'contraindications' => InteractionEvidenceSection.contraindications,
    'warnings_and_cautions' =>
      InteractionEvidenceSection.warningsAndCautions,
    'warnings' => InteractionEvidenceSection.warnings,
    'drug_interactions' => InteractionEvidenceSection.drugInteractions,
    'precautions' => InteractionEvidenceSection.precautions,
    'overlay' => InteractionEvidenceSection.overlay,
    _ => throw InteractionUnsupportedValueException(
        field: 'evidence.section',
        value: value,
      ),
  };
}

InteractionMatchKind _parseMatchKind(String value) {
  return switch (value) {
    'name' => InteractionMatchKind.name,
    'class' => InteractionMatchKind.classMatch,
    'overlay' => InteractionMatchKind.overlay,
    _ => throw InteractionUnsupportedValueException(
        field: 'evidence.matchKind',
        value: value,
      ),
  };
}

InteractionSourceType _parseSourceType(String value) {
  return switch (value) {
    'fda_label' => InteractionSourceType.fdaLabel,
    'curated' => InteractionSourceType.curated,
    _ => throw InteractionUnsupportedValueException(
        field: 'evidence.source.type',
        value: value,
      ),
  };
}

Map<String, dynamic> _requiredMap(
  Map<String, dynamic> json,
  String key,
) {
  if (!json.containsKey(key)) {
    throw InteractionModelFormatException('Missing required field: $key');
  }
  return _valueAsMap(json[key], key);
}

Map<String, dynamic> _valueAsMap(dynamic value, String field) {
  if (value is! Map) {
    throw InteractionModelFormatException('$field must be an object');
  }

  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw InteractionModelFormatException(
        '$field contains a non-string key',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<dynamic> _requiredList(
  Map<String, dynamic> json,
  String key,
) {
  if (!json.containsKey(key) || json[key] is! List) {
    throw InteractionModelFormatException(
      'Missing or invalid list field: $key',
    );
  }
  return List<dynamic>.from(json[key] as List);
}

String _requiredString(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw InteractionModelFormatException(
      'Missing or invalid string field: $key',
    );
  }
  return value;
}

String? _optionalString(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw InteractionModelFormatException('$key must be a string');
  }
  return value;
}

Uri _requiredUri(
  Map<String, dynamic> json,
  String key,
) {
  final value = _requiredString(json, key);
  return _parseUri(value, key);
}

Uri? _optionalUri(
  Map<String, dynamic> json,
  String key,
) {
  final value = _optionalString(json, key);
  if (value == null) {
    return null;
  }
  return _parseUri(value, key);
}

Uri _parseUri(String value, String field) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw InteractionModelFormatException(
      '$field must be an absolute URI',
    );
  }
  return uri;
}

DateTime? _optionalDate(
  Map<String, dynamic> json,
  String key,
) {
  final value = _optionalString(json, key);
  if (value == null) {
    return null;
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw InteractionModelFormatException(
      '$key must be an ISO-8601 date',
    );
  }
  return parsed;
}
