import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/sync/sync_providers.dart';
import '../../core/theme/app_theme.dart';

/// Minimal authentication screen using Supabase email + password auth.
///
/// Styled with existing Sheep design tokens.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final supabase = ref.read(supabaseProvider);
      if (_isSignUp) {
        final res = await supabase.auth.signUp(email: email, password: password);
        if (res.session == null) {
          setState(() => _error = 'Please check your email to confirm your account.');
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Scaffold(
      backgroundColor: colors.surfaceBase,
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colors.surfacePanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo / title
              Text(
                'sheep',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isSignUp ? 'Create an account' : 'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.inkSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),

              // Email field
              _buildField(
                controller: _emailController,
                hint: 'Email',
                colors: colors,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),

              // Password field
              _buildField(
                controller: _passwordController,
                hint: 'Password',
                colors: colors,
                obscure: true,
                onSubmitted: (_) => _submit(),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFCF6679), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 20),

              // Submit button
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isSignUp ? 'Sign Up' : 'Sign In',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Toggle sign-in / sign-up
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSignUp = !_isSignUp;
                    _error = null;
                  });
                },
                child: Text(
                  _isSignUp
                      ? 'Already have an account? Sign in'
                      : "Don't have an account? Sign up",
                  style: TextStyle(
                    color: colors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Skip (use offline-only)
              TextButton(
                onPressed: () {
                  // Navigate to main app without auth — sync disabled.
                  Navigator.of(context).pushReplacementNamed('/home');
                },
                child: Text(
                  'Use offline only',
                  style: TextStyle(
                    color: colors.inkMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required AppColors colors,
    bool obscure = false,
    TextInputType? keyboardType,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: TextStyle(color: colors.inkPrimary, fontSize: 14),
      cursorColor: colors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.inkMuted, fontSize: 14),
        filled: true,
        fillColor: colors.surfaceBase,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
      ),
    );
  }
}
