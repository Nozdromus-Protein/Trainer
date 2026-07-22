import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/domain/body_analysis.dart';
import 'package:licznik_treningu/features/trainer/domain/body_measurement.dart';
import 'package:licznik_treningu/features/trainer/domain/body_muscle.dart';

void main() {
  group('estimateBodyCompositionLocally', () {
    test(
        'mężczyzna z obwodami pasa i szyi — wzór US Navy w sensownych zakresach',
        () {
      final result = estimateBodyCompositionLocally(
        weightKg: 100,
        heightCm: 185,
        age: 28,
        sex: 'Mężczyzna',
        waistCm: 96,
        neckCm: 41,
      );

      expect(result.hasData, isTrue);
      expect(result.method, 'formulas');
      expect(result.bodyFatPercent, greaterThan(10));
      expect(result.bodyFatPercent, lessThan(40));
      expect(result.waterPercent, greaterThan(40));
      expect(result.waterPercent, lessThan(70));
      expect(result.musclePercent, greaterThan(30));
      expect(result.musclePercent, lessThan(60));
      expect(result.bmi, closeTo(29.2, 0.2));
      expect(result.ffmi, greaterThan(15));
      expect(result.visceralFatLevel, greaterThan(0));
    });

    test('bez obwodów działa wzór Deurenberga (BMI + wiek)', () {
      final result = estimateBodyCompositionLocally(
        weightKg: 80,
        heightCm: 178,
        age: 35,
        sex: 'Mężczyzna',
      );

      expect(result.hasData, isTrue);
      // Deurenberg: 1.2×BMI + 0.23×wiek − 10.8 − 5.4.
      final bmi = 80 / (1.78 * 1.78);
      expect(result.bodyFatPercent,
          closeTo(1.2 * bmi + 0.23 * 35 - 10.8 - 5.4, 0.2));
      expect(result.visceralFatLevel, 0); // brak pasa → brak szacunku trzewnego
    });

    test(
        'kobieta ma wyższy szacunek tkanki tłuszczowej przy tych samych danych',
        () {
      final male = estimateBodyCompositionLocally(
          weightKg: 70, heightCm: 170, age: 30, sex: 'Mężczyzna');
      final female = estimateBodyCompositionLocally(
          weightKg: 70, heightCm: 170, age: 30, sex: 'Kobieta');
      expect(female.bodyFatPercent, greaterThan(male.bodyFatPercent));
    });

    test('brak masy albo wzrostu zwraca pusty szacunek', () {
      expect(
          estimateBodyCompositionLocally(
                  weightKg: 0, heightCm: 180, age: 30, sex: '')
              .hasData,
          isFalse);
      expect(
          estimateBodyCompositionLocally(
                  weightKg: 80, heightCm: 0, age: 30, sex: '')
              .hasData,
          isFalse);
    });
  });

  group('BodyAnalysisResult', () {
    test('toJson → fromJson zachowuje wszystkie pola', () {
      final original = BodyAnalysisResult(
        id: 'analysis-1',
        date: DateTime(2026, 7, 11, 9, 30),
        photoFrontPath: '/photos/front.jpg',
        photoSidePath: '/photos/side.jpg',
        photoBackPath: '/photos/back.jpg',
        composition: const BodyCompositionEstimate(
          bodyFatPercent: 21.4,
          musclePercent: 42.3,
          waterPercent: 55.1,
          bonePercent: 11.8,
          visceralFatLevel: 8,
          bmi: 29.2,
          ffmi: 23.4,
          method: 'ai_photo',
        ),
        currentSilhouette: 'Mezomorf z tendencją endomorficzną',
        targetSilhouetteId: 'v_taper',
        postureNotes: 'Lekka protrakcja barków.',
        symmetryNotes: 'Prawe ramię mocniejsze.',
        strengths: const ['Szerokie plecy', 'Mocne nogi'],
        weaknesses: const ['Talia', 'Łydki'],
        estimatedMeasurementsCm: const {'waist': 96.0, 'chest': 112.5},
        summary: 'Solidna baza mięśniowa.',
        trainingRecommendations: const ['Więcej podciągania'],
        nutritionRecommendations: const ['Deficyt 300 kcal'],
        risks: const ['Asymetria do obserwacji'],
        confidencePercent: 72,
        source: 'gemini',
        contextUsed: const ['profil', 'pomiary'],
      );

      final restored = BodyAnalysisResult.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.date, original.date);
      expect(restored.photoSidePath, original.photoSidePath);
      expect(restored.composition.bodyFatPercent, 21.4);
      expect(restored.composition.method, 'ai_photo');
      expect(restored.currentSilhouette, original.currentSilhouette);
      expect(restored.targetSilhouetteId, 'v_taper');
      expect(restored.targetGoal, SilhouetteGoal.vTaper);
      expect(
          restored.estimatedMeasurementsCm, original.estimatedMeasurementsCm);
      expect(restored.strengths, original.strengths);
      expect(restored.risks, original.risks);
      expect(restored.confidencePercent, 72);
      expect(restored.contextUsed, original.contextUsed);
      expect(restored.photoCount, 3);
    });

    test('fromAiJson toleruje stringi, procenty i filtruje nieznane wymiary',
        () {
      final result = BodyAnalysisResult.fromAiJson(
        {
          'composition': {
            'bodyFatPercent': '18,5%',
            'musclePercent': 44,
            'waterPercent': '58.2',
            'bmi': 24.1,
          },
          'currentSilhouette': ' V-taper w budowie ',
          'strengths': 'Dobre proporcje barków',
          'weaknesses': ['Łydki', ''],
          'estimatedMeasurementsCm': {
            'waist': '95',
            'chest': 111.5,
            'unknown_part': 50,
            'thigh': 0,
            'arm': 999,
          },
          'confidencePercent': '150',
        },
        id: 'analysis-ai',
        date: DateTime(2026, 7, 11),
        source: 'openai',
        targetSilhouetteId: 'lean_shredded',
        contextUsed: const ['profil'],
      );

      expect(result.composition.bodyFatPercent, 18.5);
      expect(result.composition.musclePercent, 44);
      expect(result.composition.waterPercent, 58.2);
      expect(result.composition.method, 'ai_photo');
      expect(result.currentSilhouette, 'V-taper w budowie');
      // Pojedynczy string staje się jednoelementową listą; puste wpisy odpadają.
      expect(result.strengths, ['Dobre proporcje barków']);
      expect(result.weaknesses, ['Łydki']);
      // Nieznane klucze, zera i wartości absurdalne (>250 cm) odfiltrowane.
      expect(result.estimatedMeasurementsCm.keys.toSet(), {'waist', 'chest'});
      expect(result.estimatedMeasurementsCm['waist'], 95);
      // Pewność przycięta do 0-100.
      expect(result.confidencePercent, 100);
      expect(result.targetGoal, SilhouetteGoal.leanShredded);
    });
  });

  group('computeSilhouetteNutritionTargets', () {
    SilhouetteNutritionTargets? compute(SilhouetteGoal? goal,
            {String sex = 'Mężczyzna'}) =>
        computeSilhouetteNutritionTargets(
          goal: goal,
          weightKg: 100,
          heightCm: 185,
          age: 28,
          sex: sex,
          trainingDaysPerWeek: 4,
        );

    test('każda sylwetka ma inne zapotrzebowanie; faza wynika z sylwetki', () {
      final lean = compute(SilhouetteGoal.leanShredded)!;
      final athletic = compute(SilhouetteGoal.athletic)!;
      final muscular = compute(SilhouetteGoal.muscular)!;

      // Redukcja < utrzymanie < masa.
      expect(lean.goalKcal, lessThan(athletic.goalKcal));
      expect(athletic.goalKcal, lessThan(muscular.goalKcal));
      expect(lean.phaseLabel, 'Redukcja');
      expect(athletic.phaseLabel, 'Utrzymanie');
      expect(muscular.phaseLabel, contains('Nadwyżka'));

      // Białko wg sylwetki (g/kg × 100 kg): definicja najwyżej.
      expect(lean.proteinG, 220);
      expect(athletic.proteinG, 170);
      expect(lean.proteinG, greaterThan(muscular.proteinG));

      // Makra spinają się z kaloriami (4/4/9 z tolerancją zaokrągleń do 5 g).
      for (final targets in [lean, athletic, muscular]) {
        final macroKcal =
            targets.proteinG * 4 + targets.carbsG * 4 + targets.fatG * 9;
        expect((macroKcal - targets.goalKcal).abs(), lessThanOrEqualTo(60),
            reason: '${targets.silhouetteId}: makra ≈ kcal celu');
        expect(targets.carbsG, greaterThan(0));
        expect(targets.bmrKcal, greaterThan(1500));
        expect(targets.tdeeKcal, greaterThan(targets.bmrKcal));
      }
    });

    test('kobieta ma niższe zapotrzebowanie przy tym samym profilu', () {
      final male = compute(SilhouetteGoal.athletic)!;
      final female = compute(SilhouetteGoal.athletic, sex: 'Kobieta')!;
      expect(female.goalKcal, lessThan(male.goalKcal));
    });

    test('legacy target also keeps planned training outside the base', () {
      final noTraining = computeSilhouetteNutritionTargets(
        goal: SilhouetteGoal.athletic,
        weightKg: 96,
        heightCm: 185,
        age: 30,
        sex: 'Mężczyzna',
        trainingDaysPerWeek: 0,
      )!;
      final sixDays = computeSilhouetteNutritionTargets(
        goal: SilhouetteGoal.athletic,
        weightKg: 96,
        heightCm: 185,
        age: 30,
        sex: 'Mężczyzna',
        trainingDaysPerWeek: 6,
      )!;
      expect(noTraining.tdeeKcal, 2190);
      expect(sixDays.goalKcal, noTraining.goalKcal);
    });

    test('brak sylwetki albo profilu zwraca null', () {
      expect(compute(null), isNull);
      expect(
        computeSilhouetteNutritionTargets(
          goal: SilhouetteGoal.athletic,
          weightKg: 0,
          heightCm: 185,
          age: 28,
          sex: '',
          trainingDaysPerWeek: 3,
        ),
        isNull,
      );
    });

    test('toJson niesie komplet pól dla mostu do Kalorii', () {
      final targets = compute(SilhouetteGoal.vTaper)!;
      final json = targets.toJson();
      expect(json['schema'], SilhouetteNutritionTargets.schema);
      expect(json['silhouetteId'], 'v_taper');
      expect(json['silhouetteLabel'], SilhouetteGoal.vTaper.label);
      expect(json['goalKcal'], targets.goalKcal);
      expect(json['proteinG'], targets.proteinG);
      expect(json['carbsG'], targets.carbsG);
      expect(json['fatG'], targets.fatG);
      expect(json['phaseLabel'], 'Lekka redukcja');
    });
  });

  group('computeWeightTrend', () {
    BodyMeasurement measurement(DateTime date, double kg) => BodyMeasurement(
          id: 'm_${date.microsecondsSinceEpoch}',
          date: date,
          weightKg: kg,
          waistCm: 0,
          chestCm: 0,
          armCm: 0,
          thighCm: 0,
          hipsCm: 0,
          calfCm: 0,
          shouldersCm: 0,
          note: '',
        );

    test('równomierny spadek daje ujemne tempo tygodniowe', () {
      final now = DateTime(2026, 7, 11, 12);
      final trend = computeWeightTrend([
        measurement(DateTime(2026, 7, 10, 12), 98.0),
        measurement(DateTime(2026, 7, 3, 12), 98.8),
        measurement(DateTime(2026, 6, 26, 12), 99.6),
      ], now: now)!;

      expect(trend.kgPerWeek, closeTo(-0.8, 0.05));
      expect(trend.currentKg, 98.0);
      expect(trend.firstKg, 99.6);
      expect(trend.samples, 3);
    });

    test('przyrost masy daje dodatnie tempo', () {
      final now = DateTime(2026, 7, 11);
      final trend = computeWeightTrend([
        measurement(DateTime(2026, 7, 9), 82.0),
        measurement(DateTime(2026, 6, 25), 81.0),
      ], now: now)!;
      expect(trend.kgPerWeek, greaterThan(0.3));
    });

    test(
        'null przy pojedynczym pomiarze, pomiarach z tą samą chwilą i poza oknem',
        () {
      final now = DateTime(2026, 7, 11);
      expect(
          computeWeightTrend([measurement(DateTime(2026, 7, 10), 98)],
              now: now),
          isNull);
      final sameMoment = DateTime(2026, 7, 10, 8);
      expect(
        computeWeightTrend(
            [measurement(sameMoment, 98), measurement(sameMoment, 97)],
            now: now),
        isNull,
      );
      // Stare pomiary poza oknem 42 dni nie liczą się do trendu.
      expect(
        computeWeightTrend([
          measurement(DateTime(2026, 3, 1), 105),
          measurement(DateTime(2026, 2, 1), 108),
        ], now: now),
        isNull,
      );
    });
  });

  group('SilhouetteGoal', () {
    test('katalog ma unikalne id i partie do ilustracji', () {
      final ids = SilhouetteGoal.values.map((goal) => goal.id).toSet();
      expect(ids.length, SilhouetteGoal.values.length);
      for (final goal in SilhouetteGoal.values) {
        expect(goal.label, isNotEmpty);
        expect(goal.description, isNotEmpty);
        expect(goal.strategy, isNotEmpty);
        expect(goal.highlightPrimary, isNotEmpty,
            reason: '${goal.id} musi podświetlać partie na modelu ciała');
      }
    });

    test('fromId odnajduje typ i odrzuca nieznane', () {
      expect(SilhouetteGoal.fromId('v_taper'), SilhouetteGoal.vTaper);
      expect(SilhouetteGoal.fromId('athletic'), SilhouetteGoal.athletic);
      expect(SilhouetteGoal.fromId(''), isNull);
      expect(SilhouetteGoal.fromId(null), isNull);
      expect(SilhouetteGoal.fromId('nope'), isNull);
    });

    test('partie celów istnieją w modelu mięśni', () {
      for (final goal in SilhouetteGoal.values) {
        for (final muscle in [
          ...goal.highlightPrimary,
          ...goal.highlightSecondary
        ]) {
          expect(BodyMuscle.values, contains(muscle));
        }
      }
    });
  });
}
