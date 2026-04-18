import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'result/result_screen.dart'; // Adjust path if needed

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  User? get _user => FirebaseAuth.instance.currentUser;

  // Safe "Delete All" Dialog
  Future<void> _confirmDeleteAll(BuildContext context, User user) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear History"),
        content: const Text("Are you sure you want to delete all your verification history? This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete All", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ref = FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .collection("verifications");

      final snap = await ref.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("History cleared"), backgroundColor: Colors.black87),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          "History",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.trash2, color: Colors.grey),
            onPressed: () {
              if (user != null) {
                _confirmDeleteAll(context, user); 
              }
            },
          )
        ],
      ),
      body: user == null
          ? const Center(child: Text("Please login to view history"))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("users")
                  .doc(user.uid)
                  .collection("verifications")
                  .orderBy("createdAt", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Failed to load history"));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.history, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text("No history yet", style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final document = docs[index];
                    final docId = document.id; // Get the specific document ID
                    final data = document.data() as Map<String, dynamic>;

                    final input = (data["input"] ?? "").toString();
                    final inputType = (data["inputType"] ?? "text").toString();
                    final verdict = (data["verdict"] ?? "unverified").toString();
                    
                    final rawConfidence = data["confidence"];
                    final double confidenceValue = (rawConfidence is num) ? rawConfidence.toDouble() : 0.0;
                    final String confidenceText = confidenceValue > 0 ? "${confidenceValue.toStringAsFixed(1)}%" : "";

                    final rawResult = data["rawResult"] as Map<String, dynamic>?;

                    final ocrMeta = data["ocr_meta"] as Map<String, dynamic>?;
                    final ocrConfidence = ocrMeta?["confidence"];
                    final imagePath = ocrMeta?["imagePath"];

                    final ts = data["createdAt"] as Timestamp?;
                    final date = ts == null
                        ? "Just now"
                        : "${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}";

                    final bool isFake = verdict.toLowerCase() == "fake" || verdict.toLowerCase() == "false";
                    final bool isVerified = verdict.toLowerCase() == "real" || verdict.toLowerCase() == "verified";

                    IconData icon;
                    Color color;
                    String badgeText;

                    if (isFake) {
                      icon = LucideIcons.alertTriangle;
                      color = Colors.red;
                      badgeText = "FAKE";
                    } else if (isVerified) {
                      icon = LucideIcons.shieldCheck;
                      color = Colors.green;
                      badgeText = "REAL";
                    } else {
                      icon = LucideIcons.badgeInfo;
                      color = Colors.orange;
                      badgeText = "UNKNOWN";
                    }

                    // Wrap the item in a Dismissible widget for Swipe-to-Delete
                    return Dismissible(
                      key: Key(docId), // Unique key is required for Dismissible
                      direction: DismissDirection.endToStart, // Only swipe left
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 15),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        child: const Icon(LucideIcons.trash2, color: Colors.white, size: 28),
                      ),
                      onDismissed: (direction) async {
                        // 1. Delete the item from Firestore
                        await FirebaseFirestore.instance
                            .collection("users")
                            .doc(user.uid)
                            .collection("verifications")
                            .doc(docId)
                            .delete();

                        // 2. Show a quick confirmation SnackBar
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Item deleted"),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: GestureDetector(
                        onTap: rawResult == null
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ResultScreen(
                                      data: rawResult,
                                      originalText: input,
                                      usedQuery: data["usedQuery"],
                                      resultMode: inputType,
                                    ),
                                  ),
                                );
                              },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              if (inputType == "image" &&
                                  imagePath != null &&
                                  File(imagePath).existsSync())
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(imagePath),
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon, color: color, size: 20),
                                ),

                              const SizedBox(width: 15),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      input.isEmpty ? "Verification" : input,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "${inputType.toUpperCase()} • $date",
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    
                                    if (confidenceText.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          "AI Confidence: $confidenceText",
                                          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                                        ),
                                      ),

                                    if (inputType == "image" && ocrConfidence != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          "OCR Match: ${ocrConfidence.toStringAsFixed(0)}%",
                                          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 10),

                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}