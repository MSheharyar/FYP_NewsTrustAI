import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;

class ApiService {
  // Backend Configuration
  // Set useLocalBackend to true for development, false for production
  static const bool useLocalBackend = true; // ✅ Set to true for local testing

  // Optional override:
  // flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
  static final String _baseUrlOverride =
      const String.fromEnvironment('API_BASE_URL', defaultValue: '').trim();
  
  // Production Server (AWS EC2 or deployed backend)
  static const String _productionUrl = "http://127.0.0.1:8000"; // FORCED TO LOCALHOST
  
  // Local Development
  // Web/Desktop use localhost, Mobile uses device-specific URLs
  static String get _localUrl {
    // Keep original behavior: web builds use the deployed backend by default.
    // Use --dart-define=API_BASE_URL=... to override when needed.
    if (kIsWeb) return "http://127.0.0.1:8000";

    // Android emulator cannot reach host via localhost.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return "http://10.0.2.2:8000";
    }

    return "http://localhost:8000";
  }
  
  static String get _base {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    return useLocalBackend ? _localUrl : _productionUrl;
  }

  static Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  static String _extractErrorMessage(http.Response res) {
    final fallback = "Server error ${res.statusCode}";
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        final detail = m["detail"];
        if (detail is String && detail.trim().isNotEmpty) return detail.trim();
        if (detail is List && detail.isNotEmpty) {
          // FastAPI validation errors are often a list of {loc, msg, type}
          final first = detail.first;
          if (first is Map && first["msg"] is String) return (first["msg"] as String).trim();
          return "Request validation failed";
        }
        final message = m["message"];
        if (message is String && message.trim().isNotEmpty) return message.trim();
      }
      if (decoded is String && decoded.trim().isNotEmpty) return decoded.trim();
    } catch (_) {
      // ignore JSON errors; fall back below
    }
    if (res.body.trim().isNotEmpty && res.body.length < 200) {
      return "$fallback: ${res.body.trim()}";
    }
    return fallback;
  }

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse("$_base$path"),
            headers: await _authHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return {"error": true, "message": "Invalid server response format"};
      }

      return {"error": true, "message": _extractErrorMessage(res)};
    } on TimeoutException {
      return {"error": true, "message": "Request timed out. Please try again."};
    } catch (e) {
      return {"error": true, "message": e.toString()};
    }
  }

  static Future<List<dynamic>> _getList(String path) async {
    try {
      final headers = await _authHeaders();
      final res = await http
          .get(Uri.parse("$_base$path"), headers: headers)
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);

        if (decoded is List) return decoded;

        if (decoded is Map && decoded["items"] is List) {
          return decoded["items"] as List;
        }
      }
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }
    return [];
  }

  // ✅ UPDATED: supports query
  static Future<Map<String, dynamic>> verifyText(
    String text, {
    String? query,
  }) {
    final payload = <String, dynamic>{
      "text": text,
      if (query != null && query.trim().isNotEmpty) "query": query.trim(),
    };
    return _postJson("/verify-text", payload);
  }

  static Future<Map<String, dynamic>> analyzeLink(String url) {
    return _postJson("/analyze-link", {"url": url.trim()});
  }

  static Future<List<dynamic>> fetchTrending({bool force = false}) async {
    return _getList("/trending");
  }

  static Future<List<dynamic>> fetchQuickExamples() async {
    final items = await fetchTrending();
    return items.take(5).toList();
  }

  static Future<Map<String, dynamic>> chat(
    String message, {
    List<Map<String, dynamic>>? history,
    String? context,
  }) {
    return _postJson("/chat", {
      "message": message,
      if (history != null && history.isNotEmpty) "history": history,
      if (context != null && context.isNotEmpty) "context": context,
    });
  }

  // ✅ Robust: fixes www., //, relative paths, "null"/"none"
  static String? resolveNewsImageUrl(Map<String, dynamic> item) {
    String s(dynamic v) => (v ?? "").toString().trim();

    bool bad(String v) {
      final x = v.trim().toLowerCase();
      return x.isEmpty || x == "null" || x == "none" || x == "na";
    }

    String normalize(String raw) {
      var url = raw.trim();

      // handle scheme-less urls
      if (url.startsWith("//")) url = "https:$url";
      if (url.startsWith("www.")) url = "https://$url";

      // absolute already
      if (url.startsWith("http://") || url.startsWith("https://")) return url;

      // relative -> attach backend base
      if (url.startsWith("/")) return "$_base$url";
      return "$_base/$url";
    }

    // backend fixed fields first
    final fixed = s(item["imageFixedUrl"]);
    if (!bad(fixed)) return normalize(fixed);

    final fixed2 = s(item["image_fixed_url"]);
    if (!bad(fixed2)) return normalize(fixed2);

    // common feed fields
    final img = s(item["imageUrl"]);
    if (!bad(img)) return normalize(img);

    final img2 = s(item["image_url"]);
    if (!bad(img2)) return normalize(img2);

    final img3 = s(item["image"]);
    if (!bad(img3)) return normalize(img3);

    final thumb = s(item["thumbnail"]);
    if (!bad(thumb)) return normalize(thumb);

    return null;
  }
}