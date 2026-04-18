import 'result_view_model.dart';

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  return double.tryParse(s);
}

String _safeStr(dynamic v, [String fallback = ""]) {
  if (v == null) return fallback;
  return v.toString();
}

bool _isTrue(dynamic v) => v == true || v == "true" || v == 1;

double _normScore(dynamic raw) {
  final d = _toDouble(raw);
  if (d == null) return 0.0;
  if (d <= 1.0) return d * 100.0;
  return d.clamp(0.0, 100.0);
}

String _inferType(Map<String, dynamic> m) {
  final t = _safeStr(m["type"], "").toLowerCase().trim();
  if (t.isNotEmpty) return t;
  if (m.containsKey("rating") || m.containsKey("textualRating")) return "factcheck";
  if (_safeStr(m["method"], "").toLowerCase().contains("gdelt")) return "live";
  return "db";
}

List<SourceMatchVM> _parseSources(Map<String, dynamic> data) {
  final rawList = (data["matched_sources"] ?? data["top_matches"] ?? data["sources"]);
  if (rawList is! List) return [];

  final out = <SourceMatchVM>[];
  for (final it in rawList) {
    if (it is! Map) continue;
    final m = Map<String, dynamic>.from(it);

    final timeVal = _safeStr(m["publishedAt"] ?? m["scrapedAt"] ?? m["time"] ?? "", "").trim();
    final type = _inferType(m);

    out.add(
      SourceMatchVM(
        source: _safeStr(m["source"] ?? m["sourceName"] ?? m["publisher"], "Source"),
        domain: _safeStr(m["domain"] ?? m["host"] ?? "", ""),
        url: _safeStr(m["url"] ?? m["link"] ?? "", ""),
        time: timeVal.isEmpty ? null : timeVal,
        score: _normScore(m["score"] ?? m["match_score"] ?? m["similarity"]),
        trusted: _isTrue(m["trusted"]) || _isTrue(m["is_trusted"]),
        type: type,
        rating: _safeStr(m["rating"] ?? m["textualRating"], "").trim().isEmpty
            ? null
            : _safeStr(m["rating"] ?? m["textualRating"]).trim(),
      ),
    );
  }
  return out;
}

ResultViewModel parseResultData(
  Map<String, dynamic> data, {
  String? usedQuery,
  String resultMode = "text",
  String? inputUrl,
}) {
  final bool hasHybrid = data.containsKey("final_label") || data.containsKey("final_confidence");
  final bool hasVerify = data.containsKey("verified") ||
      data.containsKey("top_matches") ||
      data.containsKey("matched_sources");
  final bool hasBert = data.containsKey("label") || data.containsKey("confidence");

  final String q = _safeStr(data["query_used"], _safeStr(usedQuery, "")).trim();

  final String linkDomain = _safeStr(data["link_domain"], "").trim();
  final String tier = _safeStr(data["source_tier"], "").toLowerCase().trim();
  final String method = _safeStr(data["verification_method"], "").toLowerCase().trim();

  String label = "unverified";
  double? conf;

  if (hasHybrid) {
    label = _safeStr(data["final_label"], "unverified").toLowerCase().trim();
    conf = _toDouble(data["final_confidence"]) ?? _toDouble(data["confidence"]);
  } else if (hasVerify) {
    label = _isTrue(data["verified"]) ? "real" : "unverified";
    conf = _toDouble(data["confidence"]);
  } else if (hasBert) {
    final l = _safeStr(data["label"], "unknown").toLowerCase();
    label = (l.contains("fake")) ? "fake" : (l.contains("real") ? "real" : "unverified");
    conf = _toDouble(data["confidence"]);
  }

  // ✅ If method says edited claim suspected, force it into "unverified" UI state
  if (method == "edited_claim_suspected") {
    label = "unverified";
    conf = conf ?? _toDouble(data["final_confidence"]) ?? _toDouble(data["confidence"]);
  }

  final bool isReal = label == "real" || label == "verified" || label == "true";
  final bool isFake = label == "fake" || label == "false";
  final bool isUnverified = !isReal && !isFake;

  String verdictTitle;
  String badgeText;
  String verdictSubtitle;

  if (method == "edited_claim_suspected") {
    verdictTitle = "Not Verified";
    badgeText = "Unverified";
    verdictSubtitle = "Edited / altered claim suspected.";
  } else if (isReal) {
    verdictTitle = "Verified";
    badgeText = "Verified";
    verdictSubtitle = "We found strong supporting evidence.";
  } else if (isFake) {
    verdictTitle = "Fake / Misleading";
    badgeText = "Fake";
    verdictSubtitle = "Evidence suggests this claim is not reliable.";
  } else {
    verdictTitle = "Unverified (Insufficient Evidence)";
    badgeText = "Unverified";
    verdictSubtitle = "We couldn’t confirm this claim with strong evidence.";
  }

  final String backendReason = _safeStr(data["final_reason"], "").trim();
  String reasonText = backendReason.isNotEmpty
      ? backendReason
      : (method == "edited_claim_suspected"
          ? "We found similar articles, but key facts (person/place/date/number/org) don’t match."
          : (isReal
              ? "We found matching reporting from credible sources."
              : isFake
                  ? "We found signals that contradict or discredit the claim."
                  : "We found similar coverage, but not enough strong evidence to verify."));

  String whatCheckedText =
      "We searched our trusted database and performed a live source lookup for similar coverage.";

  if (method == "input_too_vague") {
    whatCheckedText = "We couldn’t verify because the input text was too incomplete or unclear.";
  } else if (method == "db_match" || method == "soft_db_match" || method == "weak_similar_coverage") {
    whatCheckedText = "We compared your claim against our news database and looked for matching coverage.";
  } else if (method.startsWith("gdelt")) {
    whatCheckedText = "We performed a live lookup across major news domains for similar coverage.";
  } else if (method == "google_factcheck") {
    whatCheckedText = "We searched published fact-check databases for the same claim and reviewed ratings.";
  } else if (method == "edited_claim_suspected") {
    whatCheckedText = "We found related coverage but detected mismatched key facts, so we did not verify it.";
  }

  final tips = <String>[
    "Try a shorter claim (1–2 lines) instead of full paragraphs.",
    "Add key names/places (e.g., person + city + event).",
    "Verify again after a few minutes (sources update).",
    "If it’s from social media, verify the original publisher link.",
  ];

  final sources = _parseSources(data);

  final factsDebugRaw = data["facts_debug"];
  final Map<String, dynamic>? factsDebug =
      (factsDebugRaw is Map) ? Map<String, dynamic>.from(factsDebugRaw) : null;

  return ResultViewModel(
    verdictTitle: verdictTitle,
    verdictSubtitle: verdictSubtitle,
    reasonTitle: "Why this result?",
    reasonText: reasonText,
    whatCheckedText: whatCheckedText,
    tips: tips,
    badgeText: badgeText,
    confidence: conf,
    method: method,
    tier: tier,
    linkDomain: linkDomain,
    queryUsed: q,
    sources: sources,
    factsDebug: factsDebug,
    isReal: isReal,
    isFake: isFake,
    isUnverified: isUnverified,
  );
}
