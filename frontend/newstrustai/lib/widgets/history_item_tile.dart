import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../screens/result/result_screen.dart';
import '../utils/app_utils.dart';

/// A single swipe-to-delete history entry tile used in HistoryScreen.
class HistoryItemTile extends StatelessWidget {
  final String docId;
  final String uid;
  final Map<String, dynamic> data;

  const HistoryItemTile({
    super.key,
    required this.docId,
    required this.uid,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final input = (data['input'] ?? '').toString();
    final inputType = (data['inputType'] ?? 'text').toString();
    final verdict = (data['verdict'] ?? 'unverified').toString();

    final rawConfidence = data['confidence'];
    final double confidenceValue =
        (rawConfidence is num) ? rawConfidence.toDouble() : 0.0;
    final String confidenceText =
        confidenceValue > 0 ? '${confidenceValue.toStringAsFixed(1)}%' : '';

    final rawResult = data['rawResult'] as Map<String, dynamic>?;
    final ocrMeta = data['ocr_meta'] as Map<String, dynamic>?;
    final ocrConfidence = ocrMeta?['confidence'];
    final imagePath = ocrMeta?['imagePath'];

    final ts = data['createdAt'] as Timestamp?;
    final date = ts == null
        ? 'Just now'
        : '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}';

    final badge = verdictBadge(
      verdict,
      fakeIcon: LucideIcons.alertTriangle,
      realIcon: LucideIcons.shieldCheck,
      unknownIcon: LucideIcons.badgeInfo,
    );

    return Dismissible(
      key: Key(docId),
      direction: DismissDirection.endToStart,
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
      onDismissed: (_) async {
        final savedData = Map<String, dynamic>.from(data);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('verifications')
            .doc(docId)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Verification deleted'),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Undo',
                textColor: Colors.amber,
                onPressed: () {
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('verifications')
                      .doc(docId)
                      .set(savedData);
                },
              ),
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
                      usedQuery: data['usedQuery'],
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
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              if (inputType == 'image' &&
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
                    color: badge.color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(badge.icon, color: badge.color, size: 20),
                ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      input.isEmpty ? 'Verification' : input,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${inputType.toUpperCase()} • $date',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (confidenceText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'AI Confidence: $confidenceText',
                          style: TextStyle(
                              fontSize: 11,
                              color: badge.color,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (inputType == 'image' && ocrConfidence != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'OCR Match: ${ocrConfidence.toStringAsFixed(0)}%',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.blueGrey),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badge.badgeText,
                  style: TextStyle(
                    color: badge.color,
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
  }
}
