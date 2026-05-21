import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/api_service.dart';

class ChatbotScreen extends StatefulWidget {
  /// Optional verification result context loaded when launched from ResultScreen.
  /// When non-null the bot opens with a context-aware greeting and themed chips.
  final String? verificationContext;

  const ChatbotScreen({super.key, this.verificationContext});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _isTyping = false;

  // Conversation history sent to the backend for multi-turn context.
  // Each entry: {"role": "user"|"model", "parts": [String]}
  final List<Map<String, dynamic>> _chatHistory = [];

  late final List<_ChatMsg> _messages;
  late final List<_QuickChip> _chips;

  @override
  void initState() {
    super.initState();

    final bool hasContext = widget.verificationContext != null &&
        widget.verificationContext!.trim().isNotEmpty;

    if (hasContext) {
      // Parse key fields from context so the greeting shows the actual result
      String claim = '';
      String verdict = '';
      String confidence = '';
      String reason = '';
      for (final line in widget.verificationContext!.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('Claim:')) {
          claim = trimmed.replaceFirst('Claim:', '').trim();
        } else if (trimmed.startsWith('Verdict:')) {
          verdict = trimmed.replaceFirst('Verdict:', '').trim();
        } else if (trimmed.startsWith('Confidence:')) {
          confidence = trimmed.replaceFirst('Confidence:', '').trim();
        } else if (trimmed.startsWith('Reason:')) {
          reason = trimmed.replaceFirst('Reason:', '').trim();
        }
      }

      final claimLine = claim.isNotEmpty ? '\n\n📰 Claim: $claim' : '';
      final verdictLine = verdict.isNotEmpty ? '\n🔍 Verdict: $verdict' : '';
      final confLine = confidence.isNotEmpty ? '\n📊 Confidence: $confidence' : '';
      final reasonLine = reason.isNotEmpty ? '\n💬 Reason: $reason' : '';

      _messages = [
        _ChatMsg.bot(
          "I can see you just verified a news claim 🔍"
          "$claimLine$verdictLine$confLine$reasonLine\n\n"
          "Ask me anything about this result — for example:\n"
          "• \"Why was this classified as Fake?\"\n"
          "• \"What evidence did you find?\"\n"
          "• \"How confident are you in this result?\"",
        ),
      ];
      _chips = const [
        _QuickChip("Why Fake? 🤔", "Why was this claim classified as fake? Explain simply."),
        _QuickChip("Explain Evidence 📋", "What evidence was found? Explain the sources and confidence score."),
        _QuickChip("Spotting Tips 💡", "Give me practical tips to spot misinformation."),
      ];
    } else {
      _messages = [
        _ChatMsg.bot(
          "Hi! I'm NewsTrust AI Bot 🤖\n\n"
          "I can help you:\n"
          "• Understand why news may be fake\n"
          "• Learn to spot misinformation\n"
          "• Guide you through news verification\n\n"
          "Ask me anything or paste a headline to analyze.",
        ),
      ];
      _chips = const [
        _QuickChip("Spotting Tips 💡", "Give me practical tips to spot misinformation."),
        _QuickChip("Verify News 🔍", "How can I verify news on my own? Step by step."),
        _QuickChip("How it works ⚙️", "How does the NewsTrustAI verification system work?"),
      ];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _isTyping) return;

    setState(() {
      _messages.add(_ChatMsg.user(msg));
      _controller.clear();
    });
    _scrollToBottom();
    await _sendToAI(msg);
  }

  /// Sends a user message to the Gemini backend and appends the reply.
  Future<void> _sendToAI(String userText) async {
    setState(() => _isTyping = true);
    _scrollToBottom();

    // Snapshot of history *before* this turn — backend appends the new message
    final historySnapshot = List<Map<String, dynamic>>.from(_chatHistory);

    try {
      final res = await ApiService.chat(
        userText,
        history: historySnapshot,
        context: widget.verificationContext,
      );

      if (!mounted) return;

      final reply = (res["reply"] as String?)?.trim() ?? "";

      if (res["error"] == true || reply.isEmpty) {
        final errMsg = (res["message"] as String?)?.trim() ?? "I couldn't get a response.";
        _addBotMessage("❌ $errMsg");
        return;
      }

      // Record both turns so future messages have full context
      _chatHistory.add({"role": "user", "parts": [userText]});
      _chatHistory.add({"role": "model", "parts": [reply]});

      _addBotMessage(reply);
    } catch (e) {
      if (!mounted) return;
      _addBotMessage("❌ Connection error. Please check your connection and try again.");
    }
  }

  /// Runs the real verification pipeline and then asks Gemini to explain it.
  Future<void> _verifyClaim(String claim) async {
    setState(() => _isTyping = true);
    _scrollToBottom();

    try {
      // Step 1 — run the actual hybrid verification
      final res = await ApiService.verifyText(claim);
      if (!mounted) return;

      if (res["error"] == true) {
        _addBotMessage("❌ Verification failed: ${res["message"] ?? "Unknown error"}");
        return;
      }

      final label = (res["final_label"] ?? "unverified").toString().toUpperCase();
      final confidence = res["final_confidence"] ?? res["confidence"] ?? 0;
      final reason = (res["final_reason"] ?? "").toString().trim();

      final claimContext =
          "Verification result for claim: \"$claim\"\n"
          "Verdict: $label\n"
          "Confidence: $confidence%\n"
          "${reason.isNotEmpty ? "Reason: $reason" : ""}".trim();

      // Step 2 — ask AI to explain the result in plain language
      final historySnapshot = List<Map<String, dynamic>>.from(_chatHistory);
      final aiRes = await ApiService.chat(
        "Explain this verification result to the user in simple, friendly language.",
        history: historySnapshot,
        context: claimContext,
      );
      if (!mounted) return;

      final reply = (aiRes["reply"] as String?)?.trim() ?? "Verdict: $label ($confidence% confidence)";

      _chatHistory.add({"role": "user", "parts": ["Verify this claim: $claim"]});
      _chatHistory.add({"role": "model", "parts": [reply]});

      _addBotMessage(reply);
    } catch (e) {
      if (!mounted) return;
      _addBotMessage("❌ Verification failed. Please try again in a moment.");
    }
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add(_ChatMsg.bot(text));
      _isTyping = false;
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text(
          "AI Assistant",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_chatHistory.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.rotateCcw, size: 18, color: Colors.black54),
              tooltip: "Clear chat",
              onPressed: () {
                setState(() {
                  _messages
                    ..clear()
                    ..add(_ChatMsg.bot("Chat cleared. How can I help you?"));
                  _chatHistory.clear();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Quick-action chips
          Container(
            height: 56,
            color: Colors.white,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: _chips.length,
              itemBuilder: (_, i) => ActionChip(
                label: Text(
                  _chips[i].title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                backgroundColor: Colors.blue[50],
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onPressed: _isTyping ? null : () => _send(_chips[i].payload),
              ),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
            ),
          ),
          const Divider(height: 1),

          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (_, i) {
                if (_isTyping && i == _messages.length) {
                  return const _TypingBubble();
                }
                final msg = _messages[i];
                // Offer a verify button for long user messages that look like claims
                final bool showVerify = msg.isUser &&
                    msg.text.split(RegExp(r"\s+")).length >= 5 &&
                    !msg.hasAction;
                if (showVerify) {
                  return _ChatBubble(
                    msg: _ChatMsg.botWithAction(
                      "Would you like me to verify this claim?\n\n\"${msg.text}\"",
                      actionLabel: "Verify Authenticity 🔍",
                      actionPayload: msg.text,
                    ),
                    onActionTap: _verifyClaim,
                    isTyping: _isTyping,
                  );
                }
                return _ChatBubble(
                  msg: msg,
                  onActionTap: _verifyClaim,
                  isTyping: _isTyping,
                );
              },
            ),
          ),

          // Input area
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            decoration: const BoxDecoration(color: Colors.white),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isTyping,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: _isTyping ? "AI is thinking..." : "Ask me anything...",
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _isTyping ? null : _send,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: _isTyping ? Colors.grey[300] : Colors.blue[700],
                  child: IconButton(
                    icon: const Icon(LucideIcons.send, color: Colors.white, size: 18),
                    onPressed: _isTyping ? null : () => _send(_controller.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Data models ───────────────────────────

class _QuickChip {
  final String title;
  final String payload;
  const _QuickChip(this.title, this.payload);
}

class _ChatMsg {
  final bool isUser;
  final String text;
  final String? actionLabel;
  final String? actionPayload;
  bool get hasAction => actionLabel != null;

  const _ChatMsg._(
    this.isUser,
    this.text, {
    this.actionLabel,
    this.actionPayload,
  });

  factory _ChatMsg.user(String t) => _ChatMsg._(true, t);
  factory _ChatMsg.bot(String t) => _ChatMsg._(false, t);
  factory _ChatMsg.botWithAction(
    String t, {
    required String actionLabel,
    required String actionPayload,
  }) =>
      _ChatMsg._(false, t, actionLabel: actionLabel, actionPayload: actionPayload);
}

// ─────────────────────────── Widgets ───────────────────────────

class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  final void Function(String) onActionTap;
  final bool isTyping;

  const _ChatBubble({
    required this.msg,
    required this.onActionTap,
    required this.isTyping,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.blue[100],
              child: const Icon(LucideIcons.bot, size: 16, color: Colors.blue),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[700] : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 0),
                  bottomRight: Radius.circular(isUser ? 0 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  if (msg.actionLabel != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isTyping
                            ? null
                            : () => onActionTap(msg.actionPayload!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue[700],
                          elevation: 0,
                          side: BorderSide(color: Colors.blue[100]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          msg.actionLabel!,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 36, top: 4, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.bot, size: 14, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              "AI is thinking...",
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
