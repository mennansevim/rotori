import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';

/// Login / Kayıt ekranı — e-posta + şifre.
/// Sign in with Apple butonu iOS Faz 7'de eklenecek (App Store şartı).
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

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      '🇯🇵 Japan-Trip',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegister ? 'Hesap oluştur' : 'Giriş yap',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-posta'),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Geçerli bir e-posta gir'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Şifre'),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'En az 6 karakter'
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
                          : Text(_isRegister ? 'Kayıt ol' : 'Giriş yap'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _isRegister = !_isRegister),
                      child: Text(
                        _isRegister
                            ? 'Zaten hesabın var mı? Giriş yap'
                            : 'Hesabın yok mu? Kayıt ol',
                      ),
                    ),
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
