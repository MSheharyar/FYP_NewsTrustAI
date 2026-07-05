import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '/../services/api_service.dart';
import '/../utils/app_utils.dart';
import '../../verify_link_screen.dart';

class NewsCard extends StatelessWidget {
  final dynamic item;
  const NewsCard({super.key, required this.item});

  // Deterministic accent colour based on source name
  static Color _sourceColor(String source) {
    const palette = [
      Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
      Color(0xFFC62828), Color(0xFF00695C), Color(0xFF4527A0),
      Color(0xFF283593), Color(0xFF558B2F),
    ];
    return palette[source.hashCode.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final map = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
    final String title  = (map['title']  ?? 'No Title').toString();
    final String source = (map['source'] ?? 'News').toString();
    final String? url   = extractNewsUrl(map);
    final String? imageUrl = ApiService.resolveNewsImageUrl(map);
    final Color accent  = _sourceColor(source);

    return Container(
      margin: const EdgeInsets.only(right: 16, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image / header ───────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: _buildHeader(imageUrl, source, accent),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.toUpperCase(),
                    style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.25),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: url == null
                          ? null
                          : () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => VerifyLinkScreen(initialUrl: url))),
                      icon: const Icon(LucideIcons.shieldCheck, size: 13),
                      label: const Text("Verify", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent.withValues(alpha: 0.1),
                        foregroundColor: accent,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
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

  Widget _buildHeader(String? imageUrl, String source, Color accent) {
    // If image URL exists, try to load it
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _gradientFallback(source, accent),
      );
    }
    return _gradientFallback(source, accent);
  }

  Widget _gradientFallback(String source, Color accent) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.newspaper, color: Colors.white, size: 28),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              source,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
