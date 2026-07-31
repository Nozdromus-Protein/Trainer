enum MuscleGroup {
  chest('Klatka piersiowa'),
  back('Plecy'),
  shoulders('Barki'),
  biceps('Biceps'),
  triceps('Triceps'),
  forearms('Przedramiona'),
  core('Core'),
  quadriceps('Czworogłowe uda'),
  hamstrings('Dwugłowe uda'),
  glutes('Pośladki'),
  calves('Łydki'),
  fullBody('Całe ciało'),
  cardio('Kondycja'),
  other('Inne');

  const MuscleGroup(this.label);

  final String label;

  static MuscleGroup fromText(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('klatk') || normalized.contains('chest')) {
      return MuscleGroup.chest;
    }
    if (normalized.contains('plec') ||
        normalized.contains('grzbiet') ||
        normalized.contains('back')) {
      return MuscleGroup.back;
    }
    if (normalized.contains('bark') ||
        normalized.contains('ramion') ||
        normalized.contains('shoulder')) {
      return MuscleGroup.shoulders;
    }
    if (normalized.contains('biceps')) return MuscleGroup.biceps;
    if (normalized.contains('triceps')) return MuscleGroup.triceps;
    if (normalized.contains('przedram')) return MuscleGroup.forearms;
    // Łydki PRZED brzuchem: „mięsień brzuchaty łydki" (gastrocnemius) zawiera
    // podciąg „brzuch", więc bez tej kolejności łydka lądowała w core.
    if (normalized.contains('lydk') ||
        normalized.contains('łydk') ||
        normalized.contains('calf') ||
        normalized.contains('brzuchaty') ||
        normalized.contains('plaszczkowat') ||
        normalized.contains('płaszczkowat')) {
      return MuscleGroup.calves;
    }
    if (normalized.contains('brzuch') ||
        normalized.contains('core') ||
        normalized.contains('stabil')) {
      return MuscleGroup.core;
    }
    if (normalized.contains('czwor') ||
        normalized.contains('quad') ||
        normalized.contains('przod uda')) {
      return MuscleGroup.quadriceps;
    }
    if (normalized.contains('dwug') ||
        normalized.contains('hamstring') ||
        normalized.contains('tyl uda')) {
      return MuscleGroup.hamstrings;
    }
    if (normalized.contains('poslad') ||
        normalized.contains('poślad') ||
        normalized.contains('glute')) {
      return MuscleGroup.glutes;
    }
    if (normalized.contains('lydk') || normalized.contains('calf')) {
      return MuscleGroup.calves;
    }
    if (normalized.contains('cardio') ||
        normalized.contains('kondyc') ||
        normalized.contains('wydol')) {
      return MuscleGroup.cardio;
    }
    if (normalized.contains('cale cialo') || normalized.contains('full body')) {
      return MuscleGroup.fullBody;
    }
    return MuscleGroup.other;
  }
}

enum EquipmentType {
  bodyweight('Masa ciała'),
  dumbbell('Hantle'),
  barbell('Sztanga'),
  kettlebell('Kettlebell'),
  machine('Maszyna'),
  cable('Wyciąg'),
  resistanceBand('Guma oporowa'),
  pullUpBar('Drążek'),
  bench('Ławka'),
  rack('Stojaki / rack'),
  step('Step / podwyższenie'),
  cardioMachine('Sprzęt cardio'),
  mat('Mata'),
  other('Inny sprzęt');

  const EquipmentType(this.label);

  final String label;

  /// Stabilny klucz do zapisu w ustawieniach (nazwa wartości enuma).
  String get key => name;

  static EquipmentType? fromKey(String value) {
    final normalized = value.trim();
    for (final type in EquipmentType.values) {
      if (type.name == normalized) return type;
    }
    return null;
  }

  static Set<EquipmentType> fromText(String value) {
    final normalized = value.trim().toLowerCase();
    final result = <EquipmentType>{};
    if (normalized.contains('masa ciała') ||
        normalized.contains('masa ciala') ||
        normalized.contains('bodyweight') ||
        normalized.contains('bez sprzętu') ||
        normalized.contains('bez sprzetu')) {
      result.add(EquipmentType.bodyweight);
    }
    if (normalized.contains('hant')) result.add(EquipmentType.dumbbell);
    if (normalized.contains('sztang')) result.add(EquipmentType.barbell);
    if (normalized.contains('kett')) result.add(EquipmentType.kettlebell);
    if (normalized.contains('maszyn')) result.add(EquipmentType.machine);
    if (normalized.contains('wyciąg') ||
        normalized.contains('wyciag') ||
        normalized.contains('cable') ||
        normalized.contains('link')) {
      result.add(EquipmentType.cable);
    }
    if (normalized.contains('gum') || normalized.contains('band')) {
      result.add(EquipmentType.resistanceBand);
    }
    if (normalized.contains('drąż') ||
        normalized.contains('draz') ||
        normalized.contains('poręcz') ||
        normalized.contains('porecz') ||
        normalized.contains('barier') ||
        normalized.contains('pull-up bar')) {
      result.add(EquipmentType.pullUpBar);
    }
    if (normalized.contains('ławk') || normalized.contains('lawk')) {
      result.add(EquipmentType.bench);
    }
    // „rack"/„stojaki"/„klatka treningowa" — uwaga: NIE mylić z „klatka
    // piersiowa" (to partia, nie sprzęt), dlatego dopasowujemy tylko jawne słowa.
    if (normalized.contains('rack') ||
        normalized.contains('stojak') ||
        normalized.contains('klatka treningowa') ||
        normalized.contains('klatka siłowa') ||
        normalized.contains('klatka silowa')) {
      result.add(EquipmentType.rack);
    }
    if (normalized.contains('step') ||
        normalized.contains('podwyż') ||
        normalized.contains('podwyz') ||
        normalized.contains('skrzyni') ||
        normalized.contains('stopień') ||
        normalized.contains('stopie')) {
      result.add(EquipmentType.step);
    }
    if (normalized.contains('bież') ||
        normalized.contains('biez') ||
        normalized.contains('rower') ||
        normalized.contains('ergometr') ||
        normalized.contains('orbitrek')) {
      result.add(EquipmentType.cardioMachine);
    }
    if (normalized.contains('mat')) result.add(EquipmentType.mat);
    if (result.isEmpty) result.add(EquipmentType.other);
    return result;
  }
}

enum TrainingGoal {
  strength('Siła'),
  muscleGain('Masa mięśniowa'),
  fatLoss('Redukcja'),
  conditioning('Kondycja'),
  mobility('Mobilność'),
  stability('Stabilizacja');

  const TrainingGoal(this.label);

  final String label;

  static TrainingGoal? fromText(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('sił') || normalized.contains('sil')) {
      return TrainingGoal.strength;
    }
    if (normalized.contains('masa') ||
        normalized.contains('mięś') ||
        normalized.contains('mies') ||
        normalized.contains('hipert')) {
      return TrainingGoal.muscleGain;
    }
    if (normalized.contains('redu') ||
        normalized.contains('spal') ||
        normalized.contains('fat')) {
      return TrainingGoal.fatLoss;
    }
    if (normalized.contains('kond') ||
        normalized.contains('wydol') ||
        normalized.contains('cardio')) {
      return TrainingGoal.conditioning;
    }
    if (normalized.contains('mobil') || normalized.contains('zakres')) {
      return TrainingGoal.mobility;
    }
    if (normalized.contains('stabil') || normalized.contains('core')) {
      return TrainingGoal.stability;
    }
    return null;
  }
}
