import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../result_view_model.dart'; 

class MatchedSourceCard extends StatelessWidget {
  final SourceMatchVM src;
  const MatchedSourceCard({super.key, required this.src});

  Future<void> _open(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null) return;
    if (!await canLaunchUrl(u)) return;
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  String _typeLabel() {
    final t = src.type.toLowerCase();
    if (t == "factcheck") return "Fact-check";
    if (t == "live") return "Live sources";
    if (t == "db") return "Database";
    return "Source";
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return "Unknown date";
    try {
      final dt = DateTime.parse(rawDate);
      final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      return "${months[dt.month - 1]} ${dt.day}, ${dt.year}";
    } catch (e) {
      return rawDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color tagColor = src.trusted ? Colors.green : Colors.orange;
    final t = src.type.toLowerCase();
    final Color typeColor =
        (t == "factcheck") ? Colors.blue : (t == "live") ? Colors.purple : Colors.teal;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  src.source.isEmpty ? "Source" : src.source,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _typeLabel(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: typeColor),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  src.trusted ? "Trusted" : "Other",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tagColor),
                ),
              )
            ],
          ),
          const SizedBox(height: 14),
          
          if (src.time != null && src.time!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(LucideIcons.calendar, size: 14, color: Colors.black54),
                  const SizedBox(width: 6),
                  Text(_formatDate(src.time), style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            
          if (src.domain.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(LucideIcons.globe, size: 14, color: Colors.black54),
                  const SizedBox(width: 6),
                  Text(src.domain, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
                ],
              ),
            ),

          if (src.rating != null && src.rating!.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "Rating: ${src.rating}",
                style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w700),
              ),
            ),

          const SizedBox(height: 14),
          
          // The Animated Match Score Progress Bar
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: src.score),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      "Match: ${value.toStringAsFixed(0)}%", 
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.w800,
                        color: value > 80 ? Colors.green[700] : (value > 50 ? Colors.orange[700] : Colors.red[700])
                      )
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value / 100,
                        backgroundColor: Colors.grey[200],
                        color: value > 80 ? Colors.green : (value > 50 ? Colors.orange : Colors.red),
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              );
            }
          ),
          
          const SizedBox(height: 16),
          
          if (src.url.trim().isNotEmpty)
            InkWell(
              onTap: () => _open(src.url),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.externalLink, size: 14, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      "Read original article",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
