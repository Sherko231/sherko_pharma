import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/sdif_models.dart';

abstract interface class SdifGateway {
  Future<List<SdifDrugSearchResult>> searchDrugByAtc(String atcCode);

  Future<SdifCheckResult> checkInteractions(List<String> drugs);
}

class SdifClient implements SdifGateway {
  SdifClient({
    required Uri baseUri,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        baseUri = _normalizeBaseUri(baseUri) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Timeout must be positive',
      );
    }
  }

  static const int maxCheckDrugs = 10;
  static const int maxDrugQueryLength = 80;
  static const int maxAtcCodeLength = 32;

  final http.Client _client;
  final bool _ownsClient;
  final Uri baseUri;
  final Duration timeout;

  @override
  Future<List<SdifDrugSearchResult>> searchDrugByAtc(
    String atcCode,
  ) async {
    final normalizedAtc = _validateAtcCode(atcCode);
    final requestUri = baseUri.resolve('api/search-drugs').replace(
      queryParameters: {'atc': normalizedAtc},
    );

    final response = await _send(
      () => _client.get(
        requestUri,
        headers: const {'Accept': 'application/json'},
      ),
    );

    _ensureSuccess(response);
    return _parseSearchResponse(response.body);
  }

  @override
  Future<SdifCheckResult> checkInteractions(
    List<String> drugs,
  ) async {
    final normalizedDrugs = _validateDrugs(drugs);
    final requestUri = baseUri.resolve('api/check');

    final response = await _send(
      () => _client.post(
        requestUri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'drugs': normalizedDrugs}),
      ),
    );

    _ensureSuccess(response);
    return _parseCheckResponse(response.body);
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw SdifTimeoutException(timeout);
    } on http.ClientException catch (error) {
      throw SdifTransportException(error.message);
    } catch (_) {
      throw const SdifTransportException();
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SdifApiException(statusCode: response.statusCode);
    }
  }

  List<SdifDrugSearchResult> _parseSearchResponse(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const SdifMalformedResponseException();
    }

    if (decoded is! List) {
      throw const SdifMalformedResponseException();
    }

    try {
      return List.unmodifiable(
        decoded.map(
          (value) => SdifDrugSearchResult.fromJson(
            _valueAsMap(value),
          ),
        ),
      );
    } on SdifModelFormatException {
      throw const SdifMalformedResponseException();
    } catch (_) {
      throw const SdifMalformedResponseException();
    }
  }

  SdifCheckResult _parseCheckResponse(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const SdifMalformedResponseException();
    }

    if (decoded is! Map) {
      throw const SdifMalformedResponseException();
    }

    try {
      return SdifCheckResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on SdifUnsupportedValueException catch (error) {
      throw SdifUnsupportedResponseValueException(
        field: error.field,
        value: error.value,
      );
    } on SdifModelFormatException {
      throw const SdifMalformedResponseException();
    } catch (_) {
      throw const SdifMalformedResponseException();
    }
  }

  String _validateAtcCode(String atcCode) {
    final trimmed = atcCode.trim();
    if (trimmed.isEmpty) {
      throw const SdifInvalidRequestException(
        'ATC code must not be blank.',
      );
    }
    if (trimmed.length > maxAtcCodeLength) {
      throw const SdifInvalidRequestException(
        'ATC code is outside the local transport bound.',
      );
    }
    return trimmed;
  }

  List<String> _validateDrugs(List<String> drugs) {
    if (drugs.length < 2 || drugs.length > maxCheckDrugs) {
      throw const SdifInvalidRequestException(
        'SDIF checks require 2 to 10 provider-resolved drug inputs.',
      );
    }

    final normalized = <String>[];
    for (final drug in drugs) {
      final trimmed = drug.trim();
      if (trimmed.isEmpty) {
        throw const SdifInvalidRequestException(
          'SDIF drug inputs must not be blank.',
        );
      }
      if (trimmed.length > maxDrugQueryLength) {
        throw const SdifInvalidRequestException(
          'SDIF drug inputs must be at most 80 characters.',
        );
      }
      normalized.add(trimmed);
    }
    return List.unmodifiable(normalized);
  }

  static Uri _normalizeBaseUri(Uri uri) {
    if (!uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'Base URI must be an absolute HTTP(S) URI',
      );
    }

    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(
      path: path,
      query: null,
      fragment: null,
    );
  }

  static Map<String, dynamic> _valueAsMap(dynamic value) {
    if (value is! Map) {
      throw const SdifMalformedResponseException();
    }
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      throw const SdifMalformedResponseException();
    }
  }
}

sealed class SdifException implements Exception {
  const SdifException();
}

class SdifInvalidRequestException extends SdifException {
  const SdifInvalidRequestException(this.message);

  final String message;

  @override
  String toString() => 'SdifInvalidRequestException: $message';
}

class SdifTimeoutException extends SdifException {
  const SdifTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() => 'SdifTimeoutException after $timeout';
}

class SdifTransportException extends SdifException {
  const SdifTransportException([this.message]);

  final String? message;

  @override
  String toString() => message == null
      ? 'SdifTransportException'
      : 'SdifTransportException: $message';
}

class SdifApiException extends SdifException {
  const SdifApiException({required this.statusCode});

  final int statusCode;
}

class SdifMalformedResponseException extends SdifException {
  const SdifMalformedResponseException();
}

class SdifUnsupportedResponseValueException extends SdifException {
  const SdifUnsupportedResponseValueException({
    required this.field,
    required this.value,
  });

  final String field;
  final String value;
}
