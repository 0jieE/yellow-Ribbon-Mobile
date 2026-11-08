import 'package:flutter/material.dart';

import '../theme.dart';

/// Whole-screen message with a retry.
///
/// Was copy-pasted as a private `_Placeholder` into four list screens, which
/// is why they had drifted apart on padding and wording. Scrollable so
/// pull-to-refresh still works when there is nothing to pull.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.onRetry,
    this.title,
    this.retryLabel = "Retry",
  });

  final IconData icon;
  final String? title;
  final String message;
  final Future<void> Function() onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final heading = title;

    return RefreshIndicator(
      color: kAmber,
      onRefresh: onRetry,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 70),
        children: [
          Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kAmber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: kInk),
          ),
          const SizedBox(height: 16),
          if (heading != null) ...[
            Text(
              heading,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: kInk,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 170,
              child: ElevatedButton(
                onPressed: onRetry,
                child: Text(retryLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
