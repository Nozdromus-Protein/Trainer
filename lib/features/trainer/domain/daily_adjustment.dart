/// Dzienna korekta aktywności liczona przez Trainera dla Licznika Kalorii.
///
/// Trainer jest głównym miejscem zbierania aktywności (treningi, kroki,
/// biegi, chód, dane z Health Connect / zegarka). Ten model to gotowy
/// "pakiet dnia" przekazywany mostem do aplikacji Licznik Kalorii:
/// spalone kcal w rozbiciu na źródła + sugerowane dodatki (woda, węgle,
/// białko). Wartości kcal pochodzą z systemu kredytów aktywności
/// (deduplikacja po stabilnych kluczach), więc pakiet nie zawiera
/// podwójnie policzonych aktywności.
class TrainerDailyAdjustment {
  const TrainerDailyAdjustment({
    required this.id,
    required this.date,
    required this.workoutKcal,
    required this.stepsKcal,
    required this.runKcal,
    required this.walkKcal,
    this.workKcal = 0,
    required this.otherKcal,
    required this.healthActiveKcal,
    required this.healthDerivedKcal,
    required this.totalAdjustmentKcal,
    required this.extraWaterMl,
    required this.extraCarbsG,
    required this.extraProteinG,
    required this.workoutExtraWaterMl,
    required this.workoutExtraCarbsG,
    required this.workoutExtraProteinG,
    required this.steps,
    required this.distanceKm,
    required this.activityMinutes,
    required this.sources,
    required this.dataStatus,
    required this.includedKeys,
    required this.createdAt,
    required this.updatedAt,
  });

  static const schema = 'trainer.daily_adjustment.v1';

  /// Statusy danych pakietu.
  static const statusFull = 'full';
  static const statusPartial = 'partial';
  static const statusNone = 'none';

  final String id;
  final DateTime date;

  /// Kcal z treningów zapisanych w Trainerze (siłowe + cardio z sesji).
  final int workoutKcal;

  /// Szacunek kcal ze zwykłych kroków (po odjęciu kroków pokrytych
  /// przez zarejestrowany bieg/chód — bez podwójnego liczenia).
  final int stepsKcal;

  /// Kcal z zaliczonych biegów.
  final int runKcal;

  /// Kcal z zaliczonego chodu mierzonego.
  final int walkKcal;

  /// Net kcal of general work activity used as a fallback. It overlaps with
  /// ordinary steps and watch active calories, so it is never blindly summed.
  final int workKcal;

  /// Kcal z pozostałych aktywności (rower, inne cardio) zaliczonych w kredytach.
  final int otherKcal;

  /// Surowe aktywne kcal odczytane z Health Connect (informacyjnie).
  final int healthActiveKcal;

  /// Część korekty poza jawnym treningiem Trainera. Jest wyprowadzona z jednego
  /// zunifikowanego wyniku dnia, więc aktywne kcal zegarka nie dublują treningu.
  final int healthDerivedKcal;

  /// Łączna aktywność dnia po deduplikacji zegarka, pracy, kroków, biegów,
  /// chodu i treningu. Nadal równa [workoutKcal] + [healthDerivedKcal].
  final int totalAdjustmentKcal;

  /// Sugerowana dodatkowa woda łącznie (treningi + aktywność dzienna).
  final int extraWaterMl;

  /// Sugerowane dodatkowe węglowodany łącznie.
  final int extraCarbsG;

  /// Sugerowane dodatkowe białko łącznie.
  final int extraProteinG;

  /// Część wody wynikająca z samych treningów Trainera — Licznik Kalorii
  /// może ją doliczyć zawsze, bo jego własny odczyt Health Connect
  /// o treningach Trainera nie wie.
  final int workoutExtraWaterMl;
  final int workoutExtraCarbsG;
  final int workoutExtraProteinG;

  final int steps;
  final double distanceKm;
  final int activityMinutes;

  /// Źródła danych pakietu, np. trainer_workout, trainer_steps,
  /// trainer_run, trainer_walk, health_connect.
  final List<String> sources;

  /// [statusFull] / [statusPartial] / [statusNone].
  final String dataStatus;

  /// Klucze deduplikacji zaliczonych aktywności (do diagnostyki i ochrony
  /// przed ponownym doliczeniem tej samej aktywności po stronie Kalorii).
  final List<String> includedKeys;

  final DateTime createdAt;
  final DateTime updatedAt;

  String get dateKey {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  /// Stabilny klucz deduplikacji pakietu — jeden pakiet na dzień.
  String get deduplicationKey => 'trainer_daily_adjustment:$dateKey';

  bool get hasAnyData =>
      totalAdjustmentKcal > 0 ||
      steps > 0 ||
      distanceKm > 0 ||
      activityMinutes > 0;

  /// Kcal części zdrowotnej bez treningów — do bezpiecznego fallbacku
  /// po stronie Kalorii, gdy tamta aplikacja nie ma własnych danych HC.
  int get healthOnlyKcal => healthDerivedKcal;

  TrainerDailyAdjustment copyWith({
    String? id,
    DateTime? date,
    int? workoutKcal,
    int? stepsKcal,
    int? runKcal,
    int? walkKcal,
    int? workKcal,
    int? otherKcal,
    int? healthActiveKcal,
    int? healthDerivedKcal,
    int? totalAdjustmentKcal,
    int? extraWaterMl,
    int? extraCarbsG,
    int? extraProteinG,
    int? workoutExtraWaterMl,
    int? workoutExtraCarbsG,
    int? workoutExtraProteinG,
    int? steps,
    double? distanceKm,
    int? activityMinutes,
    List<String>? sources,
    String? dataStatus,
    List<String>? includedKeys,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TrainerDailyAdjustment(
      id: id ?? this.id,
      date: date ?? this.date,
      workoutKcal: workoutKcal ?? this.workoutKcal,
      stepsKcal: stepsKcal ?? this.stepsKcal,
      runKcal: runKcal ?? this.runKcal,
      walkKcal: walkKcal ?? this.walkKcal,
      workKcal: workKcal ?? this.workKcal,
      otherKcal: otherKcal ?? this.otherKcal,
      healthActiveKcal: healthActiveKcal ?? this.healthActiveKcal,
      healthDerivedKcal: healthDerivedKcal ?? this.healthDerivedKcal,
      totalAdjustmentKcal: totalAdjustmentKcal ?? this.totalAdjustmentKcal,
      extraWaterMl: extraWaterMl ?? this.extraWaterMl,
      extraCarbsG: extraCarbsG ?? this.extraCarbsG,
      extraProteinG: extraProteinG ?? this.extraProteinG,
      workoutExtraWaterMl: workoutExtraWaterMl ?? this.workoutExtraWaterMl,
      workoutExtraCarbsG: workoutExtraCarbsG ?? this.workoutExtraCarbsG,
      workoutExtraProteinG: workoutExtraProteinG ?? this.workoutExtraProteinG,
      steps: steps ?? this.steps,
      distanceKm: distanceKm ?? this.distanceKm,
      activityMinutes: activityMinutes ?? this.activityMinutes,
      sources: sources ?? this.sources,
      dataStatus: dataStatus ?? this.dataStatus,
      includedKeys: includedKeys ?? this.includedKeys,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'id': id,
        'date': date.toIso8601String(),
        'dateKey': dateKey,
        'workoutKcal': workoutKcal,
        'stepsKcal': stepsKcal,
        'runKcal': runKcal,
        'walkKcal': walkKcal,
        'workKcal': workKcal,
        'otherKcal': otherKcal,
        'healthActiveKcal': healthActiveKcal,
        'healthDerivedKcal': healthDerivedKcal,
        'totalAdjustmentKcal': totalAdjustmentKcal,
        'extraWaterMl': extraWaterMl,
        'extraCarbsG': extraCarbsG,
        'extraProteinG': extraProteinG,
        'workoutExtraWaterMl': workoutExtraWaterMl,
        'workoutExtraCarbsG': workoutExtraCarbsG,
        'workoutExtraProteinG': workoutExtraProteinG,
        'steps': steps,
        'distanceKm': distanceKm,
        'activityMinutes': activityMinutes,
        'sources': sources,
        'dataStatus': dataStatus,
        'includedKeys': includedKeys,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deduplicationKey': deduplicationKey,
      };

  /// Payload dla mostu do Licznika Kalorii — to samo co [toJson] plus
  /// wskazówka integracyjna. Licznik używa deduplicationKey + dateKey
  /// i traktuje pakiet jako JEDNĄ korektę dnia (aktualizacja zamiast duplikatu).
  Map<String, dynamic> toCalorieBridgeJson() => {
        ...toJson(),
        'integrationNote':
            'Pakiet korekty dnia z Trainera. Licznik Kalorii powinien '
                'doliczać go raz na dzień (klucz deduplicationKey), a przy zmianie '
                'aktualizować istniejącą korektę zamiast tworzyć nową.',
      };

  factory TrainerDailyAdjustment.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final date = DateTime.tryParse(json['date']?.toString() ?? '') ?? now;
    return TrainerDailyAdjustment(
      id: json['id']?.toString() ??
          'daily_adjustment_${date.year}_${date.month}_${date.day}',
      date: date,
      workoutKcal: _intValue(json['workoutKcal']),
      stepsKcal: _intValue(json['stepsKcal']),
      runKcal: _intValue(json['runKcal']),
      walkKcal: _intValue(json['walkKcal']),
      workKcal: _intValue(json['workKcal']),
      otherKcal: _intValue(json['otherKcal']),
      healthActiveKcal: _intValue(json['healthActiveKcal']),
      healthDerivedKcal: _intValue(json['healthDerivedKcal']),
      totalAdjustmentKcal: _intValue(json['totalAdjustmentKcal']),
      extraWaterMl: _intValue(json['extraWaterMl']),
      extraCarbsG: _intValue(json['extraCarbsG']),
      extraProteinG: _intValue(json['extraProteinG']),
      workoutExtraWaterMl: _intValue(json['workoutExtraWaterMl']),
      workoutExtraCarbsG: _intValue(json['workoutExtraCarbsG']),
      workoutExtraProteinG: _intValue(json['workoutExtraProteinG']),
      steps: _intValue(json['steps']),
      distanceKm: _doubleValue(json['distanceKm']),
      activityMinutes: _intValue(json['activityMinutes']),
      sources: _stringList(json['sources']),
      dataStatus: _statusValue(json['dataStatus']),
      includedKeys: _stringList(json['includedKeys']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? date,
    );
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value?.toString() ?? '').replaceAll(',', '.')) ?? 0;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  static String _statusValue(Object? value) {
    final normalized = (value?.toString() ?? '').trim().toLowerCase();
    if (normalized == statusFull ||
        normalized == statusPartial ||
        normalized == statusNone) {
      return normalized;
    }
    return statusNone;
  }
}
