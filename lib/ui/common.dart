import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// App-wide currency formatter. Change the symbol here once.
final money = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 0);

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
