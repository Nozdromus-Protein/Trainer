/// Wyciąganie kart ćwiczeń ze ZWYKŁEGO TEKSTU odpowiedzi AI (czysty Dart).
///
/// Etap: „Karty ćwiczeń w rozmowie z Trenerem AI" — ścieżka awaryjna.
///
/// Docelowo backend zwraca dane strukturalne (`exerciseSuggestions`). Dopóki
/// tego nie robi — albo gdy model zignoruje format — nadal chcemy pokazać
/// interaktywne karty. Ten moduł czyta tekst odpowiedzi i wyciąga z niego
/// ćwiczenia na dwa sposoby:
///
///  1. **Pozycje wyliczenia** („- Wyciskanie sztangi — 4×8", „**Pompki**").
///     Nazwę dopasowujemy do bazy elastycznie (pełna fraza, zawieranie,
///     wspólne słowa znaczące, synonimy PL↔EN). Gdy nic nie pasuje, karta
///     i tak powstaje — jako ćwiczenie NOWE, które użytkownik może dodać
///     do bazy. Bez tego propozycje spoza bazy przepadały bez śladu.
///  2. **Skan całego tekstu** po nazwach z bazy — dla odpowiedzi bez listy.
///
/// Zasada nadrzędna: lepiej nie pokazać karty niż pokazać śmieć. Dlatego
/// pozycja wyliczenia musi wyglądać jak nazwa ćwiczenia (krótka, bez pytajnika,
/// bez czasownika instruktażowego na starcie), a skan całego tekstu wymaga
/// wyliczenia albo co najmniej dwóch różnych ćwiczeń.
library;

import '../domain/ai_structured_reply.dart';
import '../domain/exercise.dart';
import 'exercise_search.dart';

/// Maksymalna liczba kart wyciągniętych z jednej odpowiedzi.
const int kMaxExtractedExerciseCards = 8;

/// Znalezione w tekście ćwiczenie.
class ExtractedExerciseMention {
  const ExtractedExerciseMention({
    required this.name,
    required this.fromListItem,
    this.exercise,
    this.contextLine = '',
  });

  /// Nazwa tak, jak zapisała ją AI (albo nazwa z bazy przy dopasowaniu).
  final String name;

  /// Czy nazwa stała w pozycji wyliczenia (punkt listy / pogrubienie).
  final bool fromListItem;

  /// Dopasowane ćwiczenie z bazy. `null` = propozycja spoza bazy.
  final Exercise? exercise;

  /// Linia, w której znaleziono nazwę.
  final String contextLine;

  bool get isInDatabase => exercise != null;
}

/// Szuka w [text] ćwiczeń — z bazy [library_] oraz nowych, spoza niej.
///
/// [assumeExerciseContext] ustawiaj na `true`, gdy pytanie użytkownika wprost
/// dotyczyło ćwiczeń — wtedy próg pewności jest niższy, bo wiadomo, po co
/// przyszła odpowiedź.
List<ExtractedExerciseMention> findExerciseMentions(
  String text, {
  required List<Exercise> library_,
  bool assumeExerciseContext = false,
  int limit = kMaxExtractedExerciseCards,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const <ExtractedExerciseMention>[];

  // Indeks nazw z bazy: najdłuższe najpierw, żeby „Przysiad bułgarski" wygrał
  // z „Przysiad" i nie produkował dwóch kart dla jednego wystąpienia.
  final entries = <({String needle, List<String> tokens, Exercise exercise})>[];
  for (final exercise in library_) {
    final normalized = _normalize(exercise.name);
    if (normalized.length < 4) continue;
    entries.add((
      needle: normalized,
      tokens: _significantTokens(normalized),
      exercise: exercise,
    ));
  }
  entries.sort((a, b) => b.needle.length.compareTo(a.needle.length));

  final lines = trimmed.split(RegExp(r'[\r\n]+'));
  final found = <String, ExtractedExerciseMention>{};
  final consumedLines = <String>{};
  var listItemCount = 0;

  // --- 1. Pozycje wyliczenia ---
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || !_looksLikeListItem(line)) continue;
    listItemCount++;
    if (found.length >= limit) continue;

    final candidate = _exerciseNameFromListItem(line);
    if (candidate.isEmpty) continue;

    final match = matchExerciseByName(candidate, entries);
    final key = match?.id ?? _normalize(candidate);
    if (key.isEmpty || found.containsKey(key)) continue;
    found[key] = ExtractedExerciseMention(
      name: match?.name ?? candidate,
      fromListItem: true,
      exercise: match,
      contextLine: line,
    );
    consumedLines.add(line);
  }

  // --- 2. Skan całego tekstu po nazwach z bazy ---
  // Linie, które już dały kartę z wyliczenia, pomijamy — inaczej „Pompki na
  // poręczach (dipy)" produkowałoby dwie karty z jednego punktu listy.
  if (found.length < limit) {
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || consumedLines.contains(line)) continue;
      final normalizedLine = _normalize(line);
      if (normalizedLine.isEmpty) continue;
      // Maska zajętych fragmentów — bez niej „Przysiad bułgarski" dawałby
      // dodatkowo kartę „Przysiad" z tego samego kawałka tekstu.
      final consumed = List<bool>.filled(normalizedLine.length, false);

      for (final entry in entries) {
        if (found.length >= limit) break;
        final at = _indexOfWholePhrase(normalizedLine, entry.needle, consumed);
        if (at < 0) continue;
        for (var i = at; i < at + entry.needle.length; i++) {
          consumed[i] = true;
        }
        if (found.containsKey(entry.exercise.id)) continue;
        found[entry.exercise.id] = ExtractedExerciseMention(
          name: entry.exercise.name,
          fromListItem: _looksLikeListItem(line),
          exercise: entry.exercise,
          contextLine: line,
        );
      }
      if (found.length >= limit) break;
    }
  }

  if (found.isEmpty) return const <ExtractedExerciseMention>[];

  // Próg pewności. Wyliczenie albo jawne pytanie o ćwiczenia wystarczą;
  // w innym razie potrzebne są co najmniej dwa różne ćwiczenia, żeby luźna
  // wzmianka („dziś odpuść przysiady") nie zamieniała się w kartę.
  final hasList = listItemCount > 0 || found.values.any((m) => m.fromListItem);
  if (!hasList && !assumeExerciseContext && found.length < 2) {
    return const <ExtractedExerciseMention>[];
  }

  return found.values.toList();
}

/// Dopasowuje nazwę do ćwiczenia z bazy. `null` = brak pewnego dopasowania.
///
/// Reguły są CELOWO zachowawcze: złe dopasowanie („wyciskanie sztangi" →
/// „wyciskanie hantli") jest gorsze niż jego brak. Nierozpoznana nazwa nie
/// przepada — trafia na kartę jako ćwiczenie NOWE, a przy dodawaniu do bazy
/// i tak przechodzi przez wykrywanie duplikatów.
Exercise? matchExerciseByName(
  String name,
  List<({String needle, List<String> tokens, Exercise exercise})> entries,
) {
  final normalized = _normalize(name);
  if (normalized.isEmpty) return null;
  final tokens = _significantTokens(normalized);

  // 1. Dokładnie ta sama nazwa.
  for (final entry in entries) {
    if (entry.needle == normalized) return entry.exercise;
  }

  // 2. WSZYSTKIE słowa znaczące krótszej nazwy występują w dłuższej.
  //    „Rozpiętki z hantlami" ⊂ „Rozpiętki z hantlami na ławce skośnej" → tak.
  //    „Wyciskanie leżąc" vs „Wyciskanie sztangi na ławce" → nie (brak „leżąc").
  //    Nazwy jednosłowowe wymagają trafienia dokładnego (punkt 1), bo samo
  //    „wyciskanie" pasowałoby do połowy bazy.
  Exercise? best;
  var bestScore = 0;
  for (final entry in entries) {
    final other = entry.tokens;
    final shorter = tokens.length <= other.length ? tokens : other;
    final longer = tokens.length <= other.length ? other : tokens;
    if (shorter.length < 2) continue;
    if (!shorter.every(longer.contains)) continue;
    // Im więcej wspólnych słów i im mniejsza różnica długości, tym lepiej.
    final score = shorter.length * 100 - (longer.length - shorter.length);
    if (score > bestScore) {
      bestScore = score;
      best = entry.exercise;
    }
  }
  if (best != null) return best;

  // 3. Synonimy PL↔EN — tylko przy DOKŁADNYCH hasłach ze słownika po obu
  //    stronach. Dopasowanie po fragmencie („wyciskanie") dawało trafienia
  //    w przypadkowe ćwiczenia.
  final direct = kPlEnExerciseSynonyms[normalized];
  if (direct != null) {
    for (final entry in entries) {
      final candidate = kPlEnExerciseSynonyms[entry.needle];
      if (candidate == null) continue;
      if (direct.toSet().intersection(candidate.toSet()).isNotEmpty) {
        return entry.exercise;
      }
    }
  }
  return null;
}

/// Buduje karty ćwiczeń z tekstu odpowiedzi AI.
///
/// [recoveryVerdict] pozwala dołożyć ocenę zgodności z dzisiejszą regeneracją
/// (warstwa aplikacji zna mapę regeneracji; ten moduł zostaje czystym Dartem).
List<AiExerciseSuggestion> extractExerciseSuggestionsFromText(
  String text, {
  required List<Exercise> library_,
  ({String label, AiRecoveryCompatibility compatibility}) Function(Exercise)?
      recoveryVerdict,
  bool assumeExerciseContext = false,
  int limit = kMaxExtractedExerciseCards,
}) {
  final mentions = findExerciseMentions(
    text,
    library_: library_,
    assumeExerciseContext: assumeExerciseContext,
    limit: limit,
  );
  final suggestions = <AiExerciseSuggestion>[];
  for (final mention in mentions) {
    final exercise = mention.exercise;
    if (exercise == null) {
      // Ćwiczenie spoza bazy — karta i tak powstaje, żeby dało się je dodać.
      // Pola, których nie znamy, zostają puste (karta ich nie pokazuje).
      suggestions.add(AiExerciseSuggestion(
        name: mention.name,
        reasonRecommended: 'Trener AI zaproponował to ćwiczenie.',
        alreadyInDatabase: false,
      ));
      continue;
    }
    final verdict = recoveryVerdict?.call(exercise);
    suggestions.add(AiExerciseSuggestion(
      name: exercise.name,
      exerciseId: exercise.id,
      description: exercise.description,
      primaryMuscles: exercise.muscles.take(1).toList(),
      secondaryMuscles: exercise.supportingMuscles,
      equipment: exercise.equipment,
      difficulty: exercise.level,
      entryType: exercise.entryType.label,
      reasonRecommended: 'Trener AI wymienił to ćwiczenie w odpowiedzi.',
      recoveryCompatibility:
          verdict?.compatibility ?? AiRecoveryCompatibility.unknown,
      recoveryNote: verdict?.label ?? '',
      alreadyInDatabase: true,
      suggestedSets: exercise.defaultSets,
      suggestedReps: exercise.defaultReps,
      suggestedDurationSec: exercise.defaultDurationSec,
    ));
  }
  return suggestions;
}

/// Czy pytanie użytkownika wprost dotyczy doboru ćwiczeń.
bool questionAsksForExercises(String question) {
  final q = _normalize(question);
  if (q.isEmpty) return false;
  const asks = [
    'jakie cwiczenia',
    'jakie cwiczenie',
    'cwiczenia na',
    'cwiczenie na',
    'co moge zrobic',
    'co mozna zrobic',
    'zaproponuj cwicz',
    'pokaz cwicz',
    'daj cwicz',
    'co trenowac',
    'co dzis trenowac',
    'czym zastapic',
    'zamiennik',
    'alternatywa dla',
    'co zamiast',
  ];
  return asks.any(q.contains);
}

/// Rozpoznaje w pytaniu prośbę o ANALIZĘ zestawu („Przeanalizuj mój zestaw
/// Push", „Co poprawiłbyś w tym zestawie?", „Dopasuj go do mojego sprzętu").
///
/// Zwraca nazwę zestawu wskazanego przez użytkownika (dopasowaną do [planNames])
/// albo pusty tekst, gdy prośby nie ma. Samo rozpoznanie NICZEGO nie uruchamia —
/// czat pokazuje tylko przycisk otwierający pełną analizę.
///
/// [fallbackName] (np. aktywny zestaw) jest używany, gdy użytkownik nie nazwał
/// zestawu wprost („co poprawiłbyś w tym zestawie?").
String detectPlanAnalysisRequest(
  String question, {
  required List<String> planNames,
  String fallbackName = '',
}) {
  final q = _normalize(question);
  if (q.isEmpty) return '';

  const analysisVerbs = [
    'przeanalizuj',
    'zanalizuj',
    'analiza',
    'ocen',
    'co poprawi',
    'co bys poprawi',
    'popraw',
    'dopasuj',
    'usun z niego',
    'usun zbedne',
    'dodaj brakujace',
    'czy ten zestaw',
    'czy moj zestaw',
    'wystarczajaca objetosc',
  ];
  const planWords = ['zestaw', 'plan', 'program', 'trening'];

  final hasVerb = analysisVerbs.any(q.contains);
  if (!hasVerb) return '';
  final hasPlanWord =
      planWords.any(q.contains) || q.contains(' go ') || q.endsWith(' go');
  if (!hasPlanWord) return '';

  // Nazwa wprost w pytaniu ma pierwszeństwo (najdłuższa pasująca).
  final byLength = [...planNames]..sort((a, b) => b.length.compareTo(a.length));
  for (final name in byLength) {
    final normalized = _normalize(name);
    if (normalized.length < 3) continue;
    if (q.contains(normalized)) return name;
  }
  return fallbackName;
}

// ============================================================================
// Pomocnicze
// ============================================================================

/// Normalizacja pod dopasowanie: bez diakrytyków, bez interpunkcji i markdownu,
/// pojedyncze spacje.
String _normalize(String value) {
  final base = normalizeSearchText(value);
  final buffer = StringBuffer();
  for (final rune in base.runes) {
    final char = String.fromCharCode(rune);
    final code = char.codeUnitAt(0);
    final isWord =
        (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
    buffer.write(isWord ? char : ' ');
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Słowa niosące znaczenie (bez przyimków i krótkich wtrętów).
const Set<String> _kStopWords = {
  'na', 'w', 'z', 've', 'ze', 'do', 'od', 'po', 'przy', 'i', 'oraz', 'lub',
  'the', 'and', 'for', 'with', 'sie', 'sobie', 'przez',
};

List<String> _significantTokens(String normalized) {
  return normalized
      .split(' ')
      .where((token) => token.length >= 3 && !_kStopWords.contains(token))
      .toList();
}

/// Czy linia wygląda na punkt wyliczenia albo pogrubioną nazwę.
bool _looksLikeListItem(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('- ') ||
      trimmed.startsWith('* ') ||
      trimmed.startsWith('• ') ||
      trimmed.startsWith('– ') ||
      trimmed.startsWith('—')) {
    return true;
  }
  if (RegExp(r'^\d+[\.\)]\s').hasMatch(trimmed)) return true;
  // Markdown: „**Wyciskanie hantli** — 3×10".
  if (trimmed.startsWith('**')) return true;
  return false;
}

/// Czasowniki instruktażowe — linia zaczynająca się od nich to porada,
/// nie nazwa ćwiczenia.
const Set<String> _kInstructionStarters = {
  'pij', 'zjedz', 'spij', 'pamietaj', 'odpocznij', 'skonsultuj', 'unikaj',
  'zwieksz', 'zmniejsz', 'utrzymuj', 'rozciagnij', 'rozgrzej', 'skup',
  'zadbaj', 'kontroluj', 'oddychaj', 'nie', 'jesli', 'jezeli', 'uwaga',
  'wazne', 'trenuj', 'zacznij', 'zakoncz', 'sprawdz', 'obserwuj', 'daj',
};

/// Wyciąga nazwę ćwiczenia z pozycji wyliczenia.
///
/// „- **Wyciskanie hantli** — 3 serie po 10" → „Wyciskanie hantli".
/// Zwraca pusty tekst, gdy linia nie wygląda na nazwę ćwiczenia.
String _exerciseNameFromListItem(String line) {
  var text = line.trimLeft();
  // Znacznik wyliczenia.
  text = text.replaceFirst(RegExp(r'^([-*•–—]+|\d+[\.\)])\s*'), '');
  // Pogrubienie: gdy jest, nazwą jest DOKŁADNIE jego zawartość.
  final bold = RegExp(r'^\*\*(.+?)\*\*').firstMatch(text);
  if (bold != null) {
    text = bold.group(1) ?? '';
  } else {
    // Inaczej nazwa kończy się na pierwszym separatorze opisu.
    final cut = text.split(RegExp(r'\s[–—-]\s|[:(]|,\s'));
    text = cut.isEmpty ? text : cut.first;
  }
  text = text.replaceAll('*', '').replaceAll('_', '').trim();
  text = text.replaceFirst(RegExp(r'[\.;:,]+$'), '').trim();

  if (!_looksLikeExerciseName(text)) return '';
  return text;
}

/// Filtr zdroworozsądkowy: czy to może być nazwa ćwiczenia.
bool _looksLikeExerciseName(String name) {
  final trimmed = name.trim();
  if (trimmed.length < 3 || trimmed.length > 48) return false;
  if (trimmed.contains('?')) return false;
  final normalized = _normalize(trimmed);
  if (normalized.isEmpty) return false;
  final words = normalized.split(' ');
  if (words.length > 6) return false;
  if (_kInstructionStarters.contains(words.first)) return false;
  // Sama liczba albo jednostki („3 serie", „45 s") to nie nazwa.
  if (RegExp(r'^\d').hasMatch(normalized)) return false;
  return true;
}

/// Indeks [needle] w [haystack] jako pełnych słów, pomijając fragmenty już
/// zajęte przez dłuższą nazwę. −1 = brak dopasowania.
int _indexOfWholePhrase(String haystack, String needle, List<bool> consumed) {
  var from = 0;
  while (from <= haystack.length - needle.length) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) return -1;
    final endsAt = at + needle.length;
    final startOk = at == 0 || haystack[at - 1] == ' ';
    final endOk = endsAt == haystack.length || haystack[endsAt] == ' ';
    var free = true;
    for (var i = at; i < endsAt; i++) {
      if (consumed[i]) {
        free = false;
        break;
      }
    }
    if (startOk && endOk && free) return at;
    from = at + 1;
  }
  return -1;
}
