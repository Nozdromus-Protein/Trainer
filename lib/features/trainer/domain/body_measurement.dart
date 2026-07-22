/// Trend masy ciała z pomiarów: regresja liniowa wagi po czasie w oknie
/// [windowDays] dni. Zwraca null przy mniej niż dwóch pomiarach z wagą.
/// [kgPerWeek] > 0 = przybieranie, < 0 = chudnięcie.
({double kgPerWeek, double currentKg, double firstKg, int samples})? computeWeightTrend(
  List<BodyMeasurement> measurements, {
  int windowDays = 42,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final cutoff = reference.subtract(Duration(days: windowDays));
  final points = <(double, double)>[];
  BodyMeasurement? newest;
  BodyMeasurement? oldest;
  for (final measurement in measurements) {
    if (measurement.weightKg <= 0) continue;
    if (measurement.date.isBefore(cutoff) || measurement.date.isAfter(reference)) continue;
    points.add((
      measurement.date.difference(cutoff).inMinutes / (60 * 24),
      measurement.weightKg,
    ));
    if (newest == null || measurement.date.isAfter(newest.date)) newest = measurement;
    if (oldest == null || measurement.date.isBefore(oldest.date)) oldest = measurement;
  }
  if (points.length < 2 || newest == null || oldest == null) return null;

  final n = points.length.toDouble();
  var sumX = 0.0, sumY = 0.0, sumXy = 0.0, sumXx = 0.0;
  for (final point in points) {
    sumX += point.$1;
    sumY += point.$2;
    sumXy += point.$1 * point.$2;
    sumXx += point.$1 * point.$1;
  }
  final denominator = n * sumXx - sumX * sumX;
  if (denominator.abs() < 1e-9) return null; // wszystkie pomiary tego samego dnia
  final slopePerDay = (n * sumXy - sumX * sumY) / denominator;

  return (
    kgPerWeek: slopePerDay * 7,
    currentKg: newest.weightKg,
    firstKg: oldest.weightKg,
    samples: points.length,
  );
}

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
    this.neckCm = 0,
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

  /// Obwód szyi (cm) — potrzebny m.in. do wzoru US Navy na % tkanki tłuszczowej.
  final double neckCm;
  final String note;
  final List<String> progressPhotoPaths;

  bool get hasAnyMeasurement =>
      weightKg > 0 || waistCm > 0 || chestCm > 0 || armCm > 0 || thighCm > 0 || hipsCm > 0 || calfCm > 0 || shouldersCm > 0 || neckCm > 0;

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
    double? neckCm,
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
      neckCm: neckCm ?? this.neckCm,
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
        'neckCm': neckCm,
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
      neckCm: (json['neckCm'] as num?)?.toDouble() ?? 0,
      note: json['note']?.toString() ?? '',
      progressPhotoPaths: ((json['progressPhotoPaths'] as List?) ?? const []).map((value) => value.toString()).where((value) => value.trim().isNotEmpty).toList(),
    );
  }
}
