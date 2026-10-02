import 'dart:convert';
import 'dart:io';

import 'package:sherko_pharma/features/interactions/application/sdif_reviewed_atc_bridge.dart';
import 'package:sherko_pharma/features/interactions/data/sdif_client.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_models.dart';
import 'package:sherko_pharma/features/interactions/domain/sdif_reviewed_identity_models.dart';

const _currentReviewedIdentities = <SdifReviewedScientificIdentity>[
  SdifReviewedScientificIdentity(
    scientificIngredientId: 1,
    preferredName: 'Amoxicillin',
    reviewedAtcCodes: ['J01CA04'],
  ),
  SdifReviewedScientificIdentity(
    scientificIngredientId: 2,
    preferredName: 'Caffeine',
    reviewedAtcCodes: ['N06BC01'],
  ),
  SdifReviewedScientificIdentity(
    scientificIngredientId: 3,
    preferredName: 'Paracetamol',
    reviewedAtcCodes: ['N02BE01'],
  ),
];

Future<void> main(List<String> args) async {
  final baseUri = _readBaseUri(args);
  final client = SdifClient(
    baseUri: baseUri,
    timeout: const Duration(seconds: 10),
  );
  final bridge = SdifReviewedAtcBridge(gateway: client);

  try {
    final resolutions = await bridge.resolveIdentities(
      _currentReviewedIdentities,
    );
    final resolved = <SdifResolvedScientificIdentity>[];
    final statuses = <String, int>{};

    for (final resolution in resolutions) {
      final statusName = resolution.status.name;
      statuses[statusName] = (statuses[statusName] ?? 0) + 1;
      final resolvedIdentity = resolution.resolvedIdentity;
      if (resolvedIdentity != null) {
        resolved.add(resolvedIdentity);
      }
    }

    if (resolved.length != _currentReviewedIdentities.length) {
      _fail(
        'Live SDIF acceptance requires all current reviewed identities to '
        'resolve uniquely. Statuses: ${jsonEncode(statuses)}',
      );
    }

    final checked = await bridge.checkResolvedIdentities(resolved);
    final familyCounts = <String, int>{
      for (final family in SdifInteractionFamily.values) family.name: 0,
    };
    final severityScoreCounts = <String, int>{};
    for (final hit in checked.providerResult.interactions) {
      familyCounts[hit.family.name] = (familyCounts[hit.family.name] ?? 0) + 1;
      final score = hit.severityScore.toString();
      severityScoreCounts[score] = (severityScoreCounts[score] ?? 0) + 1;
    }

    final output = <String, Object?>{
      'base_uri': baseUri.toString(),
      'reviewed_identity_count': _currentReviewedIdentities.length,
      'resolved_identity_count': resolved.length,
      'resolution_status_counts': statuses,
      'basket_integrity_verified': true,
      'basket_count': checked.providerResult.basket.length,
      'interaction_hit_count': checked.providerResult.interactions.length,
      'interaction_family_counts': familyCounts,
      'provider_native_severity_score_counts': severityScoreCounts,
      'absence_of_hits_is_not_a_safety_classification': true,
    };

    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(output),
    );
  } on Object catch (error) {
    _fail('Live SDIF acceptance failed: $error');
  } finally {
    client.close();
  }
}

Uri _readBaseUri(List<String> args) {
  var value = 'http://127.0.0.1:3000/';
  for (var index = 0; index < args.length; index++) {
    if (args[index] == '--base-url') {
      if (index + 1 >= args.length) {
        _fail('--base-url requires a value.');
      }
      value = args[index + 1];
      index += 1;
      continue;
    }
    _fail('Unknown argument: ${args[index]}');
  }

  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    _fail('--base-url must be an absolute HTTP(S) URI.');
  }
  return uri;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(2);
}
