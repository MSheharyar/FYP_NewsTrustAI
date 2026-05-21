import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AnalysisLoadingOverlay extends StatefulWidget {
  const AnalysisLoadingOverlay({super.key});

  @override
  State<AnalysisLoadingOverlay> createState() => _AnalysisLoadingOverlayState();
}

class _AnalysisLoadingOverlayState extends State<AnalysisLoadingOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  static const _steps = [
    (LucideIcons.fileText, "Preprocessing text..."),
    (LucideIcons.database, "Searching 36,000+ articles..."),
    (LucideIcons.cpu, "Running AI models..."),
    (LucideIcons.checkCircle, "Calculating verdict..."),
  ];

  static const _delays = [0, 1600, 3400, 5500];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scheduleSteps();
  }

  void _scheduleSteps() {
    for (int i = 0; i < _delays.length; i++) {
      Future.delayed(Duration(milliseconds: _delays[i]), () {
        if (mounted) setState(() => _currentStep = i);
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing icon
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.blue[600],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Analyzing your claim...",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "This usually takes 5–10 seconds",
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const SizedBox(height: 24),

              // Step list
              ..._steps.asMap().entries.map((entry) {
                final i = entry.key;
                final (icon, label) = entry.value;
                final isDone = i < _currentStep;
                final isCurrent = i == _currentStep;
                final isPending = i > _currentStep;

                return AnimatedOpacity(
                  opacity: isPending ? 0.3 : 1.0,
                  duration: const Duration(milliseconds: 450),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: isDone
                                ? Icon(
                                    LucideIcons.checkCircle2,
                                    size: 18,
                                    color: Colors.green[600],
                                    key: ValueKey('done_$i'),
                                  )
                                : isCurrent
                                    ? SizedBox(
                                        key: ValueKey('spin_$i'),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.blue[600],
                                        ),
                                      )
                                    : Icon(
                                        icon,
                                        size: 18,
                                        color: Colors.grey[400],
                                        key: ValueKey('idle_$i'),
                                      ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                              color: isDone
                                  ? Colors.green[700]
                                  : isCurrent
                                      ? Colors.blue[700]
                                      : Colors.grey[400],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
