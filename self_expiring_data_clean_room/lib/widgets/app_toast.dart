import 'package:flutter/material.dart';
import '../theme.dart';

enum ToastKind { success, error, info }

/// Shows a custom SnackBar styled per the brand color palette.
/// For [ToastKind.error], an optional `onRetry` callback adds a RETRY action.
void showAppToast(
  BuildContext context, {
  required ToastKind kind,
  required String message,
  VoidCallback? onRetry,
}) {
  final ({Color bg, Color fg, IconData icon}) style = switch (kind) {
    ToastKind.success => (
        bg: AppColors.success,
        fg: Colors.white,
        icon: Icons.check_circle_outline,
      ),
    ToastKind.error => (
        bg: AppColors.danger,
        fg: Colors.white,
        icon: Icons.error_outline,
      ),
    ToastKind.info => (
        bg: AppColors.primary,
        fg: Colors.white,
        icon: Icons.info_outline,
      ),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: style.bg,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(style.icon, color: style.fg, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: style.fg, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        action: onRetry != null
            ? SnackBarAction(label: 'RETRY', textColor: Colors.white, onPressed: onRetry)
            : null,
      ),
    );
}
