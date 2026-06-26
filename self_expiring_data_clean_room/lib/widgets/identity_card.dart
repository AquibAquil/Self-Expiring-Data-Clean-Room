import 'package:flutter/material.dart';
import '../theme.dart';

/// Compact card at the top of the home screen showing who's signed in.
/// Friendly name primary, atSign secondary (monospace), role chip on the right.
class IdentityCard extends StatelessWidget {
  const IdentityCard({
    super.key,
    required this.friendlyName,
    required this.atSign,
    required this.roleLabel,
  });

  final String friendlyName;
  final String atSign;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final initial = friendlyName.isNotEmpty
        ? friendlyName.characters.first.toUpperCase()
        : atSign.replaceFirst('@', '').characters.first.toUpperCase();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friendlyName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(atSign, style: monoStyle(size: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                roleLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
