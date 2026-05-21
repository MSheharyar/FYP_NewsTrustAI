import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:newstrustai/services/auth_service.dart';
import 'login_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? get user => FirebaseAuth.instance.currentUser;
  bool _isUploadingPhoto = false;

  // Checks if the user logged in using a standard email and password
  bool get isEmailPasswordUser {
    if (user == null) return false;
    // Look through their linked providers for the 'password' provider
    return user!.providerData.any((provider) => provider.providerId == 'password');
  }
  
  String get displayName {
    return user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : "User";
  }

  String get email {
    return user?.email ?? "No email";
  }

  String get photoUrl {
    return user?.photoURL ??
        "https://ui-avatars.com/api/?name=${displayName.replaceAll(' ', '+')}&background=random";
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final uid = user?.uid;
    if (uid == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final ref = FirebaseStorage.instance.ref('profile_pictures/$uid.jpg');
      await ref.putData(await picked.readAsBytes());
      final downloadUrl = await ref.getDownloadURL();

      await user!.updatePhotoURL(downloadUrl);
      await user!.reload();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'photoUrl': downloadUrl}, SetOptions(merge: true));

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload photo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Account'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final uid = user?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      await user!.delete();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.code == 'requires-recent-login'
                ? 'Please sign out and sign in again before deleting your account.'
                : (e.message ?? 'Failed to delete account.')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete account.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.blue),
            SizedBox(width: 10),
            Text("Privacy & Security"),
          ],
        ),
        content: const Text(
          "Your data is protected:\n\n"
          "• Verification history is stored securely in Firebase Firestore.\n"
          "• We never share your data with third parties.\n"
          "• You can delete your history anytime from the History tab.\n"
          "• All network traffic uses HTTPS encryption.\n"
          "• Authentication is handled by Firebase Auth.",
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got it", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 10),
            Text("How to Use"),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            "NewsTrustAI lets you verify news in three ways:\n\n"
            "📝 Verify Text\n"
            "Paste any news headline or paragraph. The system checks it against our database, live sources, and Google Fact Check.\n\n"
            "🔗 Verify Link\n"
            "Paste a full URL. The app fetches the article and runs the same checks.\n\n"
            "🖼️ Scan Image\n"
            "Upload a screenshot. OCR extracts the text and verifies it automatically.\n\n"
            "🤖 AI Assistant\n"
            "Chat with our AI for tips on spotting misinformation or to explain any result.\n\n"
            "📊 History & Analytics\n"
            "View all past verifications and see your personal trend insights.",
            style: TextStyle(height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ---------------- HEADER ----------------
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _isUploadingPhoto
                          ? const SizedBox(
                              width: 100,
                              height: 100,
                              child: CircularProgressIndicator(),
                            )
                          : CircleAvatar(
                              radius: 50,
                              backgroundImage: NetworkImage(photoUrl),
                              backgroundColor: Colors.blue.shade50,
                            ),
                      GestureDetector(
                        onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    email,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  
                  // EDIT PROFILE BUTTON
                  ElevatedButton(
                    onPressed: () async {
                      // Navigate to Edit Screen and wait for the result
                      final didUpdate = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProfileScreen(currentName: displayName),
                        ),
                      );
                      
                      // If the user saved changes, rebuild the UI to show the new name
                      if (didUpdate == true) {
                        setState(() {}); 
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text(
                      "Edit Profile",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ---------------- SETTINGS ----------------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // ---------------- RESET PASSWORD ----------------
                  if (isEmailPasswordUser)
                    _ProfileOption(
                      icon: LucideIcons.key,
                      title: "Reset Password",
                      onTap: () async {
                        if (user?.email == null || user!.email!.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("No email associated with this account.")),
                          );
                          return;
                        }

                        final messenger = ScaffoldMessenger.of(context);
                        final send = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text("Reset Password"),
                            content: Text("Send a password reset link to ${user!.email}?"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("Cancel"),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                child: const Text("Send", style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );

                        if (send != true || !mounted) return;
                        try {
                          await AuthService().sendPasswordResetEmail(user!.email!);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text("Reset link sent! Check your inbox."),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (_) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text("Failed to send reset link."),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                    ),

                  _ProfileOption(
                    icon: LucideIcons.shield,
                    title: "Privacy & Security",
                    onTap: _showPrivacyDialog,
                  ),
                  _ProfileOption(
                    icon: LucideIcons.helpCircle,
                    title: "Help & Support",
                    onTap: _showHelpDialog,
                  ),

                  const SizedBox(height: 20),

                  // ---------------- LOGOUT ----------------
                  _ProfileOption(
                    icon: LucideIcons.logOut,
                    title: "Log Out",
                    iconColor: Colors.red,
                    textColor: Colors.red,
                    onTap: () async {
                      final nav = Navigator.of(context);
                      await AuthService().signOut();
                      nav.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  const Text(
                    "App Version 1.0.0",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _deleteAccount,
                    child: const Text(
                      'Delete Account',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= PROFILE OPTION TILE =================
class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? textColor;
  final Color? iconColor;

  const _ProfileOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (iconColor ?? Colors.blue).withValues(alpha:0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: iconColor ?? Colors.blue[700],
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: textColor ?? Colors.black87,
          ),
        ),
        trailing: const Icon(
          LucideIcons.chevronRight,
          size: 18,
          color: Colors.grey,
        ),
      ),
    );
  }
}