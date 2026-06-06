import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VerdictCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double? confidence;
  final String method;

  const VerdictCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.confidence,
    this.method = "",
  });

  bool _hasWord(String text, String word) {
    final r = RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false);
    return r.hasMatch(text);
  }

  bool _looksUnverified(String t) {
    final s = t.toLowerCase();
    return s.contains("unverified") ||
        s.contains("not verified") ||
        s.contains("insufficient") ||
        s.contains("no evidence");
  }

  bool _looksFake(String t) {
    final s = t.toLowerCase();
    return s.contains("fake") || s.contains("misleading") || _hasWord(t, "false");
  }

  bool _looksVerified(String t) {
    if (_looksUnverified(t)) return false;
    return _hasWord(t, "verified") || _hasWord(t, "real") || _hasWord(t, "true");
  }

  Color _toneColor() {
    final m = method.toLowerCase().trim();
    if (m == "edited_claim_suspected") return Colors.amber;
    if (m == "soft_db_match") return const Color(0xFF00897B); // teal
    if (m == "weak_similar_coverage") return Colors.blueGrey;

    if (_looksFake(title)) return Colors.red;
    if (_looksUnverified(title)) return Colors.amber;
    if (_looksVerified(title)) return Colors.green;

    return Colors.blueGrey;
  }

  IconData _toneIcon() {
    final m = method.toLowerCase().trim();
    if (m == "edited_claim_suspected") return LucideIcons.alertTriangle;
    if (m == "soft_db_match") return LucideIcons.checkCircle2;
    if (m == "weak_similar_coverage") return LucideIcons.helpCircle;

    if (_looksFake(title)) return LucideIcons.shieldAlert;
    if (_looksUnverified(title)) return LucideIcons.badgeHelp;
    if (_looksVerified(title)) return LucideIcons.badgeCheck;

    return LucideIcons.helpCircle;
  }

  String _confidenceLine() {
    if (confidence == null) return "";
    final c = confidence!.clamp(0, 100).toDouble();
    final m = method.toLowerCase().trim();
    if (m == "soft_db_match") return "Fuzzy match — ${c.toStringAsFixed(0)}% similarity";
    if (m == "weak_similar_coverage") return "Weak match — ${c.toStringAsFixed(0)}% similarity";
    if (c >= 95) return "Very high accuracy (95–100%)";
    if (c >= 85) return "High accuracy (85–95%)";
    if (c >= 70) return "Medium accuracy (70–84%)";
    if (c > 0) return "Low accuracy (${c.toStringAsFixed(0)}%) - Likely Fake/Unverified";
    return "Confidence unavailable";
  }

  @override
  Widget build(BuildContext context) {
    final tone = _toneColor();
    final icon = _toneIcon();
    final confLine = _confidenceLine();
    
    // Normalize confidence for the gauge (0.0 to 1.0)
    final double gaugeValue = (confidence == null || confidence! <= 0) ? 0.0 : (confidence! / 100.0).clamp(0.0, 1.0);

    final bool isVerifiedStyle =
        _looksVerified(title) && method.toLowerCase().trim() != "edited_claim_suspected";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26), 
      decoration: BoxDecoration(
        color: tone.withValues(alpha:isVerifiedStyle ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tone.withValues(alpha:isVerifiedStyle ? 0.18 : 0.12)),
        boxShadow: [
          BoxShadow(
            color: (isVerifiedStyle ? tone : Colors.black).withValues(alpha:isVerifiedStyle ? 0.18 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // The Animated Circular Gauge
          SizedBox(
            width: 80,
            height: 80,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: gaugeValue),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: value, // Dynamically updates!
                      strokeWidth: 6,
                      backgroundColor: tone.withValues(alpha:0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(tone),
                    ),
                    Center(child: child!),
                  ],
                );
              },
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha:0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tone, size: 30),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (confLine.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha:0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                confLine,
                style: TextStyle(
                  color: tone.withValues(alpha:0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
