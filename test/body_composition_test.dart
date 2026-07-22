import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/trainer_models.dart';

void main() {
  group('computeBodyCompositionBreakdown — rozłączny podział masy', () {
    test('przypadek referencyjny: 95,3 kg / 23% BF', () {
      final breakdown = computeBodyCompositionBreakdown(
        bodyWeightKg: 95.3,
        bodyFatPercent: 23,
      )!;
      expect(breakdown.fatMassKg, closeTo(21.9, 0.05));
      expect(breakdown.fatFreeMassKg, closeTo(73.4, 0.05));
      expect(breakdown.fatFreeMassPercent, 77.0);
      // Suma kilogramów DOKŁADNIE równa masie ciała.
      expect(breakdown.fatMassKg + breakdown.fatFreeMassKg, closeTo(95.3, 0.0001));
      // Procenty sumują się DOKŁADNIE do 100 (bez 99,9/100,1).
      expect(breakdown.bodyFatPercent + breakdown.fatFreeMassPercent, 100.0);
    });

    test('zaokrąglenia: procenty zawsze sumują się do 100', () {
      for (final bf in [3.14159, 17.777, 23.05, 41.949, 59.99]) {
        for (final weight in [48.3, 77.7, 95.3, 142.19]) {
          final breakdown = computeBodyCompositionBreakdown(
            bodyWeightKg: weight,
            bodyFatPercent: bf,
          );
          expect(breakdown, isNotNull, reason: 'bf=$bf, waga=$weight');
          // Suma procentów = 100 (tolerancja tylko na reprezentację double —
          // wyświetlane wartości z toStringAsFixed(1) sumują się DOKŁADNIE).
          expect(
            breakdown!.bodyFatPercent + breakdown.fatFreeMassPercent,
            closeTo(100.0, 1e-9),
            reason: 'bf=$bf, waga=$weight',
          );
          final displayedSum =
              double.parse(breakdown.bodyFatPercent.toStringAsFixed(1)) +
                  double.parse(breakdown.fatFreeMassPercent.toStringAsFixed(1));
          expect(displayedSum, closeTo(100.0, 1e-9));
          expect(
            breakdown.fatMassKg + breakdown.fatFreeMassKg,
            closeTo(weight, 0.0001),
          );
          expect(breakdown.fatMassKg, greaterThanOrEqualTo(0));
          expect(breakdown.fatFreeMassKg, greaterThan(0));
        }
      }
    });

    test('brak masy ciała → null', () {
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: 0, bodyFatPercent: 20),
        isNull,
      );
    });

    test('brak BF → null', () {
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: 90, bodyFatPercent: 0),
        isNull,
      );
    });

    test('wartości ujemne → null', () {
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: -80, bodyFatPercent: 20),
        isNull,
      );
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: 80, bodyFatPercent: -5),
        isNull,
      );
    });

    test('NaN → null', () {
      expect(
        computeBodyCompositionBreakdown(
          bodyWeightKg: double.nan,
          bodyFatPercent: 20,
        ),
        isNull,
      );
      expect(
        computeBodyCompositionBreakdown(
          bodyWeightKg: 80,
          bodyFatPercent: double.nan,
        ),
        isNull,
      );
    });

    test('nieskończoność → null', () {
      expect(
        computeBodyCompositionBreakdown(
          bodyWeightKg: double.infinity,
          bodyFatPercent: 20,
        ),
        isNull,
      );
      expect(
        computeBodyCompositionBreakdown(
          bodyWeightKg: 80,
          bodyFatPercent: double.infinity,
        ),
        isNull,
      );
    });

    test('wartości skrajne: BF ≥ 100% i masa poza zakresem → null', () {
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: 80, bodyFatPercent: 100),
        isNull,
      );
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: 80, bodyFatPercent: 130),
        isNull,
      );
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: 10, bodyFatPercent: 20),
        isNull,
      );
      expect(
        computeBodyCompositionBreakdown(bodyWeightKg: 900, bodyFatPercent: 20),
        isNull,
      );
    });
  });

  group('FFMI — zawsze z FFM i wzrostu', () {
    test('liczy FFMI z FFM i wzrostu', () {
      // FFM 73.4 kg przy 185 cm → 73.4/1.85² + 6.1×(1.8−1.85) ≈ 21.1.
      final ffmi = computeFfmi(fatFreeMassKg: 73.4, heightCm: 185)!;
      expect(ffmi, closeTo(21.1, 0.15));
    });

    test('bez normalizacji: czysty FFM/wzrost²', () {
      final ffmi = computeFfmi(
        fatFreeMassKg: 73.4,
        heightCm: 185,
        normalizedTo180cm: false,
      )!;
      expect(ffmi, closeTo(73.4 / (1.85 * 1.85), 0.05));
    });

    test('brak danych / niefizyczne wartości → null', () {
      expect(computeFfmi(fatFreeMassKg: 0, heightCm: 185), isNull);
      expect(computeFfmi(fatFreeMassKg: -10, heightCm: 185), isNull);
      expect(computeFfmi(fatFreeMassKg: 70, heightCm: 0), isNull);
      expect(computeFfmi(fatFreeMassKg: double.nan, heightCm: 185), isNull);
      expect(computeFfmi(fatFreeMassKg: 70, heightCm: 999), isNull);
    });
  });

  group('Zakres niepewności i poziom pewności', () {
    test('słowne poziomy pewności', () {
      expect(confidenceLevelFor(90), ConfidenceLevel.high);
      expect(confidenceLevelFor(68), ConfidenceLevel.moderate);
      expect(confidenceLevelFor(30), ConfidenceLevel.low);
      expect(confidenceLevelFor(double.nan), ConfidenceLevel.low);
    });

    test('zakres BF rośnie przy niższej pewności', () {
      final high = bodyFatRangeForConfidence(
        bodyFatPercent: 23,
        confidencePercent: 85,
      );
      final low = bodyFatRangeForConfidence(
        bodyFatPercent: 23,
        confidencePercent: 30,
      );
      expect(high.max - high.min, lessThan(low.max - low.min));
      expect(high.min, lessThan(23));
      expect(high.max, greaterThan(23));
    });

    test('mała zmiana BF mieści się w marginesie błędu', () {
      expect(
        bodyFatChangeWithinErrorMargin(
          deltaPercentPoints: -0.6,
          olderConfidencePercent: 68,
          newerConfidencePercent: 70,
        ),
        isTrue,
      );
      expect(
        bodyFatChangeWithinErrorMargin(
          deltaPercentPoints: -4.0,
          olderConfidencePercent: 68,
          newerConfidencePercent: 70,
        ),
        isFalse,
      );
      // Słabsze ogniwo: niska pewność jednej z analiz poszerza margines.
      expect(
        bodyFatChangeWithinErrorMargin(
          deltaPercentPoints: -2.0,
          olderConfidencePercent: 20,
          newerConfidencePercent: 90,
        ),
        isTrue,
      );
    });
  });

  group('Masa przy docelowym BF (zachowana FFM)', () {
    test('zwraca zakres, nie jedną liczbę', () {
      final range = weightRangeForTargetBodyFat(
        fatFreeMassKg: 73.4,
        targetBodyFatMinPercent: 12,
        targetBodyFatMaxPercent: 15,
      )!;
      expect(range.min, closeTo(73.4 / 0.88, 0.2));
      expect(range.max, closeTo(73.4 / 0.85, 0.2));
      expect(range.min, lessThan(range.max));
    });

    test('niefizyczne wejście → null', () {
      expect(
        weightRangeForTargetBodyFat(
          fatFreeMassKg: 0,
          targetBodyFatMinPercent: 12,
          targetBodyFatMaxPercent: 15,
        ),
        isNull,
      );
      expect(
        weightRangeForTargetBodyFat(
          fatFreeMassKg: 70,
          targetBodyFatMinPercent: 0,
          targetBodyFatMaxPercent: 15,
        ),
        isNull,
      );
    });
  });

  group('Parametr kostny — uczciwe nazewnictwo', () {
    test('nazwa zależy od wartości', () {
      expect(boneParameterLabel(bonePercent: 0), 'Brak wystarczających danych');
      expect(boneParameterLabel(bonePercent: 4.2), 'Szacowana masa mineralna kości');
      expect(boneParameterLabel(bonePercent: 12), 'Szacowana masa szkieletu');
      expect(boneParameterLabel(bonePercent: 22), 'Parametr kostny (niewiarygodny)');
    });

    test('wiarygodność biologiczna', () {
      expect(boneParameterPlausible(4), isTrue);
      expect(boneParameterPlausible(15), isTrue);
      expect(boneParameterPlausible(22), isFalse);
      expect(boneParameterPlausible(0), isFalse);
      expect(boneParameterPlausible(double.nan), isFalse);
    });
  });

  group('Walidacja biologiczna', () {
    test('poprawny wynik przechodzi walidację', () {
      final validation = validateBodyComposition(
        bodyWeightKg: 95.3,
        bodyFatPercent: 23,
        musclePercent: 42,
        waterPercent: 55,
        bonePercent: 4,
      );
      expect(validation.isReliable, isTrue);
      expect(validation.issues, isEmpty);
    });

    test('mięśnie przekraczające FFM → problem blokujący', () {
      final validation = validateBodyComposition(
        bodyWeightKg: 95.3,
        bodyFatPercent: 23,
        musclePercent: 80, // FFM to 77% — mięśnie nie mogą być większe
      );
      expect(validation.isReliable, isFalse);
      expect(
        validation.messages.join(' '),
        contains('nie mogą przekraczać beztłuszczowej masy'),
      );
    });

    test('NaN w danych → problem blokujący', () {
      final validation = validateBodyComposition(
        bodyWeightKg: 95.3,
        bodyFatPercent: double.nan,
      );
      expect(validation.isReliable, isFalse);
    });

    test('BF poza biologicznym zakresem → problem blokujący', () {
      expect(
        validateBodyComposition(bodyWeightKg: 95.3, bodyFatPercent: 75)
            .isReliable,
        isFalse,
      );
      expect(
        validateBodyComposition(bodyWeightKg: 95.3, bodyFatPercent: 1.2)
            .isReliable,
        isFalse,
      );
    });

    test('brak masy ciała → problem blokujący', () {
      final validation = validateBodyComposition(
        bodyWeightKg: 0,
        bodyFatPercent: 23,
      );
      expect(validation.isReliable, isFalse);
    });

    test('woda poza zakresem → ostrzeżenie (bez blokady)', () {
      final validation = validateBodyComposition(
        bodyWeightKg: 95.3,
        bodyFatPercent: 23,
        waterPercent: 90,
      );
      expect(validation.hasIssues, isTrue);
      expect(validation.isReliable, isTrue);
    });

    test('niewiarygodny parametr kostny → ostrzeżenie z możliwością pominięcia', () {
      final validation = validateBodyComposition(
        bodyWeightKg: 95.3,
        bodyFatPercent: 23,
        bonePercent: 20,
      );
      expect(validation.hasIssues, isTrue);
      expect(validation.isReliable, isTrue);
      expect(validation.messages.join(' '), contains('pominąć'));
    });
  });

  group('Migracja starych analiz', () {
    test('stara analiza (bez nowych pól) wczytuje się jako schemaVersion 1', () {
      final restored = BodyAnalysisResult.fromJson({
        'id': 'old_analysis',
        'date': '2026-05-01T10:00:00.000',
        'composition': {
          'bodyFatPercent': 24.5,
          'musclePercent': 41.0,
          'waterPercent': 54.0,
          'bonePercent': 11.0,
          'bmi': 27.0,
          'ffmi': 21.0,
          'method': 'ai_photo',
        },
        'currentSilhouette': 'Mezomorf',
        'confidencePercent': 70,
        'source': 'gemini',
      });
      // Stare wartości NIE są nadpisywane.
      expect(restored.composition.bodyFatPercent, 24.5);
      expect(restored.composition.musclePercent, 41.0);
      expect(restored.currentSilhouette, 'Mezomorf');
      // Oznaczenie wcześniejszej wersji modelu + bezpieczne domyślne nowych pól.
      expect(restored.schemaVersion, 1);
      expect(restored.lowReliability, isFalse);
      expect(restored.validationIssues, isEmpty);
      expect(restored.bodyFatRangeMinPercent, 0);
      // FFM da się policzyć z masy i BF (przeliczenie, nie nadpisanie).
      final breakdown = computeBodyCompositionBreakdown(
        bodyWeightKg: 95.3,
        bodyFatPercent: restored.composition.bodyFatPercent,
      );
      expect(breakdown, isNotNull);
    });

    test('nowa analiza serializuje i odtwarza nowe pola (kopia bez utraty)', () {
      // Konstrukcja przez fromJson dla pełnej kontroli pól.
      final result = BodyAnalysisResult.fromJson({
        'id': 'new_analysis',
        'date': '2026-07-12T09:00:00.000',
        'composition': {'bodyFatPercent': 23.0, 'method': 'ai_photo'},
        'schemaVersion': 2,
        'bodyWeightKgAtAnalysis': 95.3,
        'waistCmAtAnalysis': 92.0,
        'bodyFatRangeMinPercent': 20.0,
        'bodyFatRangeMaxPercent': 26.0,
        'validationIssues': ['test'],
        'lowReliability': true,
        'strategyIdAtAnalysis': 'recomposition',
        'physiqueIdAtAnalysis': 'athletic',
        'possibleImbalances': ['możliwa asymetria barków'],
        'modelVersion': 'gemini-2.5-flash',
        'rawAiJson': '{"x":1}',
      });
      final roundtrip = BodyAnalysisResult.fromJson(result.toJson());
      expect(roundtrip.schemaVersion, 2);
      expect(roundtrip.bodyWeightKgAtAnalysis, 95.3);
      expect(roundtrip.waistCmAtAnalysis, 92.0);
      expect(roundtrip.bodyFatRangeMinPercent, 20.0);
      expect(roundtrip.bodyFatRangeMaxPercent, 26.0);
      expect(roundtrip.lowReliability, isTrue);
      expect(roundtrip.strategyIdAtAnalysis, 'recomposition');
      expect(roundtrip.physiqueIdAtAnalysis, 'athletic');
      expect(roundtrip.possibleImbalances, ['możliwa asymetria barków']);
      expect(roundtrip.modelVersion, 'gemini-2.5-flash');
      expect(roundtrip.rawAiJson, '{"x":1}');
    });

    test('fromAiJson: zakres BF i ostrożne pola wizualne', () {
      final result = BodyAnalysisResult.fromAiJson(
        {
          'composition': {
            'bodyFatPercent': '23',
            'bodyFatRangePercent': {'min': 26, 'max': 20}, // celowo odwrócone
          },
          'possibleImbalances': ['możliwa tendencja do przodopochylenia'],
          'watchAreas': 'obwód talii',
          'developmentPriorities': ['barki', 'plecy'],
          'confidencePercent': 68,
        },
        id: 'ai_1',
        date: DateTime(2026, 7, 12),
        source: 'gemini',
        modelVersion: 'gemini-2.5-flash',
      );
      expect(result.schemaVersion, 2);
      expect(result.bodyFatRangeMinPercent, 20);
      expect(result.bodyFatRangeMaxPercent, 26);
      expect(result.possibleImbalances, hasLength(1));
      expect(result.watchAreas, ['obwód talii']);
      expect(result.developmentPriorities, hasLength(2));
      expect(result.modelVersion, 'gemini-2.5-flash');
    });
  });
}
