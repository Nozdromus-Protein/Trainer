/// Tryby prowadzenia treningu i wynik wykonania serii (czysty Dart).
///
/// Etap: „Trainer jako inteligentny trener". Zamiast ręcznego wpisywania
/// ciężaru/powtórzeń/RPE użytkownik potwierdza wykonanie jednym z prostych
/// wyników ([SetOutcome]), a aplikacja sama dobiera i szacuje resztę.
library;

/// Tryb prowadzenia treningu.
enum GuidanceMode {
  /// Trainer ustala ciężar, serie, powtórzenia i przerwy — użytkownik potwierdza.
  full('full', 'Pełne prowadzenie',
      'Trainer ustala ciężar, serie, powtórzenia i przerwy. Ty potwierdzasz wykonanie.'),

  /// Trainer proponuje parametry, ale użytkownik może je zmienić.
  assisted('assisted', 'Prowadzenie z korektą',
      'Trainer proponuje parametry, a Ty możesz je zmienić przed serią.'),

  /// Użytkownik ustala wszystko sam (Trainer nadal analizuje i ostrzega).
  manual('manual', 'Tryb ręczny',
      'Sam ustalasz wszystko. Trainer i tak zapisuje, analizuje regenerację i ostrzega przed przeciążeniem.');

  const GuidanceMode(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static GuidanceMode fromKey(String value) {
    final normalized = value.trim();
    for (final mode in GuidanceMode.values) {
      if (mode.key == normalized || mode.name == normalized) return mode;
    }
    return GuidanceMode.full; // domyślnie pełne prowadzenie
  }
}

/// Wynik wykonania serii wybierany przez użytkownika (minimum danych).
enum SetOutcome {
  /// Wykonane zgodnie z planem — zapisujemy zaplanowane parametry.
  asPlanned('as_planned', 'Wykonane zgodnie z planem'),

  /// Nie ukończono zaplanowanej liczby powtórzeń/czasu.
  notCompleted('not_completed', 'Nie ukończyłem serii'),

  /// Seria przerwana (nie liczona jak pełne wykonanie).
  interrupted('interrupted', 'Przerwałem serię'),

  /// Zrobione inaczej — wtedy pokazujemy panel ręcznej korekty.
  didDifferently('did_differently', 'Zrobiłem inaczej');

  const SetOutcome(this.key, this.label);

  final String key;
  final String label;

  static SetOutcome? fromKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    for (final outcome in SetOutcome.values) {
      if (outcome.key == normalized || outcome.name == normalized) {
        return outcome;
      }
    }
    return null;
  }

  /// Czy wynik oznacza pełne, poprawne wykonanie serii.
  bool get isFullCompletion => this == SetOutcome.asPlanned;

  /// Czy seria ma być oznaczona jako nieudana/niepełna (nie liczy się jak pełna).
  bool get marksAsFailure =>
      this == SetOutcome.notCompleted || this == SetOutcome.interrupted;
}
