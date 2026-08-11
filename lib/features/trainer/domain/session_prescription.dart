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
    this.decisionKey = '',
    this.reasonBullets = const [],
    this.confidence = 0,
    this.targetRir = 0,
    this.previousSummary = '',
    this.deltaSummary = '',
    this.limitingMuscleLabel = '',
    this.limitingReadinessPercent = 0,
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

  // ===== Wytłumaczalność rekomendacji (spec: punkty 16–19) =====

  /// Decyzja silnika: `PROGRESS` | `MAINTAIN` | `REDUCE` | `DELOAD` |
  /// `RECOVERY_SESSION`. Puste = starszy zapis bez decyzji.
  final String decisionKey;

  /// Powody rekomendacji w formacie `+opis` / `-opis` (spec 17).
  /// Trzymane jako proste stringi, żeby zapis sesji pozostał kompatybilny.
  final List<String> reasonBullets;

  /// Pewność rekomendacji 0–1 (0 = starszy zapis bez oceny).
  final double confidence;

  /// Docelowy zapas powtórzeń do upadku (0 = nie wyznaczono).
  final int targetRir;

  /// Skrót poprzedniego wykonania („90 kg × 10 · RPE 8,5").
  final String previousSummary;

  /// Co się zmieniło względem ostatniego treningu („+2,5 kg").
  final String deltaSummary;

  /// Partia, która najbardziej ograniczyła rekomendację (nazwa dla UI).
  final String limitingMuscleLabel;

  /// Gotowość tej partii (0 = brak danych).
  final double limitingReadinessPercent;

  bool get manuallyOverridden => manualDurationSec > 0;

  /// Czy recepta niesie pełne wyjaśnienie (nowy format).
  bool get hasExplanation => reasonBullets.isNotEmpty || decisionKey.isNotEmpty;

  List<String> get positiveReasons =>
      [for (final r in reasonBullets) if (r.startsWith('+')) r.substring(1).trim()];

  List<String> get negativeReasons =>
      [for (final r in reasonBullets) if (r.startsWith('-')) r.substring(1).trim()];

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
    String? decisionKey,
    List<String>? reasonBullets,
    double? confidence,
    int? targetRir,
    String? previousSummary,
    String? deltaSummary,
    String? limitingMuscleLabel,
    double? limitingReadinessPercent,
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
        decisionKey: decisionKey ?? this.decisionKey,
        reasonBullets: reasonBullets ?? this.reasonBullets,
        confidence: confidence ?? this.confidence,
        targetRir: targetRir ?? this.targetRir,
        previousSummary: previousSummary ?? this.previousSummary,
        deltaSummary: deltaSummary ?? this.deltaSummary,
        limitingMuscleLabel: limitingMuscleLabel ?? this.limitingMuscleLabel,
        limitingReadinessPercent:
            limitingReadinessPercent ?? this.limitingReadinessPercent,
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
        if (decisionKey.isNotEmpty) 'decisionKey': decisionKey,
        if (reasonBullets.isNotEmpty) 'reasonBullets': reasonBullets,
        if (confidence > 0) 'confidence': confidence,
        if (targetRir > 0) 'targetRir': targetRir,
        if (previousSummary.isNotEmpty) 'previousSummary': previousSummary,
        if (deltaSummary.isNotEmpty) 'deltaSummary': deltaSummary,
        if (limitingMuscleLabel.isNotEmpty)
          'limitingMuscleLabel': limitingMuscleLabel,
        if (limitingReadinessPercent > 0)
          'limitingReadinessPercent': limitingReadinessPercent,
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
        decisionKey: json['decisionKey']?.toString() ?? '',
        reasonBullets: [
          for (final value in (json['reasonBullets'] as List? ?? const []))
            value.toString(),
        ],
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        targetRir: (json['targetRir'] as num?)?.toInt() ?? 0,
        previousSummary: json['previousSummary']?.toString() ?? '',
        deltaSummary: json['deltaSummary']?.toString() ?? '',
        limitingMuscleLabel: json['limitingMuscleLabel']?.toString() ?? '',
        limitingReadinessPercent:
            (json['limitingReadinessPercent'] as num?)?.toDouble() ?? 0,
      );
}
