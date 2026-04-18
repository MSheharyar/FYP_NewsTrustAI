import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api_service.dart';
import 'result/result_screen.dart';

class VerifyLinkScreen extends StatefulWidget {
  final String? initialUrl;
  const VerifyLinkScreen({super.key, this.initialUrl});

  @override
  State<VerifyLinkScreen> createState() => _VerifyLinkScreenState();
}

class _VerifyLinkScreenState extends State<VerifyLinkScreen> {
  late final TextEditingController _controller;

  bool _isLoading = false;

  // ✅ Trending (same idea as VerifyTextScreen)
  bool _loadingTrending = false;
  List<dynamic> _trending = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? "");
    _loadTrendingLinks(); // ✅ load trending links for examples section
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VerifyLinkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUrl != null &&
        widget.initialUrl!.trim().isNotEmpty &&
        widget.initialUrl != oldWidget.initialUrl) {
      _controller.text = widget.initialUrl!.trim();
    }
  }

  // ✅ fetch trending like HomeTab does (doesn't affect any other logic)
  Future<void> _loadTrendingLinks() async {
    if (_loadingTrending) return;
    setState(() => _loadingTrending = true);

    try {
      final items = await ApiService.fetchTrending();
      if (!mounted) return;
      setState(() {
        _trending = items;
        _loadingTrending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTrending = false);
    }
  }

  String _extractTitle(dynamic item) {
    if (item is Map<String, dynamic>) {
      return (item["title"] ?? "Untitled").toString();
    }
    if (item is Map) {
      final m = Map<String, dynamic>.from(item);
      return (m["title"] ?? "Untitled").toString();
    }
    return "Untitled";
  }

  String? _extractUrl(dynamic item) {
    Map<String, dynamic> m = {};
    if (item is Map<String, dynamic>) {
      m = item;
    } else if (item is Map) {
      m = Map<String, dynamic>.from(item);
    }

    final v = m["url"] ??
        m["link"] ??
        m["articleUrl"] ??
        m["article_url"] ??
        m["newsUrl"] ??
        m["news_url"] ??
        m["sourceUrl"] ??
        m["source_url"] ??
        m["webUrl"] ??
        m["web_url"];

    if (v == null) return null;

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    if (s.startsWith("www.")) return "https://$s";
    return s;
  }

  bool _isValidUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return false;

    final parsed = Uri.tryParse(u);
    if (parsed == null) return false;

    if (!(parsed.scheme == "http" || parsed.scheme == "https")) return false;
    if (parsed.host.isEmpty) return false;

    return true;
  }

  Future<void> _safeAnalyzeLink() async {
    if (_isLoading) return;
    await _analyzeLink();
  }

  Future<void> _analyzeLink() async {
    final url = _controller.text.trim();

    if (!_isValidUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please paste a valid full URL (https://...)"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await ApiService.analyzeLink(url);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result["error"] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result["message"] ?? "Error"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    result["input_url"] = result["input_url"] ?? url;
    result["link_domain"] = result["link_domain"] ?? Uri.parse(url).host;
  
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          data: result,
          originalText: url,
          usedQuery: url,
          resultMode: "link",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Verify Link",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Paste article link below", style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),

              TextField(
                controller: _controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: "https://example.com/news/...",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _safeAnalyzeLink,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    disabledBackgroundColor: Colors.blue[200],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Analyze Link",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.info, color: Colors.blue[700], size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Tip: Link verification works best for article pages (not social media screenshots). "
                        "Paste the full URL including https://",
                        style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),

              // ✅ Trending Examples (Links)
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Trending Examples",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                    tooltip: "Refresh",
                    onPressed: _loadTrendingLinks,
                    icon: const Icon(LucideIcons.refreshCcw, size: 18),
                  ),
                ],
              ),

              if (_loadingTrending)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_trending.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text("No trending links available",
                      style: TextStyle(color: Colors.black54)),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _trending.length > 5 ? 5 : _trending.length,
                  itemBuilder: (context, i) {
                    final item = _trending[i];
                    final title = _extractTitle(item);
                    final url = _extractUrl(item);

                    return Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.trendingUp, color: Colors.green[600], size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: (url == null || url.isEmpty)
                                ? null
                                : () => setState(() => _controller.text = url),
                            child: const Text("Use"),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}