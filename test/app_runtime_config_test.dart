import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/app/app_runtime.dart';

void main() {
  test('runtime configuration requires HTTPS URL and publishable key', () {
    const missing = AppRuntimeConfig(
      supabaseUrl: '',
      publishableKey: '',
    );
    expect(missing.problems, hasLength(2));

    const insecure = AppRuntimeConfig(
      supabaseUrl: 'http://example.test',
      publishableKey: 'publishable',
    );
    expect(
      insecure.problems,
      contains('SUPABASE_URL must be a valid HTTPS project URL.'),
    );

    const valid = AppRuntimeConfig(
      supabaseUrl: 'https://project.example.test',
      publishableKey: 'publishable',
    );
    expect(valid.problems, isEmpty);
  });
}
