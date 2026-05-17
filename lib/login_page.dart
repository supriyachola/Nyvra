// login_page.dart — v4 (FORCE SIGNUP — no email confirmation)
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

const Color _kBg     = Color(0xFF080D18);
const Color _kCard   = Color(0xFF111827);
const Color _kPurple = Color(0xFF7B6EF6);
const Color _kGreen  = Color(0xFF00D4AA);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {

  late final TabController _tabCtrl;

  final _loginFormKey      = GlobalKey<FormState>();
  final _loginEmail        = TextEditingController();
  final _loginPassword     = TextEditingController();

  final _signupFormKey     = GlobalKey<FormState>();
  final _signupName        = TextEditingController();
  final _signupEmail       = TextEditingController();
  final _signupPassword    = TextEditingController();
  final _signupConfirmPass = TextEditingController();

  bool _loginObscure         = true;
  bool _signupObscure        = true;
  bool _signupConfirmObscure = true;
  bool _isLoading            = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _signupName.dispose();
    _signupEmail.dispose();
    _signupPassword.dispose();
    _signupConfirmPass.dispose();
    super.dispose();
  }

  void _navigateToMain(User user, {String? nameOverride}) {
    if (!mounted) return;
    final meta        = user.userMetadata?['full_name']?.toString().trim() ?? '';
    final rawName     = nameOverride ?? meta;
    final displayName = rawName.isNotEmpty
        ? '${rawName[0].toUpperCase()}${rawName.substring(1)}'
        : user.email?.split('@').first ?? 'Nyvra User';
    Navigator.pushReplacementNamed(
      context,
      '/main',
      arguments: <String, String>{
        'userName':  displayName,
        'userEmail': user.email ?? '',
      },
    );
  }

  // ── LOGIN ───────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final res = await supabase.auth.signInWithPassword(
        email:    _loginEmail.text.trim(),
        password: _loginPassword.text.trim(),
      );
      if (res.user != null && mounted) {
        _navigateToMain(res.user!);
      } else {
        _snack('Login failed — please try again.');
      }
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Login failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── SIGN UP — with auto-login fallback ─────────────────────
  Future<void> _signUp() async {
    if (!_signupFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email    = _signupEmail.text.trim();
    final password = _signupPassword.text.trim();
    final name     = _signupName.text.trim();

    try {
      // Step 1: Sign up
      final res = await supabase.auth.signUp(
        email:    email,
        password: password,
        data:     {'full_name': name},
      );

      if (!mounted) return;

      // Step 2a: Session exists = confirmed immediately ✅
      if (res.session != null && res.user != null) {
        await _saveProfile(res.user!.id, name, email);
        _navigateToMain(res.user!, nameOverride: name);
        return;
      }

      // Step 2b: No session = email confirmation still ON somewhere
      // Try immediate sign-in as fallback — works if user was created
      if (res.user != null) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          final loginRes = await supabase.auth.signInWithPassword(
            email:    email,
            password: password,
          );
          if (loginRes.user != null && mounted) {
            await _saveProfile(loginRes.user!.id, name, email);
            _navigateToMain(loginRes.user!, nameOverride: name);
            return;
          }
        } catch (_) {}

        _snack('Account created! Please log in with your credentials.');
        _tabCtrl.animateTo(0);
        _loginEmail.text    = email;
        _loginPassword.text = password;
        return;
      }

      _snack('Sign up failed — please try again.');

    } on AuthException catch (e) {
      // Already registered — just log in
      if (e.message.toLowerCase().contains('already registered') ||
          e.message.toLowerCase().contains('already exists')) {
        try {
          final loginRes = await supabase.auth.signInWithPassword(
            email:    email,
            password: password,
          );
          if (loginRes.user != null && mounted) {
            _navigateToMain(loginRes.user!, nameOverride: name);
            return;
          }
        } catch (_) {}
      }
      _snack(e.message);
    } catch (e) {
      _snack('Sign up failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile(String uid, String name, String email) async {
    try {
      await supabase.from('profiles').upsert({
        'id':    uid,
        'name':  name,
        'email': email,
      });
    } catch (e) {
      debugPrint('Profile save error: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText:       hint,
        hintStyle:      const TextStyle(color: Colors.white38),
        prefixIcon:     Icon(icon, color: Colors.white38, size: 20),
        suffixIcon:     suffix,
        filled:         true,
        fillColor:      const Color(0xFF1A2332),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kPurple, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
        errorStyle: const TextStyle(color: Color(0xFFFFC9C9)),
      );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 13,
        fontWeight: FontWeight.w600),
  );

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

              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_kPurple, _kGreen],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 38),
              ),

              const SizedBox(height: 20),

              const Text('Nyvra',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),

              const SizedBox(height: 6),

              Text('Your personal safety companion',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13)),

              const SizedBox(height: 36),

              Container(
                decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(14)),
                child: TabBar(
                  controller: _tabCtrl,
                  indicator: BoxDecoration(
                      color: _kPurple,
                      borderRadius: BorderRadius.circular(12)),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.4),
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  tabs: const [Tab(text: 'Login'), Tab(text: 'Sign Up')],
                ),
              ),

              const SizedBox(height: 28),

              SizedBox(
                height: 480,
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [_buildLoginForm(), _buildSignUpForm()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
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
            decoration: _dec('Min 6 characters', Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                    _loginObscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white38, size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _loginObscure = !_loginObscure),
                )),
            validator: (v) =>
            (v?.trim().length ?? 0) < 6 ? 'Min 6 characters' : null,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                disabledBackgroundColor: _kPurple.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
                  : const Text('Login',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignUpForm() {
    return Form(
      key: _signupFormKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Full Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _signupName,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Your name', Icons.person_outline_rounded),
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
              decoration: _dec('you@example.com', Icons.mail_outline_rounded),
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
              decoration: _dec('Min 6 characters', Icons.lock_outline_rounded,
                  suffix: IconButton(
                    icon: Icon(
                      _signupObscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white38, size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _signupObscure = !_signupObscure),
                  )),
              validator: (v) =>
              (v?.trim().length ?? 0) < 6 ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 14),
            _label('Confirm Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _signupConfirmPass,
              obscureText: _signupConfirmObscure,
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Re-enter password', Icons.lock_outline_rounded,
                  suffix: IconButton(
                    icon: Icon(
                      _signupConfirmObscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white38, size: 20,
                    ),
                    onPressed: () => setState(
                            () => _signupConfirmObscure = !_signupConfirmObscure),
                  )),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please confirm your password';
                }
                if (v.trim() != _signupPassword.text.trim()) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  disabledBackgroundColor: _kGreen.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : const Text('Create Account',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
