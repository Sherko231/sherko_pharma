enum SdifInteractionFamily {
  substance,
  classLevel,
  cyp,
  epha,
}

class SdifDrugSearchResult {
  const SdifDrugSearchResult({
    required this.brandName,
    required this.atcCode,
    required this.substances,
  });

  factory SdifDrugSearchResult.fromJson(Map<String, dynamic> json) {
    return SdifDrugSearchResult(
      brandName: _requiredString(json, 'brand_name'),
      atcCode: _requiredString(json, 'atc_code'),
      substances: _requiredString(json, 'substances'),
    );
  }

  final String brandName;
  final String atcCode;
  final String substances;
}

class SdifBasketDrug {
  const SdifBasketDrug({
    required this.brand,
    required this.atcCode,
    required this.substances,
  });

  factory SdifBasketDrug.fromJson(Map<String, dynamic> json) {
    return SdifBasketDrug(
      brand: _requiredString(json, 'brand'),
      atcCode: _requiredString(json, 'atc_code'),
      substances: _requiredStringList(json, 'substances'),
    );
  }

  final String brand;
  final String atcCode;
  final List<String> substances;
}

class SdifInteractionHit {
  const SdifInteractionHit({
    required this.drugA,
    required this.drugAAtc,
    required this.drugARoute,
    required this.drugB,
    required this.drugBAtc,
    required this.drugBRoute,
    required this.family,
    required this.severityScore,
    required this.severityLabel,
    required this.severityIndicator,
    required this.keyword,
    required this.description,
    required this.explanation,
    required this.source,
    required this.comboHint,
  });

  factory SdifInteractionHit.fromJson(Map<String, dynamic> json) {
    return SdifInteractionHit(
      drugA: _requiredString(json, 'drug_a'),
      drugAAtc: _requiredString(json, 'drug_a_atc'),
      drugARoute: _requiredString(json, 'drug_a_route'),
      drugB: _requiredString(json, 'drug_b'),
      drugBAtc: _requiredString(json, 'drug_b_atc'),
      drugBRoute: _requiredString(json, 'drug_b_route'),
      family: _parseInteractionFamily(
        _requiredString(json, 'interaction_type'),
      ),
      severityScore: _requiredU8(json, 'severity_score'),
      severityLabel: _requiredString(json, 'severity_label'),
      severityIndicator: _requiredString(json, 'severity_indicator'),
      keyword: _requiredString(json, 'keyword'),
      description: _requiredString(json, 'description'),
      explanation: _requiredString(json, 'explanation'),
      source: _requiredString(json, 'source'),
      comboHint: _requiredString(json, 'combo_hint'),
    );
  }

  final String drugA;
  final String drugAAtc;
  final String drugARoute;
  final String drugB;
  final String drugBAtc;
  final String drugBRoute;
  final SdifInteractionFamily family;
  final int severityScore;
  final String severityLabel;
  final String severityIndicator;
  final String keyword;
  final String description;
  final String explanation;
  final String source;
  final String comboHint;
}

class SdifCheckResult {
  const SdifCheckResult({
    required this.basket,
    required this.interactions,
  });

  factory SdifCheckResult.fromJson(Map<String, dynamic> json) {
    final basket = _requiredList(json, 'basket');
    final interactions = _requiredList(json, 'interactions');

    return SdifCheckResult(
      basket: List.unmodifiable(
        basket.map(
          (value) => SdifBasketDrug.fromJson(
            _valueAsMap(value, 'basket'),
          ),
        ),
      ),
      interactions: List.unmodifiable(
        interactions.map(
          (value) => SdifInteractionHit.fromJson(
            _valueAsMap(value, 'interactions'),
          ),
        ),
      ),
    );
  }

  final List<SdifBasketDrug> basket;
  final List<SdifInteractionHit> interactions;
}

class SdifModelFormatException implements Exception {
  const SdifModelFormatException(this.message);

  final String message;

  @override
  String toString() => 'SdifModelFormatException: $message';
}

class SdifUnsupportedValueException implements Exception {
  const SdifUnsupportedValueException({
    required this.field,
    required this.value,
  });

  final String field;
  final String value;

  @override
  String toString() => 'Unsupported $field value: $value';
}

SdifInteractionFamily _parseInteractionFamily(String value) {
  return switch (value) {
    'substance' => SdifInteractionFamily.substance,
    'class-level' => SdifInteractionFamily.classLevel,
    'CYP' => SdifInteractionFamily.cyp,
    'epha' => SdifInteractionFamily.epha,
    _ => throw SdifUnsupportedValueException(
        field: 'interaction_type',
        value: value,
      ),
  };
}

List<dynamic> _requiredList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw SdifModelFormatException(
      'Missing or invalid list field: $key',
    );
  }
  return List<dynamic>.from(value);
}

List<String> _requiredStringList(
  Map<String, dynamic> json,
  String key,
) {
  final values = _requiredList(json, key);
  final result = <String>[];
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    if (value is! String) {
      throw SdifModelFormatException(
        '$key[$index] must be a string',
      );
    }
    result.add(value);
  }
  return List.unmodifiable(result);
}

Map<String, dynamic> _valueAsMap(dynamic value, String field) {
  if (value is! Map) {
    throw SdifModelFormatException('$field entries must be objects');
  }

  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw SdifModelFormatException(
        '$field contains a non-string key',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] is! String) {
    throw SdifModelFormatException(
      'Missing or invalid string field: $key',
    );
  }
  return json[key] as String;
}

int _requiredU8(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0 || value > 255) {
    throw SdifModelFormatException(
      '$key must be an integer from 0 to 255',
    );
  }
  return value;
}
