/// Recepta pojedynczego ćwiczenia dla AKTUALNEJ sesji treningowej.
///
/// Etap: rekomendacje mają być wyliczone PRZED rozpoczęciem ćwiczenia i stanowić
/// domyślny plan sesji, a nie pojawiać się dopiero po jego wykonaniu. Recepta
/// rozdziela trzy poziomy danych, których nie wolno mieszać:
///
///  1. [basePrescription]        — bazowy plan programu (nie jest nadpisywany),
///  2. [recommendedPrescription] — rekomendacja Trainera na tę sesję,
///  3. wartości efektywne        — używane w tej sesji (rekomendacja albo
///     ręczne nadpisanie użytkownika przed startem serii).
///
/// Recepta jest liczona raz, przy uruchamianiu treningu (snapshot), i NIE jest
/// losowo przeliczana w trakcie tej samej sesji.
library;

/// Zestaw parametrów jednego ćwiczenia (plan bazowy albo rekomendacja).
class Prescription {
  const Prescription({
    required this.sets,
    required this.reps,
    required this.weightKg,
    required this.durationSec,
    required this.restSeconds,
  });

  final int sets;
  final int reps;
  final double weightKg;
  final int durationSec;
  final int restSeconds;

  Prescription copyWith({
    int? sets,
    int? reps,
    double? weightKg,
    int? durationSec,
    int? restSeconds,
  }) =>
      Prescription(
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        weightKg: weightKg ?? this.weightKg,
        durationSec: durationSec ?? this.durationSec,
        restSeconds: restSeconds ?? this.restSeconds,
      );

  Map<String, dynamic> toJson() => {
        'sets': sets,
        'reps': reps,
        'weightKg': weightKg,
        'durationSec': durationSec,
        'restSeconds': restSeconds,
      };

  factory Prescription.fromJson(Map<String, dynamic> json) => Prescription(
        sets: (json['sets'] as num?)?.toInt() ?? 0,
        reps: (json['reps'] as num?)?.toInt() ?? 0,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        restSeconds: (json['restSeconds'] as num?)?.toInt() ?? 0,
      );
}

/// Recepta ćwiczenia na aktualną sesję: baza + rekomendacja + wartości efektywne
/// + kontekst (przyczyna, źródło danych, ręczne nadpisanie).
class SessionPrescription {
  const SessionPrescription({
    required this.base,
    required this.recommended,
    required this.reason,
    this.dataSource = 'base',
    this.hasEnoughHistory = false,
    this.isCalibrating = false,
    this.manualDurationSec = 0,
    this.generatedAtIso = '',
  });

  /// Bazowy plan programu — NIE jest trwale nadpisywany przez rekomendację.
  final Prescription base;

  /// Rekomendacja Trainera na tę sesję.
  final Prescription recommended;

  /// Krótka przyczyna rekomendacji (do wyjaśnienia użytkownikowi).
  final String reason;

  /// Źródło danych rekomendacji: `history` | `calibration` | `base`.
  final String dataSource;

  /// Czy była wystarczająca (i poprawna) historia do rekomendacji.
  final bool hasEnoughHistory;

  /// Czy ćwiczenie jest w okresie kalibracyjnym (pierwsze wykonania).
  final bool isCalibrating;

  /// Ręcznie nadpisany czas serii (s) przed startem; 0 = brak nadpisania.
  final int manualDurationSec;

  /// Kiedy recepta powstała (ISO8601) — snapshot sesji.
  final String generatedAtIso;

  bool get manuallyOverridden => manualDurationSec > 0;

  // ===== Które wartości rekomendacja zmieniła względem planu bazowego =====

  bool get weightChanged =>
      base.weightKg > 0 && (recommended.weightKg - base.weightKg).abs() > 0.01;
  bool get repsChanged => base.reps > 0 && recommended.reps != base.reps;
  bool get durationChanged =>
      base.durationSec > 0 && recommended.durationSec != base.durationSec;
  bool get restChanged =>
      base.restSeconds > 0 && recommended.restSeconds != base.restSeconds;

  /// Czy rekomendacja w ogóle różni się od planu bazowego (główne pola).
  bool get recommendationApplied =>
      weightChanged || repsChanged || durationChanged;

  /// Efektywny czas serii używany w sesji (ręczne nadpisanie ma pierwszeństwo).
  int get effectiveDurationSec =>
      manualDurationSec > 0 ? manualDurationSec : recommended.durationSec;

  /// Efektywne parametry sesji (rekomendacja + ewentualne nadpisanie czasu).
  Prescription get effective => manualDurationSec > 0
      ? recommended.copyWith(durationSec: manualDurationSec)
      : recommended;

  SessionPrescription copyWith({
    Prescription? base,
    Prescription? recommended,
    String? reason,
    String? dataSource,
    bool? hasEnoughHistory,
    bool? isCalibrating,
    int? manualDurationSec,
    String? generatedAtIso,
  }) =>
      SessionPrescription(
        base: base ?? this.base,
        recommended: recommended ?? this.recommended,
        reason: reason ?? this.reason,
        dataSource: dataSource ?? this.dataSource,
        hasEnoughHistory: hasEnoughHistory ?? this.hasEnoughHistory,
        isCalibrating: isCalibrating ?? this.isCalibrating,
        manualDurationSec: manualDurationSec ?? this.manualDurationSec,
        generatedAtIso: generatedAtIso ?? this.generatedAtIso,
      );

  Map<String, dynamic> toJson() => {
        'base': base.toJson(),
        'recommended': recommended.toJson(),
        'reason': reason,
        'dataSource': dataSource,
        'hasEnoughHistory': hasEnoughHistory,
        'isCalibrating': isCalibrating,
        if (manualDurationSec > 0) 'manualDurationSec': manualDurationSec,
        if (generatedAtIso.isNotEmpty) 'generatedAtIso': generatedAtIso,
      };

  factory SessionPrescription.fromJson(Map<String, dynamic> json) =>
      SessionPrescription(
        base: Prescription.fromJson(
            Map<String, dynamic>.from(json['base'] as Map? ?? const {})),
        recommended: Prescription.fromJson(
            Map<String, dynamic>.from(json['recommended'] as Map? ?? const {})),
        reason: json['reason']?.toString() ?? '',
        dataSource: json['dataSource']?.toString() ?? 'base',
        hasEnoughHistory: json['hasEnoughHistory'] as bool? ?? false,
        isCalibrating: json['isCalibrating'] as bool? ?? false,
        manualDurationSec: (json['manualDurationSec'] as num?)?.toInt() ?? 0,
        generatedAtIso: json['generatedAtIso']?.toString() ?? '',
      );
}
