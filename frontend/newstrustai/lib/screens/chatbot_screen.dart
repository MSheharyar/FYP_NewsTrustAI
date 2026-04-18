import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/api_service.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _isTyping = false;

  final List<_ChatMsg> _messages = [
    _ChatMsg.bot(
      "Hi! I’m NewsTrust AI Bot 🤖\n\n"
      "I can help you verify news and teach you how to spot misinformation.\n\n"
      "Try asking: “How to spot fake news?” or paste a headline to verify.",
    ),
  ];

  // Updated Chips to match FYP Rubric
  final List<_QuickChip> _chips = const [
    _QuickChip("Spotting Tips 💡", "tips"),
    _QuickChip("Verify News 🔍", "verify news"),
    _QuickChip("How it works ⚙️", "help"),
  ];

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
    if (msg.isEmpty) return;

    setState(() {
      _messages.add(_ChatMsg.user(msg));
      _controller.clear();
    });
    _scrollToBottom();
    await _botReply(msg);
  }

  Future<void> _botReply(String userText) async {
    setState(() => _isTyping = true);
    _scrollToBottom();
    final lower = userText.toLowerCase().trim();

    await Future.delayed(const Duration(milliseconds: 1200));

    // ✅ RUBRIC: Provides tips on spotting misinformation
    if (lower.contains("tips") || lower.contains("spot") || lower.contains("how to")) {
      _addBotMessage(
        "🛡️ **Tips to Spot Misinformation:**\n\n"
        "1. **Check the Source:** Is it a known news org or a random blog?\n"
        "2. **Read Beyond the Headline:** Headlines are often clickbait.\n"
        "3. **Check the Date:** Old news is often reshared as 'breaking'.\n"
        "4. **Look for Evidence:** Does the article cite sources or quotes?\n"
        "5. **Reverse Image Search:** Fake news often reuses old photos."
      );
    } 
    // ✅ RUBRIC: Explains why news may be fake
    else if (lower.contains("why") && (lower.contains("fake") || lower.contains("misleading"))) {
      _addBotMessage(
        "News is often flagged as **Fake** if:\n"
        "• It contradicts established facts from trusted sources.\n"
        "• The metadata (dates/locations) doesn't match the claim.\n"
        "• The language is designed to provoke extreme emotion rather than inform."
      );
    }
    else if (lower.contains("help") || lower.contains("how it works")) {
      _addBotMessage("Paste any news headline here. I will run it through our mBERT model and cross-reference it with live news databases to give you a verdict.");
    }
    // Logic to offer verification for long strings
    else if (userText.split(RegExp(r"\s+")).length >= 5) {
      setState(() {
        _messages.add(_ChatMsg.botWithAction(
          "Do you want me to analyze this claim for authenticity?\n\n“$userText”",
          actionLabel: "Verify Authenticity 🔍",
          actionPayload: userText,
        ));
        _isTyping = false;
      });
    } else {
      _addBotMessage("I'm here to help! Paste a claim to verify it, or ask for tips on spotting fake news.");
    }
    _scrollToBottom();
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add(_ChatMsg.bot(text));
      _isTyping = false;
    });
  }

  // ✅ RUBRIC: AI chatbot to guide users through verification
  Future<void> _verifyClaim(String claim) async {
    setState(() => _isTyping = true);
    _scrollToBottom();
    
    try {
      final res = await ApiService.verifyText(claim);
      if (!mounted) return;
      
      setState(() => _isTyping = false);
      final label = (res["final_label"] ?? "unverified").toString().toUpperCase();
      final reason = res["final_reason"] ?? "No specific discrepancy found, but evidence is limited.";
      
      _addBotMessage(
        "📢 **Verification Result: $label**\n\n"
        "**Analysis:** $reason\n\n"
        "Remember to always check the 'Read original article' links in the Result screen for more context."
      );
    } catch (e) {
      _addBotMessage("❌ I ran into an error while verifying. Please try again in a moment.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("AI Assistant", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Quick Chips
          Container(
            height: 60,
            color: Colors.white,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, i) => ActionChip(
                label: Text(_chips[i].title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                backgroundColor: Colors.blue[50],
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onPressed: () => _send(_chips[i].payload),
              ),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _chips.length,
            ),
          ),
          const Divider(height: 1),
          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (_, i) {
                if (_isTyping && i == _messages.length) return const _TypingBubble();
                return _ChatBubble(msg: _messages[i], onActionTap: _verifyClaim);
              },
            ),
          ),
          // Input Area
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            decoration: const BoxDecoration(color: Colors.white),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "Ask me anything...",
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    ),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue[700],
                  child: IconButton(
                    icon: const Icon(LucideIcons.send, color: Colors.white, size: 18),
                    onPressed: () => _send(_controller.text),
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

  const _ChatMsg._(this.isUser, this.text, {this.actionLabel, this.actionPayload});
  factory _ChatMsg.user(String t) => _ChatMsg._(true, t);
  factory _ChatMsg.bot(String t) => _ChatMsg._(false, t);
  factory _ChatMsg.botWithAction(String t, {required String actionLabel, required String actionPayload}) 
    => _ChatMsg._(false, t, actionLabel: actionLabel, actionPayload: actionPayload);
}

class _ChatBubble extends StatelessWidget {
  final _ChatMsg msg;
  final void Function(String payload) onActionTap;
  const _ChatBubble({required this.msg, required this.onActionTap});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg.text, style: TextStyle(color: isUser ? Colors.white : Colors.black87, height: 1.4)),
                  if (msg.actionLabel != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => onActionTap(msg.actionPayload!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue[700],
                          elevation: 0,
                          side: BorderSide(color: Colors.blue[100]!),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(msg.actionLabel!, style: const TextStyle(fontWeight: FontWeight.bold)),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: const Text("Bot is typing...", style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
      ),
    );
  }
}