import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import 'auth_repository.dart';

/// Login / Kayıt ekranı — e-posta + şifre + Sign in with Apple (iOS/macOS).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  // DEV: test kullanıcısı önden dolu — tek tık "Giriş yap".
  // (Prod'da bu varsayılanlar kaldırılacak.)
  final _emailController = TextEditingController(text: 'demo@japantrip.app');
  final _passwordController = TextEditingController(text: 'Demo1234!');
  bool _isRegister = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isRegister) {
        await repo.signUpWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await repo.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      // Başarı: authStateProvider tetikler → router HomeScreen'e yönlendirir.
    } on Exception catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Apple butonu yalnızca iOS/macOS'ta gösterilir. `kIsWeb` + platform
  /// kontrolü `dart:io` kullanmadan (foundation) yapılır; böylece web
  /// derlemesi `dart:io`'ya hiç dokunmaz ve buton web/Android'de render olmaz.
  bool get _canUseApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _signInWithApple() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithApple();
      // Başarı: authStateProvider tetikler → router yönlendirir.
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    // Hero: 旅 karakteri (gradient) + "Rotori" + tagline
                    const _AuthBrandHero(),
                    const SizedBox(height: 12),
                    Text(
                      _isRegister
                          ? s.s('auth.createAccount')
                          : s.s('auth.signIn'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration:
                          InputDecoration(labelText: s.s('auth.email')),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? s.s('auth.emailInvalid')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration:
                          InputDecoration(labelText: s.s('auth.password')),
                      validator: (v) => (v == null || v.length < 6)
                          ? s.s('auth.passwordTooShort')
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegister
                              ? s.s('auth.register')
                              : s.s('auth.signIn')),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _isRegister = !_isRegister),
                      child: Text(
                        _isRegister
                            ? s.s('auth.haveAccount')
                            : s.s('auth.noAccount'),
                      ),
                    ),
                    // Sign in with Apple — yalnızca iOS/macOS'ta görünür.
                    if (_canUseApple) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              s.s('auth.or'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _busy ? null : _signInWithApple,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(s.s('auth.signInWithApple')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Auth ekranı hero: 旅 karakteri gradient boyalı, altında "Rotori" markası ve
/// "Sürpriz yok, plan var." tagline'ı. Apple-style büyük tipografi.
class _AuthBrandHero extends StatelessWidget {
  const _AuthBrandHero();

  // Sakura → Fuji (mor) gradient — marka aksi.
  static const _brandGradient = [
    Color(0xFFFF8FAB), // sakura
    Color(0xFF7C6AEF), // fuji
  ];

  @override
  Widget build(BuildContext context) {
    final s = LanguageScope.of(context);
    return Column(
      children: [
        // 旅 karakteri — gradient boya (ShaderMask).
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: _brandGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            '旅',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 84,
              fontWeight: FontWeight.w700,
              height: 1.0,
              color: Colors.white, // ShaderMask ile boyanır.
              letterSpacing: -2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          s.s('drawer.brand'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.s('auth.tagline'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.60),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
