import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/main.dart';

/// Motywy Trainera: kompletność listy i poprawność wyszukiwania po id.
void main() {
  test('id motywów są unikalne', () {
    final Set<String> ids = <String>{};
    for (final TrainerThemeStyle style in kTrainerThemeStyles) {
      expect(ids.add(style.id), isTrue, reason: 'duplikat id: ${style.id}');
    }
  });

  test('themeStyleById zwraca właściwy motyw, a nieznane id → pierwszy', () {
    for (final TrainerThemeStyle style in kTrainerThemeStyles) {
      expect(themeStyleById(style.id).id, style.id);
    }
    expect(themeStyleById('nie-ma-takiego').id, kTrainerThemeStyles.first.id);
  });

  test('nowe motywy 2026-07 są na liście', () {
    final Set<String> ids =
        kTrainerThemeStyles.map((style) => style.id).toSet();
    for (final String expected in const <String>[
      'ember_forge',
      'circuit_tech',
      'trail_topo',
      'crimson_beast',
      'teal_titan',
      'porcelain_calm',
    ]) {
      expect(ids, contains(expected));
    }
  });

  test('każdy motyw definiuje akcent i nazwę', () {
    for (final TrainerThemeStyle style in kTrainerThemeStyles) {
      expect(style.name.trim(), isNotEmpty, reason: style.id);
      expect((style.accent >> 24) & 0xFF, 0xFF,
          reason: '${style.id}: akcent bez pełnej alfy');
      expect(style.backgroundStyle.trim(), isNotEmpty, reason: style.id);
    }
  });
}
