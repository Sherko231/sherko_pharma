import 'package:flutter/foundation.dart' show kReleaseMode;

enum DdiRuntimeProvider {
  interactionChecker,
  sdif,
}

class DdiRuntimeSelection {
  const DdiRuntimeSelection.interactionChecker()
      : provider = DdiRuntimeProvider.interactionChecker,
        sdifBaseUri = null;

  DdiRuntimeSelection.sdif(Uri baseUri)
      : provider = DdiRuntimeProvider.sdif,
        sdifBaseUri = baseUri;

  final DdiRuntimeProvider provider;
  final Uri? sdifBaseUri;

  bool get usesInteractionChecker =>
      provider == DdiRuntimeProvider.interactionChecker;

  bool get usesSdif => provider == DdiRuntimeProvider.sdif;
}

class DdiRuntimeConfig {
  const DdiRuntimeConfig({
    this.providerValue = interactionCheckerValue,
    this.sdifBaseUriValue = defaultSdifBaseUri,
    this.allowSdif = true,
  });

  factory DdiRuntimeConfig.fromEnvironment({
    bool allowSdif = !kReleaseMode,
  }) {
    return DdiRuntimeConfig(
      providerValue: const String.fromEnvironment(
        'DDI_PROVIDER',
        defaultValue: interactionCheckerValue,
      ),
      sdifBaseUriValue: const String.fromEnvironment(
        'SDIF_BASE_URI',
        defaultValue: defaultSdifBaseUri,
      ),
      allowSdif: allowSdif,
    );
  }

  static const String interactionCheckerValue = 'interaction_checker';
  static const String sdifValue = 'sdif';
  static const String defaultSdifBaseUri = 'http://127.0.0.1:3000/';

  final String providerValue;
  final String sdifBaseUriValue;
  final bool allowSdif;

  List<String> get problems {
    final issues = <String>[];
    final provider = providerValue.trim().toLowerCase();

    if (provider != interactionCheckerValue && provider != sdifValue) {
      issues.add(
        'DDI_PROVIDER must be "interaction_checker" or "sdif".',
      );
      return issues;
    }

    if (provider == sdifValue) {
      if (!allowSdif) {
        issues.add(
          'DDI_PROVIDER=sdif is development-only and is not enabled in release mode.',
        );
      }

      final uri = Uri.tryParse(sdifBaseUriValue.trim());
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        issues.add(
          'SDIF_BASE_URI must be a valid HTTP(S) base URI without credentials, query, or fragment.',
        );
      }
    }

    return issues;
  }

  DdiRuntimeSelection get selection {
    final issues = problems;
    if (issues.isNotEmpty) {
      throw StateError(
        'Cannot resolve invalid DDI runtime configuration: ${issues.join(' ')}',
      );
    }

    final provider = providerValue.trim().toLowerCase();
    if (provider == sdifValue) {
      return DdiRuntimeSelection.sdif(Uri.parse(sdifBaseUriValue.trim()));
    }
    return const DdiRuntimeSelection.interactionChecker();
  }
}
