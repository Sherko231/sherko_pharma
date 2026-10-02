import '../data/sdif_client.dart';
import '../domain/sdif_reviewed_identity_models.dart';

class SdifReviewedAtcBridge {
  SdifReviewedAtcBridge({required this.gateway});

  final SdifGateway gateway;

  Future<SdifReviewedAtcResolution> resolveIdentity(
    SdifReviewedScientificIdentity identity,
  ) async {
    final normalized = _validateIdentity(identity);
    final candidates = <String, SdifProviderDrugSelection>{};

    for (final reviewedAtcCode in normalized.reviewedAtcCodes) {
      final results = await gateway.searchDrugByAtc(reviewedAtcCode);
      for (final result in results) {
        final providerAtcCode = result.atcCode.trim();
        if (providerAtcCode != reviewedAtcCode) {
          throw SdifReviewedAtcIntegrityException(
            'SDIF returned ATC "$providerAtcCode" for reviewed ATC '
            '"$reviewedAtcCode".',
          );
        }

        final brandName = result.brandName.trim();
        final substances = result.substances.trim();
        if (brandName.isEmpty || substances.isEmpty) {
          throw const SdifReviewedAtcIntegrityException(
            'SDIF reviewed-ATC lookup returned incomplete provider identity data.',
          );
        }

        final candidate = SdifProviderDrugSelection(
          reviewedAtcCode: reviewedAtcCode,
          brandName: brandName,
          providerAtcCode: providerAtcCode,
          substances: substances,
        );
        candidates[_candidateKey(candidate)] = candidate;
      }
    }

    final resolvedCandidates = List<SdifProviderDrugSelection>.unmodifiable(
      candidates.values,
    );
    final status = switch (resolvedCandidates.length) {
      0 => SdifReviewedAtcResolutionStatus.unmapped,
      1 => SdifReviewedAtcResolutionStatus.resolved,
      _ => SdifReviewedAtcResolutionStatus.ambiguous,
    };

    return SdifReviewedAtcResolution(
      identity: normalized,
      status: status,
      candidates: resolvedCandidates,
    );
  }

  Future<List<SdifReviewedAtcResolution>> resolveIdentities(
    List<SdifReviewedScientificIdentity> identities,
  ) async {
    final results = <SdifReviewedAtcResolution>[];
    for (final identity in identities) {
      results.add(await resolveIdentity(identity));
    }
    return List.unmodifiable(results);
  }

  Future<SdifReviewedIdentityCheckResult> checkResolvedIdentities(
    List<SdifResolvedScientificIdentity> identities,
  ) async {
    if (identities.length < 2 || identities.length > SdifClient.maxCheckDrugs) {
      throw const SdifReviewedAtcInvalidInputException(
        'SDIF reviewed-identity checks require 2 to 10 resolved identities.',
      );
    }

    final providerBrands = <String>[];
    final seenProviderBrands = <String>{};
    for (final identity in identities) {
      _validateIdentity(identity.identity);
      final providerDrug = identity.providerDrug;
      final brandName = providerDrug.brandName.trim();
      final atcCode = providerDrug.providerAtcCode.trim();
      if (brandName.isEmpty || atcCode.isEmpty) {
        throw const SdifReviewedAtcInvalidInputException(
          'Resolved SDIF provider selections must include brand and ATC.',
        );
      }
      if (!seenProviderBrands.add(brandName)) {
        throw const SdifReviewedAtcIntegrityException(
          'Distinct scientific identities resolved to the same SDIF provider brand.',
        );
      }
      providerBrands.add(brandName);
    }

    final result = await gateway.checkInteractions(
      List.unmodifiable(providerBrands),
    );
    _validateBasket(identities, result.basket);

    return SdifReviewedIdentityCheckResult(
      identities: List.unmodifiable(identities),
      providerResult: result,
    );
  }

  void _validateBasket(
    List<SdifResolvedScientificIdentity> expected,
    List<dynamic> actualBasket,
  ) {
    if (actualBasket.length != expected.length) {
      throw SdifReviewedAtcBasketIntegrityException(
        'SDIF basket returned ${actualBasket.length} item(s) for '
        '${expected.length} resolved identities.',
      );
    }

    for (var index = 0; index < expected.length; index++) {
      final providerDrug = expected[index].providerDrug;
      final basketDrug = actualBasket[index];
      if (basketDrug.brand.trim() != providerDrug.brandName.trim() ||
          basketDrug.atcCode.trim() != providerDrug.providerAtcCode.trim()) {
        throw SdifReviewedAtcBasketIntegrityException(
          'SDIF basket item ${index + 1} did not match the reviewed provider '
          'selection.',
        );
      }

      final expectedSubstances = _normalizedSubstanceSet(
        providerDrug.substances.split(', '),
      );
      final actualSubstances = _normalizedSubstanceSet(
        basketDrug.substances,
      );
      if (!_sameStringLists(expectedSubstances, actualSubstances)) {
        throw SdifReviewedAtcBasketIntegrityException(
          'SDIF basket item ${index + 1} returned a different active-substance '
          'set than the reviewed ATC selection.',
        );
      }
    }
  }

  SdifReviewedScientificIdentity _validateIdentity(
    SdifReviewedScientificIdentity identity,
  ) {
    if (identity.scientificIngredientId <= 0) {
      throw const SdifReviewedAtcInvalidInputException(
        'Scientific ingredient ID must be positive.',
      );
    }
    final preferredName = identity.preferredName.trim();
    if (preferredName.isEmpty) {
      throw const SdifReviewedAtcInvalidInputException(
        'Scientific preferred name must not be blank.',
      );
    }
    if (identity.reviewedAtcCodes.isEmpty) {
      throw const SdifReviewedAtcInvalidInputException(
        'At least one reviewed ATC code is required.',
      );
    }

    final reviewedAtcCodes = <String>[];
    final seenAtcCodes = <String>{};
    for (final rawAtcCode in identity.reviewedAtcCodes) {
      final atcCode = rawAtcCode.trim();
      if (atcCode.isEmpty || atcCode.length > SdifClient.maxAtcCodeLength) {
        throw const SdifReviewedAtcInvalidInputException(
          'Reviewed ATC codes must be nonblank and within the SDIF transport bound.',
        );
      }
      if (seenAtcCodes.add(atcCode)) {
        reviewedAtcCodes.add(atcCode);
      }
    }

    return SdifReviewedScientificIdentity(
      scientificIngredientId: identity.scientificIngredientId,
      preferredName: preferredName,
      reviewedAtcCodes: List.unmodifiable(reviewedAtcCodes),
    );
  }

  static String _candidateKey(SdifProviderDrugSelection candidate) {
    return '${candidate.providerAtcCode}\u0000${candidate.brandName}\u0000'
        '${candidate.substances}';
  }

  static List<String> _normalizedSubstanceSet(Iterable<String> values) {
    final normalized = values
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    return normalized;
  }

  static bool _sameStringLists(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

sealed class SdifReviewedAtcBridgeException implements Exception {
  const SdifReviewedAtcBridgeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class SdifReviewedAtcInvalidInputException
    extends SdifReviewedAtcBridgeException {
  const SdifReviewedAtcInvalidInputException(super.message);
}

class SdifReviewedAtcIntegrityException
    extends SdifReviewedAtcBridgeException {
  const SdifReviewedAtcIntegrityException(super.message);
}

class SdifReviewedAtcBasketIntegrityException
    extends SdifReviewedAtcBridgeException {
  const SdifReviewedAtcBasketIntegrityException(super.message);
}
