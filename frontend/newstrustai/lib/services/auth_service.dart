import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(clientId: '936316195806-vdut0mv024h4b1ci7ms2pd0psv41luoi.apps.googleusercontent.com');

  Future<User?> signInWithGoogle() async {
    // 1. Trigger the Google Authentication flow
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    // 2. Obtain auth details from the request
    final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

    // 3. Create a new credential
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth?.accessToken,
      idToken: googleAuth?.idToken,
    );

    // 4. Sign in to Firebase with the credential
    final UserCredential userCredential = await _auth.signInWithCredential(credential);
    return userCredential.user;
  }
  Future<User?> signInWithFacebook() async {
    final LoginResult result = await FacebookAuth.instance.login();
    if (result.status != LoginStatus.success) return null;

    final OAuthCredential credential = FacebookAuthProvider.credential(
      result.accessToken!.tokenString,
    );

    final UserCredential userCredential = await _auth.signInWithCredential(credential);
    return userCredential.user;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint("Error signing out of Google: $e");
    }
    try {
      await FacebookAuth.instance.logOut();
    } catch (e) {
      debugPrint("Error signing out of Facebook: $e");
    }
  }
  // Add this method to AuthService
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException {
      // Re-throw to let the UI handle the specific error message
      rethrow; 
    }
  }
}