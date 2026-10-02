import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';

void main() {
  group('SdifClient', () {
    test('GETs exact ATC lookup and parses typed search result', () async {
      late http.Request capturedRequest;
      final api = SdifClient(
        baseUri: Uri.parse('https://example.test/sdif'),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode([
              {
                'brand_name': 'Example Brand',
                'atc_code': 'J01CA04',
                'substances': 'Amoxicillin',
              },
            ]),
            200,
          );
        }),
      );

      final result = await api.searchDrugByAtc(' J01CA04 ');

      expect(capturedRequest.method, 'GET');
      expect(
        capturedRequest.url.toString(),
        'https://example.test/sdif/api/search-drugs?atc=J01CA04',
      );
      expect(result, hasLength(1));
      expect(result.single.brandName, 'Example Brand');
      expect(result.single.atcCode, 'J01CA04');
      expect(result.single.substances, 'Amoxicillin');
    });

    test('POSTs trimmed drug inputs and preserves all interaction families', () async {
      late http.Request capturedRequest;
      final api = SdifClient(
        baseUri: Uri.parse('http://127.0.0.1:3000'),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(jsonEncode(_checkPayload()), 200);
        }),
      );

      final result = await api.checkInteractions(
        const [' Example A ', 'Example B'],
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.toString(),
        'http://127.0.0.1:3000/api/check',
      );
      expect(
        jsonDecode(capturedRequest.body),
        {
          'drugs': ['Example A', 'Example B'],
        },
      );
      expect(result.basket, hasLength(2));
      expect(result.basket.first.brand, 'Example A®');
      expect(result.basket.first.substances, ['alpha']);
      expect(result.interactions, hasLength(4));
      expect(
        result.interactions.map((hit) => hit.family).toList(),
        [
          SdifInteractionFamily.substance,
          SdifInteractionFamily.classLevel,
          SdifInteractionFamily.cyp,
          SdifInteractionFamily.epha,
        ],
      );
      expect(
        result.interactions.map((hit) => hit.severityScore).toList(),
        [3, 2, 1, 0],
      );
      expect(result.interactions.first.severityLabel, 'Kontraindiziert');
      expect(result.interactions.first.severityIndicator, '###');
      expect(result.interactions.first.source, 'Swissmedic FI');
      expect(result.interactions.last.source, 'EPha');
    });

    test('accepts an empty interaction list without inventing a classification', () async {
      final payload = _checkPayload()..['interactions'] = <dynamic>[];
      final api = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      final result = await api.checkInteractions(
        const ['Example A', 'Example B'],
      );

      expect(result.basket, hasLength(2));
      expect(result.interactions, isEmpty);
    });

    test('ignores additive unknown response fields', () async {
      final payload = _checkPayload();
      payload['future_top_level'] = true;
      final interaction =
          (payload['interactions']! as List<dynamic>).first as Map<String, dynamic>;
      interaction['future_interaction_field'] = {'ignored': true};

      final api = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      final result = await api.checkInteractions(
        const ['Example A', 'Example B'],
      );

      expect(result.interactions.first.family, SdifInteractionFamily.substance);
    });

    test('rejects invalid local requests without using the network', () async {
      var calls = 0;
      final api = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient((_) async {
          calls += 1;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        api.searchDrugByAtc('   '),
        throwsA(isA<SdifInvalidRequestException>()),
      );
      await expectLater(
        api.checkInteractions(const ['Only one']),
        throwsA(isA<SdifInvalidRequestException>()),
      );
      await expectLater(
        api.checkInteractions(const ['Example A', '   ']),
        throwsA(isA<SdifInvalidRequestException>()),
      );
      await expectLater(
        api.checkInteractions(
          ['Example A', List.filled(81, 'x').join()],
        ),
        throwsA(isA<SdifInvalidRequestException>()),
      );
      await expectLater(
        api.checkInteractions(List.filled(11, 'Example')),
        throwsA(isA<SdifInvalidRequestException>()),
      );

      expect(calls, 0);
    });

    test('rejects malformed JSON and missing required fields', () async {
      final malformed = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient(
          (_) async => http.Response('not-json', 200),
        ),
      );

      await expectLater(
        malformed.checkInteractions(const ['Example A', 'Example B']),
        throwsA(isA<SdifMalformedResponseException>()),
      );

      final missingFieldPayload = _checkPayload();
      final interaction =
          (missingFieldPayload['interactions']! as List<dynamic>).first
              as Map<String, dynamic>;
      interaction.remove('severity_score');
      final missingField = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(missingFieldPayload), 200),
        ),
      );

      await expectLater(
        missingField.checkInteractions(const ['Example A', 'Example B']),
        throwsA(isA<SdifMalformedResponseException>()),
      );
    });

    test('reports unsupported future interaction family explicitly', () async {
      final payload = _checkPayload();
      final interaction =
          (payload['interactions']! as List<dynamic>).first as Map<String, dynamic>;
      interaction['interaction_type'] = 'future-family';
      final api = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(payload), 200),
        ),
      );

      try {
        await api.checkInteractions(const ['Example A', 'Example B']);
        fail('Expected unsupported response value');
      } on SdifUnsupportedResponseValueException catch (error) {
        expect(error.field, 'interaction_type');
        expect(error.value, 'future-family');
      }
    });

    test('reports non-2xx API status without parsing provider content', () async {
      final api = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient(
          (_) async => http.Response('provider unavailable', 503),
        ),
      );

      try {
        await api.checkInteractions(const ['Example A', 'Example B']);
        fail('Expected API exception');
      } on SdifApiException catch (error) {
        expect(error.statusCode, 503);
      }
    });

    test('reports timeout separately from transport failure', () async {
      final timeoutApi = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        timeout: const Duration(milliseconds: 1),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response(jsonEncode(_checkPayload()), 200);
        }),
      );

      await expectLater(
        timeoutApi.checkInteractions(const ['Example A', 'Example B']),
        throwsA(isA<SdifTimeoutException>()),
      );

      final transportApi = SdifClient(
        baseUri: Uri.parse('https://example.test/'),
        httpClient: MockClient((_) async {
          throw http.ClientException('offline');
        }),
      );

      await expectLater(
        transportApi.checkInteractions(const ['Example A', 'Example B']),
        throwsA(isA<SdifTransportException>()),
      );
    });

    test('rejects non-HTTP absolute base URIs', () {
      expect(
        () => SdifClient(baseUri: Uri.parse('file:///tmp/sdif')),
        throwsArgumentError,
      );
    });
  });
}

Map<String, dynamic> _checkPayload() {
  return {
    'basket': [
      {
        'brand': 'Example A®',
        'atc_code': 'A01AA01',
        'substances': ['alpha'],
      },
      {
        'brand': 'Example B®',
        'atc_code': 'B01BB02',
        'substances': ['beta'],
      },
    ],
    'interactions': [
      _interaction(
        type: 'substance',
        score: 3,
        label: 'Kontraindiziert',
        indicator: '###',
        source: 'Swissmedic FI',
      ),
      _interaction(
        type: 'class-level',
        score: 2,
        label: 'Schwerwiegend',
        indicator: '##',
        source: 'Swissmedic FI',
      ),
      _interaction(
        type: 'CYP',
        score: 1,
        label: 'Vorsicht',
        indicator: '#',
        source: 'Swissmedic FI',
      ),
      _interaction(
        type: 'epha',
        score: 0,
        label: 'Keine Einstufung',
        indicator: '-',
        source: 'EPha',
      ),
    ],
  };
}

Map<String, dynamic> _interaction({
  required String type,
  required int score,
  required String label,
  required String indicator,
  required String source,
}) {
  return {
    'drug_a': 'Example A®',
    'drug_a_atc': 'A01AA01',
    'drug_a_route': 'p.o.',
    'drug_b': 'Example B®',
    'drug_b_atc': 'B01BB02',
    'drug_b_route': '',
    'interaction_type': type,
    'severity_score': score,
    'severity_label': label,
    'severity_indicator': indicator,
    'keyword': 'beta',
    'description': 'Provider-native interaction description.',
    'explanation': 'Provider-native explanation.',
    'source': source,
    'combo_hint': '',
  };
}
