/// Profil sprzętowy użytkownika i ograniczenia treningowe (czysty Dart).
///
/// Etap: „Programy zgodne ze sprzętem". Model opisuje, jaki sprzęt użytkownik
/// posiada (tryb gotowy albo własny zestaw) oraz jakie ma ograniczenia
/// zdrowotne. Filtr programów (`equipment_program_filter.dart`) używa tego
/// modelu, żeby NIE proponować ćwiczeń wymagających niedostępnego sprzętu.
library;

import 'trainer_enums.dart';

/// Gotowy tryb sprzętowy — bazowy, jednoznaczny zestaw dostępnego sprzętu.
enum EquipmentMode {
  bodyweight(
    'Masa własnego ciała',
    'Tylko ćwiczenia bez sprzętu (mata dozwolona)',
  ),
  dumbbellBench(
    'Hantle + ławka',
    'Hantle, ławka i masa ciała',
  ),
  barbellDumbbellBench(
    'Sztanga + hantle + ławka',
    'Sztanga, hantle, ławka i masa ciała (rack/stojaki osobno)',
  ),
  homeMixed(
    'Domowy trening mieszany',
    'Zaznacz posiadany sprzęt domowy',
  ),
  fullGym(
    'Pełna siłownia',
    'Wolne ciężary, maszyny, wyciągi, drążki, stojaki, cardio',
  ),
  custom(
    'Własny zestaw',
    'Ręcznie zaznacz każdy posiadany element',
  );

  const EquipmentMode(this.label, this.description);

  final String label;
  final String description;

  String get key => name;

  static EquipmentMode? fromKey(String value) {
    final normalized = value.trim();
    for (final mode in EquipmentMode.values) {
      if (mode.name == normalized) return mode;
    }
    return null;
  }

  /// Czy tryb pozwala użytkownikowi ręcznie wybierać elementy sprzętu.
  bool get isUserSelectable =>
      this == EquipmentMode.homeMixed || this == EquipmentMode.custom;
}

/// Sprzęt zawsze „dostępny" — masa ciała i mata są darmowe/wszechobecne.
const Set<EquipmentType> kAlwaysAvailableEquipment = <EquipmentType>{
  EquipmentType.bodyweight,
  EquipmentType.mat,
};

/// Domyślny zestaw dla trybu „Domowy mieszany" (można edytować w UI).
const Set<EquipmentType> kDefaultHomeMixedEquipment = <EquipmentType>{
  EquipmentType.dumbbell,
  EquipmentType.resistanceBand,
  EquipmentType.kettlebell,
  EquipmentType.pullUpBar,
};

/// Profil sprzętowy: tryb + (dla trybów wybieralnych) własny zestaw.
class EquipmentProfile {
  const EquipmentProfile({
    this.mode = EquipmentMode.homeMixed,
    this.customOwned = const <EquipmentType>{},
  });

  final EquipmentMode mode;

  /// Zestaw zaznaczony ręcznie — używany tylko w trybach [EquipmentMode.homeMixed]
  /// i [EquipmentMode.custom]. Masa ciała i mata są dokładane automatycznie.
  final Set<EquipmentType> customOwned;

  /// Efektywny, pełny zestaw dostępnego sprzętu (z masą ciała i matą).
  Set<EquipmentType> resolveOwned() {
    switch (mode) {
      case EquipmentMode.bodyweight:
        return {...kAlwaysAvailableEquipment};
      case EquipmentMode.dumbbellBench:
        return {
          ...kAlwaysAvailableEquipment,
          EquipmentType.dumbbell,
          EquipmentType.bench,
        };
      case EquipmentMode.barbellDumbbellBench:
        // UWAGA: rack/stojaki NIE są tu automatyczne — to osobne wymaganie.
        return {
          ...kAlwaysAvailableEquipment,
          EquipmentType.dumbbell,
          EquipmentType.barbell,
          EquipmentType.bench,
        };
      case EquipmentMode.fullGym:
        return EquipmentType.values.toSet();
      case EquipmentMode.homeMixed:
      case EquipmentMode.custom:
        return {...kAlwaysAvailableEquipment, ...customOwned};
    }
  }

  EquipmentProfile copyWith({
    EquipmentMode? mode,
    Set<EquipmentType>? customOwned,
  }) {
    return EquipmentProfile(
      mode: mode ?? this.mode,
      customOwned: customOwned ?? this.customOwned,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.key,
        'owned': customOwned.map((e) => e.key).toList(),
      };

  factory EquipmentProfile.fromJson(Map<String, dynamic> json) {
    final mode = EquipmentMode.fromKey(json['mode']?.toString() ?? '') ??
        EquipmentMode.homeMixed;
    final owned = <EquipmentType>{};
    final rawOwned = json['owned'];
    if (rawOwned is List) {
      for (final item in rawOwned) {
        final type = EquipmentType.fromKey(item.toString());
        if (type != null) owned.add(type);
      }
    }
    return EquipmentProfile(mode: mode, customOwned: owned);
  }

  /// Buduje profil z zapisanych ustawień strukturalnych albo — gdy ich brak —
  /// migruje ze starego pola tekstowego `equipment` (zgodność wsteczna).
  ///
  /// [modeKey] / [ownedKeys] pochodzą z nowych pól ustawień. Gdy oba są puste,
  /// czytamy [legacyText] (np. „masa ciała, hantle, drążek, mata" albo
  /// „siłownia"), żeby istniejący użytkownicy NIE stracili konfiguracji.
  factory EquipmentProfile.resolve({
    String modeKey = '',
    List<String> ownedKeys = const <String>[],
    String legacyText = '',
  }) {
    final mode = EquipmentMode.fromKey(modeKey);
    if (mode != null) {
      final owned = <EquipmentType>{};
      for (final key in ownedKeys) {
        final type = EquipmentType.fromKey(key);
        if (type != null) owned.add(type);
      }
      return EquipmentProfile(mode: mode, customOwned: owned);
    }
    return EquipmentProfile.fromLegacyText(legacyText);
  }

  /// Migracja ze starego, wolnego tekstu sprzętu na profil strukturalny.
  factory EquipmentProfile.fromLegacyText(String legacyText) {
    final normalized = legacyText.trim().toLowerCase();
    if (normalized.isEmpty) {
      // Brak danych: konserwatywnie tylko masa ciała (nic nie „wymyślamy").
      return const EquipmentProfile(mode: EquipmentMode.bodyweight);
    }
    if (normalized.contains('siłown') ||
        normalized.contains('silown') ||
        normalized.contains('gym') ||
        normalized.contains('full gym')) {
      return const EquipmentProfile(mode: EquipmentMode.fullGym);
    }
    final parsed = EquipmentType.fromText(legacyText)
        .where((t) => t != EquipmentType.other)
        .toSet();
    final owned =
        parsed.where((t) => !kAlwaysAvailableEquipment.contains(t)).toSet();
    if (owned.isEmpty) {
      return const EquipmentProfile(mode: EquipmentMode.bodyweight);
    }
    return EquipmentProfile(mode: EquipmentMode.custom, customOwned: owned);
  }

  /// Krótki, czytelny opis dostępnego sprzętu (do informacji „dopasowano do…").
  String get ownedSummary {
    final owned = resolveOwned()
        .where((t) => !kAlwaysAvailableEquipment.contains(t))
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (owned.isEmpty) return 'masa własnego ciała';
    return owned.map((t) => t.label.toLowerCase()).join(', ');
  }

  @override
  bool operator ==(Object other) =>
      other is EquipmentProfile &&
      other.mode == mode &&
      _setEquals(other.customOwned, customOwned);

  @override
  int get hashCode => Object.hash(
        mode,
        Object.hashAllUnordered(customOwned),
      );
}

bool _setEquals(Set<EquipmentType> a, Set<EquipmentType> b) =>
    a.length == b.length && a.containsAll(b);

/// Ograniczenie treningowe (kontuzja / preferencja) wpływające na dobór ćwiczeń.
enum TrainingLimitation {
  noJumps('Bez podskoków'),
  noRunning('Bez biegania'),
  knees('Ochrona kolan'),
  lowerBack('Ochrona dolnego odcinka pleców'),
  overhead('Bez ćwiczeń nad głową'),
  noLying('Bez ćwiczeń w leżeniu');

  const TrainingLimitation(this.label);

  final String label;

  String get key => name;

  static TrainingLimitation? fromKey(String value) {
    final normalized = value.trim();
    for (final limit in TrainingLimitation.values) {
      if (limit.name == normalized) return limit;
    }
    return null;
  }

  /// Wykrywa ograniczenia zapisane w wolnym tekście (zgodność wsteczna).
  static Set<TrainingLimitation> fromText(String text) {
    final l = text.toLowerCase();
    final result = <TrainingLimitation>{};
    if (l.contains('podskok') ||
        l.contains('skok') ||
        l.contains('wybicie') ||
        l.contains('jump') ||
        l.contains('plyo')) {
      result.add(TrainingLimitation.noJumps);
    }
    if (l.contains('bieg') || l.contains('run') || l.contains('jogging')) {
      result.add(TrainingLimitation.noRunning);
    }
    if (l.contains('kolan') || l.contains('knee')) {
      result.add(TrainingLimitation.knees);
    }
    if (l.contains('plec') ||
        l.contains('lędź') ||
        l.contains('ledz') ||
        l.contains('lędźw') ||
        l.contains('kręgosłup') ||
        l.contains('kregoslup') ||
        l.contains('back')) {
      result.add(TrainingLimitation.lowerBack);
    }
    if (l.contains('nad głow') ||
        l.contains('nad glow') ||
        l.contains('overhead') ||
        l.contains('bark')) {
      result.add(TrainingLimitation.overhead);
    }
    if (l.contains('leż') || l.contains('lez') || l.contains('lying')) {
      result.add(TrainingLimitation.noLying);
    }
    return result;
  }
}

/// Zestaw ograniczeń: flagi strukturalne + własny tekst użytkownika.
class LimitationProfile {
  const LimitationProfile({
    this.flags = const <TrainingLimitation>{},
    this.customText = '',
  });

  final Set<TrainingLimitation> flags;
  final String customText;

  bool get isEmpty => flags.isEmpty && customText.trim().isEmpty;

  /// Buduje profil z zapisanych flag albo — gdy ich brak — z wolnego tekstu.
  factory LimitationProfile.resolve({
    List<String> flagKeys = const <String>[],
    String legacyText = '',
  }) {
    final flags = <TrainingLimitation>{};
    for (final key in flagKeys) {
      final flag = TrainingLimitation.fromKey(key);
      if (flag != null) flags.add(flag);
    }
    if (flags.isEmpty && legacyText.trim().isNotEmpty) {
      flags.addAll(TrainingLimitation.fromText(legacyText));
    }
    return LimitationProfile(flags: flags, customText: legacyText.trim());
  }
}
