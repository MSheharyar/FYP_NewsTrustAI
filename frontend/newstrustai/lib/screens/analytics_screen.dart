import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Please log in to view analytics")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("Verification Insights", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .collection("verifications")
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.barChart3, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  const Text("No verification history yet", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text("Start verifying news to see insights", style: TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          final totalScans = docs.length;
          
          // Calculate statistics
          int fakeCount = 0;
          int realCount = 0;
          int unverifiedCount = 0;
          Map<String, int> verdictsByDay = {};
          Map<String, int> fakeSourceCounts = {};

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final verdict = (data['verdict'] ?? '').toString().toLowerCase();
            
            // Count by verdict
            if (verdict == 'fake' || verdict == 'false') {
              fakeCount++;
            } else if (verdict == 'real' || verdict == 'verified') {
              realCount++;
            } else {
              unverifiedCount++;
            }

            // Count by day (last 7 days)
            final createdAt = data['createdAt'] as Timestamp?;
            if (createdAt != null) {
              final date = createdAt.toDate();
              final dayName = _getDayName(date.weekday);
              verdictsByDay[dayName] = (verdictsByDay[dayName] ?? 0) + 1;
            }

            // Track fake sources
            if (verdict == 'fake' || verdict == 'false') {
              final input = (data['input'] ?? '').toString();
              if (input.contains('http')) {
                // Extract domain from URL
                try {
                  final uri = Uri.parse(input);
                  final domain = uri.host.replaceAll('www.', '');
                  if (domain.isNotEmpty) {
                    fakeSourceCounts[domain] = (fakeSourceCounts[domain] ?? 0) + 1;
                  }
                } catch (_) {}
              }
            }
          }

          // Calculate Percentages for FYP Rubric
          int fakePercent = totalScans == 0 ? 0 : ((fakeCount / totalScans) * 100).round();
          int realPercent = totalScans == 0 ? 0 : ((realCount / totalScans) * 100).round();

          // Get top 3 fake sources
          final topFakeSources = fakeSourceCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          final top3 = topFakeSources.take(3).toList();

          // Get this week's data (last 7 days)
          final weekData = _getWeekData(verdictsByDay, totalScans);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Overview Cards
                Row(
                  children: [
                    Expanded(
                      child: _OverviewCard(
                        label: "Total Scans",
                        value: totalScans.toString(),
                        color: Colors.blue,
                        icon: LucideIcons.scan,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _OverviewCard(
                        label: "Fake Detected",
                        value: fakeCount.toString(),
                        subtitle: "($fakePercent%)", // Added Percentage
                        color: Colors.red,
                        icon: LucideIcons.alertTriangle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: _OverviewCard(
                        label: "Verified Real",
                        value: realCount.toString(),
                        subtitle: "($realPercent%)", // Added Percentage
                        color: Colors.green,
                        icon: LucideIcons.checkCircle,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _OverviewCard(
                        label: "Unverified",
                        value: unverifiedCount.toString(),
                        color: Colors.orange,
                        icon: LucideIcons.helpCircle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),

                // 2. Weekly Activity Chart
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Weekly Breakdown", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: weekData.map((day) {
                          return _BarColumn(
                            label: day['day'] as String,
                            height: (day['height'] as double).clamp(10.0, 120.0),
                            color: day['count'] as int > 0 ? Colors.blue : Colors.blue[50]!,
                            count: day['count'] as int,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                // 3. Top Fake Sources (only show if there are any)
                if (top3.isNotEmpty) ...[
                  const Text("Most Frequent Fake Sources", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  ...top3.map((entry) {
                    final maxCount = top3.first.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SourceTile(
                        name: entry.key,
                        count: entry.value,
                        percentage: entry.value / maxCount,
                      ),
                    );
                  }),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.shield, color: Colors.green[400], size: 40),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Text(
                            "No fake news sources detected yet. Keep verifying!",
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  List<Map<String, dynamic>> _getWeekData(Map<String, int> verdictsByDay, int total) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxCount = verdictsByDay.values.isEmpty ? 1 : verdictsByDay.values.reduce((a, b) => a > b ? a : b);
    
    return days.map((day) {
      final count = verdictsByDay[day] ?? 0;
      final height = count == 0 ? 10.0 : (count / maxCount * 100.0 + 20.0);
      
      return {
        'day': day,
        'count': count,
        'height': height,
      };
    }).toList();
  }
}

class _OverviewCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle; // Added for percentage
  final Color color;
  final IconData icon;

  const _OverviewCard({
    required this.label, 
    required this.value, 
    this.subtitle, 
    required this.color, 
    required this.icon
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              if (subtitle != null) ...[
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3.0),
                  child: Text(subtitle!, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ]
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  final String label;
  final double height;
  final Color color;
  final int count;

  const _BarColumn({required this.label, required this.height, required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (count > 0)
          Text(count.toString(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        if (count > 0) const SizedBox(height: 4),
        Container(
          width: 12,
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  final String name;
  final int count;
  final double percentage;

  const _SourceTile({required this.name, required this.count, required this.percentage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text("$count detected", style: TextStyle(color: Colors.red[400], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage,
            backgroundColor: Colors.grey[100],
            color: Colors.red[400],
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }
}