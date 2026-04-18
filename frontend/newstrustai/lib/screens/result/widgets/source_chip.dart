import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SourceChip extends StatelessWidget {
  final String text;
  final bool active;
  const SourceChip({super.key, required this.text, this.active = true});

  @override
  Widget build(BuildContext context) {
    final bg = active ? Colors.green.withOpacity(0.12) : Colors.grey.withOpacity(0.12);
    final fg = active ? Colors.green[700] : Colors.grey[700];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? LucideIcons.checkCircle : LucideIcons.info, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}
