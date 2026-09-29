import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sherko_pharma/features/interactions/data/interaction_checker_client.dart';
import 'package:sherko_pharma/features/interactions/domain/interaction_check_models.dart';

void main() {
  group('InteractionCheckerClient', () {
    test('POSTs trimmed items and parses typed evidence/source metadata', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode(_checkPayload()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = InteractionCheckerClient(
        httpClient: client,
        baseUri: Uri.parse('https://example.test/api/v1'),
      );

      final result = await api.checkInteractions(
        const [' lisinopril ', 'ibuprofen'],
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.toString(),
        'https://example.test/api/v1/checks',
      );
      expect(
        capturedRequest.headers['content-type'],
        contains('application/json'),
      );
      expect(
        jsonDecode(capturedRequest.body),
        {
          'items': ['lisinopril', 'ibuprofen'],
        },
      );

      expect(result.items, hasLength(2));
      expect(result.items.first.substance.id, 'lisinopril');
      expect(result.items.first.substance.kind, InteractionSubstanceKind.drug);
      expect(result.items[1].matchedOn, 'Advil');
      expect(result.unresolved, isEmpty);
      expect(result.pairs, hasLength(1));

      final pair = result.pairs.single;
      expect(pair.severity, InteractionSeverity.moderate);
      expect(pair.severityLabel, 'Moderate');
      expect(pair.a.id, 'lisinopril');
      expect(pair.b.id, 'ibuprofen');
      expect(pair.evidence, hasLength(1));

      final evidence = pair.evidence.single;
      expect(evidence.from, 'lisinopril');
      expect(evidence.about, 'ibuprofen');
      expect(
        evidence.section,
        InteractionEvidenceSection.drugInteractions,
      );
      expect(evidence.severity, InteractionEvidenceSeverity.moderate);
      expect(evidence.matchKind, InteractionMatchKind.classMatch);
      expect(evidence.source.type, InteractionSourceType.fdaLabel);
      expect(
        evidence.source.url.host,
        'dailymed.nlm.nih.gov',
      );
      expect(
        evidence.source.effectiveDate,
        DateTime.parse('2025-01-02'),
      );

      expect(
        result.summary[InteractionSeverity.moderate],
        1,
      );
      expect(
        result.data.labelExportDate,
        DateTime.parse('2026-09-03'),
      );
      expect(
        result.data.generatedAt,
        DateTime.parse('2026-09-07'),
      );
      expect(result.disclaimer, startsWith('Not medical advice.'));
      expect(
        result.attribution.url.toString(),
        'https://interaction-checker.com',
      );
      expect(result.attribution.license, 'Free with attribution');
    });

    test('parses every documented pair severity explicitly', () async {
      for (final entry in {
        'major': InteractionSeverity.major,
        'moderate': InteractionSeverity.moderate,
        'minor': InteractionSeverity.minor,
        'none': InteractionSeverity.none,
        'unknown': InteractionSeverity.unknown,
      }.entries) {
        final client = MockClient((_) async {
          return http.Response(
            jsonEncode(_checkPayload(pairSeverity: entry.key)),
            200,
          );
        });
        final api = InteractionCheckerClient(httpClient: client);

        final result = await api.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        );

        expect(result.pairs.single.severity, entry.value);
      }
    });

    test('keeps unresolved items and suggestions without auto-selecting', () async {
      final payload = _checkPayload();
      payload['unresolved'] = [
        {
          'query': 'ibuprofenn',
          'suggestions': [
            _substance(
              id: 'ibuprofen',
              name: 'Ibuprofen',
              url: 'https://interaction-checker.com/drugs/ibuprofen',
            ),
          ],
        },
      ];

      final api = InteractionCheckerClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      final result = await api.checkInteractions(
        const ['lisinopril', 'ibuprofenn'],
      );

      expect(result.unresolved, hasLength(1));
      expect(result.unresolved.single.query, 'ibuprofenn');
      expect(result.unresolved.single.suggestions, hasLength(1));
      expect(
        result.unresolved.single.suggestions.single.id,
        'ibuprofen',
      );
    });

    test('rejects invalid local requests without using the network', () async {
      var calls = 0;
      final api = InteractionCheckerClient(
        httpClient: MockClient((_) async {
          calls += 1;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.checkInteractions(const ['lisinopril']),
        throwsA(isA<InteractionCheckerInvalidRequestException>()),
      );
      await expectLater(
        api.checkInteractions(const ['lisinopril', '   ']),
        throwsA(isA<InteractionCheckerInvalidRequestException>()),
      );
      await expectLater(
        api.checkInteractions(['lisinopril', List.filled(81, 'x').join()]),
        throwsA(isA<InteractionCheckerInvalidRequestException>()),
      );
      await expectLater(
        api.checkInteractions(List.filled(11, 'lisinopril')),
        throwsA(isA<InteractionCheckerInvalidRequestException>()),
      );

      expect(calls, 0);
    });

    test('maps 429 Retry-After without retrying', () async {
      var calls = 0;
      final api = InteractionCheckerClient(
        httpClient: MockClient((_) async {
          calls += 1;
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'rate_limited',
                'message': 'Too many requests',
              },
            }),
            429,
            headers: {'retry-after': '30'},
          );
        }),
      );

      try {
        await api.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        );
        fail('Expected rate-limit exception');
      } on InteractionCheckerRateLimitException catch (error) {
        expect(error.retryAfter, const Duration(seconds: 30));
        expect(error.providerCode, 'rate_limited');
        expect(error.providerMessage, 'Too many requests');
      }

      expect(calls, 1);
    });

    test('preserves provider error code/message on non-429 errors', () async {
      final api = InteractionCheckerClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'unavailable',
                'message': 'Temporarily unavailable',
              },
            }),
            503,
          );
        }),
      );

      try {
        await api.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        );
        fail('Expected API exception');
      } on InteractionCheckerApiException catch (error) {
        expect(error.statusCode, 503);
        expect(error.providerCode, 'unavailable');
        expect(error.providerMessage, 'Temporarily unavailable');
      }
    });

    test('reports malformed JSON and missing required fields', () async {
      final malformed = InteractionCheckerClient(
        httpClient: MockClient(
          (_) async => http.Response('not-json', 200),
        ),
      );

      await expectLater(
        malformed.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        ),
        throwsA(isA<InteractionCheckerMalformedResponseException>()),
      );

      final missingFieldPayload = _checkPayload()..remove('disclaimer');
      final missingField = InteractionCheckerClient(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(missingFieldPayload),
            200,
          ),
        ),
      );

      await expectLater(
        missingField.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        ),
        throwsA(isA<InteractionCheckerMalformedResponseException>()),
      );
    });

    test('reports future unsupported pair severity explicitly', () async {
      final api = InteractionCheckerClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode(_checkPayload(pairSeverity: 'critical')),
            200,
          );
        }),
      );

      try {
        await api.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        );
        fail('Expected unsupported response value');
      } on InteractionCheckerUnsupportedResponseValueException catch (error) {
        expect(error.field, 'pair.severity');
        expect(error.value, 'critical');
      }
    });

    test('does not allow unknown evidence severity', () async {
      final payload = _checkPayload();
      final pairs = payload['pairs']! as List<dynamic>;
      final pair = pairs.single as Map<String, dynamic>;
      final evidence = pair['evidence']! as List<dynamic>;
      final firstEvidence = evidence.single as Map<String, dynamic>;
      firstEvidence['severity'] = 'unknown';

      final api = InteractionCheckerClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      await expectLater(
        api.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        ),
        throwsA(
          isA<InteractionCheckerUnsupportedResponseValueException>(),
        ),
      );
    });

    test('reports timeout separately from transport failure', () async {
      final timeoutApi = InteractionCheckerClient(
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(jsonEncode(_checkPayload()), 200);
        }),
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        timeoutApi.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        ),
        throwsA(isA<InteractionCheckerTimeoutException>()),
      );

      final transportApi = InteractionCheckerClient(
        httpClient: MockClient((_) async {
          throw http.ClientException('offline');
        }),
      );

      await expectLater(
        transportApi.checkInteractions(
          const ['lisinopril', 'ibuprofen'],
        ),
        throwsA(isA<InteractionCheckerTransportException>()),
      );
    });

    test('ignores additive unknown optional fields', () async {
      final payload = _checkPayload();
      payload['futureTopLevelField'] = {'ignored': true};
      final pair =
          (payload['pairs']! as List<dynamic>).single as Map<String, dynamic>;
      pair['futurePairField'] = 'ignored';
      final summary = payload['summary']! as Map<String, dynamic>;
      summary['futureSeverity'] = 99;

      final api = InteractionCheckerClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      final result = await api.checkInteractions(
        const ['lisinopril', 'ibuprofen'],
      );

      expect(result.pairs.single.severity, InteractionSeverity.moderate);
      expect(result.summary.length, 5);
    });
  });
}

Map<String, dynamic> _checkPayload({
  String pairSeverity = 'moderate',
}) {
  final hasEvidence = pairSeverity != 'unknown';
  final evidenceSeverity = switch (pairSeverity) {
    'major' => 'major',
    'moderate' => 'moderate',
    'minor' => 'minor',
    'none' => 'none',
    _ => 'moderate',
  };

  return {
    'items': [
      {
        ..._substance(
          id: 'lisinopril',
          name: 'Lisinopril',
          url: 'https://interaction-checker.com/drugs/lisinopril',
        ),
        'query': 'lisinopril',
      },
      {
        ..._substance(
          id: 'ibuprofen',
          name: 'Ibuprofen',
          url: 'https://interaction-checker.com/drugs/ibuprofen',
        ),
        'query': 'Advil',
        'matchedOn': 'Advil',
      },
    ],
    'unresolved': <dynamic>[],
    'pairs': [
      {
        'a': _substance(
          id: 'lisinopril',
          name: 'Lisinopril',
          url: 'https://interaction-checker.com/drugs/lisinopril',
        ),
        'b': _substance(
          id: 'ibuprofen',
          name: 'Ibuprofen',
          url: 'https://interaction-checker.com/drugs/ibuprofen',
        ),
        'severity': pairSeverity,
        'severityLabel':
            pairSeverity[0].toUpperCase() + pairSeverity.substring(1),
        'url':
            'https://interaction-checker.com/?d=lisinopril,ibuprofen',
        'page':
            'https://interaction-checker.com/interactions/ibuprofen-and-lisinopril',
        'evidence': hasEvidence
            ? [
                {
                  'from': 'lisinopril',
                  'about': 'ibuprofen',
                  'section': 'drug_interactions',
                  'sectionLabel': 'Drug interactions',
                  'severity': evidenceSeverity,
                  'quote': 'Example sourced label sentence.',
                  'matchedTerm': 'nsaids',
                  'matchKind': 'class',
                  'source': {
                    'type': 'fda_label',
                    'name': 'Zestril prescribing label',
                    'url':
                        'https://dailymed.nlm.nih.gov/dailymed/lookup.cfm?setid=test',
                    'effectiveDate': '2025-01-02',
                  },
                },
              ]
            : <dynamic>[],
      },
    ],
    'summary': {
      'major': pairSeverity == 'major' ? 1 : 0,
      'moderate': pairSeverity == 'moderate' ? 1 : 0,
      'minor': pairSeverity == 'minor' ? 1 : 0,
      'none': pairSeverity == 'none' ? 1 : 0,
      'unknown': pairSeverity == 'unknown' ? 1 : 0,
    },
    'data': {
      'labelExportDate': '2026-09-03',
      'generatedAt': '2026-09-07',
    },
    'disclaimer': 'Not medical advice. Example disclaimer.',
    'attribution': {
      'text': 'Data from Interaction Checker',
      'url': 'https://interaction-checker.com',
      'license': 'Free with attribution',
    },
  };
}

Map<String, dynamic> _substance({
  required String id,
  required String name,
  required String url,
}) {
  return {
    'id': id,
    'name': name,
    'kind': 'drug',
    'url': url,
  };
}
