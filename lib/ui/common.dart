import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// App-wide currency formatter. The symbol is read live from settings, so a
/// business can change it once and every figure in the UI and in SMS messages
/// updates. (Falls back to the default symbol before settings load.)
NumberFormat get money => NumberFormat.currency(
    symbol: '${AppSettings.instance.currencySymbol} ', decimalDigits: 0);

/// A circular avatar showing a person's first initial over a deterministic
/// warm colour. Used in the list, detail header, picker, and history.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.radius = 24});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final color = AppTheme.avatarColor(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.14),
      child: Text(
        letter,
        style: AppTheme.money(
            size: radius * 0.8, color: color, weight: FontWeight.w600),
      ),
    );
  }
}
