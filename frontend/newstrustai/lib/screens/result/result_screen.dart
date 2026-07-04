import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'result_parser.dart';
import 'result_view_model.dart';
import 'widgets/verdict_card.dart';
import 'widgets/matched_source_card.dart';
import 'widgets/debug_details_card.dart';
import '/services/firestore_history_service.dart';
import '/widgets/highlighted_text.dart';
import '/screens/chatbot_screen.dart';

// ─── Radial confidence gauge ────────────────────────────────────────────────

class _ConfidenceGauge extends StatefulWidget {
  final double value; // 0–100
  final Color color;
  const _ConfidenceGauge({required this.value, required this.color});

  @override
  State<_ConfidenceGauge> createState() => _ConfidenceGaugeState();
}

class _ConfidenceGaugeState extends State<_ConfidenceGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _anim = Tween<double>(begin: 0, end: widget.value / 100)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: const Size(110, 110),
        painter: _GaugePainter(
          progress: _anim.value,
          color: widget.color,
          trackColor: widget.color.withValues(alpha: 0.12),
        ),
        child: SizedBox(
          width: 110,
          height: 110,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${(widget.value * _anim.value).toStringAsFixed(0)}%",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: widget.color,
                  ),
                ),
                Text(
                  "confidence",
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  final Color color;
  final Color trackColor;
  const _GaugePainter(
      {required this.progress,
      required this.color,
      required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const startAngle = 2.356; // 135° in radians (bottom-left)
    const sweepFull = 4.712; // 270°

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 8;
    final strokeWidth = 10.0;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Track (background arc)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull,
      false,
      trackPaint,
    );

    // Fill arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepFull * progress,
        false,
        fillPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────

class ResultScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  final String? originalText;
  final String? usedQuery;
  final String resultMode; 

  const ResultScreen({
    super.key,
    required this.data,
    this.originalText,
    this.usedQuery,
    this.resultMode = "text",
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _history = FirestoreHistoryService();
  bool _saved = false;
  bool? _feedbackGiven; // null = not yet given, true = helpful, false = not helpful

  Future<void> _submitFeedback(bool helpful, String verdict) async {
    if (_feedbackGiven != null) return;
    setState(() => _feedbackGiven = helpful);
    try {
      await _history.saveFeedback(verdict: verdict, helpful: helpful);
    } catch (_) {}
  }

  String _safeStr(dynamic v, [String fallback = ""]) {
    if (v == null) return fallback;
    return v.toString();
  }

  Future<void> _open(String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme) return;
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(u, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveToFirestoreOnce();
    });
  }

  Future<void> _saveToFirestoreOnce() async {
    if (_saved) return;
    _saved = true;

    final String inputUrl = (widget.data["input_url"] ??
            (widget.resultMode == "link"
                ? (widget.originalText ?? widget.usedQuery ?? "")
                : ""))
        .toString()
        .trim();

    final String inputToStore = widget.resultMode == "link"
        ? inputUrl
        : (widget.originalText ?? widget.usedQuery ?? "").toString().trim();

    final ResultViewModel vm = parseResultData(
      widget.data,
      usedQuery: widget.usedQuery,
      resultMode: widget.resultMode,
      inputUrl: widget.resultMode == "link" ? inputUrl : null,
    );

    final String verdict = vm.isReal ? "verified" : (vm.isFake ? "fake" : (vm.isMixed ? "mixed" : "unverified"));

    final List<Map<String, dynamic>> topMatches = vm.sources.map((s) {
      return {
        "type": s.type,
        "source": s.source,
        "domain": s.domain,
        "url": s.url,
        "time": s.time,
        "score": s.score,
        "trusted": s.trusted,
        "rating": s.rating,
      };
    }).toList();

    try {
      await _history.saveVerification(
        rawResult: widget.data,
        inputType: widget.resultMode,
        input: inputToStore,
        usedQuery: vm.queryUsed.isNotEmpty ? vm.queryUsed : (widget.usedQuery ?? ""),
        verdict: verdict,
        confidence: vm.confidence,
        method: vm.method,
        reason: vm.reasonText,
        topMatches: topMatches,
      );
    } catch (_) { }
  }

  // 🌟 Clean UI Helper for Tabbed Information 🌟
  Widget _buildAnalysisInsights(ResultViewModel vm) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            ExpansionTile(
              initiallyExpanded: true, // Keep the most important one open!
              leading: const Icon(LucideIcons.info, color: Colors.blue),
              title: Text(vm.reasonTitle, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(vm.reasonText, style: const TextStyle(color: Colors.black87, height: 1.4)),
              ],
            ),
            const Divider(height: 1),
            ExpansionTile(
              leading: const Icon(LucideIcons.search, color: Colors.purple),
              title: const Text("Verification Process", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                ...vm.whatCheckedText
                    .split('\n')
                    .where((line) => line.trim().isNotEmpty)
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          line.trim(),
                          style: const TextStyle(color: Colors.black87, height: 1.5),
                        ),
                      ),
                    ),
                if (vm.queryUsed.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    "Query used: ${vm.queryUsed}",
                    style: TextStyle(color: Colors.grey[700], fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
            const Divider(height: 1),
            ExpansionTile(
              leading: const Icon(LucideIcons.lightbulb, color: Colors.orange),
              title: const Text("Next Steps", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                ...vm.tips.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("•  ", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                        Expanded(child: Text(t, style: const TextStyle(color: Colors.black87, height: 1.3))),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildResultSummary(ResultViewModel vm) {
    final String methodLabel = _prettyMethodName(vm.method);
    final double confidence = vm.confidence?.clamp(0, 100).toDouble() ?? 0.0;
    final bool hasConfidence = vm.confidence != null;
    final bool hasDisagreement = vm.modelDisagreement;
    final Color statusColor = vm.isReal
        ? Colors.green[700]!
        : vm.isFake
            ? Colors.red[700]!
            : vm.isMixed
                ? Colors.purple[700]!
                : Colors.orange[800]!;
    final String statusLabel = vm.isReal
        ? "Supports the claim"
        : vm.isFake
            ? "Contradicts the claim"
            : vm.isMixed
                ? "Disputed / mixed signals"
                : "Insufficient evidence";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Quick summary", style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(methodLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasConfidence) ...[
            Center(
              child: _ConfidenceGauge(
                value: confidence,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (vm.queryUsed.trim().isNotEmpty) ...[
            Text("Query used", style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(vm.queryUsed, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4)),
          ],
          if (hasDisagreement) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Model and evidence disagree. Review this result carefully.",
                      style: TextStyle(color: Colors.orange[900], fontSize: 13, height: 1.4, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _prettyMethodName(String method) {
    switch (method.toLowerCase().trim()) {
      case "db_match":
        return "Verified by database coverage";
      case "soft_db_match":
        return "Soft match in stored news coverage";
      case "weak_similar_coverage":
        return "Weak related coverage found";
      case "google_factcheck":
        return "Published fact-check evidence";
      case "gdelt_main_sources":
        return "Live lookup from major sources";
      case "gdelt_other_major_sources":
        return "Live lookup from other major sources";
      case "edited_claim_suspected":
        return "Related coverage found, but key facts mismatch";
      case "input_too_vague":
        return "Input was too vague to verify";
      case "bert_only":
        return "Model-only prediction";
      case "bert_suggested_real":
        return "AI model suggests real (low confidence)";
      case "db_and_bert":
        return "Database evidence with model validation";
      case "factcheck_and_bert":
        return "Fact-check evidence with model validation";
      case "db_and_bert_conflict":
      case "factcheck_and_bert_conflict":
        return "Evidence and model disagreement";
      default:
        return "System evidence from multiple checks";
    }
  }

  Widget _buildModelEvidenceCard(ResultViewModel vm) {
    final bool hasModel = vm.bertLabel.isNotEmpty;
    final bool isFake = vm.bertLabel == "fake";
    // When evidence wins (isReal) but model flagged fake, soften the display
    final bool evidenceOverride = vm.modelDisagreement && vm.isReal;
    final String evidenceType = _prettyMethodName(vm.method);
    final String predictionText = hasModel
        ? (isFake
            ? (evidenceOverride ? "Flagged (overridden by evidence)" : "Fake / Misleading")
            : "Real")
        : "Not used";
    final String consensusText = vm.modelDisagreement
        ? (evidenceOverride
            ? "Evidence from trusted sources overrides the model flag. Verdict stands as Verified."
            : "Evidence and model disagree. This result requires careful review.")
        : hasModel
            ? "Evidence and model are aligned."
            : "Model prediction was not available.";
    final Color titleColor = vm.modelDisagreement
        ? (evidenceOverride ? Colors.blueGrey[700]! : Colors.orange[800]!)
        : Colors.blueGrey[900]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.layers, size: 18, color: titleColor),
              const SizedBox(width: 10),
              Text(
                "How the verdict was reached",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: titleColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "Evidence source: $evidenceType",
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          if (hasModel) ...[
            Text(
              "Model signal: $predictionText",
              style: TextStyle(fontWeight: FontWeight.w700, color: titleColor),
            ),
            if (!evidenceOverride && vm.bertConfidence != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    "${vm.bertConfidence!.toStringAsFixed(0)}%",
                    style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Model confidence",
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: (vm.bertConfidence! / 100.0).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(titleColor),
                ),
              ),
            ],
          ] else ...[
            Text(
              "Model signal: not available for this result.",
              style: TextStyle(color: Colors.black54),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            consensusText,
            style: TextStyle(color: vm.modelDisagreement ? Colors.orange[800]! : Colors.black54, height: 1.4),
          ),
          if (vm.nliConfirmed) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.checkCircle2, size: 15, color: Colors.teal[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Semantically verified — NLI model confirms the claim matches trusted sources.",
                      style: TextStyle(color: Colors.teal[800], fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (vm.staleEvidence) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.clock, size: 15, color: Colors.amber[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vm.evidenceAgeDays != null
                          ? "Evidence is ${vm.evidenceAgeDays} days old — verify with current sources."
                          : "Evidence may be outdated — verify with current sources.",
                      style: TextStyle(color: Colors.amber[900], fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (vm.bertNote != null && vm.bertNote!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 15, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "AI model note: ${vm.bertNote}",
                      style: TextStyle(color: Colors.grey[700], fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _buildLanguageBadge(vm.detectedLanguage),
        ],
      ),
    );
  }

  String _buildChatContext(ResultViewModel vm) {
    final buf = StringBuffer();
    // Include the actual claim so the AI knows WHAT was verified
    final claim = (widget.originalText ?? widget.usedQuery ?? '').trim();
    if (claim.isNotEmpty) buf.writeln("Claim: \"$claim\"");
    buf.writeln("Verdict: ${vm.verdictTitle} (${vm.badgeText})");
    if (vm.confidence != null) {
      buf.writeln("Confidence: ${vm.confidence!.toStringAsFixed(0)}%");
    }
    buf.writeln("Verification method: ${vm.method}");
    buf.writeln("Reason: ${vm.reasonText}");
    if (vm.bertLabel.isNotEmpty) {
      buf.write("AI model prediction: ${vm.bertLabel}");
      if (vm.bertConfidence != null) {
        buf.write(" (${vm.bertConfidence!.toStringAsFixed(0)}% confidence)");
      }
      buf.writeln();
    }
    if (vm.modelDisagreement) {
      buf.writeln("Note: Evidence and model disagreed on this result.");
    }
    if (vm.sources.isNotEmpty) {
      buf.writeln("Matched sources: ${vm.sources.map((s) => s.source).join(", ")}");
    }
    return buf.toString().trim();
  }

  Widget _buildLanguageBadge(String lang) {
    final bool isUrdu = lang == "urdu";
    final Color bg = isUrdu ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD);
    final Color fg = isUrdu ? const Color(0xFF2E7D32) : const Color(0xFF1565C0);
    final String label = isUrdu ? "Verified in: اردو (Urdu)" : "Verified in: English";

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.globe, size: 14, color: fg),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ResultViewModel vm = parseResultData(
      widget.data,
      usedQuery: widget.usedQuery,
      resultMode: widget.resultMode,
      inputUrl: widget.resultMode == "link" ? (widget.originalText ?? widget.usedQuery) : null,
    );

    final String inputUrl = (widget.data["input_url"] ??
            (widget.resultMode == "link" ? (widget.originalText ?? widget.usedQuery ?? "") : ""))
        .toString()
        .trim();

    final String linkDomain = _safeStr(widget.data["link_domain"], vm.linkDomain).trim();
    final String tier = _safeStr(widget.data["source_tier"], vm.tier).trim().toLowerCase();

    Color tierColor() {
      if (tier == "main") return Colors.green;
      if (tier == "other") return Colors.orange;
      return Colors.grey;
    }

    String tierText() {
      if (tier == "main") return "Main site";
      if (tier == "other") return "Other site";
      return "Unknown";
    }

    // Split sources into grouped lists
    final factchecks = vm.sources.where((s) => s.type.toLowerCase() == "factcheck").toList();
    final dbSources = vm.sources.where((s) => s.type.toLowerCase() == "db").toList();
    final liveSources = vm.sources.where((s) => s.type.toLowerCase() == "live").toList();
    final unknown = vm.sources.where((s) {
      final t = s.type.toLowerCase();
      return t != "factcheck" && t != "db" && t != "live";
    }).toList();

    final List<dynamic>? highlightedWords = widget.data["highlighted_words"];
    final String? explanationText = widget.data["explanation_text"];
    final bool hasExplainability = (highlightedWords != null && highlightedWords.isNotEmpty) &&
        widget.resultMode == "text" &&
        widget.originalText != null &&
        widget.originalText!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Analysis Result",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: "Share result",
            icon: const Icon(LucideIcons.share2),
            onPressed: () {
              final conf = vm.confidence != null
                  ? "${vm.confidence!.toStringAsFixed(0)}% confidence"
                  : "";
              final sources = vm.sources.isNotEmpty
                  ? "\nSources: ${vm.sources.take(3).map((s) => s.source).join(', ')}"
                  : "";
              final text =
                  "NewsTrust AI Result\n\nVerdict: ${vm.verdictTitle}\n$conf\n\n"
                  "${vm.reasonText}$sources\n\n"
                  "Verified using NewsTrust AI — an AI-powered fake news detector.";
              Share.share(text, subject: "NewsTrust AI Verification Result");
            },
          ),
        ],
      ),
      body: SafeArea(
        // 🌟 Replaced SingleChildScrollView with hyper-performant CustomScrollView! 🌟
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Static Header Content wrapped in a SliverPadding
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Degraded result banner — shown when one verification thread failed.
                  if (widget.data["degraded"] == true) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.alertTriangle, size: 16, color: Colors.amber[800]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Some checks didn't finish, so this result may be incomplete.",
                              style: TextStyle(color: Colors.amber[900], fontSize: 13, height: 1.4, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Try again"),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  VerdictCard(
                    title: vm.verdictTitle,
                    subtitle: vm.verdictSubtitle,
                    confidence: vm.confidence,
                    method: vm.method,
                  ),
                  const SizedBox(height: 16),

                  _buildResultSummary(vm),
                  const SizedBox(height: 16),

                  _buildModelEvidenceCard(vm),
                  if (vm.bertLabel.isNotEmpty) const SizedBox(height: 16),

                  if (hasExplainability) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(LucideIcons.sparkles, size: 18, color: Colors.purple),
                              SizedBox(width: 8),
                              Text("Explainability Analysis", style: TextStyle(fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          HighlightedText(
                            text: widget.originalText!,
                            highlightedWords: highlightedWords,
                          ),
                          if (explanationText != null && explanationText.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                explanationText,
                                style: TextStyle(fontSize: 13, color: Colors.purple[900], height: 1.4),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const HighlightingLegend(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.resultMode == "link" && inputUrl.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 6))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Verified link:", style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _open(inputUrl),
                            child: Text(inputUrl, style: const TextStyle(color: Colors.blue, fontSize: 12, decoration: TextDecoration.underline)),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: Text("Domain: ${linkDomain.isEmpty ? "unknown" : linkDomain}", style: const TextStyle(color: Colors.black54, fontSize: 12))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: tierColor().withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                                child: Text(tierText(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: tier == "main" ? Colors.green[700] : Colors.orange[700])),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // The new interactive Insights list
                  _buildAnalysisInsights(vm),
                  const SizedBox(height: 16),

                  if (vm.factsDebug != null) ...[
                    DebugDetailsCard(factsDebug: vm.factsDebug!),
                    const SizedBox(height: 16),
                  ],

                  if (vm.sources.isNotEmpty) 
                    const Text("Checked against:", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                ]),
              ),
            ),

            // Fact-Check Sources Sliver
            if (factchecks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _groupHeader("Fact-check results", LucideIcons.badgeInfo),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => MatchedSourceCard(src: factchecks[index]),
                    childCount: factchecks.length,
                  ),
                ),
              ),
            ],

            // Database Matches Sliver
            if (dbSources.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _groupHeader("Database matches", LucideIcons.database),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => MatchedSourceCard(src: dbSources[index]),
                    childCount: dbSources.length,
                  ),
                ),
              ),
            ],

            // Live Sources Sliver
            if (liveSources.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _groupHeader("Live sources", LucideIcons.globe),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => MatchedSourceCard(src: liveSources[index]),
                    childCount: liveSources.length,
                  ),
                ),
              ),
            ],

            // Other/Unknown Sources Sliver
            if (unknown.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _groupHeader("Other sources", LucideIcons.link),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => MatchedSourceCard(src: unknown[index]),
                    childCount: unknown.length,
                  ),
                ),
              ),
            ],

            // Empty State
            if (vm.sources.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: const Text("No matched sources were returned.", style: TextStyle(color: Colors.black54)),
                  ),
                ),
              ),

            // Feedback widget
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: _feedbackGiven == null
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Was this result helpful?",
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black87),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: "Yes, helpful",
                                  icon: const Icon(LucideIcons.thumbsUp, size: 20),
                                  color: Colors.green[600],
                                  onPressed: () {
                                    final verdict = vm.isReal ? "verified" : (vm.isFake ? "fake" : (vm.isMixed ? "mixed" : "unverified"));
                                    _submitFeedback(true, verdict);
                                  },
                                ),
                                IconButton(
                                  tooltip: "Not helpful",
                                  icon: const Icon(LucideIcons.thumbsDown, size: 20),
                                  color: Colors.red[400],
                                  onPressed: () {
                                    final verdict = vm.isReal ? "verified" : (vm.isFake ? "fake" : (vm.isMixed ? "mixed" : "unverified"));
                                    _submitFeedback(false, verdict);
                                  },
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _feedbackGiven! ? LucideIcons.thumbsUp : LucideIcons.thumbsDown,
                              size: 18,
                              color: _feedbackGiven! ? Colors.green[600] : Colors.red[400],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Thank you for your feedback!",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: _feedbackGiven! ? Colors.green[700] : Colors.red[500],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            // Ask AI Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatbotScreen(
                          verificationContext: _buildChatContext(vm),
                        ),
                      ),
                    ),
                    icon: const Icon(LucideIcons.bot, size: 18),
                    label: const Text(
                      "Ask AI to explain this result",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      side: BorderSide(color: Colors.blue[200]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ),
            ),

            // Verify Another Button (Bottom Spacer)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Verify Another",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
