import 'package:flutter/material.dart';

class HighlightedText extends StatelessWidget {
  final String text;
  final List<dynamic> highlightedWords;

  const HighlightedText({
    super.key,
    required this.text,
    required this.highlightedWords,
  });

  @override
  Widget build(BuildContext context) {
    // If no words to highlight, just return plain text
    if (highlightedWords.isEmpty || text.trim().isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
      );
    }

    // Convert highlighted words to a lower-cased list of strings for easy matching
    final List<String> matchWords = highlightedWords
        .map((w) => w.toString().toLowerCase().trim())
        .where((w) => w.isNotEmpty)
        .toList();

    // Use a regular expression to split the text into words and non-words (punctuation/spaces)
    // This \u0600-\u06FF range ensures it perfectly captures Urdu text as well!
    final RegExp wordBoundary = RegExp(r"(\b[a-zA-Z0-9_\u0600-\u06FF'-]+\b|\s+|\S)");
    final Iterable<Match> matches = wordBoundary.allMatches(text);

    final List<TextSpan> spans = [];

    for (final m in matches) {
      final String segment = m.group(0) ?? "";
      if (segment.isEmpty) continue;

      // Check if this segment is an actual word vs just a space or period
      final bool isWord = RegExp(r"^[a-zA-Z0-9_\u0600-\u06FF'-]+$").hasMatch(segment);
      final bool shouldHighlight = isWord && matchWords.contains(segment.toLowerCase());

      if (shouldHighlight) {
        // Highlight the LIME fake features (Yellow background, Red text)
        spans.add(TextSpan(
          text: segment,
          style: const TextStyle(
            color: Colors.red,
            backgroundColor: Color(0xFFFFF59D), // Light yellow
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ));
      } else {
        // Normal un-highlighted text
        spans.add(TextSpan(
          text: segment,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 15,
            height: 1.5,
          ),
        ));
      }
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}

class HighlightingLegend extends StatelessWidget {
  const HighlightingLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF59D),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            "Fake Indicator",
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            "These words strongly influenced the AI to classify this text as fake.",
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}
