// login_page.dart
// ─────────────────────────────────────────────────────────────
// Login + Sign Up tabs. On success → pushReplacementNamed('/main')
// with userName and userEmail as arguments.
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'supabase_service.dart';

// ── Design tokens (match main.dart) ──────────────────────────
const Color _kBg      = Color(0xFF080D18);
const Color _kCard    = Color(0xFF111827);
const Color _kPurple  = Color(0xFF7B6EF6);
const Color _kGreen   = Color(0xFF00D4AA);
const Color _kAmber   = Color(0xFFFFA726);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabCtrl;

  // ── Login controllers ──────────────────────────────────────
  final _loginFormKey   = GlobalKey<FormState>();
  final _loginEmail     = TextEditingController();
  final _loginPassword  = TextEditingController();

  // ── Sign-up controllers ────────────────────────────────────
  final _signupFormKey  = GlobalKey<FormState>();
  final _signupName     = TextEditingController();
  final _signupEmail    = TextEditingController();
  final _signupPassword = TextEditingController();

  bool _loginObscure   = true;
  bool _signupObscure  = true;
  bool _isLoading      = false;
  bool _hasNavigated   = false;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    // Listen for OAuth / magic-link / email-confirm login completing
    // ✅ Only navigate on an explicit signedIn event — NOT on tokenRefreshed
    // or initialSession, which would fire even before the user has confirmed.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted || _hasNavigated) return;
      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        _navigateToMain(data.session!.user);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _authSub?.cancel();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _signupName.dispose();
    _signupEmail.dispose();
    _signupPassword.dispose();
    super.dispose();
  }

  // ── Navigate to main app ───────────────────────────────────
  void _navigateToMain(User? user, {String? nameOverride}) {
    if (_hasNavigated) return;
    _hasNavigated = true;

    final email    = user?.email ?? _loginEmail.text.trim();
    final meta     = user?.userMetadata?['full_name']?.toString().trim();
    final rawName  = nameOverride ?? meta ?? email.split('@').first;
    final userName = rawName.isEmpty
        ? 'Nyvra User'
        : '${rawName[0].toUpperCase()}${rawName.substring(1)}';

    Navigator.pushReplacementNamed(
      context,
      '/main',
      arguments: <String, String>{
        'userName':  userName,
        'userEmail': email,
      },
    );
  }

  // ── LOGIN ──────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email:    _loginEmail.text.trim(),
        password: _loginPassword.text.trim(),
      );
      if (mounted) _navigateToMain(res.user);
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── SIGN UP ────────────────────────────────────────────────
  Future<void> _signUp() async {
    if (!_signupFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email:    _signupEmail.text.trim(),
        password: _signupPassword.text.trim(),
        data:     {'full_name': _signupName.text.trim()},
      );

      if (!mounted) return;

      if (res.user != null) {
        // Also save to profiles table immediately
        try {
          await Supabase.instance.client.from('profiles').upsert({
            'id':    res.user!.id,
            'name':  _signupName.text.trim(),
            'email': _signupEmail.text.trim(),
          });
        } catch (_) {}

        _navigateToMain(res.user, nameOverride: _signupName.text.trim());
      } else {
        // Email confirmation required
        _snack('Check your email to confirm your account, then log in.');
        _tabCtrl.animateTo(0);
      }
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Sign up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI helpers ─────────────────────────────────────────────
  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText:    hint,
      hintStyle:   const TextStyle(color: Colors.white38),
      prefixIcon:  Icon(icon, color: Colors.white38, size: 20),
      suffixIcon:  suffix,
      filled:      true,
      fillColor:   const Color(0xFF1A2332),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kPurple, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFFC9C9)),
    );
  }

  // ════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // ── Logo + title ───────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kPurple, Color(0xFF5A52D5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _kPurple.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 36),
              ),

              const SizedBox(height: 16),

              const Text(
                'Nyvra',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                'Your personal safety companion',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 36),

              // ── Tab bar ────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  indicator: BoxDecoration(
                    color: _kPurple,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor:
                  Colors.white.withValues(alpha: 0.4),
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  tabs: const [
                    Tab(text: 'Login'),
                    Tab(text: 'Sign Up'),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Tab views ──────────────────────────────────
              SizedBox(
                height: 380,
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _LoginForm(),
                    _SignUpForm(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // LOGIN FORM
  // ─────────────────────────────────────────────────────────────
  Widget _LoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          _label('Email'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _loginEmail,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('you@example.com', Icons.mail_outline_rounded),
            validator: (v) {
              final e = v?.trim() ?? '';
              if (e.isEmpty) return 'Enter your email';
              if (!e.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),

          const SizedBox(height: 16),

          _label('Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _loginPassword,
            obscureText: _loginObscure,
            style: const TextStyle(color: Colors.white),
            decoration: _dec(
              'Min 6 characters',
              Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  _loginObscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _loginObscure = !_loginObscure),
              ),
            ),
            validator: (v) =>
            (v?.trim().length ?? 0) < 6
                ? 'Min 6 characters'
                : null,
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                disabledBackgroundColor:
                _kPurple.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
                  : const Text(
                'Login',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SIGN UP FORM
  // ─────────────────────────────────────────────────────────────
  Widget _SignUpForm() {
    return Form(
      key: _signupFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          _label('Full Name'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _signupName,
            style: const TextStyle(color: Colors.white),
            decoration:
            _dec('Your name', Icons.person_outline_rounded),
            validator: (v) =>
            (v?.trim().isEmpty ?? true) ? 'Enter your name' : null,
          ),

          const SizedBox(height: 14),

          _label('Email'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _signupEmail,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration:
            _dec('you@example.com', Icons.mail_outline_rounded),
            validator: (v) {
              final e = v?.trim() ?? '';
              if (e.isEmpty) return 'Enter your email';
              if (!e.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),

          const SizedBox(height: 14),

          _label('Password'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _signupPassword,
            obscureText: _signupObscure,
            style: const TextStyle(color: Colors.white),
            decoration: _dec(
              'Min 6 characters',
              Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  _signupObscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _signupObscure = !_signupObscure),
              ),
            ),
            validator: (v) =>
            (v?.trim().length ?? 0) < 6
                ? 'Min 6 characters'
                : null,
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGreen,
                disabledBackgroundColor:
                _kGreen.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
                  : const Text(
                'Create Account',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );
}