import 'package:flutter/material.dart';

/// Widget to display text with highlighted words based on explainability data
/// FYP 2 Requirement: Highlight suspicious/influential words
class HighlightedText extends StatelessWidget {
  final String text;
  final List<dynamic>? highlightedWords;

  const HighlightedText({
    super.key,
    required this.text,
    this.highlightedWords,
  });

  @override
  Widget build(BuildContext context) {
    if (highlightedWords == null || highlightedWords!.isEmpty) {
      return Text(
        text,
        style: const TextStyle(fontSize: 16, height: 1.5),
      );
    }

    // Build a list of text spans with highlighting
    final List<TextSpan> spans = [];
    int currentIndex = 0;

    // Sort highlighted words by start position
    final sortedWords = List<Map<String, dynamic>>.from(
      highlightedWords!.map((w) => Map<String, dynamic>.from(w as Map)),
    )..sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));

    for (var wordInfo in sortedWords) {
      final int start = wordInfo['start'] as int;
      final int end = wordInfo['end'] as int;
      final String impact = wordInfo['impact'] as String? ?? 'neutral';
      final double score = (wordInfo['score'] as num?)?.toDouble() ?? 0.0;

      // Add unhighlighted text before this word
      if (start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, start),
          style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
        ));
      }

      // Add highlighted word
      Color bgColor;
      Color textColor;

      switch (impact) {
        case 'negative':
          // Red for suspicious/fake indicators
          bgColor = Colors.red.withOpacity(0.15 + (score * 0.15));
          textColor = Colors.red[900]!;
          break;
        case 'positive':
          // Green for credible indicators
          bgColor = Colors.green.withOpacity(0.15 + (score * 0.15));
          textColor = Colors.green[900]!;
          break;
        case 'neutral':
        default:
          // Blue for factual elements (names, numbers)
          bgColor = Colors.blue.withOpacity(0.10 + (score * 0.10));
          textColor = Colors.blue[900]!;
      }

      spans.add(TextSpan(
        text: text.substring(start, end),
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          backgroundColor: bgColor,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ));

      currentIndex = end;
    }

    // Add remaining text
    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}

/// Legend widget to explain highlighting colors
class HighlightingLegend extends StatelessWidget {
  const HighlightingLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Highlighted Words Explained:",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LegendItem(
                color: Colors.red.withOpacity(0.2),
                label: "Suspicious indicators",
              ),
              const SizedBox(width: 12),
              _LegendItem(
                color: Colors.green.withOpacity(0.2),
                label: "Credible signals",
              ),
            ],
          ),
          const SizedBox(height: 4),
          _LegendItem(
            color: Colors.blue.withOpacity(0.15),
            label: "Factual elements (names, dates, numbers)",
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.grey[300]!),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
