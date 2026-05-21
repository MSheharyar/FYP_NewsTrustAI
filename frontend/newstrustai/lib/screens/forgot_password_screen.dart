import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_utils.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  bool _resetSent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String s) => s.contains('@');

  Future<String?> _emailForPhone(String phoneE164) async {
    final doc = await FirebaseFirestore.instance
        .collection('phone_to_email')
        .doc(phoneE164)
        .get();
    if (!doc.exists) return null;
    final email = (doc.data()?['email'] ?? '').toString().trim();
    return email.isEmpty ? null : email;
  }

  Future<void> _sendReset() async {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      showAppSnackBar(context, 'Please enter your email or phone number.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String email;

      if (_looksLikeEmail(input)) {
        email = input;
      } else {
        final phone = normalizePhone(input);
        if (!phone.startsWith('+')) {
          showAppSnackBar(context, 'Enter phone like +923001234567 or 03xx...');
          return;
        }
        final resolved = await _emailForPhone(phone);
        if (!mounted) return;
        if (resolved == null) {
          // Show consistent message — do not reveal whether email exists
          setState(() { _resetSent = true; });
          showAppSnackBar(
            context,
            'If this number is registered, a password reset link has been sent.',
            color: Colors.green,
          );
          return;
        }
        email = resolved;
      }

      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      } catch (_) {
        // Swallow all errors to avoid revealing whether the account exists
      }

      if (!mounted) return;
      setState(() { _resetSent = true; });
      showAppSnackBar(
        context,
        'If this email is registered, a password reset link has been sent.',
        color: Colors.green,
        duration: const Duration(seconds: 5),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Enter your email address or registered phone number. We\'ll send a password reset link to the associated email.',
                      style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Email or Phone (03xx... or +92...)',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _resetSent ? null : _sendReset,
                      child: Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _resetSent ? Colors.grey : Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Send Reset Link',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Back to Login',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
