import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Status konta użytkownika dla UI. Bezpieczny także wtedy, gdy Firebase nie
/// jest skonfigurowany (aplikacja działa wtedy w pełni lokalnie).
class TrainerAccountState {
  const TrainerAccountState({
    required this.firebaseAvailable,
    required this.signedIn,
    this.uid,
    this.email,
    this.displayName,
    this.providerLabel = '',
  });

  final bool firebaseAvailable;
  final bool signedIn;
  final String? uid;
  final String? email;
  final String? displayName;
  final String providerLabel;

  static const unavailable = TrainerAccountState(firebaseAvailable: false, signedIn: false);
}

/// Serwis konta i synchronizacji chmurowej Trainera (Firebase Auth + Firestore).
///
/// Wszystko jest OPCJONALNE: gdy w projekcie nie ma konfiguracji Firebase
/// (`google-services.json` / `firebase_options.dart`), [init] po prostu ustawia
/// [firebaseAvailable] = false i aplikacja działa lokalnie jak dotąd. Logowanie
/// nigdy nie jest wymuszane, a dane lokalne nie są kasowane po zalogowaniu.
class TrainerAccountService extends ChangeNotifier {
  Future<void>? _initFuture;
  bool _firebaseAvailable = false;
  User? _user;
  StreamSubscription<User?>? _authSub;

  /// Czas ostatniej udanej synchronizacji z chmurą (na tym urządzeniu).
  DateTime? lastCloudSyncAt;

  bool get firebaseAvailable => _firebaseAvailable;
  bool get signedIn => _user != null;
  User? get user => _user;

  TrainerAccountState get state {
    if (!_firebaseAvailable) return TrainerAccountState.unavailable;
    final u = _user;
    return TrainerAccountState(
      firebaseAvailable: true,
      signedIn: u != null,
      uid: u?.uid,
      email: u?.email,
      displayName: u?.displayName,
      providerLabel: _providerLabel(u),
    );
  }

  String _providerLabel(User? u) {
    if (u == null) return '';
    for (final p in u.providerData) {
      if (p.providerId.contains('google')) return 'Google';
      if (p.providerId.contains('password')) return 'E-mail';
    }
    return u.isAnonymous ? 'Gość' : 'Konto';
  }

  /// Inicjalizuje Firebase w sposób bezpieczny. Brak konfiguracji nie jest
  /// błędem — zostaje wtedy tryb lokalny. Zwraca zapamiętany future, więc wielu
  /// wywołujących (init w main + brama logowania) czeka na TĘ SAMĄ inicjalizację.
  Future<void> init() => _initFuture ??= _runInit();

  Future<void> _runInit() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseAvailable = true;
      _user = FirebaseAuth.instance.currentUser;
      _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
        _user = u;
        notifyListeners();
      });
    } catch (error) {
      _firebaseAvailable = false;
      // Brak/niepełna konfiguracja Firebase — aplikacja działa lokalnie.
      debugPrint('[Account] Firebase niedostępny (tryb lokalny): $error');
    }
    notifyListeners();
  }

  void _ensureAvailable() {
    if (!_firebaseAvailable) {
      throw Exception(
        'Firebase nie jest skonfigurowany. Uruchom `flutterfire configure` '
        'albo dodaj google-services.json, aby włączyć logowanie i chmurę.',
      );
    }
  }

  Future<void> registerWithEmail(String email, String password) async {
    _ensureAvailable();
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signInWithEmail(String email, String password) async {
    _ensureAvailable();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// NATYWNE logowanie Google (google_sign_in → signInWithCredential). Bez
  /// przeglądarki / redirectu, więc NIE występuje błąd „missing initial state"
  /// z web-flow `signInWithProvider`. Wymaga włączonego dostawcy Google w
  /// konsoli Firebase i poprawnego SHA-1 dla aplikacji Android.
  Future<void> signInWithGoogle() async {
    _ensureAvailable();
    final GoogleSignIn googleSignIn = GoogleSignIn(scopes: <String>['email']);
    final GoogleSignInAccount? account = await googleSignIn.signIn();
    if (account == null) {
      throw Exception('Logowanie Google anulowane.');
    }
    final GoogleSignInAuthentication auth = await account.authentication;
    if (auth.idToken == null && auth.accessToken == null) {
      throw Exception(
        'Brak tokenu Google. Sprawdź SHA-1 i klienta OAuth (Web client) w Firebase.',
      );
    }
    final OAuthCredential credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> sendPasswordReset(String email) async {
    _ensureAvailable();
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    if (!_firebaseAvailable) return;
    // Wyloguj też z natywnego Google, żeby następne logowanie pokazało wybór konta.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  /// Maksymalny rozmiar jednego dokumentu-kawałka (znaki JSON). Bezpiecznie pod
  /// limitem Firestore 1 MB/dokument.
  static const int _maxChunkChars = 400000;

  /// Kolekcja kopii: trainer_users/{uid}/backups. `null` przy pustym uid.
  CollectionReference<Map<String, dynamic>>? _backupsCollection() {
    final String uid = _user?.uid.trim() ?? '';
    if (uid.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('trainer_users')
        .doc(uid)
        .collection('backups');
  }

  /// Pobiera i skleja payload danych z chmury (albo null, gdy brak kopii).
  Future<Map<String, dynamic>?> downloadPayload() async {
    _ensureAvailable();
    final CollectionReference<Map<String, dynamic>>? backups =
        _backupsCollection();
    if (backups == null) throw Exception('Nie jesteś zalogowany (pusty uid).');

    final snap = await backups.doc('latest').get();
    final data = snap.data();
    if (data == null) return null;

    final int chunkCount = (data['chunkCount'] as num?)?.toInt() ?? 0;
    if (chunkCount > 0) {
      final StringBuffer buffer = StringBuffer();
      for (int i = 0; i < chunkCount; i++) {
        final part = await backups.doc('part_$i').get();
        final Object? chunk = part.data()?['data'];
        if (chunk is String) buffer.write(chunk);
      }
      return _decodeJsonMap(buffer.toString());
    }

    // Zgodność wsteczna: payload zapisany prosto w polu dataJson albo jako mapa.
    final raw = data['dataJson'];
    if (raw is String && raw.isNotEmpty) return _decodeJsonMap(raw);
    final nested = data['data'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return null;
  }

  /// Zapisuje payload danych do chmury. Struktura:
  ///   trainer_users/{uid}                 (dokument-korzeń: metadane + test)
  ///   trainer_users/{uid}/backups/latest  (metadane najnowszej kopii)
  ///   trainer_users/{uid}/backups/part_{i}(kawałki JSON, każdy pod limitem 1 MB)
  Future<void> uploadPayload(Map<String, dynamic> data) async {
    _ensureAvailable();
    final String uid = _user?.uid.trim() ?? '';
    if (uid.isEmpty) throw Exception('Nie jesteś zalogowany (pusty uid).');

    final DocumentReference<Map<String, dynamic>> root =
        FirebaseFirestore.instance.collection('trainer_users').doc(uid);
    final CollectionReference<Map<String, dynamic>> backups =
        root.collection('backups');

    // Oczyszczenie danych: NaN/Infinity → null, DateTime → ISO, puste klucze
    // usuwane, niestandardowe obiekty → String, poprawny UTF-8.
    final Map<String, dynamic> sanitized = _sanitizeBackupMap(data);
    final String payload = _safeFirestoreString(jsonEncode(sanitized));
    final int totalChars = payload.length;
    // Cięcie bezpieczne dla par zastępczych (emoji) — zwykłe `substring` co N
    // znaków potrafi rozdzielić emoji na granicy kawałka, przez co Firestore
    // odrzuca zapis z `invalid-argument`. Patrz [splitBackupPayloadIntoChunks].
    final List<String> chunks = splitBackupPayloadIntoChunks(
      payload,
      maxChunkChars: _maxChunkChars,
    );
    final int chunkCount = chunks.length;

    // Poprzednia liczba kawałków — żeby po zapisie usunąć osierocone part_i,
    // gdy nowa kopia jest mniejsza (inaczej stare dokumenty zalegałyby w chmurze).
    int previousChunkCount = 0;
    try {
      final DocumentSnapshot<Map<String, dynamic>> oldLatest =
          await backups.doc('latest').get();
      previousChunkCount =
          ((oldLatest.data()?['chunkCount']) as num?)?.toInt() ?? 0;
    } catch (_) {}

    debugPrint(
      '[Account] Backup → trainer_users/$uid/backups • '
      'znaki(JSON)=$totalChars • kawałki=$chunkCount • '
      'typ=String(JSON) • kluczy=${sanitized.length}',
    );

    // Najpierw mały dokument testowy — weryfikacja ścieżki/uprawnień/sieci.
    await root.set({
      'appVersion': 'trainer',
      'lastBackupTestAt': DateTime.now().toIso8601String(),
      'platform': defaultTargetPlatform.name,
    }, SetOptions(merge: true));

    // Zapis kawałków — każdy osobny dokument omija limit 1 MB/dokument.
    for (int i = 0; i < chunkCount; i++) {
      await backups.doc('part_$i').set({
        'index': i,
        'data': chunks[i],
      });
    }

    await backups.doc('latest').set({
      'chunkCount': chunkCount,
      'totalChars': totalChars,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtIso': DateTime.now().toIso8601String(),
      'platform': defaultTargetPlatform.name,
      'appVersion': 'trainer',
    });

    // Sprzątanie osieroconych kawałków poprzedniej, większej kopii (best-effort
    // — ich obecność nie psuje odczytu, bo download czyta tylko chunkCount).
    for (int i = chunkCount; i < previousChunkCount; i++) {
      try {
        await backups.doc('part_$i').delete();
      } catch (_) {}
    }

    lastCloudSyncAt = DateTime.now();
    notifyListeners();
  }

  Map<String, dynamic>? _decodeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// Czas ostatniej modyfikacji kopii w chmurze (dla statusu synchronizacji).
  Future<DateTime?> cloudUpdatedAt() async {
    if (!_firebaseAvailable) return null;
    final CollectionReference<Map<String, dynamic>>? backups =
        _backupsCollection();
    if (backups == null) return null;
    try {
      final snap = await backups.doc('latest').get();
      final iso = snap.data()?['updatedAtIso'];
      if (iso is String) return DateTime.tryParse(iso);
    } catch (_) {}
    return null;
  }

  // --- Automatyczne kopie w chmurze (Trainer: po każdym ćwiczeniu + raz dziennie) ---

  static const String _autoBackupDateKey = 'trainer_last_auto_backup_date';
  DateTime? _lastAutoBackupAt;

  String _todayKey() {
    final DateTime d = DateTime.now();
    final String month = d.month.toString().padLeft(2, '0');
    final String day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  /// Kopia „zdarzeniowa" (np. po każdym ćwiczeniu podczas treningu) z lekkim
  /// throttlingiem, żeby przy szybkich zmianach nie zapisywać w kółko. Payload
  /// budowany dopiero gdy naprawdę wysyłamy (kosztowny eksport pomijany przy
  /// throttlu). Wywołaj z `minInterval: Duration.zero`, żeby wymusić kopię.
  Future<void> autoBackupEvent(
    Map<String, dynamic> Function() buildPayload, {
    Duration minInterval = const Duration(seconds: 45),
  }) async {
    if (!_firebaseAvailable || _user == null) return;
    final DateTime now = DateTime.now();
    if (_lastAutoBackupAt != null &&
        now.difference(_lastAutoBackupAt!) < minInterval) {
      return;
    }
    _lastAutoBackupAt = now;
    try {
      await uploadPayload(buildPayload());
    } catch (error) {
      debugPrint('[Account] Auto-backup (zdarzenie) nieudany: $error');
    }
  }

  /// Kopia dzienna — co najwyżej raz na dobę kalendarzową (znacznik w prefs
  /// przeżywa restart). Nie robi nic, gdy nie zalogowano albo Firebase brak.
  Future<void> autoBackupDailyIfNeeded(
    Map<String, dynamic> Function() buildPayload,
  ) async {
    if (!_firebaseAvailable || _user == null) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String today = _todayKey();
    if (prefs.getString(_autoBackupDateKey) == today) return;
    try {
      await uploadPayload(buildPayload());
      await prefs.setString(_autoBackupDateKey, today);
      _lastAutoBackupAt = DateTime.now();
    } catch (error) {
      debugPrint('[Account] Auto-backup (dzienny) nieudany: $error');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// Globalna instancja serwisu konta. Inicjalizowana w `main()` przez [init].
final TrainerAccountService trainerAccountService = TrainerAccountService();

/// Rekurencyjnie oczyszcza dane pod zapis do Firestore/JSON:
/// double NaN/Infinity → null, DateTime → ISO String, niestandardowe obiekty →
/// String, puste/niepoprawne klucze map usuwane.
Object? _sanitizeBackupValue(Object? value) {
  if (value == null) return null;
  if (value is bool || value is String || value is int) return value;
  if (value is double) {
    if (value.isNaN || value.isInfinite) return null;
    return value;
  }
  if (value is DateTime) return value.toIso8601String();
  if (value is Map) return _sanitizeBackupMap(value);
  if (value is Iterable) {
    return value.map(_sanitizeBackupValue).toList();
  }
  return value.toString();
}

Map<String, dynamic> _sanitizeBackupMap(Map<dynamic, dynamic> input) {
  final Map<String, dynamic> out = <String, dynamic>{};
  input.forEach((Object? key, Object? value) {
    if (key == null) return;
    final String k = key.toString().trim();
    if (k.isEmpty) return;
    out[k] = _sanitizeBackupValue(value);
  });
  return out;
}

/// Zamienia niesparowane surogaty UTF-16 na znak zastępczy — Firestore wymaga
/// poprawnego UTF-8, więc uszkodzone znaki w danych nie wywalą zapisu.
String _safeFirestoreString(String s) {
  final int len = s.length;
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < len; i++) {
    final int c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 < len) {
        final int n = s.codeUnitAt(i + 1);
        if (n >= 0xDC00 && n <= 0xDFFF) {
          sb.writeCharCode(c);
          sb.writeCharCode(n);
          i++;
          continue;
        }
      }
      sb.writeCharCode(0xFFFD);
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      sb.writeCharCode(0xFFFD);
    } else {
      sb.writeCharCode(c);
    }
  }
  return sb.toString();
}

/// Dzieli payload backupu na kawałki mieszczące się w limicie dokumentu
/// Firestore, NIGDY nie przecinając pary zastępczej UTF-16. Zwykłe cięcie
/// `substring` co N znaków może rozdzielić emoji (surogat wysoki na końcu
/// jednego kawałka, niski na początku następnego) — Firestore odrzuca wtedy
/// zapis z `invalid-argument` i auto-backup pada każdego dnia po cichu.
/// Sklejenie kawałków w kolejności odtwarza payload 1:1.
List<String> splitBackupPayloadIntoChunks(
  String payload, {
  int maxChunkChars = 400000,
}) {
  if (payload.isEmpty) return <String>[''];
  final List<String> chunks = <String>[];
  int start = 0;
  while (start < payload.length) {
    int end = min(start + maxChunkChars, payload.length);
    // Nie kończ kawałka surogatem wysokim — przesuń granicę o 1 w lewo,
    // żeby cała para (emoji) trafiła do następnego kawałka.
    if (end < payload.length) {
      final int last = payload.codeUnitAt(end - 1);
      if (last >= 0xD800 && last <= 0xDBFF && end - 1 > start) {
        end -= 1;
      }
    }
    chunks.add(payload.substring(start, end));
    start = end;
  }
  return chunks;
}
