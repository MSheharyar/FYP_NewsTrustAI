import 'result_view_model.dart';

// Single source of truth for converting internal verification_method values
// into plain-language strings shown to the user. No pipeline jargon reaches the UI.
const Map<String, String> kMethodFriendlyText = {
  'db_match': 'We found this story in trusted news sources.',
  'soft_db_match': 'We found a closely matching story in trusted sources.',
  'weak_similar_coverage': 'We found loosely related coverage, but not a strong match.',
  'edited_claim_suspected':
      'This looks like an altered version of a real story — key details (names, places, or numbers) don\'t match.',
  'input_too_vague':
      'There wasn\'t enough detail to check this. Try pasting the full claim.',
  'google_factcheck': 'A professional fact-checking organization has reviewed this.',
  'newsapi_cross_verified': 'Recent reporting from trusted publishers supports this.',
  'gdelt_main_sources': 'Major news outlets are reporting this.',
  'gdelt_other_major_sources': 'Some established outlets are reporting this.',
  'nli_semantic': 'The evidence we found supports this claim.',
  'nli_contradiction': 'The evidence we found contradicts this claim.',
  'bert_only':
      'Our AI model flagged the wording as likely fake; we couldn\'t find supporting sources.',
  'bert_suggested_real':
      'Our AI model thinks this is likely genuine, but we couldn\'t confirm it with sources.',
  'no_evidence': 'We couldn\'t find any evidence about this claim.',
  'error_degraded': 'Part of our check didn\'t complete. Please try again in a moment.',
};

String friendlyMethod(String? method) =>
    kMethodFriendlyText[method] ?? 'We analyzed this claim against our sources.';

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

  // edited_claim_suspected — keep as unverified in UI (backend returns unverified)
  if (method == "edited_claim_suspected") {
    label = "unverified";
    conf = conf ?? _toDouble(data["final_confidence"]) ?? _toDouble(data["confidence"]);
  }

  final bool isReal = label == "real" || label == "verified" || label == "true";
  final bool isFake = label == "fake" || label == "false";
  final bool isMixed = label == "mixed";
  final bool isUnverified = !isReal && !isFake && !isMixed;

  String verdictTitle;
  String badgeText;
  String verdictSubtitle;

  if (method == "edited_claim_suspected") {
    verdictTitle = "Not Verified";
    badgeText = "Unverified";
    verdictSubtitle = "Edited / altered claim suspected — key facts don't match known coverage.";
  } else if (isReal && method == "soft_db_match") {
    verdictTitle = "Likely Real";
    badgeText = "Likely Real";
    verdictSubtitle = "Similar coverage found, but not a strong direct match — treat with some caution.";
  } else if (isReal && method == "weak_similar_coverage") {
    verdictTitle = "Possibly Real";
    badgeText = "Unconfirmed";
    verdictSubtitle = "Weak related coverage found — insufficient to confirm.";
  } else if (isReal) {
    verdictTitle = "Verified";
    badgeText = "Verified";
    verdictSubtitle = "We found strong supporting evidence.";
  } else if (isFake) {
    verdictTitle = "Fake / Misleading";
    badgeText = "Fake";
    verdictSubtitle = "Evidence suggests this claim is not reliable.";
  } else if (isMixed) {
    verdictTitle = "Disputed / Mixed Signals";
    badgeText = "Mixed";
    verdictSubtitle = "Fact-checkers have reached conflicting conclusions on this claim.";
  } else {
    verdictTitle = "Unverified (Insufficient Evidence)";
    badgeText = "Unverified";
    verdictSubtitle = "We couldn’t confirm this claim with strong evidence.";
  }

  final String detectedLanguage =
      _safeStr(data["detected_language"], "english").toLowerCase().trim();

  final bool staleEvidence = _isTrue(data["stale_evidence"]);
  final int? evidenceAgeDays = (data["evidence_age_days"] is num)
      ? (data["evidence_age_days"] as num).toInt()
      : null;
  final bool nliConfirmed = _isTrue(data["nli_confirmed"]);
  final String? bertNote = (data["bert_note"] is String && (data["bert_note"] as String).isNotEmpty)
      ? data["bert_note"] as String
      : null;

  final String backendReason = _safeStr(data["final_reason"], "").trim();
  final String explanationText = _safeStr(data["explanation_text"], "").trim();
  final String bertLabel = _safeStr(data["bert_label"], _safeStr(data["label"], "")).toLowerCase().trim();
  // Backend sends bert_confidence as 0–1 float; convert to 0–100 for display.
  double? rawBertConf = _toDouble(data["bert_confidence"] ?? data["confidence"]);
  if (rawBertConf != null && rawBertConf <= 1.0) rawBertConf = rawBertConf * 100.0;
  final double? bertConfidence = rawBertConf;
  final bool modelDisagreement = _isTrue(data["model_disagreement"]);

  String reasonText = explanationText.isNotEmpty
      ? explanationText
      : backendReason.isNotEmpty
          ? backendReason
          : (method == "edited_claim_suspected"
              ? "We found similar articles, but key facts (person/place/date/number/org) don’t match."
              : (isReal
                  ? "We found matching reporting from credible sources."
                  : isFake
                      ? "We found signals that contradict or discredit the claim."
                      : "We found similar coverage, but not enough strong evidence to verify."));

  // Build the "how we checked" text from the plain-language map.
  String whatCheckedText = friendlyMethod(method.isNotEmpty ? method : null);

  if (bertLabel.isNotEmpty && method != "bert_only") {
    final String modelLabelText = bertLabel == "fake" ? "Fake/Misleading" : "Real";
    final String modelText = bertConfidence != null
        ? "\n\nAI model also predicted '$modelLabelText' with ${bertConfidence.toStringAsFixed(0)}% confidence."
        : "\n\nAI model also predicted '$modelLabelText'.";
    whatCheckedText += modelText;
  }

  if (modelDisagreement) {
    whatCheckedText +=
        "\n\nNote: Our AI model and evidence sources reached different conclusions — review the matched sources carefully.";
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
    explanationText: explanationText,
    bertLabel: bertLabel,
    bertConfidence: bertConfidence,
    modelDisagreement: modelDisagreement,
    factsDebug: factsDebug,
    isReal: isReal,
    isFake: isFake,
    isMixed: isMixed,
    isUnverified: isUnverified,
    detectedLanguage: detectedLanguage,
    staleEvidence: staleEvidence,
    evidenceAgeDays: evidenceAgeDays,
    nliConfirmed: nliConfirmed,
    bertNote: bertNote,
  );
}
