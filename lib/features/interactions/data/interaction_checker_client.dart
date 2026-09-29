import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/interaction_check_models.dart';

abstract interface class InteractionCheckGateway {
  Future<InteractionCheckResult> checkInteractions(List<String> items);
}

class InteractionCheckerClient implements InteractionCheckGateway {
  InteractionCheckerClient({
    http.Client? httpClient,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 10),
  })  : _client = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        baseUri = _normalizeBaseUri(baseUri ?? defaultBaseUri) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Timeout must be positive',
      );
    }
  }

  static final Uri defaultBaseUri = Uri.parse(
    'https://interaction-checker.com/api/v1/',
  );

  final http.Client _client;
  final bool _ownsClient;
  final Uri baseUri;
  final Duration timeout;

  Future<InteractionCheckResult> checkInteractions(
    List<String> items,
  ) async {
    final normalizedItems = _validateItems(items);
    final requestUri = baseUri.resolve('checks');

    late final http.Response response;
    try {
      response = await _client
          .post(
            requestUri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'items': normalizedItems}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw InteractionCheckerTimeoutException(timeout);
    } on http.ClientException catch (error) {
      throw InteractionCheckerTransportException(error.message);
    } catch (_) {
      throw const InteractionCheckerTransportException();
    }

    if (response.statusCode == 429) {
      final providerError = _readProviderError(response.body);
      throw InteractionCheckerRateLimitException(
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
        providerCode: providerError?.code,
        providerMessage: providerError?.message,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final providerError = _readProviderError(response.body);
      throw InteractionCheckerApiException(
        statusCode: response.statusCode,
        providerCode: providerError?.code,
        providerMessage: providerError?.message,
      );
    }

    return _parseSuccessfulResponse(response.body);
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  List<String> _validateItems(List<String> items) {
    if (items.length < 2 || items.length > 10) {
      throw const InteractionCheckerInvalidRequestException(
        'Interaction checks require 2 to 10 items.',
      );
    }

    final normalized = <String>[];
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        throw const InteractionCheckerInvalidRequestException(
          'Interaction check items must not be blank.',
        );
      }
      if (trimmed.length > 80) {
        throw const InteractionCheckerInvalidRequestException(
          'Interaction check items must be at most 80 characters.',
        );
      }
      normalized.add(trimmed);
    }
    return List.unmodifiable(normalized);
  }

  InteractionCheckResult _parseSuccessfulResponse(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const InteractionCheckerMalformedResponseException();
    }

    if (decoded is! Map) {
      throw const InteractionCheckerMalformedResponseException();
    }

    try {
      return InteractionCheckResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on InteractionUnsupportedValueException catch (error) {
      throw InteractionCheckerUnsupportedResponseValueException(
        field: error.field,
        value: error.value,
      );
    } on InteractionModelFormatException {
      throw const InteractionCheckerMalformedResponseException();
    } catch (_) {
      throw const InteractionCheckerMalformedResponseException();
    }
  }

  static Uri _normalizeBaseUri(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'Base URI must be absolute',
      );
    }

    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(
      path: path,
      query: null,
      fragment: null,
    );
  }

  static Duration? _parseRetryAfter(String? rawValue) {
    if (rawValue == null) {
      return null;
    }
    final seconds = int.tryParse(rawValue.trim());
    if (seconds == null || seconds < 0) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  static _ProviderError? _readProviderError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return null;
      }
      final error = decoded['error'];
      if (error is! Map) {
        return null;
      }
      final code = error['code'];
      final message = error['message'];
      return _ProviderError(
        code: code is String ? code : null,
        message: message is String ? message : null,
      );
    } catch (_) {
      return null;
    }
  }
}

sealed class InteractionCheckerException implements Exception {
  const InteractionCheckerException();
}

class InteractionCheckerInvalidRequestException
    extends InteractionCheckerException {
  const InteractionCheckerInvalidRequestException(this.message);

  final String message;

  @override
  String toString() =>
      'InteractionCheckerInvalidRequestException: $message';
}

class InteractionCheckerTimeoutException
    extends InteractionCheckerException {
  const InteractionCheckerTimeoutException(this.timeout);

  final Duration timeout;

  @override
  String toString() =>
      'InteractionCheckerTimeoutException after $timeout';
}

class InteractionCheckerTransportException
    extends InteractionCheckerException {
  const InteractionCheckerTransportException([this.message]);

  final String? message;

  @override
  String toString() => message == null
      ? 'InteractionCheckerTransportException'
      : 'InteractionCheckerTransportException: $message';
}

class InteractionCheckerRateLimitException
    extends InteractionCheckerException {
  const InteractionCheckerRateLimitException({
    required this.retryAfter,
    this.providerCode,
    this.providerMessage,
  });

  final Duration? retryAfter;
  final String? providerCode;
  final String? providerMessage;
}

class InteractionCheckerApiException
    extends InteractionCheckerException {
  const InteractionCheckerApiException({
    required this.statusCode,
    this.providerCode,
    this.providerMessage,
  });

  final int statusCode;
  final String? providerCode;
  final String? providerMessage;
}

class InteractionCheckerMalformedResponseException
    extends InteractionCheckerException {
  const InteractionCheckerMalformedResponseException();
}

class InteractionCheckerUnsupportedResponseValueException
    extends InteractionCheckerException {
  const InteractionCheckerUnsupportedResponseValueException({
    required this.field,
    required this.value,
  });

  final String field;
  final String value;
}

class _ProviderError {
  const _ProviderError({
    this.code,
    this.message,
  });

  final String? code;
  final String? message;
}
