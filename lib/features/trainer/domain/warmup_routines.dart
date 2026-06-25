import 'trainer_enums.dart';

/// Partia, pod którą dobierana jest rozgrzewka i rozciąganie.
///
/// Etap 15 — moduł rozgrzewki, mobility i stretchingu. Plik jest czysto
/// domenowy (bez zależności od Fluttera), żeby logikę można było testować
/// i ponownie wykorzystywać niezależnie od UI.
enum WarmupFocus {
  legs('Nogi'),
  chest('Klatka'),
  back('Plecy'),
  shoulders('Barki'),
  general('Ogólna');

  const WarmupFocus(this.label);

  final String label;
}

/// Prosta, praktyczna procedura ruchowa (rozgrzewka / mobilizacja /
/// rozciąganie). Krok to jedno zdanie instrukcji.
class TrainingRoutine {
  const TrainingRoutine({
    required this.id,
    required this.title,
    required this.steps,
    this.numbered = true,
  });

  final String id;
  final String title;
  final List<String> steps;

  /// Czy w podglądzie tekstowym kroki mają być numerowane (rozgrzewka,
  /// rozciąganie) czy wypunktowane bez numeracji (zbiorcza mobilizacja).
  final bool numbered;
}

/// Statyczna baza prostych rozgrzewek, mobilizacji i rozciągania.
///
/// Nie zastępuje istniejących pomocników tekstowych (`buildWarmup`,
/// `buildMobility`, `buildStretching`) z ekranu „Więcej” — uzupełnia je o
/// wersję dobieraną pod partię i wykorzystywaną w trakcie treningu.
class WarmupLibrary {
  const WarmupLibrary._();

  // --- Rozgrzewki (zadanie 1) -------------------------------------------

  static const TrainingRoutine legsWarmup = TrainingRoutine(
    id: 'warmup_legs',
    title: 'Rozgrzewka — nogi',
    steps: [
      '2–3 min marszu, roweru lub skakanki.',
      'Krążenia bioder i kolan – 10 w każdą stronę.',
      'Wykroki w miejscu 2×8 na nogę.',
      'Przysiady z masą ciała 2×12, schodząc coraz niżej.',
      'Glute bridge 2×12 – aktywacja pośladków.',
      '2 lekkie serie wprowadzające pierwszego ćwiczenia.',
    ],
  );

  static const TrainingRoutine chestWarmup = TrainingRoutine(
    id: 'warmup_chest',
    title: 'Rozgrzewka — klatka',
    steps: [
      '2 min lekkiego cardio (marsz, wiosło).',
      'Krążenia ramion w przód i w tył – po 10×.',
      'Pompki na kolanach lub od ściany 2×10.',
      'Dynamiczne otwarcie klatki w ościeżnicy 2×20 s.',
      'Band pull-apart 2×15, jeśli masz gumę.',
      '2 lekkie serie wprowadzające na wyciskaniu.',
    ],
  );

  static const TrainingRoutine backWarmup = TrainingRoutine(
    id: 'warmup_back',
    title: 'Rozgrzewka — plecy',
    steps: [
      '2 min cardio (wiosło lub marsz).',
      'Cat-cow 2×8 – mobilizacja kręgosłupa.',
      'Band pull-apart i ściąganie łopatek 2×15.',
      'Martwy ciąg z kijem lub lekki 2×10 – wzorzec ruchu.',
      'Aktywacja ściągania łopatek (zwisy) 2×8.',
      '2 lekkie serie wprowadzające pierwszego ćwiczenia.',
    ],
  );

  static const TrainingRoutine shouldersWarmup = TrainingRoutine(
    id: 'warmup_shoulders',
    title: 'Rozgrzewka — barki',
    steps: [
      '2 min lekkiego cardio.',
      'Krążenia ramion i nadgarstków – po 10×.',
      'Wall slides 2×10 – mobilność barków.',
      'Face pull lub band pull-apart 2×15.',
      'Rotacje zewnętrzne barku 2×12.',
      '2 lekkie serie wprowadzające pierwszego ćwiczenia.',
    ],
  );

  static const TrainingRoutine generalWarmup = TrainingRoutine(
    id: 'warmup_general',
    title: 'Rozgrzewka ogólna',
    steps: [
      '3 min spokojnego cardio lub marszu.',
      'Krążenia bioder, barków i nadgarstków po 30 s.',
      'Glute bridge 2×12 i dead bug 2×8 na stronę.',
      'Dynamiczne wykroki 2×6 na nogę.',
      '2–3 lekkie serie wprowadzające pierwszego ćwiczenia.',
    ],
  );

  /// Wszystkie rozgrzewki w kolejności: nogi, klatka, plecy, barki, ogólna.
  static const List<TrainingRoutine> warmups = [
    legsWarmup,
    chestWarmup,
    backWarmup,
    shouldersWarmup,
    generalWarmup,
  ];

  // --- Mobilizacja (zadanie 2) ------------------------------------------

  static const TrainingRoutine hipsMobility = TrainingRoutine(
    id: 'mobility_hips',
    title: 'Mobilność — biodra',
    steps: [
      '90/90 – przejścia 2×6 na stronę.',
      'Couch stretch 2×30 s na nogę.',
      'Głęboki przysiad z oddechem – 5 spokojnych oddechów.',
      'Krążenia bioder w podporze 10× w każdą stronę.',
    ],
  );

  static const TrainingRoutine shouldersMobility = TrainingRoutine(
    id: 'mobility_shoulders',
    title: 'Mobilność — barki',
    steps: [
      'Wall slides 2×10.',
      'Rotacje zewnętrzne gumą 2×12.',
      'Przejścia z kijem nad głową (pass-through) 2×8.',
      'Rozciąganie tylnej części barku 2×30 s.',
    ],
  );

  static const TrainingRoutine spineMobility = TrainingRoutine(
    id: 'mobility_spine',
    title: 'Mobilność — kręgosłup',
    steps: [
      'Cat-cow 2×10.',
      'Rotacje T-spine w klęku 2×8 na stronę.',
      'Oddech przeponowy leżąc – 5 oddechów.',
      'Bird dog 2×8 na stronę.',
    ],
  );

  static const TrainingRoutine anklesMobility = TrainingRoutine(
    id: 'mobility_ankles',
    title: 'Mobilność — kostki',
    steps: [
      'Knee-to-wall 2×10 na nogę.',
      'Krążenia kostek po 10× w każdą stronę.',
      'Unoszenie na palce 2×15.',
      'Przysiad z naciskiem kolan w przód – 5 oddechów.',
    ],
  );

  /// Wszystkie mobilizacje: biodra, barki, kręgosłup, kostki.
  static const List<TrainingRoutine> mobility = [
    hipsMobility,
    shouldersMobility,
    spineMobility,
    anklesMobility,
  ];

  // --- Rozciąganie po treningu (zadanie 3) ------------------------------

  static const TrainingRoutine generalStretching = TrainingRoutine(
    id: 'stretch_general',
    title: 'Rozciąganie po treningu',
    steps: [
      'Oddech i marsz 2 min – uspokojenie tętna.',
      'Rozciąganie głównych partii z treningu 2×30 s.',
      'Zginacze bioder 2×30 s na stronę.',
      'Klatka i barki w ościeżnicy 2×30 s.',
      'Nie rozciągaj agresywnie miejsca bólu.',
    ],
  );

  static const TrainingRoutine legsStretching = TrainingRoutine(
    id: 'stretch_legs',
    title: 'Rozciąganie — nogi',
    steps: [
      'Czworogłowe (stojąc) 2×30 s na nogę.',
      'Dwugłowe (skłon prosty) 2×30 s.',
      'Pośladki (figure-4) 2×30 s na stronę.',
      'Łydki o ścianę 2×30 s.',
      'Zginacze bioder 2×30 s na stronę.',
    ],
  );

  static const TrainingRoutine chestStretching = TrainingRoutine(
    id: 'stretch_chest',
    title: 'Rozciąganie — klatka i barki',
    steps: [
      'Klatka w ościeżnicy 2×30 s.',
      'Tylna część barku 2×30 s na stronę.',
      'Triceps nad głową 2×30 s.',
      'Rozluźnienie karku 2×20 s.',
    ],
  );

  static const TrainingRoutine backStretching = TrainingRoutine(
    id: 'stretch_back',
    title: 'Rozciąganie — plecy',
    steps: [
      "Child's pose 2×40 s.",
      'Skłon w siadzie 2×30 s.',
      'Rotacja leżąc 2×30 s na stronę.',
      'Rozciąganie najszerszego (zwis o drążek) 2×30 s.',
    ],
  );

  static const TrainingRoutine shouldersStretching = TrainingRoutine(
    id: 'stretch_shoulders',
    title: 'Rozciąganie — barki i ramiona',
    steps: [
      'Tylna część barku 2×30 s na stronę.',
      'Triceps nad głową 2×30 s.',
      'Klatka w ościeżnicy 2×30 s.',
      'Rozluźnienie karku i kaptura 2×20 s.',
    ],
  );

  // --- Dobór pod partię (zadania 4 i 5) ---------------------------------

  /// Wybiera partię na podstawie grup mięśniowych ćwiczeń z treningu.
  /// Gdy brak jednoznacznej dominanty – zwraca rozgrzewkę ogólną.
  static WarmupFocus focusForMuscleGroups(Iterable<MuscleGroup> groups) {
    var legs = 0;
    var chest = 0;
    var back = 0;
    var shoulders = 0;
    for (final group in groups) {
      switch (group) {
        case MuscleGroup.quadriceps:
        case MuscleGroup.hamstrings:
        case MuscleGroup.glutes:
        case MuscleGroup.calves:
          legs++;
          break;
        case MuscleGroup.chest:
          chest++;
          break;
        case MuscleGroup.back:
          back++;
          break;
        case MuscleGroup.shoulders:
        case MuscleGroup.biceps:
        case MuscleGroup.triceps:
        case MuscleGroup.forearms:
          shoulders++;
          break;
        case MuscleGroup.core:
        case MuscleGroup.fullBody:
        case MuscleGroup.cardio:
        case MuscleGroup.other:
          break;
      }
    }
    var best = WarmupFocus.general;
    var bestScore = 0;
    final scored = <WarmupFocus, int>{
      WarmupFocus.legs: legs,
      WarmupFocus.chest: chest,
      WarmupFocus.back: back,
      WarmupFocus.shoulders: shoulders,
    };
    scored.forEach((focus, score) {
      if (score > bestScore) {
        bestScore = score;
        best = focus;
      }
    });
    return bestScore == 0 ? WarmupFocus.general : best;
  }

  /// Rozgrzewka dobrana pod partię.
  static TrainingRoutine warmupForFocus(WarmupFocus focus) {
    switch (focus) {
      case WarmupFocus.legs:
        return legsWarmup;
      case WarmupFocus.chest:
        return chestWarmup;
      case WarmupFocus.back:
        return backWarmup;
      case WarmupFocus.shoulders:
        return shouldersWarmup;
      case WarmupFocus.general:
        return generalWarmup;
    }
  }

  /// Rozciąganie dobrane pod partię.
  static TrainingRoutine stretchingForFocus(WarmupFocus focus) {
    switch (focus) {
      case WarmupFocus.legs:
        return legsStretching;
      case WarmupFocus.chest:
        return chestStretching;
      case WarmupFocus.back:
        return backStretching;
      case WarmupFocus.shoulders:
        return shouldersStretching;
      case WarmupFocus.general:
        return generalStretching;
    }
  }

  /// Zbiorcza mobilizacja dobrana pod partię – łączy najbardziej istotne
  /// drille w jedną procedurę do szybkiego podglądu.
  static TrainingRoutine mobilityForFocus(WarmupFocus focus) {
    final drills = switch (focus) {
      WarmupFocus.legs => const [hipsMobility, anklesMobility],
      WarmupFocus.chest => const [shouldersMobility, spineMobility],
      WarmupFocus.back => const [spineMobility, hipsMobility],
      WarmupFocus.shoulders => const [shouldersMobility, spineMobility],
      WarmupFocus.general => const [
          hipsMobility,
          shouldersMobility,
          spineMobility,
          anklesMobility,
        ],
    };
    final steps = <String>[];
    for (final drill in drills) {
      steps.add('${drill.title}:');
      for (final step in drill.steps) {
        steps.add('  • $step');
      }
    }
    return TrainingRoutine(
      id: 'mobility_focus_${focus.name}',
      title: 'Mobilność — ${focus.label}',
      steps: steps,
      numbered: false,
    );
  }
}
