import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import '../utils/app_utils.dart';
import 'verify_link_screen.dart';

class AllNewsScreen extends StatefulWidget {
  final List<dynamic> newsItems;

  const AllNewsScreen({super.key, required this.newsItems});

  @override
  State<AllNewsScreen> createState() => _AllNewsScreenState();
}

class _AllNewsScreenState extends State<AllNewsScreen> {
  // Pills shown at the top. "All" first; the rest match backend categories.
  static const List<String> _categories = [
    "All", "Politics", "Business", "Sports", "World",
    "Technology", "Entertainment", "Health", "General",
  ];

  String _selected = "All";
  late List<dynamic> _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _items = widget.newsItems; // show the passed-in list immediately
    _fetchMore();
  }

  Future<void> _fetchMore() async {
    try {
      final more = await ApiService.fetchNews(limit: 60)
          .timeout(const Duration(seconds: 20), onTimeout: () => []);
      if (!mounted) return;
      if (more.isNotEmpty) setState(() => _items = more);
    } catch (_) {
      // keep whatever we already have
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _catOf(dynamic it) {
    final m = it is Map ? it : const {};
    final c = (m['category'] ?? '').toString().trim();
    return c.isEmpty ? 'General' : c;
  }

  List<dynamic> get _filtered {
    if (_selected == "All") return _items;
    return _items.where((it) => _catOf(it) == _selected).toList();
  }

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
  // Category pills
  // =========================
  Widget _pill(String label) {
    final bool sel = _selected == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => setState(() => _selected = label),
        showCheckmark: false,
        selectedColor: const Color(0xFF1565C0),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: sel ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        shape: StadiumBorder(
          side: BorderSide(color: sel ? const Color(0xFF1565C0) : Colors.grey.shade300),
        ),
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final items = _filtered;

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
      body: Column(
        children: [
          // ── Category pills ─────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 10, top: 4),
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _categories.map(_pill).toList(),
              ),
            ),
          ),

          // ── News list ─────────────────────────────────────────────────
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _fetchMore,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          itemBuilder: (context, index) =>
                              _buildNewsCard(context, items[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      // ListView so pull-to-refresh still works in the empty state
      children: [
        const SizedBox(height: 120),
        Icon(LucideIcons.newspaper, size: 48, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _selected == "All"
                ? "No news available"
                : "No $_selected news right now",
            style: TextStyle(color: Colors.grey[600], fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
    final String category = _catOf(m);
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
                // Source + category chips
                Row(
                  children: [
                    Flexible(
                      child: Container(
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
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _sourceColor(category).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          color: _sourceColor(category),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
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
