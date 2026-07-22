/// Warstwa kontekstu danych dla asystenta AI (Etap: rozbudowa AI Trainera).
///
/// Czysty Dart. Zbiera najważniejsze dane aplikacji w uporządkowane,
/// kompaktowe streszczenie (bez wysyłania całej bazy):
///  - profil i cel użytkownika,
///  - dzisiejszy trening i aktywność (kroki, kcal, Health Connect),
///  - ostatnie 7 dni treningów (objętość, RPE, partie),
///  - mapa regeneracji mięśni + ostrzeżenia,
///  - aktywny plan / programy 30-dniowe,
///  - status synchronizacji z Licznikiem Kalorii (korekta dnia).
///
/// Dodatkowo zawiera lokalny responder ([localTrainerAnswer]) na najczęstsze
/// pytania — działa offline na realnych danych, gdy backend AI jest niedostępny.
library;

import '../domain/activity_credit.dart';
import '../domain/body_muscle.dart';
import '../domain/daily_adjustment.dart';
import '../domain/exercise.dart';
import '../domain/health_connect_snapshot.dart';
import '../domain/muscle_recovery.dart';
import '../domain/workout_plan.dart';
import '../domain/workout_session.dart';
import 'weekly_training_planner.dart';

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Buduje uporządkowany kontekst użytkownika dla asystenta AI.
Map<String, dynamic> buildTrainerAiContext({
  required DateTime now,
  required Map<String, dynamic> profile,
  required List<WorkoutLog> logs,
  required Exercise Function(String id) resolveExercise,
  required Map<BodyMuscle, MuscleRecoveryState> recovery,
  required List<TrainerActivityEntry> activities,
  required List<WorkoutPlan> plans,
  TrainerHealthConnectSnapshot? healthToday,
  TrainerDailyAdjustment? adjustmentToday,
  WeeklyTrainingAdvice? weeklyAdvice,
}) {
  final weekAgo = now.subtract(const Duration(days: 7));

  // --- Ostatnie 7 dni: dzień → ćwiczenia, serie, objętość, RPE, partie. ---
  final byDay = <String, List<WorkoutLog>>{};
  for (final log in logs) {
    if (log.date.isBefore(weekAgo) || log.date.isAfter(now)) continue;
    byDay.putIfAbsent(_dateKey(log.date), () => []).add(log);
  }
  final last7Days = <Map<String, dynamic>>[];
  final sortedKeys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final key in sortedKeys) {
    final dayLogs = byDay[key]!;
    var volume = 0.0;
    var sets = 0;
    var rpeSum = 0;
    var rpeCount = 0;
    final muscles = <String>{};
    final exercises = <Map<String, dynamic>>[];
    for (final log in dayLogs) {
      final logVolume = log.volume;
      if (logVolume.isFinite && logVolume > 0) volume += logVolume;
      sets += log.sets;
      if (log.rpe > 0) {
        rpeSum += log.rpe;
        rpeCount++;
      }
      final exercise = resolveExercise(log.exerciseId);
      for (final impact in exercise.effectiveMuscleImpacts) {
        muscles.add(impact.muscleGroup.label);
      }
      exercises.add({
        'name': exercise.name,
        'sets': log.sets,
        'reps': log.reps,
        'weight_kg': log.weightKg,
        'rpe': log.rpe,
        'duration_sec': log.durationSec,
        'failed_sets': log.workoutSets.where((s) => s.isFailure).length,
      });
    }
    last7Days.add({
      'date': key,
      'exercises': exercises,
      'total_sets': sets,
      'volume_kg': volume.round(),
      'avg_rpe': rpeCount == 0 ? null : (rpeSum / rpeCount * 10).round() / 10,
      'muscles': muscles.toList(),
    });
  }

  // --- Regeneracja mięśni (tylko partie z danymi). ---
  final recoveryList = <Map<String, dynamic>>[];
  recovery.forEach((muscle, state) {
    if (!state.hasData) return;
    recoveryList.add({
      'muscle': muscle.label,
      'recovery_percent': state.recoveryPercent?.round(),
      'status': state.status.label,
      'hours_to_full': state.estimatedHoursRemaining,
      'last_exercises': state.lastExerciseNames.take(4).toList(),
    });
  });
  recoveryList.sort((a, b) => ((a['recovery_percent'] as int?) ?? 100)
      .compareTo((b['recovery_percent'] as int?) ?? 100));

  // --- Aktywność (bieg/chód/rower) z ostatnich 7 dni. ---
  final activityList = <Map<String, dynamic>>[];
  for (final entry in activities) {
    if (entry.date.isBefore(weekAgo) || entry.date.isAfter(now)) continue;
    activityList.add({
      'date': _dateKey(entry.date),
      'type': entry.type.label,
      'duration_min': entry.durationMin,
      'kcal': entry.estimatedKcal.round(),
      'avg_heart_rate':
          entry.avgHeartRate > 0 ? entry.avgHeartRate.round() : null,
    });
    if (activityList.length >= 15) break;
  }

  // --- Plany / programy. ---
  final planList = <Map<String, dynamic>>[];
  for (final plan in plans.take(6)) {
    planList.add({
      'name': plan.name,
      'active': plan.isActive,
      'days_total': plan.days.length,
      'days_completed': plan.completedDays.length,
    });
  }

  return {
    'generated_at': now.toIso8601String(),
    'profile': profile,
    'today': {
      'date': _dateKey(now),
      'weekday': now.weekday,
      'workouts':
          last7Days.isNotEmpty && last7Days.first['date'] == _dateKey(now)
              ? last7Days.first
              : null,
      'health_connect': healthToday == null
          ? null
          : {
              'available': healthToday.isAvailable,
              'permissions': healthToday.permissionsGranted,
              'steps': healthToday.steps,
              'distance_km': (healthToday.distanceKm * 10).round() / 10,
              'active_kcal': healthToday.activeKcal.round(),
              'active_kcal_estimated': healthToday.activeKcalEstimated,
              'sleep_minutes': healthToday.sleepMinutes,
              'avg_heart_rate': healthToday.averageHeartRate.round(),
              'missing_data': healthToday.missingData,
            },
      'calorie_bridge': adjustmentToday == null
          ? null
          : {
              'total_adjustment_kcal': adjustmentToday.totalAdjustmentKcal,
              'workout_kcal': adjustmentToday.workoutKcal,
              'steps_kcal': adjustmentToday.stepsKcal,
              'run_kcal': adjustmentToday.runKcal,
              'walk_kcal': adjustmentToday.walkKcal,
              'extra_water_ml': adjustmentToday.extraWaterMl,
              'extra_carbs_g': adjustmentToday.extraCarbsG,
              'extra_protein_g': adjustmentToday.extraProteinG,
              'data_status': adjustmentToday.dataStatus,
              'updated_at': adjustmentToday.updatedAt.toIso8601String(),
            },
    },
    'last_7_days': last7Days,
    'muscle_recovery': recoveryList,
    'cardio_activities': activityList,
    'plans': planList,
    'weekly_planner': weeklyAdvice == null
        ? null
        : {
            'today': weeklyAdvice.todayHeadline,
            'avoid_today': weeklyAdvice.todayAvoid,
            'notes': weeklyAdvice.notes,
            'week': [
              for (final day in weeklyAdvice.week)
                {
                  'weekday': day.weekdayLabel,
                  'plan': day.title,
                  'reason': day.reason
                },
            ],
            'recommended_programs': [
              for (final program in weeklyAdvice.programs.take(3))
                {
                  'title': program.title,
                  'readiness': program.readinessPercent.round(),
                  'reason': program.reason
                },
            ],
          },
  };
}

/// Lokalna, offline'owa odpowiedź na najczęstsze pytania — używana, gdy
/// backend AI jest niedostępny. Zwraca null, gdy pytanie wykracza poza
/// obsługiwane tematy (wtedy pokazywany jest komunikat o braku połączenia).
String? localTrainerAnswer({
  required String question,
  required Map<BodyMuscle, MuscleRecoveryState> recovery,
  required WeeklyTrainingAdvice advice,
  TrainerDailyAdjustment? adjustmentToday,
  TrainerHealthConnectSnapshot? healthToday,
}) {
  final q = question.toLowerCase();
  bool asks(List<String> keys) => keys.any(q.contains);

  // Co trenować dzisiaj / czy mogę trenować X?
  if (asks([
    'co mogę dzisiaj',
    'co moge dzisiaj',
    'co trenować',
    'co trenowac',
    'co dziś trenować',
    'jaki trening'
  ])) {
    final buffer = StringBuffer(advice.todayHeadline);
    if (advice.todayAvoid.isNotEmpty) {
      buffer.write(
          '\n\nDziś lepiej unikać: ${advice.todayAvoid.take(4).join(', ')}.');
    }
    for (final note in advice.notes.take(2)) {
      buffer.write('\n$note');
    }
    return buffer.toString();
  }

  // Regeneracja konkretnej partii.
  final muscle = BodyMuscle.fromText(q);
  if (muscle != null &&
      asks([
        'regener',
        'zmęcz',
        'zmecz',
        'trenować',
        'trenowac',
        'mogę',
        'moge',
        'gotow'
      ])) {
    final state = recovery[muscle];
    if (state == null || !state.hasData) {
      return 'Nie mam danych regeneracji dla partii ${muscle.label} — nie była ostatnio trenowana '
          'albo nie ma zapisanych treningów. Po pierwszym treningu tej partii zobaczysz tu jej stan.';
    }
    final percent = state.recoveryPercent?.round() ?? 0;
    final hours = state.estimatedHoursRemaining;
    final readyText = percent >= 80
        ? 'Partia jest gotowa do pełnego treningu.'
        : percent >= 60
            ? 'Możesz trenować umiarkowanie, bez maksymalnej intensywności.'
            : 'Lepiej dziś ją odpuścić albo zrobić lekką wersję.';
    return '${muscle.label}: regeneracja $percent% (${state.status.label}).'
        '${hours > 0 ? ' Pełna regeneracja za ~$hours h.' : ''}\n$readyText'
        '${state.lastExerciseNames.isNotEmpty ? '\nOstatnio obciążały ją: ${state.lastExerciseNames.take(3).join(', ')}.' : ''}';
  }

  // Które mięśnie najbardziej przeciążone?
  if (asks([
    'przeciąż',
    'przeciaz',
    'najbardziej zmęcz',
    'najbardziej zmecz',
    'które mięśnie',
    'ktore miesnie'
  ])) {
    final tired = recovery.values
        .where((s) => s.hasData && (s.recoveryPercent ?? 100) < 60)
        .toList()
      ..sort(
          (a, b) => (a.recoveryPercent ?? 0).compareTo(b.recoveryPercent ?? 0));
    if (tired.isEmpty) {
      return 'Żadna partia nie jest teraz mocno zmęczona — wszystkie śledzone mięśnie mają regenerację powyżej 60%.';
    }
    final lines = tired.take(5).map((s) =>
        '• ${s.muscleGroup.label}: ${(s.recoveryPercent ?? 0).round()}% (${s.status.label})');
    return 'Najbardziej obciążone partie:\n${lines.join('\n')}';
  }

  // Układ tygodnia.
  if (asks([
    'tydzień',
    'tydzien',
    'rozłoż',
    'rozloz',
    'plan na tydz',
    'ułożony',
    'ulozony'
  ])) {
    if (advice.week.isEmpty) return null;
    final lines = advice.week.map((d) =>
        '• ${d.weekdayLabel}: ${d.title}${d.reason.isNotEmpty ? ' (${d.reason.toLowerCase()})' : ''}');
    return 'Proponowany rozkład najbliższego tygodnia na podstawie regeneracji:\n${lines.join('\n')}';
  }

  // Synchronizacja kcal z Kaloriami.
  if (asks(['kcal', 'kalorie', 'kalorii']) &&
      asks(
          ['przesłan', 'przeslan', 'wysłan', 'wyslan', 'synchro', 'licznik'])) {
    if (adjustmentToday == null) {
      return 'Dziś nie ma jeszcze pakietu korekty dnia — nie zapisano treningu ani aktywności, '
          'więc do Licznika Kalorii nic nie zostało przesłane.';
    }
    return 'Dzisiejszy pakiet dla Licznika Kalorii: ${adjustmentToday.totalAdjustmentKcal} kcal '
        '(treningi ${adjustmentToday.workoutKcal}, kroki ${adjustmentToday.stepsKcal}, '
        'bieg ${adjustmentToday.runKcal}, chód ${adjustmentToday.walkKcal}). '
        'Status danych: ${adjustmentToday.dataStatus}. Ostatnia aktualizacja: '
        '${adjustmentToday.updatedAt.hour.toString().padLeft(2, '0')}:${adjustmentToday.updatedAt.minute.toString().padLeft(2, '0')}.';
  }

  // Zapotrzebowanie na wodę.
  if (asks(['wod', 'water'])) {
    if (adjustmentToday == null || adjustmentToday.extraWaterMl <= 0) {
      return 'Dziś nie ma dodatkowej korekty wody — pojawia się po zapisanym treningu lub większej aktywności.';
    }
    return 'Dzisiejsza dodatkowa woda: +${adjustmentToday.extraWaterMl} ml. Wynika z dzisiejszych treningów '
        '(+${adjustmentToday.workoutExtraWaterMl} ml) i aktywności dziennej — im więcej spalonych kcal, tym większe zapotrzebowanie.';
  }

  // Kroki / aktywność dziś.
  if (asks(['kroki', 'ile przeszed', 'ile przesz'])) {
    if (healthToday == null || !healthToday.hasAnyDailyData) {
      return 'Nie mam dziś danych o krokach — sprawdź połączenie z Health Connect / Samsung Health w zakładce Więcej.';
    }
    return 'Dziś: ${healthToday.steps} kroków, ${healthToday.distanceKm.toStringAsFixed(1)} km, '
        '${healthToday.activeKcal.round()} aktywnych kcal'
        '${healthToday.activeKcalEstimated ? ' (szacunek Trainera)' : ' (z zegarka)'}.';
  }

  return null;
}
