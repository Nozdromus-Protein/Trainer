// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`). Ten sam zakres
// biblioteki — prywatne pola i importy z main.dart są dostępne bez zmian.
//
// Zawiera CENTRALNĄ KONFIGURACJĘ GĘSTOŚCI INTERFEJSU: jedną skalę, przez którą
// przechodzą odstępy, paddingi i rozmiary w całej aplikacji, oraz odstęp [Gap]
// używany między sekcjami stron.
part of '../../../main.dart';

// ── GĘSTOŚĆ INTERFEJSU — jedna konfiguracja dla całej aplikacji ─────────────
//
// PROBLEM, KTÓRY TO ROZWIĄZUJE: ustawienie „Gęstość UI" sterowało tylko
// [VisualDensity] i paddingiem przycisków, więc kafelki, odstępy sekcji
// i nagłówki zostawały tej samej wysokości niezależnie od wyboru. Tryb
// kompaktowy nic realnie nie zmniejszał.
//
// Teraz jedna skala ([uiDensityScale]) przechodzi przez wszystkie odstępy
// ([uiGap]), paddingi ([uiInsets]) i rozmiary kafelków ([uiSize]). NIE dotyczy
// obszarów dotykowych — te mają własną podłogę ([uiTouchSize]), żeby tryb
// kompaktowy nie zrobił z przycisków celów nie do trafienia.

/// Klucz gęstości ('compact' | 'normal' | 'large') z ustawień użytkownika.
String uiDensityOf(BuildContext context) {
  final scope = context
      .getElementForInheritedWidgetOfExactType<AppScope>()
      ?.widget as AppScope?;
  final value = scope?.notifier?.settings.uiDensity ?? 'normal';
  return normalizeUiDensity(value);
}

/// Normalizuje zapisany klucz gęstości (obce/stare wartości → 'normal').
String normalizeUiDensity(String value) {
  switch (value.trim().toLowerCase()) {
    case 'compact':
      return 'compact';
    case 'large':
      return 'large';
    default:
      return 'normal';
  }
}

/// Mnożnik odstępów dla klucza gęstości.
double uiDensityScaleFor(String density) {
  switch (normalizeUiDensity(density)) {
    case 'compact':
      return 0.68;
    case 'large':
      return 1.22;
    default:
      return 1.0;
  }
}

/// Mnożnik odstępów wynikający z aktualnych ustawień.
double uiDensityScale(BuildContext context) =>
    uiDensityScaleFor(uiDensityOf(context));

/// Odstęp (SizedBox / margines) przeskalowany gęstością. Zaokrąglany do
/// pełnych pikseli, żeby wiersze nie „drgały" po zmianie ustawienia.
double uiGap(BuildContext context, double base) {
  if (base <= 0) return base;
  final scaled = base * uiDensityScale(context);
  // Odstęp nigdy nie znika całkowicie — bez tego elementy skleiłyby się w blok.
  return scaled < 2 ? 2 : scaled.roundToDouble();
}

/// Padding karty/kafelka przeskalowany gęstością (z podłogą czytelności).
EdgeInsets uiInsets(BuildContext context, EdgeInsets base) {
  final scale = uiDensityScale(context);
  double axis(double value) {
    if (value <= 0) return value;
    final scaled = value * scale;
    return scaled < 6 ? 6 : scaled.roundToDouble();
  }

  return EdgeInsets.fromLTRB(
    axis(base.left),
    axis(base.top),
    axis(base.right),
    axis(base.bottom),
  );
}

/// Padding zawartości ARKUSZA / MODALA uwzględniający systemowy pasek
/// nawigacji i klawiaturę (spec: punkt 18).
///
/// PROBLEM, KTÓRY TO ROZWIĄZUJE: `showModalBottomSheet(useSafeArea: true)`
/// zabezpiecza tylko GÓRĘ (Flutter owija arkusz w `SafeArea(bottom: false)`),
/// więc dolny pasek nawigacji / obszar gestów potrafił nachodzić na ostatni
/// wiersz albo przyciski arkusza. Sztywny `padding: 30` tego nie rozwiązuje —
/// wysokość paska zależy od urządzenia i trybu nawigacji.
///
/// Ta funkcja dokłada do dolnego paddingu REALNY inset systemowy oraz wysokość
/// klawiatury, jeśli jest podniesiona.
EdgeInsets sheetContentInsets(BuildContext context, EdgeInsets base) {
  final media = MediaQuery.of(context);
  // `viewPadding` niesie obszar systemowy także wtedy, gdy klawiatura go
  // chwilowo przykrywa (`padding` zeruje się w takiej sytuacji).
  final systemBottom = media.viewPadding.bottom;
  final keyboard = media.viewInsets.bottom;
  final scaled = uiInsets(context, base);
  return scaled.copyWith(bottom: scaled.bottom + systemBottom + keyboard);
}

/// Dolny odstęp równy systemowemu paskowi nawigacji (do list i stopek).
double systemBottomInset(BuildContext context) =>
    MediaQuery.of(context).viewPadding.bottom;

/// Rozmiar elementu dekoracyjnego (ikona, awatar, pasek) wg gęstości.
/// [min] chroni przed zniknięciem elementu w trybie kompaktowym.
double uiSize(BuildContext context, double base, {double min = 12}) {
  final scaled = base * uiDensityScale(context);
  return scaled < min ? min : scaled.roundToDouble();
}

/// Rozmiar elementu DOTYKOWEGO. Skaluje się jak reszta, ale nigdy nie schodzi
/// poniżej bezpiecznych 44 px — tryb kompaktowy zmniejsza wygląd, nie celność.
double uiTouchSize(BuildContext context, double base) {
  final scaled = base * uiDensityScale(context);
  return scaled < 44 ? 44 : scaled.roundToDouble();
}

/// Pionowy odstęp między sekcjami strony, skalowany gęstością interfejsu.
///
/// Zamiennik `SizedBox(height: N)` tam, gdzie odstęp NIESIE UKŁAD strony
/// (przerwy między kartami i sekcjami). Świadomie nie zamieniamy nim odstępów
/// wewnątrz kart i wierszy — tam kilka pikseli to część kompozycji elementu,
/// a nie oddech między blokami treści.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: uiGap(context, size));
}