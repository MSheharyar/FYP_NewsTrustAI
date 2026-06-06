import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:newstrustai/services/auth_service.dart';
import '../utils/app_utils.dart';
import '../widgets/logo_widget.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';
import 'home/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController idController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;

  static const _blue = Color(0xFF1565C0);
  static const _indigo = Color(0xFF283593);

  @override
  void dispose() {
    idController.dispose();
    passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void showSnackBar(String message, {Color color = Colors.red}) =>
      showAppSnackBar(context, message, color: color);

  bool _looksLikeEmail(String s) => s.contains("@");

  Future<String?> _emailForPhone(String phoneE164) async {
    final doc = await _db.collection("phone_to_email").doc(phoneE164).get();
    if (!doc.exists) return null;
    final data = doc.data();
    final email = (data?["email"] ?? "").toString().trim();
    if (email.isEmpty) return null;
    return email;
  }

  Future<void> _login() async {
    final id = idController.text.trim();
    final password = passwordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      showSnackBar("Please fill all fields");
      return;
    }

    setState(() => _isLoading = true);

    try {
      String email;

      if (_looksLikeEmail(id)) {
        email = id;
      } else {
        final phone = normalizePhone(id);
        if (!phone.startsWith("+")) {
          showSnackBar("Enter phone like +923001234567 or 03xx...");
          return;
        }

        final mappedEmail = await _emailForPhone(phone);
        if (mappedEmail == null) {
          showSnackBar("No account found for this phone number");
          return;
        }
        email = mappedEmail;
      }

      await _auth.signInWithEmailAndPassword(email: email, password: password);

      final user = _auth.currentUser;
      final firstName = user?.displayName ?? "User";

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(firstName: firstName)),
      );

      showSnackBar("Login successful!", color: Colors.blue);
    } on FirebaseAuthException catch (e) {
      showSnackBar(e.message ?? "Login failed");
    } catch (_) {
      showSnackBar("Something went wrong");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _ensureFirestoreDoc(User user) async {
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();
    if (!doc.exists) {
      await docRef.set({
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _sendOtp() async {
    final phone = normalizePhone(_phoneController.text.trim());
    if (!phone.startsWith('+')) {
      showSnackBar('Enter phone like +923001234567 or 03xx...');
      return;
    }
    setState(() => _isLoading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCredential = await _auth.signInWithCredential(credential);
            final user = userCredential.user;
            if (user != null) await _ensureFirestoreDoc(user);
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(firstName: user?.displayName ?? 'User'),
              ),
            );
          } catch (_) {
            if (mounted) setState(() => _isLoading = false);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() => _isLoading = false);
            showSnackBar(e.message ?? 'Phone verification failed.');
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OtpScreen(
                  verificationId: verificationId,
                  phoneNumber: phone,
                ),
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        showSnackBar('Failed to send OTP. Please try again.');
      }
    }
  }

  Future<void> _handleFacebookSignIn() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService().signInWithFacebook();
      if (user != null) await _ensureFirestoreDoc(user);
      if (user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(firstName: user.displayName ?? "User")),
        );
        showSnackBar("Facebook Login successful!", color: Colors.blue);
      }
    } catch (e) {
      showSnackBar("Facebook Login failed or was canceled.", color: Colors.red);
      debugPrint("Facebook Auth Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService().signInWithGoogle();
      if (user != null) await _ensureFirestoreDoc(user);
      if (user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(firstName: user.displayName ?? "User")),
        );
        showSnackBar("Google Login successful!", color: Colors.blue);
      }
    } catch (e) {
      showSnackBar("Google Login failed or was canceled.", color: Colors.red);
      debugPrint("Google Auth Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Reusable styled text field ──────────────────────────────────────────────
  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _blue, width: 1.8),
        ),
      ),
    );
  }

  // ── Gradient primary button ─────────────────────────────────────────────────
  Widget _primaryButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_blue, _indigo],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _blue.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // ── Outlined social button ──────────────────────────────────────────────────
  Widget _socialButton({
    required VoidCallback onTap,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(String text) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(text, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ),
        Expanded(child: Divider(color: Colors.grey.shade200)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Gradient background ─────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1565C0), Color(0xFF283593)],
              ),
            ),
          ),

          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        // ── Header: logo + title + tagline ──────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
                          child: Column(
                            children: [
                              const LogoWidget(size: 80, padding: 4, shadowBlur: 16),
                              const SizedBox(height: 14),
                              const Text(
                                'NewsTrust AI',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Verify news. Trust facts.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── White form card ─────────────────────────────
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(32),
                              topRight: Radius.circular(32),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sign in',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Welcome back — enter your credentials below.',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                              ),
                              const SizedBox(height: 24),

                              // Email / phone field
                              _field(
                                controller: idController,
                                hint: 'Email or Phone (03xx... or +92...)',
                                icon: Icons.person_outline_rounded,
                                keyboard: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 14),

                              // Password field
                              _field(
                                controller: passwordController,
                                hint: 'Password',
                                icon: Icons.lock_outline_rounded,
                                obscure: _obscurePassword,
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.grey.shade400,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),

                              // Forgot password
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(color: _blue, fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),

                              _primaryButton('Log in', _login),
                              const SizedBox(height: 20),

                              // OTP divider
                              _divider('OR login with OTP'),
                              const SizedBox(height: 16),

                              _field(
                                controller: _phoneController,
                                hint: 'Phone Number (+92... or 03xx...)',
                                icon: Icons.phone_outlined,
                                keyboard: TextInputType.phone,
                              ),
                              const SizedBox(height: 12),
                              _primaryButton('Send OTP', _sendOtp),
                              const SizedBox(height: 20),

                              // Social login divider
                              _divider('OR continue with'),
                              const SizedBox(height: 16),

                              // Google
                              _socialButton(
                                onTap: _handleGoogleSignIn,
                                icon: FontAwesomeIcons.google,
                                iconColor: const Color(0xFFDB4437),
                                label: 'Continue with Google',
                              ),
                              const SizedBox(height: 10),

                              // Facebook
                              _socialButton(
                                onTap: _handleFacebookSignIn,
                                icon: FontAwesomeIcons.facebook,
                                iconColor: const Color(0xFF1877F2),
                                label: 'Continue with Facebook',
                              ),
                              const SizedBox(height: 24),

                              // Sign up link
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Don't have an account? ",
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                                    ),
                                    child: const Text(
                                      'Sign Up',
                                      style: TextStyle(
                                        color: _blue,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
