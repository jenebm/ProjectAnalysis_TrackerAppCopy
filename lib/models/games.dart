import 'package:flutter/material.dart';

class Games {
  static const genshin = 'Genshin Impact';
  static const starRail = 'Honkai: Star Rail';
  static const zenless = 'Zenless Zone Zero';
  static const endfield = 'Arknights: Endfield';
  static const limbus = 'Limbus Company';
  static const other = 'Other';

  static const all = [genshin, starRail, zenless, endfield, limbus, other];

  static Color color(String game) {
    switch (game) {
      case genshin:
        return const Color(0xFFF2C66D);
      case starRail:
        return const Color(0xFFA9B8FF);
      case zenless:
        return const Color(0xFFFF8A3D);
      case endfield:
        return const Color(0xFFE9F25A);
      case limbus:
        return const Color(0xFFE0533F);
      default:
        return const Color(0xFF7FD1C0);
    }
  }

  static String short(String game) {
    switch (game) {
      case genshin:
        return 'GI';
      case starRail:
        return 'HSR';
      case zenless:
        return 'ZZZ';
      case endfield:
        return 'AE';
      case limbus:
        return 'LC';
      default:
        return '?';
    }
  }
}
