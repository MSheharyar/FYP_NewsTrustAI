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

  static const _blue = Color(0xFF1565C0);
  static const _indigo = Color(0xFF283593);

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
          showAppSnackBar(
              context, 'Enter phone like +923001234567 or 03xx...');
          return;
        }
        final resolved = await _emailForPhone(phone);
        if (!mounted) return;
        if (resolved == null) {
          setState(() => _resetSent = true);
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
        // Swallow to avoid revealing whether the account exists
      }

      if (!mounted) return;
      setState(() => _resetSent = true);
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
                          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                          child: Column(
                            children: [
                              // Back button aligned left
                              Align(
                                alignment: Alignment.centerLeft,
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.arrow_back_rounded,
                                        color: Colors.white, size: 20),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Lock icon in circle
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock_reset_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'We\'ll send a reset link to your email.',
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
                          constraints: BoxConstraints(
                            minHeight: MediaQuery.of(context).size.height * 0.5,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(32),
                              topRight: Radius.circular(32),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reset your password',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Enter your email or registered phone number. We\'ll send a password reset link to the associated email.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                    height: 1.5),
                              ),
                              const SizedBox(height: 26),

                              // Input field
                              TextField(
                                controller: _controller,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: 'Email or Phone (03xx... or +92...)',
                                  hintStyle: TextStyle(
                                      color: Colors.grey.shade400, fontSize: 14),
                                  prefixIcon: Icon(Icons.alternate_email_rounded,
                                      color: Colors.grey.shade400, size: 20),
                                  filled: true,
                                  fillColor: const Color(0xFFF5F7FA),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 16),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade200),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade200),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: _blue, width: 1.8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Send reset button
                              GestureDetector(
                                onTap: _resetSent ? null : _sendReset,
                                child: Container(
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  decoration: BoxDecoration(
                                    gradient: _resetSent
                                        ? null
                                        : const LinearGradient(
                                            colors: [_blue, _indigo],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                    color: _resetSent ? Colors.grey.shade300 : null,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: _resetSent
                                        ? []
                                        : [
                                            BoxShadow(
                                              color: _blue.withValues(alpha: 0.35),
                                              blurRadius: 12,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                  ),
                                  child: Text(
                                    _resetSent ? 'Link Sent' : 'Send Reset Link',
                                    style: TextStyle(
                                      color: _resetSent
                                          ? Colors.grey.shade600
                                          : Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Back to login
                              Center(
                                child: TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                  ),
                                  child: const Text(
                                    'Back to Login',
                                    style: TextStyle(
                                      color: _blue,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
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
