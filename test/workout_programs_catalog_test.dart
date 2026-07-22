import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/exercise_intensity.dart';
import 'package:licznik_treningu/features/trainer/domain/program_exercises.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';

void main() {
  group('Pule ćwiczeń programów', _poolIdsResolveTests);

  group('Charakter dnia programu', _dayKindTests);

  group('Programy rozgrzewkowe i bramka ciężkich dni', _warmupGateCatalogTests);

  group('Migracja zapisanych planów pod bramkę rozgrzewki',
      _warmupMigrationTests);

  // Zbiór realnych identyfikatorów ćwiczeń (baza + pula programów).
  final validIds = ExerciseRepo.combined().map((e) => e.id).toSet();

  group('Pula ćwiczeń programów (kProgramExercises)', () {
    test('ma unikalne id i nie koliduje z bazą', () {
      final baseIds = ExerciseRepo.all.map((e) => e.id).toList();
      final seen = <String>{};
      final duplicates = <String>[];
      for (final ex in kProgramExercises) {
        if (!seen.add(ex.id)) duplicates.add(ex.id);
      }
      expect(duplicates, isEmpty,
          reason: 'Zduplikowane id w kProgramExercises: $duplicates');
      // Wszystkie znajdują się w bazie (zostały dołączone do all).
      for (final ex in kProgramExercises) {
        expect(baseIds.contains(ex.id), isTrue,
            reason: '${ex.id} nie trafiło do ExerciseRepo.all');
      }
    });

    test('każde ćwiczenie ma przypisane partie mięśniowe (regeneracja)', () {
      for (final ex in kProgramExercises) {
        expect(ex.effectiveMuscleImpacts, isNotEmpty,
            reason: '${ex.id} bez muscleImpacts');
        // Dokładnie jedna partia główna.
        final primaries =
            ex.muscleImpacts.where((i) => i.role == MuscleRole.primary);
        expect(primaries.length, greaterThanOrEqualTo(1),
            reason: '${ex.id} bez partii głównej');
      }
    });
  });

  group('Katalog programów 30-dniowych', () {
    final catalog =
        buildWorkoutProgramCatalog(resolveExercise: ExerciseRepo.byId);

    test('zawiera 7 programów zgodnych z metadanymi', () {
      expect(catalog.length, kWorkoutProgramCatalog.length);
      expect(catalog.length, 7);
      for (final meta in kWorkoutProgramCatalog) {
        final plan = catalog.firstWhere((p) => p.id.startsWith(meta.id));
        expect(plan.days.length, 30, reason: '${meta.id} nie ma 30 dni');
      }
    });

    test('każdy dzień ma ćwiczenia i tylko realne id', () {
      for (final plan in catalog) {
        for (var i = 0; i < plan.days.length; i++) {
          final day = plan.days[i];
          expect(day.items, isNotEmpty,
              reason: '${plan.id} dzień ${i + 1} pusty');
          for (final item in day.items) {
            expect(validIds.contains(item.exerciseId), isTrue,
                reason:
                    '${plan.id} dzień ${i + 1}: nieznane ćwiczenie ${item.exerciseId}');
            // Pozycja jest albo czasowa, albo na powtórzenia — nie obie/żadna.
            final timed = item.durationSec > 0;
            final reps = item.reps > 0;
            expect(timed || reps, isTrue,
                reason:
                    '${plan.id} ${item.exerciseId}: brak czasu i powtórzeń');
          }
          // Brak powtórzonych ćwiczeń w obrębie jednego dnia.
          final ids = day.items.map((e) => e.exerciseId).toList();
          expect(ids.length, ids.toSet().length,
              reason: '${plan.id} dzień ${i + 1}: powtórzone ćwiczenie');
        }
      }
    });

    test('dni brzucha to duży obwód (już bez bloku rozciągania)', () {
      final core = catalog.firstWhere((p) => p.id.startsWith('program_core'));
      // Dzień 1 jest dniem treningowym (pełny obwód). Rozciąganie wyprowadzone
      // do osobnych zestawów, więc pozycji jest mniej niż dawniej.
      expect(core.days.first.items.length, greaterThanOrEqualTo(14));
    });

    test('progresja rośnie: późniejszy dzień tego samego typu nie jest lżejszy',
        () {
      for (final plan in catalog) {
        // Rytm ma 5 dni, więc ten sam typ wraca co 5 dni: dzień 1 vs dzień 26.
        final loadEarly = _dayLoad(plan.days[0]);
        final loadLate = _dayLoad(plan.days[25]);
        expect(plan.days[25].kind, plan.days[0].kind,
            reason: '${plan.id}: porównywane dni muszą być tego samego typu');
        expect(loadLate, greaterThanOrEqualTo(loadEarly),
            reason: '${plan.id}: dzień 26 lżejszy niż dzień 1');
      }
    });

    test('deterministyczny — dwa buildy dają ten sam plan', () {
      final a = buildWorkoutProgram('program_legs',
          resolveExercise: ExerciseRepo.byId);
      final b = buildWorkoutProgram('program_legs',
          resolveExercise: ExerciseRepo.byId);
      expect(a.days.length, b.days.length);
      for (var i = 0; i < a.days.length; i++) {
        expect(a.days[i].items.map((e) => e.exerciseId).toList(),
            b.days[i].items.map((e) => e.exerciseId).toList());
      }
    });
  });

  group('Dni ciężkie: bez luk, od najcięższego', () {
    test('dzień siłowy nie zawiera rozciągania ani rozgrzewki', () {
      for (final id in const [
        'program_chest',
        'program_back',
        'program_legs',
        'program_shoulders'
      ]) {
        final plan = buildWorkoutProgram(id, resolveExercise: ExerciseRepo.byId);
        for (final day in plan.days.where((d) => d.kind.isHeavy)) {
          for (final item in day.items) {
            final category = ExerciseRepo.byId(item.exerciseId).category;
            expect(category, isNot('Rozciąganie'),
                reason: '$id „${day.title}": rozciąganie w dniu ciężkim');
            expect(category, isNot('Rozgrzewka'),
                reason: '$id „${day.title}": rozgrzewka w dniu ciężkim');
          }
        }
      }
    });

    test('pozycje idą od najcięższej do najlżejszej', () {
      final plan = buildWorkoutProgram('program_chest',
          resolveExercise: ExerciseRepo.byId);
      for (final day in plan.days.where((d) => d.kind.isHeavy)) {
        final scores = [
          for (final item in day.items)
            exerciseIntensityScore(ExerciseRepo.byId(item.exerciseId)),
        ];
        for (var i = 1; i < scores.length; i++) {
          expect(scores[i], lessThanOrEqualTo(scores[i - 1]),
              reason: '„${day.title}": pozycja $i cięższa od poprzedniej');
        }
      }
    });

    test('w zestawie nie ma dni lekkich — od tego jest deload', () {
      final plan =
          buildWorkoutProgram('program_chest', resolveExercise: ExerciseRepo.byId);
      expect(plan.days.where((d) => !d.kind.isHeavy), isEmpty);
      expect(plan.days.every((d) => d.items.isNotEmpty), isTrue);
    });
  });

  group('Zestaw: od najcięższego dnia do najlżejszego', () {
    test('w zestawie nie ma dni mobilności ani odpoczynku', () {
      for (final meta in kWorkoutProgramCatalog) {
        final plan =
            buildWorkoutProgram(meta.id, resolveExercise: ExerciseRepo.byId);
        expect(plan.days.any((d) => d.kind == WorkoutDayKind.mobility), isFalse,
            reason: '${meta.id}: dzień mobilności w zestawie');
        expect(plan.days.any((d) => d.kind == WorkoutDayKind.rest), isFalse,
            reason: '${meta.id}: dzień odpoczynku w zestawie');
        expect(plan.days.every((d) => d.items.isNotEmpty), isTrue,
            reason: '${meta.id}: pusty dzień w zestawie');
      }
    });

    test('rytm zestawu składa się wyłącznie z dni ciężkich', () {
      final plan =
          buildWorkoutProgram('program_chest', resolveExercise: ExerciseRepo.byId);
      for (var i = 0; i < plan.days.length; i++) {
        expect(plan.days[i].kind, WorkoutDayKind.strength,
            reason: 'dzień ${i + 1} wypadł poza rytmem zestawu');
      }
      // Charakter dnia nadal się zmienia — widać to w tytule (Siła A /
      // Hipertrofia C / Objętość B), a nie w spadku ciężkości.
      final titles = {for (final day in plan.days) day.title.split('· ').last};
      expect(titles.length, greaterThan(1),
          reason: 'zestaw powinien mieć różne rodzaje dni ciężkich');
    });
  });

  group('Rozciąganie jako osobne zestawy', () {
    test('żaden dzień programu nie ma BLOKU rozciągania', () {
      // Celujemy w blok rozciągania (pozycje z notatką „Rozciąganie"), a nie
      // w kategorię: cat_cow bywa mobilizacją w rozgrzewce i to jest w porządku.
      for (final meta in kWorkoutProgramCatalog) {
        final plan =
            buildWorkoutProgram(meta.id, resolveExercise: ExerciseRepo.byId);
        for (final day in plan.days) {
          expect(day.items.where((i) => i.note == 'Rozciąganie'), isEmpty,
              reason: '${meta.id} „${day.title}": blok rozciągania w zestawie');
        }
      }
    });

    test('każda partia ma swój zestaw rozciągania z realnych ćwiczeń', () {
      expect(kStretchWorkoutCatalog, hasLength(7));
      for (final meta in kStretchWorkoutCatalog) {
        final plan =
            buildStretchWorkout(meta, resolveExercise: ExerciseRepo.byId);
        expect(plan.id, meta.id);
        expect(plan.allowAnyDay, isTrue);
        final day = plan.days.single;
        expect(day.kind.isHeavy, isFalse);
        expect(day.items, isNotEmpty);
        for (final item in day.items) {
          expect(ExerciseRepo.byIdOrNull(item.exerciseId), isNotNull,
              reason: '${meta.id}: nieznane ćwiczenie ${item.exerciseId}');
          // Pozycje rozciągania są CZASOWE i oznaczone jako rozciąganie.
          expect(item.durationSec, greaterThan(0));
          expect(item.note, 'Rozciąganie');
        }
      }
    });

    test('program partii wskazuje swój zestaw rozciągania', () {
      for (final meta in kWorkoutProgramCatalog) {
        final stretch = stretchWorkoutForPlan(meta.id);
        expect(stretch, isNotNull, reason: '${meta.id} bez rozciągania');
        // Działa też dla zapisanego id z poziomem.
        expect(stretchWorkoutForPlan('${meta.id}_Średniozaawansowany')?.id,
            stretch!.id);
      }
      expect(stretchWorkoutForPlan('plan_wlasny'), isNull);
      expect(isStretchWorkoutPlan('stretch_legs'), isTrue);
      expect(isStretchWorkoutPlan('warmup_legs'), isFalse);
      // Rozciąganie NIE zalicza się jako rozgrzewka (bramka ciężkich dni).
      expect(isWarmupWorkoutPlan('stretch_legs'), isFalse);
    });
  });

  group('Nazwy programów', () {
    test('nie zawierają sztywnego „30 dni" (długość jest odznaką)', () {
      for (final meta in kWorkoutProgramCatalog) {
        expect(meta.title.contains('30 dni'), isFalse,
            reason: '${meta.id}: „${meta.title}" wciąż ma długość w nazwie');
        expect(meta.durationDays, 30);
      }
    });
  });

  group('Dobór ćwiczeń pod poziom i prawdziwe dni siłowe (audyt „Siła A")', () {
    Set<String> allIds(WorkoutPlan plan) => {
          for (final day in plan.days)
            for (final item in day.items) item.exerciseId,
        };

    test('początkujący NIE dostaje ćwiczeń „Zaawansowany"', () {
      final beginner = buildWorkoutProgram('program_chest',
          resolveExercise: ExerciseRepo.byId, level: 'Początkujący');
      final ids = allIds(beginner);
      // incline_bench_press i chest_dip są jawnie 'Zaawansowany'.
      expect(ids.contains('incline_bench_press'), isFalse,
          reason: 'początkujący dostał zaawansowane wyciskanie sztangi na skosie');
      expect(ids.contains('chest_dip'), isFalse,
          reason: 'początkujący dostał zaawansowane dipy na poręczach');
      // Żadne ćwiczenie w planie początkującego nie jest 'Zaawansowany'.
      for (final id in ids) {
        expect(ExerciseRepo.byId(id).level, isNot('Zaawansowany'),
            reason: '$id jest zaawansowane w planie początkującego');
      }
    });

    test('średniozaawansowany zachowuje pełną pulę (bez regresji)', () {
      final mid = buildWorkoutProgram('program_chest',
          resolveExercise: ExerciseRepo.byId, level: 'Średniozaawansowany');
      final ids = allIds(mid);
      // Zaawansowane ćwiczenia wracają dla wyższego poziomu.
      expect(
        ids.contains('incline_bench_press') || ids.contains('chest_dip'),
        isTrue,
        reason: 'średniozaawansowany powinien widzieć zaawansowane boje',
      );
    });

    test('dzień „Siła A" jest ciężko-siłowy: niskie powtórzenia, długa przerwa, '
        'bez kalistenicznego wykończenia', () {
      for (final id in const ['program_chest', 'program_back', 'program_legs']) {
        final plan =
            buildWorkoutProgram(id, resolveExercise: ExerciseRepo.byId);
        final dayA = plan.days.first; // dzień 1 = Siła A
        expect(dayA.title.contains('Siła A'), isTrue);
        expect(dayA.kind, WorkoutDayKind.strength);
        // Bez wykończenia (to plank/mountain climber dawały „gimnastyczny" ton).
        expect(dayA.items.where((i) => i.note == 'Wykończenie'), isEmpty,
            reason: '$id: Siła A nie powinna mieć kalistenicznego wykończenia');
        // Serie główne mają niskie powtórzenia (≤ 6) i długą przerwę.
        final mainSets =
            dayA.items.where((i) => i.note.startsWith('Seria główna'));
        expect(mainSets, isNotEmpty);
        for (final item in mainSets) {
          expect(item.reps, lessThanOrEqualTo(6),
              reason: '$id: seria główna Siły A ma wysokie powtórzenia');
          expect(item.restSeconds, greaterThanOrEqualTo(140),
              reason: '$id: przerwa w Sile A za krótka na trening siłowy');
        }
      }
    });
  });
}

/// Prosty wskaźnik obciążenia dnia: sumaryczny czas + serie×powtórzenia.
int _dayLoad(WorkoutDay day) {
  var load = 0;
  for (final item in day.items) {
    load += item.durationSec * item.sets;
    load += item.reps * item.sets;
  }
  return load;
}

// Fundament pod bramkę rozgrzewki: dzień programu pamięta swój charakter.
// Wcześniej _DayKind istniał tylko w generatorze i ginął po zbudowaniu planu,
// więc w trakcie działania nie dało się odróżnić dnia ciężkiego od lekkiego.
void _dayKindTests() {
  test('dni programu zapisują swój charakter (ciężki vs lekki)', () {
    final plans = buildWorkoutProgramCatalog(
      resolveExercise: (id) => ExerciseRepo.byId(id),
    );
    // Id planu to '<programId>_<poziom>' (np. program_chest_Średniozaawansowany).
    final plan = plans.firstWhere((p) => p.id.startsWith('program_chest'));
    final kinds = plan.days.map((d) => d.kind).toSet();

    expect(kinds.contains(WorkoutDayKind.unknown), isFalse,
        reason: 'każdy dzień z katalogu ma znany charakter');
    // Zestaw jest ciężki w całości — odciążenie robi deload, a nie wbudowany
    // dzień techniczny (to on schodził na pompki mimo sztangi w szafie).
    expect(plan.days.every((d) => d.kind.isHeavy), isTrue,
        reason: 'program siłowy ma same dni ciężkie');
    expect(WorkoutDayKind.strength.isHeavy, isTrue);
    expect(WorkoutDayKind.mobility.isHeavy, isFalse);
  });

  test('charakter dnia przeżywa zapis i odczyt planu', () {
    const day = WorkoutDay(
      weekday: 1,
      title: 'Dzień 1',
      items: [],
      kind: WorkoutDayKind.strength,
    );
    expect(WorkoutDay.fromJson(day.toJson()).kind, WorkoutDayKind.strength);
    // Zgodność wsteczna: starszy zapis bez pola `kind`.
    final legacy = WorkoutDay.fromJson({
      'weekday': 1,
      'title': 'Dzień 1',
      'items': <dynamic>[],
    });
    expect(legacy.kind, WorkoutDayKind.unknown);
  });
}

// Bramka rozgrzewki: ciężki dzień nie ma rozgrzewki inline — przygotowanie
// zapewnia osobny program rozgrzewkowy zbudowany z puli tej samej partii.
void _warmupGateCatalogTests() {
  final plans = buildWorkoutProgramCatalog(resolveExercise: ExerciseRepo.byId);

  test('żaden dzień programu nie ma rozgrzewki inline', () {
    // Wszystkie dni są ciężkie, więc rozgrzewkę zapewnia osobny program
    // rozgrzewkowy — inline byłoby drugą rozgrzewką pod rząd.
    for (final plan in plans) {
      expect(plan.days.every((d) => d.kind.isHeavy), isTrue,
          reason: '${plan.id}: zestaw ma dzień inny niż ciężki');
      for (final day in plan.days) {
        expect(day.items.where((i) => i.note == 'Rozgrzewka'), isEmpty,
            reason:
                '${plan.id} „${day.title}”: ciężki dzień z rozgrzewką inline');
      }
    }
  });

  test('katalog rozgrzewek buduje jednodniowe, czasowe plany z realnych id',
      () {
    expect(kWarmupWorkoutCatalog, hasLength(7));
    for (final meta in kWarmupWorkoutCatalog) {
      final plan = buildWarmupWorkout(meta, resolveExercise: ExerciseRepo.byId);
      expect(plan.id, meta.id);
      expect(plan.allowAnyDay, isTrue);
      expect(plan.days, hasLength(1));
      final day = plan.days.single;
      expect(day.kind.isHeavy, isFalse,
          reason: 'rozgrzewka nie może sama wymagać rozgrzewki');
      expect(day.items, isNotEmpty);
      for (final item in day.items) {
        expect(ExerciseRepo.byId(item.exerciseId).id, item.exerciseId,
            reason: '${meta.id}: nieznane ćwiczenie ${item.exerciseId}');
        expect(item.durationSec, greaterThan(0),
            reason: '${meta.id}: pozycje rozgrzewki są czasowe');
      }
    }
  });

  test('każdy program katalogu ma rozgrzewkę tej samej puli (też pełne id)',
      () {
    for (final programMeta in kWorkoutProgramCatalog) {
      final warmup = warmupWorkoutForPlan(programMeta.id);
      expect(warmup, isNotNull,
          reason: '${programMeta.id} bez programu rozgrzewkowego');
      // Zapisany plan ma w id poziom — mapowanie działa też dla pełnego id.
      expect(warmupWorkoutForPlan('${programMeta.id}_Średniozaawansowany')?.id,
          warmup!.id);
      // Program rozgrzewkowy i rozgrzewki inline czerpią z tej samej puli.
      final plan = plans.firstWhere((p) => p.id.startsWith(programMeta.id));
      final inlineIds = <String>{
        for (final day in plan.days)
          for (final item in day.items)
            if (item.note == 'Rozgrzewka') item.exerciseId,
      };
      expect(inlineIds.difference(warmup.exerciseIds.toSet()), isEmpty,
          reason:
              '${programMeta.id}: pula programu rozgrzewkowego rozjechała się z inline');
    }
    // Plany spoza katalogu nie mają wymaganej rozgrzewki — bramka nie blokuje.
    expect(warmupWorkoutForPlan('plan_wlasny'), isNull);
    expect(isWarmupWorkoutPlan('warmup_push'), isTrue);
    expect(isWarmupWorkoutPlan('program_chest'), isFalse);
  });
}

/// Plan barków „sprzed bramki": dni bez `kind` (unknown) i stara, ogólna
/// rozgrzewka inline (arm_circles/torso_twist/leg_swings) także w dni ciężkie.
WorkoutPlan _legacyShouldersPlan() {
  PlanItem timed(String id) => PlanItem(
      exerciseId: id,
      sets: 1,
      reps: 0,
      durationSec: 30,
      note: 'Rozgrzewka',
      restSeconds: 10);
  PlanItem reps(String id) => PlanItem(
      exerciseId: id, sets: 3, reps: 10, durationSec: 0, note: 'Seria główna');
  PlanItem stretch(String id) => PlanItem(
      exerciseId: id,
      sets: 1,
      reps: 0,
      durationSec: 30,
      note: 'Rozciąganie',
      restSeconds: 8);
  WorkoutDay day(int weekday, String title, List<PlanItem> items) =>
      WorkoutDay(weekday: weekday, title: title, items: items);
  return WorkoutPlan(
    id: 'program_shoulders_Średniozaawansowany',
    name: 'Barki — 30 dni',
    note: '',
    goal: 'Masa',
    isActive: true,
    completedDays: const {0, 2},
    activeVariantId: 'wariant_x',
    days: [
      day(1, 'Dzień 1 · Siła A', [
        timed('arm_circles'),
        timed('leg_swings'),
        reps('db_shoulder_press'),
        stretch('neck_stretch'),
      ]),
      day(2, 'Dzień 2 · Objętość B',
          [timed('torso_twist'), reps('lateral_raise')]),
      day(3, 'Dzień 3 · Dzień techniczny', [
        timed('leg_swings'),
        timed('torso_twist'),
        reps('lateral_raise'),
      ]),
      day(4, 'Dzień 4 · Mobilność',
          [timed('leg_swings'), stretch('neck_stretch')]),
      day(5, 'Dzień 5 · Siła C', [timed('torso_twist'), reps('arnold_press')]),
      day(6, 'Dzień 6 · Kondycja', [timed('arm_circles'), reps('front_raise')]),
      day(7, 'Dzień 7 · Odpoczynek',
          [timed('torso_twist'), stretch('neck_stretch')]),
    ],
  );
}

// Migracja starych zapisów: kind z rytmu generatora, ciężkie dni bez inline
// rozgrzewki (dostarcza ją bramka), lekkie z pulą partii zamiast ogólnej.
void _warmupMigrationTests() {
  bool isWarmup(PlanItem item) =>
      ExerciseRepo.byId(item.exerciseId).category == 'Rozgrzewka';

  test('uzupełnia kind, czyści ciężkie dni i podmienia pulę w lekkich', () {
    final migrated = migratePlanForWarmupGate(
      _legacyShouldersPlan(),
      resolveExercise: ExerciseRepo.byId,
    );
    expect(migrated, isNotNull);

    // Charakter dni odtworzony z deterministycznego rytmu tygodnia — a ten
    // składa się już wyłącznie z dni ciężkich (odciążenie robi deload).
    expect(migrated!.days.every((d) => d.kind == WorkoutDayKind.strength),
        isTrue);

    // Dzień ciężki: pozycje rozgrzewkowe usunięte, reszta nietknięta.
    final heavy = migrated.days.first;
    expect(heavy.items.where(isWarmup), isEmpty);
    expect(heavy.items.map((i) => i.exerciseId),
        ['db_shoulder_press', 'neck_stretch']);

    // Skoro wszystkie dni są ciężkie, rozgrzewka inline znika z całego planu —
    // także stare wymachy nóg przed treningiem barków.
    for (final day in migrated.days) {
      final ids = day.items.map((i) => i.exerciseId).toList();
      expect(ids.toSet().length, ids.length,
          reason: '„${day.title}”: zdublowane ćwiczenie po migracji');
      expect(day.items.where(isWarmup), isEmpty,
          reason: '„${day.title}”: rozgrzewka inline w ciężkim dniu');
    }
    expect(
      migrated.days
          .any((d) => d.items.any((i) => i.exerciseId == 'leg_swings')),
      isFalse,
      reason: 'po migracji barki nie rozgrzewają nóg',
    );

    // Postęp i wariant nietknięte.
    expect(migrated.completedDays, const {0, 2});
    expect(migrated.activeVariantId, 'wariant_x');
    expect(migrated.isActive, isTrue);
  });

  test('jest idempotentna — drugi przebieg nic nie zmienia', () {
    final once = migratePlanForWarmupGate(
      _legacyShouldersPlan(),
      resolveExercise: ExerciseRepo.byId,
    );
    expect(once, isNotNull);
    expect(
      migratePlanForWarmupGate(once!, resolveExercise: ExerciseRepo.byId),
      isNull,
    );
  });

  test('świeżo wygenerowany plan katalogu nie wymaga migracji', () {
    final fresh = buildWorkoutProgram('program_shoulders',
        resolveExercise: ExerciseRepo.byId);
    expect(
      migratePlanForWarmupGate(fresh, resolveExercise: ExerciseRepo.byId),
      isNull,
    );
  });

  test('plany spoza katalogu zostają bez zmian', () {
    const custom = WorkoutPlan(
      id: 'plan_wlasny',
      name: 'Mój plan',
      note: '',
      days: [
        WorkoutDay(weekday: 1, title: 'Dzień 1', items: [
          PlanItem(
              exerciseId: 'leg_swings',
              sets: 1,
              reps: 0,
              durationSec: 30,
              note: 'Rozgrzewka'),
        ]),
      ],
    );
    expect(
      migratePlanForWarmupGate(custom, resolveExercise: ExerciseRepo.byId),
      isNull,
    );
    // Cardio i rozgrzewki też nie są ruszane.
    expect(
      migratePlanForWarmupGate(
        buildCardioWorkout(kCardioWorkoutCatalog.first,
            resolveExercise: ExerciseRepo.byId),
        resolveExercise: ExerciseRepo.byId,
      ),
      isNull,
    );
    expect(
      migratePlanForWarmupGate(
        buildWarmupWorkout(kWarmupWorkoutCatalog.first,
            resolveExercise: ExerciseRepo.byId),
        resolveExercise: ExerciseRepo.byId,
      ),
      isNull,
    );
  });
}

// ExerciseRepo.byId przy nieznanym id po cichu zwraca `all.first` — literówka
// w puli programu wstawiłaby więc losowe ćwiczenie zamiast rzucić błąd.
// Ten test pilnuje, że KAŻDA pozycja każdego programu wskazuje na realne id.
void _poolIdsResolveTests() {
  test('każde ćwiczenie w programach ma istniejące id (brak cichych podmian)',
      () {
    final plans = buildWorkoutProgramCatalog(
      resolveExercise: (id) => ExerciseRepo.byId(id),
    );
    final broken = <String>{};
    for (final plan in plans) {
      for (final day in plan.days) {
        for (final item in day.items) {
          // byIdOrNull rozróżnia „nie ma takiego id" od cichej podmiany na
          // all.first, którą robi byId.
          if (ExerciseRepo.byIdOrNull(item.exerciseId) == null) {
            broken.add('${plan.id}: ${item.exerciseId}');
          }
        }
      }
    }
    expect(broken, isEmpty, reason: 'nierozpoznane id ćwiczeń: $broken');
  });

  test('byIdOrNull zwraca null dla nieznanego id, byId placeholder', () {
    expect(ExerciseRepo.byIdOrNull('nie_ma_takiego_cwiczenia_xyz'), isNull);
    // byId nigdy nie oddaje null — UI dostaje bezpieczny placeholder.
    expect(ExerciseRepo.byId('nie_ma_takiego_cwiczenia_xyz'), isNotNull);
    // Realne id rozwiązuje się na siebie.
    expect(ExerciseRepo.byIdOrNull('squat')?.id, 'squat');
  });

  test('rozgrzewka programu celuje w partie, które ten program trenuje', () {
    // Dni programu są w całości ciężkie, więc rozgrzewka mieszka wyłącznie
    // w osobnych zestawach rozgrzewkowych — tam sprawdzamy dobór pul.
    Set<String> warmupIdsOf(String warmupId) {
      final meta =
          kWarmupWorkoutCatalog.firstWhere((m) => m.id == warmupId);
      final plan = buildWarmupWorkout(meta, resolveExercise: ExerciseRepo.byId);
      return {for (final item in plan.days.single.items) item.exerciseId};
    }

    // Klatka nie może rozgrzewać nóg — to była motywacja rozbicia pul.
    final chestWarmupIds = warmupIdsOf('warmup_push');
    expect(chestWarmupIds, isNotEmpty);
    expect(chestWarmupIds.contains('leg_swings'), isFalse,
        reason: 'rozgrzewka klatki nie powinna zawierać wymachów nóg');
    expect(chestWarmupIds.contains('ankle_rocks'), isFalse);

    // Nogi z kolei rozgrzewają biodra/kostki, a nie obręcz barkową.
    final legWarmupIds = warmupIdsOf('warmup_legs');
    expect(legWarmupIds.contains('doorway_chest_opener'), isFalse,
        reason: 'rozgrzewka nóg nie powinna otwierać klatki');
    expect(
      legWarmupIds.any((id) =>
          const {'leg_swings', 'hip_circles', 'ankle_rocks'}.contains(id)),
      isTrue,
      reason: 'rozgrzewka nóg musi ruszać biodra/kostki',
    );
  });
}
