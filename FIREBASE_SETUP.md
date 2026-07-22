# Konto i synchronizacja (Firebase) — konfiguracja

Aplikacja **Trainer** działa w pełni lokalnie bez żadnej konfiguracji. Logowanie
i synchronizacja z chmurą są **opcjonalne** i włączają się dopiero po
jednorazowym podpięciu Firebase. Do tego czasu ekran „Więcej → Konto i
synchronizacja" pokazuje tryb lokalny + lokalny backup/eksport/import.

Kod jest odporny na brak konfiguracji: `TrainerAccountService.init()` łapie błąd
inicjalizacji Firebase i zostawia aplikację w trybie lokalnym (nic się nie psuje).

## Kroki (raz)

1. **Projekt Firebase** — utwórz na https://console.firebase.google.com.
2. **FlutterFire CLI** — w katalogu projektu:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   To generuje `google-services.json` (Android), `firebase_options.dart` oraz
   podpina wtyczkę Gradle `com.google.gms.google-services`. Dzięki temu
   `Firebase.initializeApp()` (bez parametrów, jak w serwisie) zadziała.
3. **Authentication** — w konsoli włącz dostawców: **Email/Password** oraz
   **Google**.
4. **Cloud Firestore** — utwórz bazę (tryb produkcyjny). Dane użytkownika trafiają
   do kolekcji `trainer_users/{uid}` (pole `dataJson` = pełny eksport aplikacji).
5. **Logowanie Google (Android)** — dodaj odcisk **SHA-1** (i SHA-256) aplikacji
   w ustawieniach projektu Firebase (Project settings → Your apps → Add
   fingerprint). Bez tego `signInWithProvider(GoogleAuthProvider())` zwróci błąd.

## Reguły bezpieczeństwa Firestore (minimum)

Każdy widzi tylko swój dokument:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /trainer_users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## Jak to działa w aplikacji

- **Synchronizuj teraz** — pobiera kopię z chmury, **scala** ją z lokalnymi
  danymi (łączenie po `id`, bez duplikowania historii), a następnie wysyła
  scaloną całość do chmury. Ustawienia lokalne pozostają nienaruszone.
- **Wyślij do chmury** — nadpisuje kopię w chmurze bieżącym stanem lokalnym.
- **Przywróć z chmury** — zastępuje dane lokalne wersją z chmury (dla nowego
  telefonu; pyta o potwierdzenie).
- **Kopia lokalna / eksport / import** — działają zawsze, także bez logowania.

Zakres danych = pełny eksport (`buildFullExport`): profil/ustawienia (w tym
wygląd), treningi, plany, ćwiczenia, serie/RPE/objętość, pomiary, korekty dnia,
aktywności i snapshoty Health Connect. Mapa regeneracji wylicza się z treningów.

## Rozwiązywanie błędów logowania

To są błędy **konfiguracji w konsoli Firebase**, nie kodu. Aplikacja pokazuje
teraz dla nich czytelne komunikaty.

### `ApiException: 10` (DEVELOPER_ERROR) przy logowaniu Google
Brakuje odcisku **SHA-1** aplikacji w Firebase i/lub dostawca **Google** nie jest
włączony (jego włączenie tworzy klienta OAuth „Web", z którego natywny
google_sign_in bierze token).
1. Firebase → **Authentication → Sign-in method** → włącz **Google**.
2. Firebase → **Ustawienia projektu → Twoje aplikacje** → wybierz aplikację
   Android (`com.example.licznik_treningu`) → **Add fingerprint** → wklej SHA-1
   (i SHA-256).
3. Pobierz **nowe `google-services.json`**, podmień w `android/app/`, przebuduj.

Odciski dla klucza **debug** na tej maszynie:
- **SHA-1:** `D6:38:71:CD:B7:01:18:B9:9C:3E:AC:FC:73:E3:F4:BC:6B:DE:55:AE`
- **SHA-256:** `03:54:35:C1:39:C4:9C:BE:D5:C8:CE:07:42:E6:34:F9:5D:DD:B0:7E:6F:C6:D9:04:92:18:34:DA:59:B4:4D:1D`

(Wygenerowane z `~/.android/debug.keystore`. Do wersji release użyj SHA-1
swojego keystore release.)

### `CONFIGURATION_NOT_FOUND` przy zakładaniu konta e-mail
Logowanie **Email/Password** nie jest włączone dla projektu.
1. Firebase → **Authentication** → jeśli trzeba, kliknij **Get started**.
2. **Sign-in method** → włącz **Email/Password** (i **Google**).

## Uwaga

Firestore ma limit 1 MB na dokument — kopia jest dzielona na kawałki
(`backups/part_i`), więc duże dane nie wywalają zapisu.
