import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:newstrustai/services/auth_service.dart';
import '../utils/app_utils.dart';
import '../widgets/logo_widget.dart';
import 'login_screen.dart';
import 'package:newstrustai/screens/home/home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController numberController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;

  static const _blue = Color(0xFF1565C0);
  static const _indigo = Color(0xFF283593);

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    numberController.dispose();
    super.dispose();
  }

  void showSnackBar(String message, {Color color = Colors.blue}) =>
      showAppSnackBar(context, message,
          color: color, duration: const Duration(seconds: 4));

  bool isValidEmail(String email) =>
      RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$").hasMatch(email);

  bool isValidPassword(String password) =>
      password.length >= 8 && RegExp(r'(?=.*?[!@#\$&*~])').hasMatch(password);

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

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService().signInWithGoogle();
      if (user != null) await _ensureFirestoreDoc(user);
      if (user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(firstName: user.displayName ?? 'User')),
        );
        showSnackBar('Google Sign-up successful!', color: Colors.blue);
      }
    } catch (e) {
      showSnackBar('Google Sign-in failed or was canceled.', color: Colors.red);
      debugPrint('Google Auth Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          MaterialPageRoute(builder: (_) => HomeScreen(firstName: user.displayName ?? 'User')),
        );
        showSnackBar('Facebook Sign-up successful!', color: Colors.blue);
      }
    } catch (e) {
      showSnackBar('Facebook Sign-in failed or was canceled.', color: Colors.red);
      debugPrint('Facebook Auth Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _phoneAlreadyUsed(String phoneE164) async {
    final doc = await _db.collection("phone_to_email").doc(phoneE164).get();
    return doc.exists;
  }

  Future<void> signupUser() async {
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final phone = normalizePhone(numberController.text);

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty ||
        password.isEmpty || phone.isEmpty) {
      showSnackBar("All fields are required", color: Colors.red);
      return;
    }
    if (!isValidEmail(email)) {
      showSnackBar("Enter a valid email address", color: Colors.red);
      return;
    }
    if (!isValidPassword(password)) {
      showSnackBar(
          "Password must be 8+ chars and include 1 special character (!@#\$&*~)",
          color: Colors.red);
      return;
    }
    if (!phone.startsWith("+")) {
      showSnackBar("Phone must be like +923001234567 or 03xx...",
          color: Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final used = await _phoneAlreadyUsed(phone);
      if (used) {
        showSnackBar("This phone number is already registered.",
            color: Colors.red);
        return;
      }

      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        showSnackBar("Signup failed (no user returned).", color: Colors.red);
        return;
      }

      await user.updateDisplayName(firstName);
      await user.reload();

      await _db.collection("users").doc(user.uid).set({
        "firstName": firstName,
        "lastName": lastName,
        "email": email,
        "phone": phone,
        "phoneVerified": false,
        "createdAt": FieldValue.serverTimestamp(),
        "lastLoginAt": FieldValue.serverTimestamp(),
        "provider": "email",
      }, SetOptions(merge: true));

      await _db.collection("phone_to_email").doc(phone).set({
        "email": email,
        "uid": user.uid,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(firstName: firstName)),
      );

      showSnackBar("Signup completed!", color: Colors.blue);
    } on FirebaseAuthException catch (e) {
      showSnackBar(e.message ?? "Signup failed", color: Colors.red);
    } catch (e) {
      debugPrint("Signup Error: $e");
      showSnackBar("Something went wrong", color: Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
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
          child: Text(text,
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 12)),
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
          // Gradient background
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
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Column(
                            children: [
                              const LogoWidget(size: 70, padding: 4, shadowBlur: 14),
                              const SizedBox(height: 12),
                              const Text(
                                'NewsTrust AI',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Create your free account',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // White form card
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(32),
                              topRight: Radius.circular(32),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sign up',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fill in the details below to get started.',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500),
                              ),
                              const SizedBox(height: 22),

                              // Name row
                              Row(
                                children: [
                                  Expanded(
                                    child: _field(
                                      controller: firstNameController,
                                      hint: 'First Name',
                                      icon: Icons.person_outline_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _field(
                                      controller: lastNameController,
                                      hint: 'Last Name',
                                      icon: Icons.person_outline_rounded,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              _field(
                                controller: emailController,
                                hint: 'Email',
                                icon: Icons.email_outlined,
                                keyboard: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 14),

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
                                  onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              const SizedBox(height: 14),

                              _field(
                                controller: numberController,
                                hint: 'Phone Number (03xx... or +92...)',
                                icon: Icons.phone_outlined,
                                keyboard: TextInputType.phone,
                              ),
                              const SizedBox(height: 22),

                              _primaryButton('Sign Up', signupUser),
                              const SizedBox(height: 20),

                              // Login link
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Already have an account? ',
                                    style: TextStyle(
                                        color: Colors.grey.shade500, fontSize: 13),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const LoginScreen()),
                                    ),
                                    child: const Text(
                                      'Log In',
                                      style: TextStyle(
                                        color: _blue,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              _divider('OR continue with'),
                              const SizedBox(height: 16),

                              _socialButton(
                                onTap: _handleGoogleSignIn,
                                icon: FontAwesomeIcons.google,
                                iconColor: const Color(0xFFDB4437),
                                label: 'Continue with Google',
                              ),
                              const SizedBox(height: 10),

                              _socialButton(
                                onTap: _handleFacebookSignIn,
                                icon: FontAwesomeIcons.facebook,
                                iconColor: const Color(0xFF1877F2),
                                label: 'Continue with Facebook',
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
