import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '/../services/api_service.dart';
import '../../verify_link_screen.dart';

class NewsCard extends StatelessWidget {
  final dynamic item;
  const NewsCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final map = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
    final String title = (map['title'] ?? 'No Title').toString();
    final String source = (map['source'] ?? 'News').toString();
    final String? url = _extractUrl(map);
    final String? imageUrl = ApiService.resolveNewsImageUrl(map);

    return Container(
      margin: const EdgeInsets.only(right: 16, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: _buildImage(imageUrl),
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.toUpperCase(), style: TextStyle(color: Colors.blue[800], fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const SizedBox(height: 5),
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.2)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: url == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => VerifyLinkScreen(initialUrl: url))),
                      icon: const Icon(LucideIcons.shieldCheck, size: 14),
                      label: const Text("Verify Authenticity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[50],
                        foregroundColor: Colors.blue[700],
                        elevation: 0,
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

  String? _extractUrl(Map m) {
    final v = m['url'] ?? m['link'] ?? m['articleUrl'];
    if (v == null) return null;
    String s = v.toString();
    if (s.startsWith("www.")) s = "https://$s";
    return s;
  }

  Widget _buildImage(String? url) {
    if (url == null || url.isEmpty) return _fallback();
    return Image.network(url, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => _fallback());
  }

  Widget _fallback() => Container(
    color: Colors.grey[100],
    child: Center(child: Image.asset("assets/images/logo.png", width: 40, opacity: const AlwaysStoppedAnimation(0.2))),
  );
}