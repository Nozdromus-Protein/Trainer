// Wydzielona część biblioteki `main.dart` (dyrektywa `part of`).
//
// ZAŁĄCZNIKI DO ROZMOWY Z AI TRAINEREM — zdjęcia (galeria/aparat) i pliki
// tekstowe. Bliźniacza implementacja żyje w Liczniku Kalorii (Dietetyk AI);
// kontrakt JSON do backendu jest wspólny, żeby oba backendy czytały to samo.
//
// Zasady, które łatwo złamać:
//  * Do backendu leci PEŁNA treść (base64 obrazu / tekst pliku), ale do
//    historii rozmowy w SharedPreferences zapisujemy TYLKO metadane —
//    inaczej kilka zdjęć rozsadziłoby zapis i kopię zapasową.
//  * Obrazy skalujemy przy wyborze: model nie potrzebuje pełnej klatki,
//    a base64 z 12 Mpix przekracza rozsądny rozmiar żądania.
part of 'main.dart';

/// Maksymalny rozmiar pojedynczego załącznika przyjmowany z dysku.
const int kAiAttachmentMaxBytes = 6 * 1024 * 1024;

/// Ile znaków pliku tekstowego trafia do modelu (dłuższe tniemy z adnotacją).
const int kAiAttachmentMaxTextChars = 40000;

/// Rozszerzenia plików tekstowych oferowane w wyborze.
const List<String> kAiTextAttachmentExtensions = <String>[
  'txt',
  'md',
  'csv',
  'json',
  'log',
  'yaml',
  'yml',
  'xml',
  'html',
];

/// Pojedynczy załącznik rozmowy. `kind` to 'image' albo 'text'.
class AiChatAttachment {
  const AiChatAttachment({
    required this.name,
    required this.mimeType,
    required this.kind,
    this.base64Data = '',
    this.text = '',
    this.sizeBytes = 0,
    this.localPath = '',
  });

  final String name;
  final String mimeType;
  final String kind;

  /// Obraz w base64 (bez prefiksu `data:`). Puste dla plików tekstowych.
  final String base64Data;

  /// Treść pliku tekstowego. Pusta dla obrazów.
  final String text;

  final int sizeBytes;

  /// Ścieżka lokalna — pozwala pokazać miniaturę bez trzymania bajtów.
  final String localPath;

  bool get isImage => kind == 'image';

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).round()} kB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Pełny ładunek dla backendu.
  Map<String, dynamic> toApiJson() => {
        'name': name,
        'mime': mimeType,
        'kind': kind,
        if (base64Data.isNotEmpty) 'data_base64': base64Data,
        if (text.isNotEmpty) 'text': text,
        'size_bytes': sizeBytes,
      };

  /// Lekki zapis do historii rozmowy (bez ładunku).
  Map<String, dynamic> toHistoryJson() => {
        'name': name,
        'mime': mimeType,
        'kind': kind,
        'size_bytes': sizeBytes,
        if (localPath.isNotEmpty) 'path': localPath,
      };

  factory AiChatAttachment.fromHistoryJson(Map<String, dynamic> json) =>
      AiChatAttachment(
        name: json['name']?.toString() ?? 'załącznik',
        mimeType: json['mime']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'text',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        localPath: json['path']?.toString() ?? '',
      );
}

/// Typ MIME zgadywany z rozszerzenia — backend potrzebuje go przy obrazach.
String aiAttachmentMimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.csv')) return 'text/csv';
  if (lower.endsWith('.html') || lower.endsWith('.xml')) return 'text/html';
  return 'text/plain';
}

/// Wczytuje obraz z dysku do postaci gotowej do wysyłki.
Future<AiChatAttachment?> aiAttachmentFromImageFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  if (bytes.lengthInBytes > kAiAttachmentMaxBytes) return null;
  final name = path.split(Platform.pathSeparator).last.split('/').last;
  return AiChatAttachment(
    name: name.isEmpty ? 'zdjecie.jpg' : name,
    mimeType: aiAttachmentMimeFromName(name),
    kind: 'image',
    base64Data: base64Encode(bytes),
    sizeBytes: bytes.lengthInBytes,
    localPath: path,
  );
}

/// Wczytuje plik tekstowy. Zbyt długie pliki tnie z adnotacją.
Future<AiChatAttachment?> aiAttachmentFromTextFile(
    String path, String displayName) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  if (bytes.lengthInBytes > kAiAttachmentMaxBytes) return null;
  String content;
  try {
    content = utf8.decode(bytes);
  } catch (_) {
    content = latin1.decode(bytes);
  }
  if (content.length > kAiAttachmentMaxTextChars) {
    content = '${content.substring(0, kAiAttachmentMaxTextChars)}\n'
        '[...] (plik przycięty — pokazano pierwsze '
        '$kAiAttachmentMaxTextChars znaków)';
  }
  return AiChatAttachment(
    name: displayName.isEmpty ? 'plik.txt' : displayName,
    mimeType: aiAttachmentMimeFromName(displayName),
    kind: 'text',
    text: content,
    sizeBytes: bytes.lengthInBytes,
    localPath: path,
  );
}

/// Arkusz wyboru źródła załącznika. Pusta lista = rezygnacja.
Future<List<AiChatAttachment>> pickAiChatAttachments(
    BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('ai_attachment_gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Zdjęcia z galerii'),
            subtitle: const Text('Możesz wybrać kilka naraz.'),
            onTap: () => Navigator.pop(sheetContext, 'gallery'),
          ),
          ListTile(
            key: const Key('ai_attachment_camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Zrób zdjęcie'),
            onTap: () => Navigator.pop(sheetContext, 'camera'),
          ),
          ListTile(
            key: const Key('ai_attachment_file'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Plik tekstowy'),
            subtitle: Text(
                kAiTextAttachmentExtensions.map((ext) => '.$ext').join(' · ')),
            onTap: () => Navigator.pop(sheetContext, 'text'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return const <AiChatAttachment>[];

  final picked = <AiChatAttachment>[];
  try {
    if (source == 'gallery' || source == 'camera') {
      final picker = ImagePicker();
      if (source == 'camera') {
        final shot = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 82,
        );
        if (shot != null) {
          final item = await aiAttachmentFromImageFile(shot.path);
          if (item != null) picked.add(item);
        }
      } else {
        final shots =
            await picker.pickMultiImage(maxWidth: 1600, imageQuality: 82);
        for (final shot in shots) {
          final item = await aiAttachmentFromImageFile(shot.path);
          if (item != null) picked.add(item);
        }
      }
    } else if (source == 'text') {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: kAiTextAttachmentExtensions,
        withData: false,
      );
      for (final file in result?.files ?? const <PlatformFile>[]) {
        final path = file.path;
        if (path == null) continue;
        final item = await aiAttachmentFromTextFile(path, file.name);
        if (item != null) picked.add(item);
      }
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nie udało się wczytać załącznika: $error')),
      );
    }
    return const <AiChatAttachment>[];
  }

  if (picked.isEmpty && context.mounted && source != 'camera') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Nie dodano załącznika. Limit pojedynczego pliku to 6 MB.'),
      ),
    );
  }
  return picked;
}

/// Pasek załączników czekających na wysyłkę — z możliwością usunięcia.
class AiAttachmentTray extends StatelessWidget {
  const AiAttachmentTray({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<AiChatAttachment> attachments;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < attachments.length; i++)
            InputChip(
              key: Key('ai_attachment_chip_$i'),
              avatar: Icon(
                attachments[i].isImage
                    ? Icons.image_outlined
                    : Icons.description_outlined,
                size: 18,
              ),
              label: Text(
                attachments[i].sizeLabel.isEmpty
                    ? attachments[i].name
                    : '${attachments[i].name} • ${attachments[i].sizeLabel}',
                overflow: TextOverflow.ellipsis,
              ),
              onDeleted: () => onRemove(i),
            ),
        ],
      ),
    );
  }
}

/// Plakietki załączników w dymku rozmowy (historia zna tylko metadane).
class AiAttachmentBadges extends StatelessWidget {
  const AiAttachmentBadges({
    super.key,
    required this.attachments,
    required this.textColor,
  });

  final List<AiChatAttachment> attachments;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in attachments)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.isImage
                        ? Icons.image_outlined
                        : Icons.description_outlined,
                    size: 14,
                    color: textColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
