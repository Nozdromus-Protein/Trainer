import 'package:flutter_test/flutter_test.dart';
import 'package:licznik_treningu/features/trainer/data/firebase_account_service.dart';

/// Testy bezpiecznego cięcia payloadu backupu na kawałki: granica kawałka NIE
/// może przeciąć pary zastępczej UTF-16 (emoji), inaczej Firestore odrzuca
/// zapis z `invalid-argument` i auto-backup pada każdego dnia po cichu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('splitBackupPayloadIntoChunks', () {
    test('sklejenie kawałków odtwarza payload 1:1', () {
      final String payload = '${'a' * 950}😀😀😀${'b' * 950}';
      final List<String> chunks =
          splitBackupPayloadIntoChunks(payload, maxChunkChars: 400);
      expect(chunks.join(), payload);
      for (final String c in chunks) {
        expect(c.length, lessThanOrEqualTo(400));
      }
    });

    test('granica kawałka nie przecina pary zastępczej (emoji)', () {
      // Surogat wysoki wypada DOKŁADNIE na ostatniej pozycji kawałka:
      // 'aaa…a😀' przy maxChunkChars ustawionym tak, żeby cięcie trafiło
      // w środek emoji bez korekty granicy.
      final String payload = '${'a' * 9}😀${'x' * 10}';
      final List<String> chunks =
          splitBackupPayloadIntoChunks(payload, maxChunkChars: 10);
      expect(chunks.join(), payload);
      for (final String chunk in chunks) {
        if (chunk.isEmpty) continue;
        final int first = chunk.codeUnitAt(0);
        final int last = chunk.codeUnitAt(chunk.length - 1);
        // Kawałek nie może zaczynać się surogatem niskim ani kończyć wysokim.
        expect(first >= 0xDC00 && first <= 0xDFFF, isFalse,
            reason: 'kawałek zaczyna się osieroconym surogatem niskim');
        expect(last >= 0xD800 && last <= 0xDBFF, isFalse,
            reason: 'kawałek kończy się osieroconym surogatem wysokim');
      }
    });

    test('pusty payload daje jeden pusty kawałek', () {
      expect(splitBackupPayloadIntoChunks(''), <String>['']);
    });
  });
}
