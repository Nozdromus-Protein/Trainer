class BodyMeasurement {
  const BodyMeasurement({
    required this.id,
    required this.date,
    required this.weightKg,
    required this.waistCm,
    required this.chestCm,
    required this.armCm,
    required this.thighCm,
    required this.hipsCm,
    required this.calfCm,
    required this.shouldersCm,
    required this.note,
    this.progressPhotoPaths = const [],
  });

  final String id;
  final DateTime date;
  final double weightKg;
  final double waistCm;
  final double chestCm;
  final double armCm;
  final double thighCm;
  final double hipsCm;
  final double calfCm;
  final double shouldersCm;
  final String note;
  final List<String> progressPhotoPaths;

  bool get hasAnyMeasurement => weightKg > 0 || waistCm > 0 || chestCm > 0 || armCm > 0 || thighCm > 0 || hipsCm > 0 || calfCm > 0 || shouldersCm > 0;

  BodyMeasurement copyWith({
    String? id,
    DateTime? date,
    double? weightKg,
    double? waistCm,
    double? chestCm,
    double? armCm,
    double? thighCm,
    double? hipsCm,
    double? calfCm,
    double? shouldersCm,
    String? note,
    List<String>? progressPhotoPaths,
  }) {
    return BodyMeasurement(
      id: id ?? this.id,
      date: date ?? this.date,
      weightKg: weightKg ?? this.weightKg,
      waistCm: waistCm ?? this.waistCm,
      chestCm: chestCm ?? this.chestCm,
      armCm: armCm ?? this.armCm,
      thighCm: thighCm ?? this.thighCm,
      hipsCm: hipsCm ?? this.hipsCm,
      calfCm: calfCm ?? this.calfCm,
      shouldersCm: shouldersCm ?? this.shouldersCm,
      note: note ?? this.note,
      progressPhotoPaths: progressPhotoPaths ?? this.progressPhotoPaths,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'weightKg': weightKg,
        'waistCm': waistCm,
        'chestCm': chestCm,
        'armCm': armCm,
        'thighCm': thighCm,
        'hipsCm': hipsCm,
        'calfCm': calfCm,
        'shouldersCm': shouldersCm,
        'note': note,
        'progressPhotoPaths': progressPhotoPaths,
      };

  factory BodyMeasurement.fromJson(Map<String, dynamic> json) {
    return BodyMeasurement(
      id: json['id']?.toString() ?? 'measurement_${DateTime.now().microsecondsSinceEpoch}',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
      waistCm: (json['waistCm'] as num?)?.toDouble() ?? 0,
      chestCm: (json['chestCm'] as num?)?.toDouble() ?? 0,
      armCm: (json['armCm'] as num?)?.toDouble() ?? 0,
      thighCm: (json['thighCm'] as num?)?.toDouble() ?? 0,
      hipsCm: (json['hipsCm'] as num?)?.toDouble() ?? 0,
      calfCm: (json['calfCm'] as num?)?.toDouble() ?? 0,
      shouldersCm: (json['shouldersCm'] as num?)?.toDouble() ?? 0,
      note: json['note']?.toString() ?? '',
      progressPhotoPaths: ((json['progressPhotoPaths'] as List?) ?? const []).map((value) => value.toString()).where((value) => value.trim().isNotEmpty).toList(),
    );
  }
}
