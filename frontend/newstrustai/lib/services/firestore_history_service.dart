import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreHistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get _user => _auth.currentUser;

  /// Ensure user document exists
  Future<void> ensureUserDoc() async {
    final u = _user;
    if (u == null) return;

    final ref = _db.collection("users").doc(u.uid);

    await ref.set({
      "email": u.email ?? "",
      "createdAt": FieldValue.serverTimestamp(),
      "lastLoginAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Save one verification result
  Future<void> saveVerification({
    required Map<String, dynamic> rawResult,
    required String inputType, // text | link | image
    required String input,
    String? usedQuery,

    required String verdict, // verified | fake | unverified
    double? confidence,
    String? method,
    String? reason,

    List<Map<String, dynamic>>? topMatches,
  }) async {
    final u = _user;
    if (u == null) return;

    await ensureUserDoc();

    final ref = _db
        .collection("users")
        .doc(u.uid)
        .collection("verifications");

    await ref.add({
      "inputType": inputType,
      "input": input,
      "usedQuery": usedQuery ?? "",

      "verdict": verdict,
      "confidence": confidence,
      "method": method ?? "",
      "reason": reason ?? "",

      "topMatches": topMatches ?? [],
      "rawResult": rawResult,

      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  /// Clear all history for current user
  Future<void> clearHistory() async {
    final u = _user;
    if (u == null) return;

    final ref = _db
        .collection("users")
        .doc(u.uid)
        .collection("verifications");

    final snap = await ref.get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }
}
