import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:rotori/features/auth/auth_repository.dart';
import 'package:rotori/features/auth/auth_screen.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
      : super(
          SupabaseClient(
            'https://example.supabase.co',
            'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  String? signedUpEmail;
  String? signedUpPassword;
  int googleSignInCalls = 0;

  @override
  Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    signedUpEmail = email;
    signedUpPassword = password;
    return AuthResponse();
  }

  @override
  Future<void> signInWithGoogle() async {
    googleSignInCalls++;
  }
}

Widget _authHarness(
  _FakeAuthRepository repository, {
  VoidCallback? onAuthSuccess,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(home: AuthScreen(onAuthSuccess: onAuthSuccess)),
  );
}

void main() {
  testWidgets('Google ile giriş butonu OAuth akışını başlatır', (tester) async {
    final repository = _FakeAuthRepository();
    var success = false;
    await tester.pumpWidget(
      _authHarness(repository, onAuthSuccess: () => success = true),
    );

    await tester.tap(find.text('Google ile Giriş Yap'));
    await tester.pump();

    expect(repository.googleSignInCalls, 1);
    expect(success, isTrue);
  });

  testWidgets('Kayıt ol formu e-posta ve şifreyi repositorye iletir',
      (tester) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_authHarness(repository));

    await tester.tap(find.text('Hesabın yok mu? Kayıt ol'));
    await tester.enterText(find.byType(TextFormField).at(0), 'new@rotori.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'Strong123!');
    await tester.tap(find.widgetWithText(FilledButton, 'Kayıt ol'));
    await tester.pump();

    expect(repository.signedUpEmail, 'new@rotori.app');
    expect(repository.signedUpPassword, 'Strong123!');
  });
}
