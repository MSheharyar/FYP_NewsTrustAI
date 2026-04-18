import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MatchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool trusted;

  const MatchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trusted,
  });

  @override
  Widget build(BuildContext context) {
    final Color c = trusted ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Row(
        children: [
          Icon(
            trusted ? LucideIcons.badgeCheck : LucideIcons.info,
            size: 18,
            color: c,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
