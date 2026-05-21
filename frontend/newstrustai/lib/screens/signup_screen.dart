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
  bool _obscurePassword = true; // Added for password visibility

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

  bool isValidEmail(String email) {
    return RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$").hasMatch(email);
  }

  bool isValidPassword(String password) {
    return password.length >= 8 && RegExp(r'(?=.*?[!@#\$&*~])').hasMatch(password);
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

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final user = await AuthService().signInWithGoogle();
      if (user != null) {
        await _ensureFirestoreDoc(user);
      }
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
      if (user != null) {
        await _ensureFirestoreDoc(user);
      }
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

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty || phone.isEmpty) {
      showSnackBar("All fields are required", color: Colors.red);
      return;
    }

    if (!isValidEmail(email)) {
      showSnackBar("Enter a valid email address", color: Colors.red);
      return;
    }

    if (!isValidPassword(password)) {
      showSnackBar("Password must be 8+ chars and include 1 special character (!@#\$&*~)", color: Colors.red);
      return;
    }

    if (!phone.startsWith("+")) {
      showSnackBar("Phone must be like +923001234567 or 03xx...", color: Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final used = await _phoneAlreadyUsed(phone);
      if (used) {
        showSnackBar("This phone number is already registered.", color: Colors.red);
        return;
      }

      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 80),
                      const LogoWidget(size: 150, padding: 20, shadowBlur: 20),
                      const SizedBox(height: 16),
                      const Text(
                        'NewsTrust AI',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: firstNameController,
                        decoration: InputDecoration(
                          hintText: "First Name",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: lastNameController,
                        decoration: InputDecoration(
                          hintText: "Last Name",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: "Email",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      TextField(
                        controller: passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: "Password",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: numberController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: "Phone Number (03xx... or +92...)",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                      const SizedBox(height: 30),
                      GestureDetector(
                        onTap: signupUser,
                        child: Container(
                          width: 200,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "Sign Up",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Already have an account? "),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginScreen()),
                              );
                            },
                            child: const Text(
                              "Log In",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ---- Social sign-up ----
                      Row(
                        children: const [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'OR continue with',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _handleGoogleSignIn,
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: Card(
                            shadowColor: Colors.blue,
                            elevation: 1,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                FaIcon(FontAwesomeIcons.google, color: Colors.blue),
                                SizedBox(width: 10),
                                Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _handleFacebookSignIn,
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: Card(
                            shadowColor: Colors.blueAccent,
                            elevation: 1,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                FaIcon(FontAwesomeIcons.facebook, color: Color(0xFF1877F2)),
                                SizedBox(width: 10),
                                Text(
                                  'Continue with Facebook',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}