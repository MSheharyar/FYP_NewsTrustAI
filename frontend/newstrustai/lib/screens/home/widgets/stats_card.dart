import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<_StatsVm> _loadStats() async {
    final u = _user;
    if (u == null) return const _StatsVm(today: 0, saved: 0, accuracyPct: null);

    final ref = FirebaseFirestore.instance.collection("users").doc(u.uid).collection("verifications");
    final todayStart = Timestamp.fromDate(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

    final todaySnap = await ref.where("createdAt", isGreaterThanOrEqualTo: todayStart).get();
    final totalSnap = await ref.get();
    final snap = await ref.orderBy("createdAt", descending: true).limit(500).get();

    int verified = 0;
    int fake = 0;
    for (final d in snap.docs) {
      final v = (d.data()["verdict"] ?? "").toString().toLowerCase();
      if (v == "verified" || v == "real") verified++;
      if (v == "fake" || v == "false") fake++;
    }

    double? acc = (verified + fake > 0) ? (verified / (verified + fake)) * 100.0 : null;
    return _StatsVm(today: todaySnap.docs.length, saved: totalSnap.docs.length, accuracyPct: acc);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StatsVm>(
      future: _loadStats(),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final s = snap.data ?? const _StatsVm(today: 0, saved: 0, accuracyPct: null);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                    child: const Icon(LucideIcons.shieldCheck, color: Colors.blue, size: 24),
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Verifications", style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(loading ? "..." : "${s.today} Today", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    ],
                  ),
                  const Spacer(),
                  if (loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Divider(height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem(s.accuracyPct == null ? "—" : "${s.accuracyPct!.toStringAsFixed(0)}%", "Accuracy", Colors.green),
                  Container(width: 1, height: 30, color: Colors.grey[100]),
                  _statItem("${s.saved}", "Total Saved", Colors.orange),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  static Widget _statItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _StatsVm {
  final int today;
  final int saved;
  final double? accuracyPct;
  const _StatsVm({required this.today, required this.saved, required this.accuracyPct});
}