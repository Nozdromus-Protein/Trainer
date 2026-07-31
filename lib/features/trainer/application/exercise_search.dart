/// Wyszukiwanie ćwiczeń: normalizacja tekstu, synonimy PL↔EN i dopasowanie
/// lokalnej bazy (Etap: naprawa importu Wger + fallback lokalny).
///
/// Czysty Dart — używane przez wyszukiwarkę Wger (tłumaczenie polskich fraz
/// na angielskie zapytania) oraz jako lokalny fallback, gdy zewnętrzna baza
/// nie zwraca sensownych wyników.
library;

import '../domain/exercise.dart';

/// Usuwa polskie znaki diakrytyczne i sprowadza tekst do lowercase.
String normalizeSearchText(String value) {
  const diacritics = {
    'ą': 'a',
    'ć': 'c',
    'ę': 'e',
    'ł': 'l',
    'ń': 'n',
    'ó': 'o',
    'ś': 's',
    'ź': 'z',
    'ż': 'z',
  };
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(diacritics[char] ?? char);
  }
  return buffer.toString().trim();
}

/// Synonimy PL → EN dla popularnych ćwiczeń (klucze znormalizowane —
/// bez diakrytyków, lowercase). Wartości to angielskie frazy wysyłane do Wger.
const Map<String, List<String>> kPlEnExerciseSynonyms = {
  'pompki': ['push up', 'push-up'],
  'pompka': ['push up', 'push-up'],
  'pompki diamentowe': ['diamond push up', 'triangle push up'],
  'przysiad': ['squat'],
  'przysiady': ['squat'],
  'przysiad bulgarski': ['bulgarian split squat'],
  'wyciskanie': ['bench press', 'press'],
  'wyciskanie sztangi': ['bench press'],
  'wyciskanie hantli': ['dumbbell press'],
  'wyciskanie zolnierskie': ['military press', 'overhead press'],
  'martwy ciag': ['deadlift'],
  'podciaganie': ['pull up', 'pull-up', 'chin up'],
  'podciagania': ['pull up', 'pull-up'],
  'brzuszki': ['crunch', 'sit up'],
  'brzuszek': ['crunch'],
  'deska': ['plank'],
  'plank': ['plank'],
  'wioslowanie': ['row', 'bent over row'],
  'uginanie ramion': ['bicep curl', 'curl'],
  'uginanie': ['curl'],
  'biceps': ['bicep curl', 'curl'],
  'triceps': ['triceps extension', 'triceps'],
  'prostowanie ramion': ['triceps extension'],
  'wykroki': ['lunge'],
  'wykrok': ['lunge'],
  'zakroki': ['reverse lunge'],
  'wznosy bokiem': ['lateral raise'],
  'wznosy': ['raise'],
  'unoszenie nog': ['leg raise'],
  'mostek': ['glute bridge', 'hip thrust'],
  'hip thrust': ['hip thrust'],
  'lydki': ['calf raise'],
  'wspiecia na palce': ['calf raise'],
  'dipy': ['dips', 'triceps dip'],
  'pajacyki': ['jumping jack'],
  'burpees': ['burpee'],
  'burpee': ['burpee'],
  'bieg': ['run', 'running'],
  'bieganie': ['run', 'running'],
  'rower': ['cycling', 'bike'],
  'sciaganie drazka': ['lat pulldown'],
  'przyciaganie': ['row', 'pulldown'],
  'plecy': ['back', 'row', 'pull up'],
  'klatka': ['chest', 'bench press', 'push up'],
  'barki': ['shoulder', 'shoulder press', 'lateral raise'],
  'nogi': ['legs', 'squat', 'lunge'],
  'posladki': ['glutes', 'hip thrust', 'glute bridge'],
  'brzuch': ['abs', 'crunch', 'plank'],
  'core': ['core', 'plank'],
  'rozciaganie': ['stretch', 'stretching'],
  'mountain climber': ['mountain climber'],
  'przywodziciele': ['adductor'],
  'kaptury': ['shrug'],
  'szrugsy': ['shrug'],
};

/// Tłumaczy zapytanie użytkownika na listę angielskich fraz do Wger.
/// Zwraca frazy w kolejności trafności; oryginalne zapytanie zawsze na liście
/// (użytkownik mógł wpisać po angielsku).
List<String> translateQueryTerms(String query) {
  final normalized = normalizeSearchText(query);
  if (normalized.isEmpty) return const [];
  final terms = <String>[query.trim()];
  // Pełne dopasowanie frazy.
  final exact = kPlEnExerciseSynonyms[normalized];
  if (exact != null) terms.addAll(exact);
  // Dopasowanie po słowach (np. „pompki na kolanach" → pompki).
  for (final entry in kPlEnExerciseSynonyms.entries) {
    if (normalized.contains(entry.key) && entry.value.isNotEmpty) {
      terms.add(entry.value.first);
    }
  }
  // Usuń duplikaty, zachowaj kolejność.
  final seen = <String>{};
  return [
    for (final term in terms)
      if (seen.add(normalizeSearchText(term))) term,
  ];
}

/// Czy ćwiczenie pasuje do frazy z wyszukiwarki — sprawdza NAZWĘ, KATEGORIĘ,
/// PARTIE MIĘŚNIOWE i SPRZĘT, z normalizacją diakrytyków i synonimami PL↔EN.
///
/// Do filtrowania w arkuszach wyboru ćwiczenia (dodaj/zamień): przy pustym
/// zapytaniu przepuszcza wszystko, więc chip partii może działać samodzielnie.
/// Dzięki wpięciu partii do haystacka wpisanie „plecy" albo „biceps" znajduje
/// ćwiczenia po partii, nie tylko po nazwie.
bool exerciseMatchesQuery(Exercise exercise, String query) {
  final normalized = normalizeSearchText(query);
  if (normalized.isEmpty) return true;
  final phrases = <String>{normalized};
  for (final term in translateQueryTerms(query)) {
    phrases.add(normalizeSearchText(term));
  }
  final haystack = normalizeSearchText(
    '${exercise.name} ${exercise.category} '
    '${exercise.muscles.join(' ')} ${exercise.equipment}',
  );
  return phrases.any((phrase) => phrase.isNotEmpty && haystack.contains(phrase));
}

/// Wyszukiwanie w lokalnej bazie ćwiczeń: nazwa, kategoria, partie, sprzęt,
/// z obsługą polskich i angielskich fraz (synonimy w obie strony).
List<Exercise> searchLocalExercises(String query, List<Exercise> exercises) {
  final normalized = normalizeSearchText(query);
  if (normalized.isEmpty) return const [];
  // Zbiór fraz do dopasowania: zapytanie + tłumaczenia EN + (dla zapytań EN)
  // polskie odpowiedniki z odwróconej mapy synonimów.
  final phrases = <String>{normalized};
  for (final term in translateQueryTerms(query)) {
    phrases.add(normalizeSearchText(term));
  }
  for (final entry in kPlEnExerciseSynonyms.entries) {
    for (final en in entry.value) {
      final enNorm = normalizeSearchText(en);
      if (enNorm == normalized || normalized.contains(enNorm)) {
        phrases.add(entry.key);
      }
    }
  }

  int scoreOf(Exercise exercise) {
    final name = normalizeSearchText(exercise.name);
    final category = normalizeSearchText(exercise.category);
    final muscles = normalizeSearchText(exercise.muscles.join(' '));
    final equipment = normalizeSearchText(exercise.equipment);
    var score = 0;
    for (final phrase in phrases) {
      if (phrase.isEmpty) continue;
      if (name == phrase) {
        score += 100;
      } else if (name.startsWith(phrase)) {
        score += 60;
      } else if (name.contains(phrase)) {
        score += 40;
      }
      if (category.contains(phrase)) score += 15;
      if (muscles.contains(phrase)) score += 12;
      if (equipment.contains(phrase)) score += 8;
    }
    return score;
  }

  final scored = <(Exercise, int)>[];
  for (final exercise in exercises) {
    final score = scoreOf(exercise);
    if (score > 0) scored.add((exercise, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final item in scored) item.$1];
}
