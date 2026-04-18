import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:newstrustai/services/auth_service.dart'; 
import 'login_screen.dart';
import 'edit_profile_screen.dart'; 

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Dynamically grab the current user so UI updates automatically 
  // when we return from the Edit Profile screen
  User? get user => FirebaseAuth.instance.currentUser;

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

  // Dummy handler for scope management (FYP limitation)
  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("This feature will be available in V2.0!"),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
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
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: NetworkImage(photoUrl),
                    backgroundColor: Colors.blue.shade50,
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
                  _ProfileOption(
                    icon: LucideIcons.settings,
                    title: "Settings",
                    onTap: _showComingSoon,
                  ),
                  _ProfileOption(
                    icon: LucideIcons.bell,
                    title: "Notifications",
                    onTap: _showComingSoon,
                  ),
                  
                  // ---------------- RESET PASSWORD ----------------
                  if (isEmailPasswordUser) // <-- Hide this widget if false
                    _ProfileOption(
                      icon: LucideIcons.key,
                      title: "Reset Password",
                      onTap: () {
                        if (user?.email == null || user!.email!.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("No email associated with this account.")),
                          );
                          return;
                        }

                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("Reset Password"),
                            content: Text("Send a password reset link to ${user!.email}?"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Cancel"),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(context); // Close dialog
                                  try {
                                    await AuthService().sendPasswordResetEmail(user!.email!);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Reset link sent! Check your inbox."),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Failed to send reset link."),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                child: const Text("Send", style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  
                  _ProfileOption(
                    icon: LucideIcons.shield,
                    title: "Privacy & Security",
                    onTap: _showComingSoon,
                  ),
                  _ProfileOption(
                    icon: LucideIcons.helpCircle,
                    title: "Help & Support",
                    onTap: _showComingSoon,
                  ),

                  const SizedBox(height: 20),

                  // ---------------- LOGOUT ----------------
                  _ProfileOption(
                    icon: LucideIcons.logOut,
                    title: "Log Out",
                    iconColor: Colors.red,
                    textColor: Colors.red,
                    onTap: () async {
                      await AuthService().signOut(); 
                      
                      if (!mounted) return;
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 5,
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (iconColor ?? Colors.blue).withOpacity(0.1),
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