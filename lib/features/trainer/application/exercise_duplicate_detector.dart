/// Wykrywanie duplikatów ćwiczeń (czysty Dart).
///
/// Etap: „Dodawanie ćwiczenia z czatu do bazy".
///
/// Zanim ćwiczenie zaproponowane przez AI trafi do bazy, sprawdzamy, czy
/// czegoś takiego już tam nie ma. Porównujemy po kolei:
///  - identyfikator ćwiczenia (z bazy albo z odpowiedzi AI),
///  - znormalizowaną nazwę (bez diakrytyków, wielkości liter, śmieci),
///  - synonimy PL↔EN (wspólny słownik z wyszukiwarką),
///  - wzorzec ruchowy + partię główną + sprzęt.
///
/// Wynik jest STOPNIOWANY ([DuplicateMatchStrength]) — decyzję zawsze
/// podejmuje użytkownik, aplikacja niczego nie scala automatycznie.
library;

import '../domain/exercise.dart';
import '../domain/trainer_enums.dart';
import '../domain/workout_volume_limits.dart';
import 'exercise_search.dart';
import 'plan_quality_analyzer.dart';

/// Siła dopasowania kandydata na duplikat.
enum DuplicateMatchStrength {
  /// To samo ćwiczenie (identyfikator albo identyczna nazwa).
  exact('To samo ćwiczenie'),

  /// Bardzo prawdopodobny duplikat (synonim / nazwa po drobnej normalizacji).
  strong('Prawdopodobnie to samo ćwiczenie'),

  /// Możliwy wariant (ten sam wzorzec ruchowy i partia, inny sprzęt/wariant).
  variant('Podobne ćwiczenie — możliwy wariant');

  const DuplicateMatchStrength(this.label);

  final String label;
}

/// Znaleziony kandydat na duplikat.
class ExerciseDuplicateMatch {
  const ExerciseDuplicateMatch({
    required this.exercise,
    required this.strength,
    required this.reason,
  });

  final Exercise exercise;
  final DuplicateMatchStrength strength;

  /// Dlaczego uznaliśmy to za duplikat („ta sama nazwa", „synonim EN"…).
  final String reason;
}

/// Szuka duplikatów ćwiczenia o podanych cechach w bazie [library_].
///
/// Zwraca listę posortowaną od najmocniejszego dopasowania. Pusta lista =
/// można bezpiecznie dodać nowe ćwiczenie.
List<ExerciseDuplicateMatch> findExerciseDuplicates({
  required String name,
  required List<Exercise> library_,
  String exerciseId = '',
  String equipment = '',
  List<String> muscles = const <String>[],
  int limit = 5,
}) {
  final matches = <ExerciseDuplicateMatch>[];
  final normalizedName = _normalizeName(name);
  if (normalizedName.isEmpty && exerciseId.trim().isEmpty) {
    return const <ExerciseDuplicateMatch>[];
  }
  final synonyms = _synonymsFor(normalizedName);
  final probeGroup = muscles.isEmpty
      ? MuscleGroup.other
      : MuscleGroup.fromText(muscles.first);
  final probeEquipment = EquipmentType.fromText(equipment);
  final probePattern = _patternFromName(name);
  final seen = <String>{};

  for (final candidate in library_) {
    if (!seen.add(candidate.id)) continue;

    // 1. Identyfikator — najmocniejszy sygnał.
    if (exerciseId.trim().isNotEmpty && candidate.id == exerciseId.trim()) {
      matches.add(ExerciseDuplicateMatch(
        exercise: candidate,
        strength: DuplicateMatchStrength.exact,
        reason: 'Ten sam identyfikator ćwiczenia w bazie.',
      ));
      continue;
    }

    final candidateName = _normalizeName(candidate.name);
    if (candidateName.isEmpty) continue;

    // 2. Identyczna nazwa po normalizacji.
    if (candidateName == normalizedName) {
      matches.add(ExerciseDuplicateMatch(
        exercise: candidate,
        strength: DuplicateMatchStrength.exact,
        reason: 'Ćwiczenie o tej samej nazwie jest już w bazie.',
      ));
      continue;
    }

    // 3. Nazwa zawiera się w nazwie (np. „Pompki" vs „Pompki klasyczne").
    if (_containsAsWords(candidateName, normalizedName) ||
        _containsAsWords(normalizedName, candidateName)) {
      matches.add(ExerciseDuplicateMatch(
        exercise: candidate,
        strength: DuplicateMatchStrength.strong,
        reason: 'Nazwa pokrywa się z „${candidate.name}".',
      ));
      continue;
    }

    // 4. Synonimy PL↔EN.
    final candidateSynonyms = _synonymsFor(candidateName);
    if (synonyms.isNotEmpty &&
        candidateSynonyms.isNotEmpty &&
        synonyms.intersection(candidateSynonyms).isNotEmpty) {
      matches.add(ExerciseDuplicateMatch(
        exercise: candidate,
        strength: DuplicateMatchStrength.strong,
        reason: 'To ta sama nazwa co „${candidate.name}" (synonim PL/EN).',
      ));
      continue;
    }

    // 5. Ten sam wzorzec ruchowy + partia główna → możliwy wariant.
    if (probeGroup != MuscleGroup.other) {
      final sameGroup = primaryMuscleGroupOf(candidate) == probeGroup;
      final samePattern = probePattern != null &&
          movementPatternOf(candidate) == probePattern;
      if (sameGroup && samePattern) {
        final sameEquipment = probeEquipment
            .intersection(candidate.equipmentTypes)
            .where((type) => type != EquipmentType.other)
            .isNotEmpty;
        matches.add(ExerciseDuplicateMatch(
          exercise: candidate,
          strength: DuplicateMatchStrength.variant,
          reason: sameEquipment
              ? 'Ten sam wzorzec ruchu, partia i sprzęt co „${candidate.name}".'
              : 'Ten sam wzorzec ruchu i partia co „${candidate.name}".',
        ));
      }
    }
  }

  matches.sort((a, b) => a.strength.index.compareTo(b.strength.index));
  return matches.take(limit).toList();
}

/// Czy wśród dopasowań jest takie, które trzeba pokazać jako ostrzeżenie
/// „to ćwiczenie prawdopodobnie już jest w bazie".
bool hasLikelyDuplicate(List<ExerciseDuplicateMatch> matches) =>
    matches.any((match) => match.strength != DuplicateMatchStrength.variant);

// ============================================================================
// Pomocnicze
// ============================================================================

/// Normalizacja nazwy: bez diakrytyków, bez interpunkcji, pojedyncze spacje.
String _normalizeName(String value) {
  final base = normalizeSearchText(value);
  return base
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Zbiór synonimów (angielskich fraz) dla znormalizowanej nazwy.
Set<String> _synonymsFor(String normalizedName) {
  if (normalizedName.isEmpty) return const <String>{};
  final result = <String>{};
  final direct = kPlEnExerciseSynonyms[normalizedName];
  if (direct != null) result.addAll(direct);
  // Dopasowanie po fragmencie: „wyciskanie sztangi leżąc" → „wyciskanie sztangi".
  for (final entry in kPlEnExerciseSynonyms.entries) {
    if (entry.key.length < 4) continue;
    if (normalizedName.contains(entry.key)) result.addAll(entry.value);
  }
  // Nazwy już angielskie („bench press") traktujemy jak własny synonim.
  if (result.isEmpty && RegExp(r'^[a-z0-9 -]+$').hasMatch(normalizedName)) {
    result.add(normalizedName);
  }
  return result;
}

/// Czy [haystack] zawiera [needle] jako pełne słowa (nie fragment wyrazu).
bool _containsAsWords(String haystack, String needle) {
  if (needle.isEmpty || haystack.isEmpty) return false;
  if (needle.length < 5) return false;
  if (haystack == needle) return true;
  return haystack.startsWith('$needle ') ||
      haystack.endsWith(' $needle') ||
      haystack.contains(' $needle ');
}

/// Wzorzec ruchowy wyprowadzony z samej nazwy (dla ćwiczeń spoza bazy).
MovementPattern? _patternFromName(String name) {
  if (name.trim().isEmpty) return null;
  final probe = Exercise(
    id: '_probe',
    name: name,
    category: 'Inne',
    muscles: const <String>[],
    equipment: '',
    level: 'Początkujący',
    illustrationType: 'generic',
    description: '',
    tips: const <String>[],
    commonMistakes: const <String>[],
    defaultSets: 3,
    defaultReps: 10,
    defaultDurationSec: 0,
    met: 4.5,
  );
  final pattern = movementPatternOf(probe);
  return pattern == MovementPattern.carryOrOther ? null : pattern;
}
