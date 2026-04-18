import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  // Add this inside your AuthService class
  Future<void> signOut() async {
    await _auth.signOut();
    try {
      // This forces the Google account picker to show up next time
      await _googleSignIn.signOut(); 
    } catch (e) {
      print("Error signing out of Google: $e");
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