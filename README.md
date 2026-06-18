# Licznik Treningu

Osobna aplikacja Flutter do ćwiczeń, zaprojektowana jako „siostrzana” aplikacja do Licznika Kalorii.

## Co jest w środku

- Baza ćwiczeń z kategoriami, mięśniami, sprzętem, poziomem i wskazówkami.
- Animowane ilustracje ćwiczeń rysowane bezpośrednio w Flutterze przez `CustomPainter`.
- Dziennik treningów: serie, powtórzenia, ciężar, czas, RPE, notatka, kalorie.
- Plan tygodniowy generowany lokalnie lub przez backend AI.
- Postęp: kalorie, czas, objętość i wykresy z ostatnich 14 dni.
- Ustawienia użytkownika: waga, wzrost, cel, poziom, URL backendu.
- Integracja z backendem FastAPI: `/analyze-workout`, `/generate-workout-plan`, `/analyze-exercise-form`.

## Jak uruchomić

1. Utwórz nowy projekt Flutter albo rozpakuj katalog jako projekt.
2. W terminalu:

```bash
flutter pub get
flutter run
```

## Backend

W aplikacji przejdź do `Więcej -> Backend AI` i wpisz adres swojego backendu z Render, np.:

```text
https://twoj-backend.onrender.com
```

W katalogu `backend/` jest plik `workout_backend_patch.py`. Możesz wkleić jego zawartość do swojego obecnego `main.py` FastAPI albo przenieść endpointy ręcznie.

