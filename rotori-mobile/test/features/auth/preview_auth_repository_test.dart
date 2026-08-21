import 'package:flutter_test/flutter_test.dart';

import 'package:rotori/features/auth/preview_auth_repository.dart';

void main() {
  test('preview auth repository Supabase olmadan kayıt ve OAuth çağrılarını tamamlar',
      () async {
    final repository = PreviewAuthRepository();

    await expectLater(
      repository.signUpWithPassword(
        email: 'preview@rotori.app',
        password: 'Strong123!',
      ),
      completes,
    );
    await expectLater(repository.signInWithGoogle(), completes);
    await expectLater(repository.signInWithApple(), completes);
  });
}
