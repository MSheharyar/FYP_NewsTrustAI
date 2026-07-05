import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../utils/app_utils.dart';
import 'verify_link_screen.dart';

class AllNewsScreen extends StatelessWidget {
  final List<dynamic> newsItems;

  const AllNewsScreen({super.key, required this.newsItems});

  // =========================
  // Image helpers
  // =========================
  Widget _newsImage(String? url, String source) {
    final u = (url ?? "").trim();

    if (u.isEmpty) return _logoFallback(source);

    return Image.network(
      u,
      height: 120,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _logoFallback(source);
      },
      errorBuilder: (_, __, ___) => _logoFallback(source),
    );
  }

  static Color _sourceColor(String source) {
    const palette = [
      Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
      Color(0xFFC62828), Color(0xFF00695C), Color(0xFF4527A0),
      Color(0xFF283593), Color(0xFF558B2F),
    ];
    return palette[source.hashCode.abs() % palette.length];
  }

  Widget _logoFallback(String source) {
    final color = _sourceColor(source);
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.newspaper, color: Colors.white, size: 30),
          const SizedBox(height: 6),
          Text(
            source,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          "Trending News",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: newsItems.isEmpty
          ? const Center(child: Text("No news available"))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: newsItems.length,
              itemBuilder: (context, index) {
                return _buildNewsCard(context, newsItems[index]);
              },
            ),
    );
  }

  Widget _buildNewsCard(BuildContext context, dynamic item) {
    final Map<String, dynamic> m = (item is Map<String, dynamic>)
        ? item
        : (item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{});

    final String title = stripHtml(m['title']?.toString()).isEmpty ? "No Title" : stripHtml(m['title']?.toString());
    final String descRaw = stripHtml(m['summary']?.toString());
    final String desc = descRaw.isEmpty ? "No summary available." : descRaw;
    final String source = (m['source'] ?? "News Source").toString();
    final String? url = extractNewsUrl(m);
    final String? imageUrl = ApiService.resolveNewsImageUrl(m);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: _newsImage(imageUrl, source),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Title
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),

                // Description
                Text(
                  desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),

                // Button
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: (url == null || url.isEmpty)
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VerifyLinkScreen(initialUrl: url),
                              ),
                            );
                          },
                    icon: const Icon(LucideIcons.search, size: 16),
                    label: const Text(
                      "Verify Authenticity",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: BorderSide(color: Colors.blue.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}