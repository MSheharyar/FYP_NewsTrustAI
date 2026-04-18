import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class DebugDetailsCard extends StatelessWidget {
  final Map<String, dynamic> factsDebug;
  const DebugDetailsCard({super.key, required this.factsDebug});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        leading: const Icon(LucideIcons.bug, size: 18, color: Colors.black54),
        title: const Text(
          "Debug details (key-facts check)",
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        subtitle: const Text(
          "Shows what facts were detected and matched",
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
        children: [
          _kv("Groups present", _joinList(factsDebug["groups_present"])),
          _kv("Groups matched", _joinList(factsDebug["groups_matched"])),
          const SizedBox(height: 8),
          _kv("Persons", _joinList(factsDebug["claim"]?["persons"])),
          _kv("Matched persons", _joinList(factsDebug["matched"]?["persons"])),
          const SizedBox(height: 6),
          _kv("Locations", _joinList(factsDebug["claim"]?["locations"])),
          _kv("Matched locations", _joinList(factsDebug["matched"]?["locations"])),
          const SizedBox(height: 6),
          _kv("Dates", _joinList(factsDebug["claim"]?["dates"])),
          _kv("Matched dates", _joinList(factsDebug["matched"]?["dates"])),
          const SizedBox(height: 6),
          _kv("Numbers", _joinList(factsDebug["claim"]?["numbers"])),
          _kv("Matched numbers", _joinList(factsDebug["matched"]?["numbers"])),
          const SizedBox(height: 6),
          _kv("Orgs", _joinList(factsDebug["claim"]?["orgs"])),
          _kv("Matched orgs", _joinList(factsDebug["matched"]?["orgs"])),
          if ((factsDebug["hard_mismatch"] ?? "").toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            _kv("Hard mismatch", factsDebug["hard_mismatch"].toString()),
          ],
        ],
      ),
    );
  }

  static Widget _kv(String k, String v) {
    if (v.trim().isEmpty) v = "—";
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              "$k:",
              style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(color: Colors.black87, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  static String _joinList(dynamic v) {
    if (v == null) return "";
    if (v is List) return v.map((e) => e.toString()).join(", ");
    return v.toString();
  }
}