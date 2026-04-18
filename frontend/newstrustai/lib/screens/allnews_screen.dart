import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import 'verify_link_screen.dart';

class AllNewsScreen extends StatelessWidget {
  final List<dynamic> newsItems;

  const AllNewsScreen({super.key, required this.newsItems});

  String? extractNewsUrl(Map<String, dynamic> m) {
    dynamic v = m['url'] ??
        m['link'] ??
        m['articleUrl'] ??
        m['article_url'] ??
        m['newsUrl'] ??
        m['news_url'] ??
        m['sourceUrl'] ??
        m['source_url'] ??
        m['webUrl'] ??
        m['web_url'];

    if (v == null) return null;

    final s = v.toString().trim();
    if (s.isEmpty) return null;
    if (s.startsWith("www.")) return "https://$s";
    if (!s.startsWith("http")) return "https://$s";
    return s;
  }

  // =========================
  // Image helpers
  // =========================
  Widget _newsImage(String? url) {
    final u = (url ?? "").trim();

    if (u.isEmpty) return _logoFallback();

    return Image.network(
      u,
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _logoFallback();
      },
      errorBuilder: (_, __, ___) => _logoFallback(),
    );
  }

  Widget _logoFallback() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFEAF2FF),
            Color(0xFFF4F7FC),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            "assets/images/logo.png",
            width: 48, // ✅ small logo
            height: 48,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 6),
          const Text(
            "NewsTrust AI",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
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

    final String title = (m['title'] ?? "No Title").toString();
    final String desc = (m['summary'] ?? "No summary available.").toString();
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
            color: Colors.black.withOpacity(0.05),
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
              height: 180,
              width: double.infinity,
              child: _newsImage(imageUrl),
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