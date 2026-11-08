import 'package:flutter/material.dart';

import '../theme.dart';

/// White card with an amber accent bar down the left of its title.
///
/// The same shape customer_app and rider_app use for their sections, so the
/// three apps read as one product. The bar is what carries the brand — the
/// card itself stays plain, which keeps a screen of six of them calm.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;

  /// Omit for a card that is all content — a summary strip, say.
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final heading = title;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) ...[
            Row(
              children: [
                Container(
                  width: 4,
                  height: 17,
                  decoration: BoxDecoration(
                    color: kAmber,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
                if (icon != null) ...[
                  Icon(icon, size: 17, color: kInk),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(
                    heading,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: kInk,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 13),
          ],
          child,
        ],
      ),
    );
  }
}

/// Label on the left, value on the right. The workhorse of every summary
/// card in this app.
class DetailRow extends StatelessWidget {
  const DetailRow(
    this.label,
    this.value, {
    super.key,
    this.emphasise = false,
    this.valueColour,
  });

  final String label;
  final String value;
  final bool emphasise;
  final Color? valueColour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: emphasise ? kInk : kMuted,
              fontSize: 13.5,
              fontWeight: emphasise ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: emphasise ? 15.5 : 13.5,
              color: valueColour ?? kInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon, then wrapping text. Used for addresses, phone numbers and notes.
class IconLine extends StatelessWidget {
  const IconLine(this.icon, this.text, {super.key, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: kMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.isEmpty ? "—" : text,
            style: TextStyle(
              fontSize: 13.5,
              color: muted ? kMuted : kInk,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small coloured chip. Used for rider states and anything else that is one
/// word plus a colour.
class TagPill extends StatelessWidget {
  const TagPill({
    super.key,
    required this.label,
    required this.colour,
    this.icon,
  });

  final String label;
  final Color colour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: colour),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: colour,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
