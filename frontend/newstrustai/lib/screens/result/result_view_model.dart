class SourceMatchVM {
  final String source;
  final String domain;
  final String url;
  final String? time;
  final double score; // 0..100
  final bool trusted;

  // ✅ NEW
  final String type; // "factcheck" | "db" | "live" | "unknown"
  final String? rating; // for factcheck

  SourceMatchVM({
    required this.source,
    required this.domain,
    required this.url,
    required this.time,
    required this.score,
    required this.trusted,
    this.type = "unknown",
    this.rating,
  });
}

class ResultViewModel {
  final String verdictTitle;
  final String verdictSubtitle;
  final String reasonTitle;
  final String reasonText;
  final String whatCheckedText;
  final List<String> tips;

  final String badgeText;
  final double? confidence;

  final String method;
  final String tier;
  final String linkDomain;
  final String queryUsed;

  final List<SourceMatchVM> sources;

  final String explanationText;
  final String bertLabel;
  final double? bertConfidence;
  final bool modelDisagreement;

  // ✅ NEW: debug details
  final Map<String, dynamic>? factsDebug;

  final bool isReal;
  final bool isFake;
  final bool isMixed;
  final bool isUnverified;

  // "english" | "urdu"
  final String detectedLanguage;

  // Stale evidence warning (evidence older than 18 months)
  final bool staleEvidence;
  final int? evidenceAgeDays;

  // NLI semantic confirmation
  final bool nliConfirmed;

  // BERT unavailability note (Fix 7)
  final String? bertNote;

  ResultViewModel({
    required this.verdictTitle,
    required this.verdictSubtitle,
    required this.reasonTitle,
    required this.reasonText,
    required this.whatCheckedText,
    required this.tips,
    required this.badgeText,
    required this.confidence,
    required this.method,
    required this.tier,
    required this.linkDomain,
    required this.queryUsed,
    required this.sources,
    required this.explanationText,
    required this.bertLabel,
    required this.bertConfidence,
    required this.modelDisagreement,
    required this.factsDebug,
    required this.isReal,
    required this.isFake,
    required this.isMixed,
    required this.isUnverified,
    this.detectedLanguage = "english",
    this.staleEvidence = false,
    this.evidenceAgeDays,
    this.nliConfirmed = false,
    this.bertNote,
  });
}