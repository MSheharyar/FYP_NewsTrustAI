import 'package:flutter/material.dart';

// ─── URL extraction ──────────────────────────────────────────────────────────

/// Extracts a usable URL from a news item map, trying all known field names.
/// Returns null if no URL is found.
String? extractNewsUrl(dynamic item) {
  Map<String, dynamic> m = {};
  if (item is Map<String, dynamic>) {
    m = item;
  } else if (item is Map) {
    m = Map<String, dynamic>.from(item);
  }

  final v = m['url'] ??
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
  if (s.startsWith('www.')) return 'https://$s';
  if (!s.startsWith('http')) return 'https://$s';
  return s;
}

// ─── HTML cleanup ────────────────────────────────────────────────────────────

/// Strips HTML tags and decodes common entities from RSS summary/description
/// text, so raw markup like `<img src="...">` never reaches the UI or the
/// verification query.
String stripHtml(String? input) {
  if (input == null) return '';
  var s = input.replaceAll(RegExp(r'<[^>]*>'), ' ');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ─── Phone normalisation ─────────────────────────────────────────────────────

/// Converts a Pakistani phone number to E.164 (+92...) format.
String normalizePhone(String phone) {
  phone = phone.trim();
  if (phone.isEmpty) return '';
  if (phone.startsWith('0')) return '+92${phone.substring(1)}';
  if (!phone.startsWith('+') && phone.length >= 10) return '+92$phone';
  return phone;
}

// ─── Verdict helpers ─────────────────────────────────────────────────────────

/// Returns true when the verdict string means "fake / false".
bool verdictIsFake(String verdict) {
  final v = verdict.toLowerCase();
  return v == 'fake' || v == 'false';
}

/// Returns true when the verdict string means "real / verified".
bool verdictIsReal(String verdict) {
  final v = verdict.toLowerCase();
  return v == 'real' || v == 'verified';
}

/// Returns (icon, color, badgeText) for a verdict string.
({IconData icon, Color color, String badgeText}) verdictBadge(
  String verdict, {
  required IconData fakeIcon,
  required IconData realIcon,
  required IconData unknownIcon,
}) {
  if (verdictIsFake(verdict)) {
    return (icon: fakeIcon, color: Colors.red, badgeText: 'FAKE');
  }
  if (verdictIsReal(verdict)) {
    return (icon: realIcon, color: Colors.green, badgeText: 'REAL');
  }
  return (icon: unknownIcon, color: Colors.orange, badgeText: 'UNKNOWN');
}

// ─── Snackbar ────────────────────────────────────────────────────────────────

/// Shows a consistently styled floating snackbar.
void showAppSnackBar(
  BuildContext context,
  String message, {
  Color color = Colors.red,
  Duration duration = const Duration(seconds: 3),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      duration: duration,
    ),
  );
}
