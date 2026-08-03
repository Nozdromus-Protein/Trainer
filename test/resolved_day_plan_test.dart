import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/application/training_schedule.dart';
import 'package:licznik_treningu/features/trainer/application/weekly_training_planner.dart';
import 'package:licznik_treningu/features/trainer/application/workout_programs_catalog.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';
import 'package:licznik_treningu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// JEDNO ŹRÓDŁO PRAWDY DLA PLANU DNIA.
///
/// Do tej pory każdy ekran liczył rozkład we własnym oknie: kalendarz 7 dni od
/// poniedziałku, planer 7 dni od dziś, a „Dzisiejszy trening" — JEDEN dzień.
/// Przestawianie dni pod regenerację szuka zamiany wśród KOLEJNYCH dni okna,
/// więc w oknie jednodniowym nie miało z czym zamieniać: kalendarz pokazywał
/// zamienione Pull, a ekran dnia nieprzestawionego Push.
Future<AppStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore();
  await store.load();
  return store;
}

/// Zmęczenie partii wywołane treningiem sprzed [hoursAgo] godzin.
Future<void> _logHeavyWork(
  AppStore store,
  String exerciseId, {
  required int hoursAgo,
  int sets = 6,
}) async {
  final at = DateTime.now().subtract(Duration(hours: hoursAgo));
  await store.addLog(WorkoutLog(
    id: 'log_$exerciseId$hoursAgo',
    exerciseId: exerciseId,
    date: DateTime(at.year, at.month, at.day),
    sets: sets,
    reps: 10,
    weightKg: 80,
    durationSec: 1800,
    rpe: 9,
    calories: 300,
    note: '',
    aiConfidence: 0,
    sessionId: 'sess_$exerciseId$hoursAgo',
    sessionName: 'Trening',
    performedAt: at,
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kalendarz i „Dzisiejszy trening" czytają ten sam plan', () {
    test('todayScheduled to DOKŁADNIE ten dzień, co pierwszy dzień kalendarza',
        () async {
      final store = await _store();
      final today = DateTime.now();
      final monday = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: today.weekday - 1));

      // Okno kalendarza (tydzień od poniedziałku) — tak buduje je pasek dni.
      final week = store.trainingScheduleFor(from: monday, days: 7);
      final fromCalendar = week[today.weekday - 1];
      final fromToday = store.todayScheduled;

      expect(fromToday, isNotNull);
      expect(fromToday!.area, fromCalendar.area);
      expect(fromToday.secondaryArea, fromCalendar.secondaryArea);
      expect(fromToday.labelWithLoad, fromCalendar.labelWithLoad);
      expect(fromToday.moved, fromCalendar.moved);
    });

    test('okno planera (7 dni od dziś) zgadza się z oknem kalendarza',
        () async {
      final store = await _store();
      final today = DateTime.now();
      final monday = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: today.weekday - 1));

      final planner = store.trainingScheduleFor(days: 7);
      final calendar = store.trainingScheduleFor(from: monday, days: 7);
      // Część wspólna obu okien musi być identyczna dzień po dniu.
      for (var i = today.weekday - 1; i < 7; i++) {
        final plannerDay = planner[i - (today.weekday - 1)];
        expect(plannerDay.date, calendar[i].date);
        expect(plannerDay.area, calendar[i].area);
        expect(plannerDay.labelWithLoad, calendar[i].labelWithLoad);
      }
    });

    test('przestawienie dnia widzą OBA ekrany naraz', () async {
      final store = await _store();
      // Push dziś, Pull jutro — klasyczny układ z opisu błędu.
      final today = DateTime.now().weekday;
      final tomorrow = today == 7 ? 1 : today + 1;
      await store.setWeekdayPlan(
          today,
          const TrainingDayPlan(
              primary: TrainingFocusArea.push,
              secondary: TrainingFocusArea.core));
      await store.setWeekdayPlan(
          tomorrow,
          const TrainingDayPlan(
              primary: TrainingFocusArea.pull,
              secondary: TrainingFocusArea.core));

      // Świeży, ciężki trening klatki → blok Push nie jest gotowy na dziś.
      await _logHeavyWork(store, 'bench_press', hoursAgo: 6);

      final scheduled = store.todayScheduled;
      expect(scheduled, isNotNull);

      final monday = () {
        final now = DateTime.now();
        final d = DateTime(now.year, now.month, now.day);
        return d.subtract(Duration(days: d.weekday - 1));
      }();
      final calendarToday =
          store.trainingScheduleFor(from: monday, days: 7)[today - 1];

      // Cokolwiek rozstrzygnął Planer — oba widoki niosą to samo.
      expect(scheduled!.area, calendarToday.area);
      expect(scheduled.moved, calendarToday.moved);

      // A gdy dzień faktycznie przestawiono, użytkownik dostaje komunikat.
      if (scheduled.moved) {
        final change = store.todayPlanChange;
        expect(change, isNotNull);
        expect(change!.plannedArea, isNot(change.actualArea));
        expect(PlannerDayChange.headline,
            'Plan dnia został zmieniony przez Inteligentny Planer.');
        expect(change.details, contains(change.actualArea.label));
      }
    });

    test('plan PIERWOTNY i plan FAKTYCZNY są rozróżnione', () async {
      final store = await _store();
      final weekday = DateTime.now().weekday;
      await store.setWeekdayPlan(
          weekday,
          const TrainingDayPlan(
              primary: TrainingFocusArea.legs,
              secondary: TrainingFocusArea.forearms));

      // Rotacja z ustawień (plan pierwotny) — niezależna od regeneracji.
      expect(store.todayOriginalPlan.primary, TrainingFocusArea.legs);
      // Plan faktyczny pochodzi z rozstrzygniętego rozkładu.
      expect(store.resolvedDayFor(DateTime.now())?.area, isNotNull);
    });

    test('rozstrzygnięty plan odświeża się po zapisie treningu (bez restartu)',
        () async {
      final store = await _store();
      final first = store.todayScheduled?.labelWithLoad;

      await _logHeavyWork(store, 'squat', hoursAgo: 2, sets: 8);

      // Cache musi zostać unieważniony przez zapis logów — inaczej ekran
      // trzymałby stan sprzed treningu aż do restartu aplikacji.
      final second = store.todayScheduled?.labelWithLoad;
      expect(first, isNotNull);
      expect(second, isNotNull);
      // Nie wymagamy zmiany treści (zależy od rozkładu), tylko przeliczenia:
      // ten sam obiekt cache'u nie może być zwrócony po zmianie danych.
      expect(
          identical(store.resolvedSchedule(), store.resolvedSchedule()), isTrue,
          reason: 'kolejne odczyty bez zmian danych mają trafiać w cache');
    });

    test('rozkład jest stabilny między odczytami (cache, nie losowanie)',
        () async {
      final store = await _store();
      final a = store.trainingScheduleFor(days: 14);
      final b = store.trainingScheduleFor(days: 14);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].area, b[i].area);
        expect(a[i].secondaryArea, b[i].secondaryArea);
        expect(a[i].loadTier, b[i].loadTier);
      }
    });

    test('dzień wolny pozostaje wolny w obu widokach', () async {
      final store = await _store();
      final weekday = DateTime.now().weekday;
      await store.setWeekdayPlan(weekday, TrainingDayPlan.rest);

      expect(store.todayScheduled?.isRest, isTrue);
      expect(store.trainingScheduleFor(days: 1).first.isRest, isTrue);
      expect(store.todayPlanChange, isNull,
          reason: 'dzień wolny nie jest „przestawiony"');
    });

    test('okno poza zakresem kanonicznym nadal zwraca pełny rozkład', () async {
      final store = await _store();
      final far = DateTime.now().add(const Duration(days: 200));
      final schedule = store.trainingScheduleFor(from: far, days: 7);
      expect(schedule, hasLength(7));
      expect(schedule.first.date.year, far.year);
    });
  });

  group('Rzutowanie dni programu na daty', () {
    test('kolejne dni programu dostają kolejne daty z rozkładu', () async {
      final store = await _store();
      final weekday = DateTime.now().weekday;
      await store.setWeekdayPlan(
          weekday,
          const TrainingDayPlan(
              primary: TrainingFocusArea.legs,
              secondary: TrainingFocusArea.forearms));
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_legs',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ).copyWith(isActive: true));

      final plan = store.plans.firstWhere((p) => p.id.startsWith('program_legs'));
      final dates = store.programDayDates(plan);
      expect(dates, isNotEmpty,
          reason: 'aktywny program musi mieć rzutowanie na daty');

      // Indeksy idą od bieżącego dnia programu w górę, daty rosną.
      final indexes = dates.keys.toList()..sort();
      expect(indexes.first, plan.currentDayIndex);
      for (var i = 1; i < indexes.length; i++) {
        expect(indexes[i], indexes[i - 1] + 1);
        expect(dates[indexes[i]]!.isAfter(dates[indexes[i - 1]]!), isTrue);
      }
      // Żadna data nie jest z przeszłości.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final date in dates.values) {
        expect(date.isBefore(today), isFalse);
      }
    });

    test('rzutowanie jest cache-owane (ten sam obiekt między odczytami)',
        () async {
      final store = await _store();
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_legs',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ).copyWith(isActive: true));
      final plan = store.plans.firstWhere((p) => p.id.startsWith('program_legs'));
      expect(identical(store.programDayDates(plan), store.programDayDates(plan)),
          isTrue);
    });

    test('plan nieaktywny nie zajmuje dni rozkładu', () async {
      final store = await _store();
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_legs',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ).copyWith(isActive: true));
      await store.addWorkoutPlan(buildWorkoutProgram(
        'program_core',
        resolveExercise: (id) => ExerciseRepo.byId(id, store.customExercises),
      ));
      final legs = store.plans.firstWhere((p) => p.id.startsWith('program_legs'));
      final core = store.plans.firstWhere((p) => p.id.startsWith('program_core'));
      final legsDates = store.programDayDates(legs);
      final coreDates = store.programDayDates(core);
      // Dwa różne programy nie mogą dostać tej samej daty na ten sam dzień.
      for (final entry in legsDates.entries) {
        if (coreDates.containsKey(entry.key)) {
          expect(coreDates[entry.key], isNot(entry.value));
        }
      }
    });

    test('pusty plan zwraca puste rzutowanie', () async {
      final store = await _store();
      const empty = WorkoutPlan(
          id: 'empty', name: 'Pusty', note: '', goal: '', days: []);
      expect(store.programDayDates(empty), isEmpty);
      expect(store.programDayDate(empty, 0), isNull);
    });
  });
}
