/// Mapa mięśni człowieka (model + maski partii) i wpływ ćwiczeń na partie.
///
/// Czysty Dart (bez Fluttera) — kolory regeneracji nakładane są w warstwie UI.
/// Maski PNG są robocze (zielone); finalny kolor nakładamy dynamicznie
/// (ColorFiltered/srcIn) na podstawie regeneracji.
library;

/// Strona modelu człowieka.
enum BodyMuscleSide { front, back }

/// Pojedyncza, anatomiczna partia mięśniowa używana na mapie regeneracji.
enum BodyMuscle {
  chest('Klatka piersiowa'),
  abs('Brzuch'),
  obliques('Skośne brzucha'),
  adductors('Przywodziciele'),
  biceps('Biceps'),
  calvesFront('Łydki (przód)'),
  calvesBack('Łydki (tył)'),
  forearmsFront('Przedramiona (przód)'),
  forearmsBack('Przedramiona (tył)'),
  frontShoulders('Barki przód'),
  rearShoulders('Barki tył'),
  supraspinatus('Mięsień nadgrzebieniowy'),
  infraspinatus('Mięsień podgrzebieniowy'),
  teresMinor('Mięsień obły mniejszy'),
  teresMajor('Mięsień obły większy'),
  subscapularis('Mięsień podłopatkowy'),
  hipFlexors('Zginacze bioder'),
  quads('Czworogłowe uda'),
  sternocleidomastoid('Szyja'),
  tibialis('Piszczele'),
  traps('Kaptury'),
  lats('Najszerszy grzbietu'),
  lowerBack('Dolny grzbiet'),
  upperBack('Górne plecy'),
  rhomboids('Mięśnie równoległoboczne'),
  levatorScapulae('Dźwigacz łopatki'),
  sideWaistBack('Boczna talia'),
  glutes('Pośladki'),
  hamstrings('Dwugłowe uda'),
  gluteMedius('Pośladkowy średni'),
  tensorFasciaeLatae('Naprężacz powięzi szerokiej'),
  sartorius('Mięsień krawiecki'),
  gracilis('Mięsień smukły'),
  soleus('Mięsień płaszczkowaty'),
  gastrocnemius('Mięsień brzuchaty łydki'),
  erectorSpinae('Prostowniki grzbietu'),
  quadratusLumborum('Mięsień czworoboczny lędźwi'),
  serratusAnterior('Mięsień zębaty przedni'),
  transverseAbdominis('Mięsień poprzeczny brzucha'),
  triceps('Triceps');

  const BodyMuscle(this.label);

  /// Czytelna nazwa partii po polsku.
  final String label;

  /// Klucz do serializacji (nazwa enuma).
  String get key => name;

  static BodyMuscle? fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final muscle in BodyMuscle.values) {
      if (muscle.name == normalized) return muscle;
    }
    return null;
  }

  /// Najlepsze dopasowanie partii na podstawie dowolnego opisu (PL/EN).
  /// Tolerancyjne — używane do wyprowadzenia wpływu ze starych pól `muscles`.
  static BodyMuscle? fromText(String value) {
    final t = value.trim().toLowerCase();
    if (t.isEmpty) return null;
    bool has(List<String> keys) => keys.any(t.contains);
    if (has(['nadgrzeb', 'supraspinat'])) return BodyMuscle.supraspinatus;
    if (has(['podgrzeb', 'infraspinat'])) return BodyMuscle.infraspinatus;
    if (has(['obły mniejszy', 'obly mniejszy', 'teres minor']))
      return BodyMuscle.teresMinor;
    if (has(['obły większy', 'obly wiekszy', 'teres major']))
      return BodyMuscle.teresMajor;
    if (has(['podłopatk', 'podlopatk', 'subscapular']))
      return BodyMuscle.subscapularis;
    if (has(['równoległ', 'rownolegl', 'rhomboid']))
      return BodyMuscle.rhomboids;
    if (has(['dźwigacz łopat', 'dzwigacz lopat', 'levator scapula']))
      return BodyMuscle.levatorScapulae;
    if (has(['pośladkowy średni', 'posladkowy sredni', 'gluteus medius']))
      return BodyMuscle.gluteMedius;
    if (has(['naprężacz powięzi', 'naprezacz powiezi', 'tensor fascia']))
      return BodyMuscle.tensorFasciaeLatae;
    if (has(['krawieck', 'sartorius'])) return BodyMuscle.sartorius;
    if (has(['smukły', 'smukly', 'gracilis'])) return BodyMuscle.gracilis;
    if (has(['płaszczkow', 'plaszczkow', 'soleus'])) return BodyMuscle.soleus;
    if (has(['brzuchaty łyd', 'brzuchaty lyd', 'gastrocnem']))
      return BodyMuscle.gastrocnemius;
    if (has(['prostownik grzbiet', 'prostowniki grzbiet', 'erector spinae']))
      return BodyMuscle.erectorSpinae;
    if (has(
        ['czworoboczny lędźwi', 'czworoboczny ledzwi', 'quadratus lumborum']))
      return BodyMuscle.quadratusLumborum;
    if (has(['zębaty przedni', 'zebaty przedni', 'serratus anterior']))
      return BodyMuscle.serratusAnterior;
    if (has([
      'poprzeczny brzucha',
      'transverse abdominis',
      'transversus abdominis'
    ])) return BodyMuscle.transverseAbdominis;
    if (has(['klatk', 'chest', 'pierś', 'piers'])) return BodyMuscle.chest;
    // BARKI PRZED SKOŚNYMI. „barki boczne" (boczny akton naramiennego) zawiera
    // podciąg „boczn", więc bez tej kolejności unoszenie bokiem lądowało
    // w mięśniach skośnych brzucha — a przez to w limitach, statystykach
    // i regeneracji jako core zamiast barków. Ten sam rodzaj pułapki co łydki
    // przed brzuchem niżej.
    //
    // Cały bark rozstrzygamy TUTAJ (przód / tył), żeby nie było dwóch miejsc
    // decydujących o tej samej partii.
    if (has(['bark', 'naramien', 'shoulder', 'delt', 'aktony'])) {
      return has(['tył', 'tyl', 'rear']) ? BodyMuscle.rearShoulders
          : BodyMuscle.frontShoulders;
    }
    if (has(['skoś', 'skos', 'oblique', 'boczn'])) return BodyMuscle.obliques;
    if (has(['brzuch', 'core', 'abs', 'prosty brzuc', 'poprzeczn']))
      return BodyMuscle.abs;
    if (has(['przywodz', 'adduct'])) return BodyMuscle.adductors;
    if (has(['biceps', 'dwugłowe ramienia', 'dwuglowe ramienia']))
      return BodyMuscle.biceps;
    if (has(['triceps', 'trójgłowe', 'trojglowe'])) return BodyMuscle.triceps;
    if (has(['przedram', 'forearm'])) return BodyMuscle.forearmsFront;
    if (has(['łyd', 'lyd', 'calf', 'calves', 'brzuchaty łyd']))
      return BodyMuscle.calvesFront;
    if (has(['piszcz', 'tibialis'])) return BodyMuscle.tibialis;
    if (has(['kaptur', 'czworobocz', 'trap'])) return BodyMuscle.traps;
    if (has(['najszer', 'lat', 'grzbiet'])) return BodyMuscle.lats;
    if (has([
      'dolny grzbiet',
      'dolne plec',
      'prostownik',
      'lower back',
      'lędźw',
      'ledzw'
    ])) return BodyMuscle.lowerBack;
    if (has([
      'górne plec',
      'gorne plec',
      'upper back',
      'rhomb',
      'równoleg',
      'rownoleg'
    ])) return BodyMuscle.upperBack;
    if (has(['plec', 'back'])) return BodyMuscle.lats;
    // (Bark rozstrzygnięty wyżej — przed skośnymi brzucha.)
    if (has(['zginacz bioder', 'hip flexor', 'biodr']))
      return BodyMuscle.hipFlexors;
    if (has([
      'czworogł',
      'czworogl',
      'quad',
      'przód uda',
      'przod uda',
      'uda przod'
    ])) return BodyMuscle.quads;
    if (has(
        ['dwugł', 'dwugl', 'hamstring', 'tył uda', 'tyl uda', 'dwugłowe uda']))
      return BodyMuscle.hamstrings;
    if (has(['pośladk', 'posladk', 'glute', 'pupa'])) return BodyMuscle.glutes;
    if (has(['szyj', 'kark', 'neck', 'mostkowo']))
      return BodyMuscle.sternocleidomastoid;
    if (has(['uda', 'noga', 'nogi', 'leg'])) return BodyMuscle.quads;
    if (has(['talia', 'waist'])) return BodyMuscle.sideWaistBack;
    return null;
  }
}

/// Rola partii w ćwiczeniu i odpowiadająca jej waga obciążenia.
enum MuscleRole {
  primary('Główna', 1.0),
  secondary('Pomocnicza', 0.5),
  stabilizer('Stabilizacja', 0.25);

  const MuscleRole(this.label, this.weight);

  final String label;
  final double weight;

  static MuscleRole fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final role in MuscleRole.values) {
      if (role.name == normalized) return role;
    }
    return MuscleRole.primary;
  }
}

/// Wpływ pojedynczej partii mięśniowej w danym ćwiczeniu.
class ExerciseMuscleImpact {
  const ExerciseMuscleImpact({
    required this.muscleGroup,
    required this.role,
    double? impactWeight,
  }) : impactWeight = impactWeight ?? -1;

  final BodyMuscle muscleGroup;
  final MuscleRole role;

  /// Waga obciążenia. Gdy nieustawiona (-1), używana jest waga z [role].
  final double impactWeight;

  double get effectiveWeight => impactWeight >= 0 ? impactWeight : role.weight;

  ExerciseMuscleImpact copyWith({
    BodyMuscle? muscleGroup,
    MuscleRole? role,
    double? impactWeight,
  }) {
    return ExerciseMuscleImpact(
      muscleGroup: muscleGroup ?? this.muscleGroup,
      role: role ?? this.role,
      impactWeight: impactWeight ?? this.impactWeight,
    );
  }

  Map<String, dynamic> toJson() => {
        'muscleGroup': muscleGroup.key,
        'role': role.name,
        if (impactWeight >= 0) 'impactWeight': impactWeight,
      };

  static ExerciseMuscleImpact? fromJson(Map<String, dynamic> json) {
    final muscle = BodyMuscle.fromKey(json['muscleGroup']);
    if (muscle == null) return null;
    final role = MuscleRole.fromKey(json['role']);
    final weight = (json['impactWeight'] as num?)?.toDouble();
    return ExerciseMuscleImpact(
        muscleGroup: muscle, role: role, impactWeight: weight);
  }
}

// ===========================================================================
// Mapowanie partii → pliki masek (względem assets/trainer/body_model/<side>/masks/).
// Niektóre partie mają kilka masek, które mają kolorować się razem.
// Adductors występują zarówno z przodu, jak i z tyłu.
// ===========================================================================

const String kBodyModelRoot = 'assets/trainer/body_model';

const Map<BodyMuscle, List<String>> kFrontMuscleMasks = {
  BodyMuscle.chest: ['chest_mask.png'],
  BodyMuscle.abs: [
    'abs_upper_mask.png',
    'abs_upper_middle_mask.png',
    'abs_lower_middle_mask.png',
    'abs_lower_mask.png',
  ],
  BodyMuscle.obliques: [
    'obliques_upper_mask.png',
    'obliques_middle_mask.png',
    'obliques_lower_mask.png',
  ],
  BodyMuscle.adductors: ['adductors_mask.png'],
  BodyMuscle.biceps: ['biceps_mask.png'],
  BodyMuscle.calvesFront: ['calves_front_mask.png'],
  BodyMuscle.forearmsFront: [
    'forearms_front_inner_mask.png',
    'forearms_front_outer_mask.png',
  ],
  BodyMuscle.frontShoulders: ['front_shoulders_mask.png'],
  BodyMuscle.subscapularis: ['front_shoulders_mask.png'],
  BodyMuscle.serratusAnterior: ['obliques_upper_mask.png'],
  BodyMuscle.transverseAbdominis: [
    'abs_lower_middle_mask.png',
    'abs_lower_mask.png'
  ],
  BodyMuscle.hipFlexors: ['hip_flexors.png'],
  BodyMuscle.quads: ['quads_inner_mask.png', 'quads_outer_mask.png'],
  BodyMuscle.sartorius: ['quads_inner_mask.png'],
  BodyMuscle.gracilis: ['adductors_mask.png'],
  BodyMuscle.tensorFasciaeLatae: ['hip_flexors.png'],
  BodyMuscle.sternocleidomastoid: ['sternocleidomastoid_mask.png'],
  BodyMuscle.tibialis: ['tibialis_mask.png'],
};

const Map<BodyMuscle, List<String>> kBackMuscleMasks = {
  BodyMuscle.adductors: ['adductors_back_mask.png'],
  BodyMuscle.calvesBack: [
    'calves_back_inner_mask.png',
    'calves_back_outer_mask.png'
  ],
  BodyMuscle.soleus: [
    'calves_back_inner_mask.png',
    'calves_back_outer_mask.png'
  ],
  BodyMuscle.gastrocnemius: [
    'calves_back_inner_mask.png',
    'calves_back_outer_mask.png'
  ],
  BodyMuscle.forearmsBack: [
    'forearms_inner_back_mask.png',
    'forearms_outer_back_mask.png'
  ],
  BodyMuscle.glutes: ['glutes_mask.png'],
  BodyMuscle.gluteMedius: ['glutes_mask.png'],
  BodyMuscle.hamstrings: [
    'hamstrings_inner_mask.png',
    'hamstrings_outer_mask.png'
  ],
  BodyMuscle.lats: ['lats_mask.png'],
  BodyMuscle.lowerBack: ['lower_back_mask.png'],
  BodyMuscle.erectorSpinae: ['lower_back_mask.png'],
  BodyMuscle.quadratusLumborum: ['side_waist_back_mask.png'],
  BodyMuscle.rearShoulders: ['rear_shoulders_mask.png'],
  BodyMuscle.supraspinatus: ['upper_back_mask.png'],
  BodyMuscle.infraspinatus: ['upper_back_mask.png'],
  BodyMuscle.teresMinor: ['rear_shoulders_mask.png'],
  BodyMuscle.teresMajor: ['lats_mask.png'],
  BodyMuscle.sideWaistBack: ['side_waist_back_mask.png'],
  BodyMuscle.traps: ['traps_mask.png'],
  BodyMuscle.triceps: ['triceps_mask.png'],
  BodyMuscle.upperBack: ['upper_back_mask.png'],
  BodyMuscle.rhomboids: ['upper_back_mask.png'],
  BodyMuscle.levatorScapulae: ['traps_mask.png'],
};

/// Mapa masek dla danej strony modelu.
Map<BodyMuscle, List<String>> muscleMasksForSide(BodyMuscleSide side) =>
    side == BodyMuscleSide.front ? kFrontMuscleMasks : kBackMuscleMasks;

/// Pełna ścieżka assetu maski.
String bodyMaskAsset(BodyMuscleSide side, String fileName) {
  final folder = side == BodyMuscleSide.front ? 'front' : 'back';
  return '$kBodyModelRoot/$folder/masks/$fileName';
}

/// Bazowy model człowieka dla strony i trybu (dzień/noc).
String bodyBaseAsset(BodyMuscleSide side, {required bool dark}) {
  if (side == BodyMuscleSide.front) {
    return dark
        ? '$kBodyModelRoot/front/body_front_night.png'
        : '$kBodyModelRoot/front/body_front_day.png';
  }
  return dark
      ? '$kBodyModelRoot/back/body_back_night.png'
      : '$kBodyModelRoot/back/body_back_day.png';
}

/// Partie widoczne na danej stronie modelu.
List<BodyMuscle> musclesOnSide(BodyMuscleSide side) =>
    muscleMasksForSide(side).keys.toList();
