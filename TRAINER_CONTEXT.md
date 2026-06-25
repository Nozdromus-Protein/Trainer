# TRAINER_CONTEXT.md

## 1. Cel dokumentu

Ten plik jest kontekstem dla AI/agenta programistycznego, np. Claude Code, Codex, Cursor Agent, Cline albo podobnego narzędzia.

Agent ma używać tego dokumentu przed wykonywaniem kolejnych etapów pracy nad aplikacją **Trainer**.

Nie wykonuj zmian na ślepo. Najpierw przeczytaj ten dokument, przeanalizuj projekt, sprawdź aktualny kod i dopiero potem wykonuj wskazany etap.

---

## 2. Nazwa i charakter projektu

Projekt: **Trainer**

Typ projektu: aplikacja mobilna Flutter / Dart.

Aplikacja Trainer jest osobną aplikacją treningową. Jest powiązana koncepcyjnie z aplikacją **Licznik Kalorii / Proteina**, ale nie wolno mieszać kodu obu projektów bez wyraźnej potrzeby.

Główne cele aplikacji Trainer:

- planowanie treningów,
- wybór ćwiczeń,
- dodawanie wykonanych ćwiczeń,
- śledzenie aktywności,
- integracja z Health Connect / Samsung Health,
- obsługa kroków, biegania, chodzenia, dystansu, kalorii aktywnych, snu i tętna,
- estetyczny dashboard treningowy,
- możliwość późniejszej komunikacji z aplikacją Licznik Kalorii / Proteina.

---

## 3. Ważne zasady pracy

Przed każdą zmianą:

1. Przeanalizuj aktualną strukturę projektu.
2. Znajdź główny plik aplikacji.
3. Sprawdź, które funkcje już istnieją.
4. Nie zakładaj, że projekt jest identyczny z opisem — kod jest źródłem prawdy.
5. Wykonaj tylko etap, który został wyraźnie wskazany w promptcie.
6. Nie rób dodatkowych zmian „przy okazji”, jeśli nie są konieczne.

---

## 4. Twarde zasady bezpieczeństwa kodu

Nie wolno:

- ucinać plików,
- nadpisywać całego `main.dart`, jeśli można zmienić tylko fragment,
- usuwać istniejących funkcji bez uzasadnienia,
- usuwać ekranów, modeli, klas ani helperów, jeśli są nadal używane,
- zmieniać nazw klas, metod, zmiennych i ekranów bez realnej potrzeby,
- zastępować prawdziwej logiki mockami,
- usuwać integracji Health Connect,
- usuwać logiki kroków, biegu, chodu, snu, tętna lub kalorii aktywnych,
- mieszać logiki aplikacji Trainer z aplikacją Licznik Kalorii bez wyraźnego polecenia,
- robić dużego refactoru bez potrzeby,
- ignorować błędów kompilacji,
- zostawiać niedomkniętych nawiasów, duplikatów klas albo martwych importów.

Jeśli zmiana wymaga większego refactoru, najpierw ogranicz zakres do minimum i opisz ryzyko.

---

## 5. Styl aplikacji

Aplikacja Trainer powinna mieć nowoczesny, czytelny i estetyczny wygląd.

Preferowany styl:

- ciemny / nowoczesny interfejs,
- świeże kolory,
- miętowe akcenty,
- czytelne karty,
- mało ścisku w UI,
- brak overflowów,
- brak nachodzenia przycisków na tekst,
- dashboard podobny jakościowo do aplikacji fitness,
- dobre odstępy między sekcjami,
- intuicyjna nawigacja.

Szczególnie ważne:

- nie robić ciasnych list,
- nie zostawiać elementów, które wyglądają jak „ściśnięte”,
- zadbać o czytelność na telefonie,
- unikać `bottom overflowed by x pixels`,
- unikać niekontrolowanego przewijania i złych wysokości kontenerów.

---

## 6. Obecne główne obszary aplikacji

Aplikacja Trainer ma lub powinna mieć następujące obszary:

### 6.1. Dzisiaj / Dashboard

Ekran podsumowania dnia.

Powinien pokazywać między innymi:

- dzisiejszy trening,
- wykonane ćwiczenia,
- kroki,
- aktywne kalorie,
- dystans,
- minuty aktywności,
- bieg/chód,
- status Health Connect / zegarka,
- korektę dnia,
- ewentualne sugestie.

### 6.2. Ćwiczenia

Ekran z bazą ćwiczeń.

Powinien umożliwiać:

- przeglądanie ćwiczeń,
- filtrowanie po partiach mięśniowych,
- wyszukiwanie ćwiczeń,
- dodawanie ćwiczenia do treningu,
- wybór poziomu trudności,
- podgląd grafiki / animacji / GIF ćwiczenia,
- poprawne dodawanie ćwiczeń bez błędów po zamknięciu wyszukiwarki.

### 6.3. Więcej

Ekran ustawień i dodatkowych funkcji.

Może zawierać:

- integracje,
- Health Connect,
- ustawienia użytkownika,
- ustawienia celów,
- synchronizację z Licznikiem Kalorii,
- diagnostykę,
- informacje o aplikacji.

### 6.4. Zdrowie i aktywność

Moduł odpowiedzialny za dane z Health Connect / Samsung Health.

Powinien obsługiwać:

- kroki,
- aktywne kalorie,
- dystans,
- ćwiczenia,
- biegi,
- chód,
- sen,
- tętno,
- status zgód,
- dane dostępne / brakujące,
- odświeżanie danych,
- informację, czy dane są częściowe.

---

## 7. Health Connect / Samsung Health

To jeden z najważniejszych modułów projektu.

Aplikacja ma pobierać dane z Health Connect, a przez niego z Samsung Health / zegarka.

Ważne typy danych:

- kroki,
- aktywne kalorie,
- dystans,
- ćwiczenia / sesje treningowe,
- tętno,
- sen,
- biegi,
- chodzenie,
- minuty aktywności.

Wcześniejsze problemy do pilnowania:

- kroki były widoczne, ale kalorie z kroków/chodu nie przeliczały się poprawnie,
- bieg i chód potrafiły się mieszać,
- chód mierzony był dodawany do biegów zamiast do chodu,
- 14 000 kroków potrafiło dać absurdalnie mało kalorii, np. około 74 kcal,
- dane z Samsung Health / Health Connect mogły nie być realnie połączone lub mogły być częściowe,
- usunięty bieg potrafił nadal być widoczny,
- aktywne kcal z biegu nie zawsze dodawały się do ogólnego celu,
- aplikacja powinna wyraźnie informować, czy dane są dostępne, brakujące, częściowe albo bez zgody.

Agent ma szczególnie uważać, żeby:

- nie dublować spalonych kalorii,
- nie mieszać biegu z chodem,
- nie liczyć tych samych kroków dwa razy,
- nie ignorować sesji treningowych,
- nie pokazywać fałszywego statusu „wszystko działa”, jeśli dane są częściowe,
- oddzielić zwykłe kroki od zarejestrowanego chodu/treningu, jeśli Health Connect zwraca takie dane osobno.

---

## 8. Korekta dnia

Aplikacja Trainer może wpływać na cele dnia w aplikacji Licznik Kalorii / Proteina.

Korekta dnia może obejmować:

- zwiększenie celu kalorii,
- zwiększenie celu wody,
- zwiększenie celu węgli,
- informacje o większym zapotrzebowaniu po treningu lub bieganiu,
- procent dodawanych aktywnych kalorii do celu, np. 30%, 50%, 65%, 80%, 100%.

Ważne:

- korekta ma być realistyczna,
- użytkownik ma widzieć, skąd pochodzi korekta,
- nie wolno dublować aktywnych kalorii,
- jeśli dane są częściowe, aplikacja ma to jasno powiedzieć,
- korekta powinna być elastyczna i możliwa do ustawienia.

---

## 9. Historia projektu i wcześniejsze założenia

W projekcie były omawiane lub wdrażane między innymi:

- nazwa aplikacji: Trainer,
- osobny projekt od Licznika Kalorii,
- dashboard treningowy,
- moduł ćwiczeń,
- baza ćwiczeń,
- dodawanie ćwiczenia,
- poprawa wyszukiwarki ćwiczeń,
- usunięcie prostych patyczakowych ilustracji,
- zastąpienie ich lepszymi grafikami / obrazami człowieka / animacjami,
- obsługa GIF-ów lub krótkich animacji ćwiczeń,
- integracja Health Connect,
- pobieranie danych z zegarka,
- status zgód,
- ekran integracji,
- wykresy tygodniowe,
- relacja trening–jedzenie,
- ostrzeżenia o danych częściowych,
- osobne traktowanie biegu i chodu,
- poprawa overflowów,
- poprawa UI,
- poprawa działania wyszukiwarki,
- naprawa błędów po zwinięciu wyszukiwarki,
- usuwanie crashy w ekranie „Więcej”.

---

## 10. Znane problemy, których nie wolno zignorować

Podczas zmian sprawdź, czy nie wracają następujące problemy:

- `bottom overflowed by x pixels`,
- przyciski nachodzące na siebie,
- tekst wychodzący poza karty,
- crash po wejściu w „Więcej”,
- brak reakcji po kliknięciu „Dodaj ćwiczenie”,
- błąd po zamknięciu / zwinięciu wyszukiwarki,
- błędne liczenie kroków,
- błędne liczenie kalorii z kroków,
- mieszanie chodu z biegami,
- duplikowanie aktywności,
- martwe przyciski,
- nieużywane importy,
- duplikaty klas,
- błędne nawiasy,
- utrata danych użytkownika,
- nieczytelny layout.

---

## 11. Zasady wykonywania etapów

Każdy etap wykonuj według tego schematu:

1. Przeczytaj cały ten plik.
2. Przeczytaj prompt użytkownika z konkretnym etapem.
3. Przeanalizuj projekt.
4. Znajdź miejsca w kodzie, które dotyczą danego etapu.
5. Zrób możliwie małą, bezpieczną zmianę.
6. Nie zmieniaj rzeczy niezwiązanych z etapem.
7. Po zmianach uruchom:
   - `flutter analyze`, jeśli środowisko pozwala,
   - testy, jeśli istnieją,
   - ewentualnie `dart format` na zmienionych plikach.
8. Jeśli nie możesz uruchomić komend, napisz to wyraźnie.
9. Na końcu podaj raport.

---

## 12. Format raportu po wykonaniu etapu

Po wykonaniu zmian wypisz raport w tym formacie:

```txt
WYKONANY ETAP:
- [numer i nazwa etapu]

ZMIENIONE PLIKI:
- [plik 1] — [krótko co zmieniono]
- [plik 2] — [krótko co zmieniono]

CO ZOSTAŁO ZROBIONE:
- [punkt 1]
- [punkt 2]
- [punkt 3]

CO TRZEBA PRZETESTOWAĆ RĘCZNIE:
- [test 1]
- [test 2]
- [test 3]

RYZYKA / UWAGI:
- [uwaga 1]
- [uwaga 2]

KOMENDY:
- flutter analyze: [wynik / nie uruchomiono]
- dart format: [wynik / nie uruchomiono]
- testy: [wynik / nie uruchomiono]
```

---

## 13. Prompt startowy dla Claude Code / Codexa

Użyj tego promptu, kiedy chcesz rozpocząć pracę nad konkretnym etapem:

```txt
Pracujesz nad aplikacją Flutter „Trainer”.

Najpierw przeczytaj plik TRAINER_CONTEXT.md.
Następnie przeanalizuj aktualny projekt i wykonaj tylko wskazany etap.

Nie ucinać plików.
Nie nadpisywać całego main.dart bez potrzeby.
Nie usuwać istniejących funkcji.
Nie zmieniać niezwiązanych ekranów.
Nie psuć integracji Health Connect / Samsung Health.
Nie mieszać logiki Trainer z aplikacją Licznik Kalorii bez wyraźnej potrzeby.
Nie dodawać mocków zamiast prawdziwej logiki.
Po zmianach wypisz raport według formatu z TRAINER_CONTEXT.md.

Wykonaj etap:
[WKLEJ TUTAJ PEŁNY OPIS ETAPU]
```

---

## 14. Miejsce na aktualny etap

Wklej tutaj aktualny etap, np. Etap 14.

```txt
ETAP 14 — [NAZWA ETAPU]

Cel:
[opisz cel]

Zakres:
- [punkt 1]
- [punkt 2]
- [punkt 3]

Wymagania:
- [wymaganie 1]
- [wymaganie 2]
- [wymaganie 3]

Nie rób:
- [czego nie robić]
- [czego nie ruszać]

Po wykonaniu:
- wypisz zmienione pliki,
- opisz, co zostało zrobione,
- opisz, co trzeba przetestować,
- uruchom flutter analyze, jeśli możesz.
```

---

## 15. Najważniejsze przypomnienie

Ten projekt jest duży i wrażliwy na przypadkowe zmiany.

Najważniejsze jest, żeby agent:

- rozumiał aktualny kod,
- wykonywał tylko jeden etap naraz,
- nie usuwał istniejącej logiki,
- nie ucinał plików,
- nie robił chaotycznych refactorów,
- jasno raportował, co zmienił,
- pilnował Health Connect, kroków, biegu, chodu i kalorii aktywnych.

Koniec dokumentu.
