class TrainingImpact {
  const TrainingImpact({
    required this.id,
    required this.sessionId,
    required this.sessionName,
    required this.date,
    required this.isTrainingDay,
    required this.estimatedBurnedKcal,
    required this.suggestedCalorieAdjustmentKcal,
    required this.suggestedExtraWaterMl,
    required this.suggestedExtraProteinG,
    required this.postWorkoutMealSuggestion,
    required this.durationMin,
    required this.exerciseCount,
    required this.setCount,
    required this.volumeKg,
    required this.averageRpe,
    required this.createdAt,
    this.source = 'Trainer',
  });

  final String id;
  final String sessionId;
  final String sessionName;
  final DateTime date;
  final bool isTrainingDay;
  final int estimatedBurnedKcal;
  final int suggestedCalorieAdjustmentKcal;
  final int suggestedExtraWaterMl;
  final int suggestedExtraProteinG;
  final String postWorkoutMealSuggestion;
  final int durationMin;
  final int exerciseCount;
  final int setCount;
  final double volumeKg;
  final double averageRpe;
  final DateTime createdAt;
  final String source;

  static const schema = 'trainer.training_impact.v1';

  String get dateKey {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  String get deduplicationKey => '$source:$sessionId:$dateKey';

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'id': id,
        'sessionId': sessionId,
        'sessionName': sessionName,
        'date': date.toIso8601String(),
        'dateKey': dateKey,
        'isTrainingDay': isTrainingDay,
        'estimatedBurnedKcal': estimatedBurnedKcal,
        'suggestedCalorieAdjustmentKcal': suggestedCalorieAdjustmentKcal,
        'suggestedExtraWaterMl': suggestedExtraWaterMl,
        'suggestedExtraProteinG': suggestedExtraProteinG,
        'postWorkoutMealSuggestion': postWorkoutMealSuggestion,
        'durationMin': durationMin,
        'exerciseCount': exerciseCount,
        'setCount': setCount,
        'volumeKg': volumeKg,
        'averageRpe': averageRpe,
        'createdAt': createdAt.toIso8601String(),
        'source': source,
        'deduplicationKey': deduplicationKey,
      };

  Map<String, dynamic> toCalorieBridgeJson() => {
        'schema': schema,
        'source': source,
        'deduplicationKey': deduplicationKey,
        'sessionId': sessionId,
        'sessionName': sessionName,
        'dateKey': dateKey,
        'date': date.toIso8601String(),
        'isTrainingDay': isTrainingDay,
        'estimatedBurnedKcal': estimatedBurnedKcal,
        'suggestedCalorieAdjustmentKcal': suggestedCalorieAdjustmentKcal,
        'suggestedExtraWaterMl': suggestedExtraWaterMl,
        'suggestedExtraProteinG': suggestedExtraProteinG,
        'postWorkoutMealSuggestion': postWorkoutMealSuggestion,
        'activityType': 'strength_training',
        'durationMin': durationMin,
        'exerciseCount': exerciseCount,
        'setCount': setCount,
        'volumeKg': volumeKg,
        'averageRpe': averageRpe,
        'createdAt': createdAt.toIso8601String(),
        'integrationNote': 'Payload pomocniczy. Licznik Kalorii powinien użyć deduplicationKey i nie dodawać tej aktywności drugi raz, jeśli sesja została już rozliczona.',
      };

  factory TrainingImpact.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? date;
    final source = json['source']?.toString() ?? 'Trainer';
    final sessionId = json['sessionId']?.toString() ?? json['id']?.toString() ?? 'session_${date.microsecondsSinceEpoch}';
    return TrainingImpact(
      id: json['id']?.toString() ?? 'impact_$sessionId',
      sessionId: sessionId,
      sessionName: json['sessionName']?.toString() ?? 'Trening',
      date: date,
      isTrainingDay: json['isTrainingDay'] as bool? ?? true,
      estimatedBurnedKcal: (json['estimatedBurnedKcal'] as num?)?.round() ?? 0,
      suggestedCalorieAdjustmentKcal: (json['suggestedCalorieAdjustmentKcal'] as num?)?.round() ?? 0,
      suggestedExtraWaterMl: (json['suggestedExtraWaterMl'] as num?)?.round() ?? 0,
      suggestedExtraProteinG: (json['suggestedExtraProteinG'] as num?)?.round() ?? 0,
      postWorkoutMealSuggestion: json['postWorkoutMealSuggestion']?.toString() ?? '',
      durationMin: (json['durationMin'] as num?)?.round() ?? 0,
      exerciseCount: (json['exerciseCount'] as num?)?.toInt() ?? 0,
      setCount: (json['setCount'] as num?)?.toInt() ?? 0,
      volumeKg: (json['volumeKg'] as num?)?.toDouble() ?? 0,
      averageRpe: (json['averageRpe'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt,
      source: source,
    );
  }
}
