/// Skala trudności (intensywności) ćwiczeń.
///
/// Pozwala odpowiedzieć na pytanie „co jest cięższe od czego": pompki są
/// lżejsze od wyciskania sztangi na ławce, bo sztanga daje realne obciążenie
/// zewnętrzne i wymaga wyższego poziomu. Dzięki temu przy podkręcaniu
/// intensywności można zaproponować cięższy wariant tego samego ruchu, a przy
/// dodawaniu ćwiczenia — wybrać je świadomie pod żądaną intensywność.
///
/// Czysty Dart, bez UI: wynik jest deterministyczny i łatwy do testów.
library;

import 'body_muscle.dart';
import 'exercise.dart';
import 'trainer_enums.dart';

/// Kategoria intensywności ćwiczenia (do etykiet i filtrów).
enum ExerciseIntensityTier {
  mobility('Mobilność', 0),
  light('Lekkie', 1),
  moderate('Umiarkowane', 2),
  heavy('Ciężkie', 3),
  maximal('Bardzo ciężkie', 4);

  const ExerciseIntensityTier(this.label, this.rank);

  final String label;

  /// 0 = najlżejsze, 4 = najcięższe.
  final int rank;
}

/// Wynik trudności 0–100. Im wyżej, tym większy potencjał obciążenia.
///
/// Składniki: poziom ćwiczenia (najmocniejszy sygnał), możliwość dołożenia
/// obciążenia zewnętrznego (sztanga > hantle > maszyna > guma > masa ciała),
/// złożoność (ile partii pracuje) oraz MET jako delikatny modyfikator.
int exerciseIntensityScore(Exercise exercise) {
  final category = exercise.category.toLowerCase();
  // Rozciąganie i rozgrzewka nie konkurują z pracą główną.
  if (category.contains('rozciąg') ||
      category.contains('rozciag') ||
      category.contains('rozgrzew')) {
    return 5;
  }

  var score = (category.contains('kardio') || category.contains('kondyc'))
      ? 25
      : 40;

  // Poziom ćwiczenia: początkujący 0, średni +15, zaawansowany +30.
  score += trainingLevelRank(exercise.level) * 15;

  // Obciążenie zewnętrzne = wyższy sufit progresji.
  final equipment = exercise.equipmentTypes;
  if (equipment.contains(EquipmentType.barbell)) {
    score += 18;
  } else if (equipment.contains(EquipmentType.dumbbell) ||
      equipment.contains(EquipmentType.kettlebell)) {
    score += 12;
  } else if (equipment.contains(EquipmentType.machine) ||
      equipment.contains(EquipmentType.cable)) {
    score += 10;
  } else if (equipment.contains(EquipmentType.resistanceBand)) {
    score += 4;
  }

  // Złożoność — ruch wielostawowy obciąża organizm mocniej niż izolacja.
  final groups = exercise.effectiveMuscleImpacts.length;
  if (groups >= 3) {
    score += 10;
  } else if (groups == 2) {
    score += 5;
  }

  // MET jako drobny modyfikator wokół wartości typowej (4.0).
  score += ((exercise.met - 4.0) * 2).round().clamp(-6, 8);

  return score.clamp(0, 100);
}

/// Kategoria intensywności wyprowadzona z [exerciseIntensityScore].
ExerciseIntensityTier exerciseIntensityTier(Exercise exercise) {
  final score = exerciseIntensityScore(exercise);
  if (score <= 12) return ExerciseIntensityTier.mobility;
  if (score < 45) return ExerciseIntensityTier.light;
  if (score < 62) return ExerciseIntensityTier.moderate;
  if (score < 80) return ExerciseIntensityTier.heavy;
  return ExerciseIntensityTier.maximal;
}

/// Czy [candidate] jest cięższe od [current].
bool isHarderThan(Exercise candidate, Exercise current) =>
    exerciseIntensityScore(candidate) > exerciseIntensityScore(current);

BodyMuscle? _primaryMuscleOf(Exercise exercise) {
  final impacts = exercise.effectiveMuscleImpacts;
  return impacts.isEmpty ? null : impacts.first.muscleGroup;
}

/// Warianty tego samego ruchu CIĘŻSZE (albo LŻEJSZE) od [current].
///
/// Zwraca ćwiczenia o tej samej partii głównej, posortowane od najbliższego
/// skokiem trudności — żeby podmiana była krokiem, a nie przeskokiem
/// z pompek prosto na maksymalny bój.
List<Exercise> alternativesByIntensity(
  Exercise current,
  List<Exercise> pool, {
  required bool harder,
}) {
  final currentScore = exerciseIntensityScore(current);
  final primary = _primaryMuscleOf(current);
  final matches = <Exercise>[];
  for (final candidate in pool) {
    if (candidate.id == current.id) continue;
    if (primary != null && _primaryMuscleOf(candidate) != primary) continue;
    final score = exerciseIntensityScore(candidate);
    if (harder ? score > currentScore : score < currentScore) {
      // Mobilność/rozciąganie nie jest „lżejszym wariantem" boju siłowego.
      if (!harder &&
          exerciseIntensityTier(candidate) == ExerciseIntensityTier.mobility) {
        continue;
      }
      matches.add(candidate);
    }
  }
  matches.sort((a, b) => (exerciseIntensityScore(a) - currentScore)
      .abs()
      .compareTo((exerciseIntensityScore(b) - currentScore).abs()));
  return matches;
}
