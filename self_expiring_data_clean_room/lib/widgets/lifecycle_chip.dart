import 'package:flutter/material.dart';
import '../theme.dart';

/// The three engagement-lifecycle states. Drives color + icon + label.
enum LifecyclePhase { active, awaiting, retired }

/// Full-width status pill shown at the top of the home screen.
/// Always visible so the user knows the engagement state without tapping anything.
class LifecycleStatusChip extends StatelessWidget {
  const LifecycleStatusChip({
    super.key,
    required this.phase,
    this.subtitle,
  });

  final LifecyclePhase phase;

  /// Optional secondary text after the main label (e.g., "2 min ago").
  final String? subtitle;

  ({Color bg, Color border, Color fg, IconData icon, String label}) _style() {
    switch (phase) {
      case LifecyclePhase.active:
        return (
          bg: AppColors.successBg,
          border: AppColors.successBorder,
          fg: AppColors.success,
          icon: Icons.circle,
          label: 'Active · waiting for both confirmations',
        );
      case LifecyclePhase.awaiting:
        return (
          bg: AppColors.warningBg,
          border: AppColors.warningBorder,
          fg: AppColors.warning,
          icon: Icons.hourglass_top_outlined,
          label: 'You confirmed. Waiting for the other side.',
        );
      case LifecyclePhase.retired:
        return (
          bg: AppColors.dangerBg,
          border: AppColors.dangerBorder,
          fg: AppColors.danger,
          icon: Icons.lock_outlined,
          label: subtitle == null
              ? 'Engagement retired'
              : 'Engagement retired · $subtitle',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: s.bg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(s.icon, color: s.fg, size: phase == LifecyclePhase.active ? 12 : 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.label,
              style: TextStyle(
                color: s.fg,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
