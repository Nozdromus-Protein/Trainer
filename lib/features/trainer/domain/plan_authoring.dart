/// Metadane POCHODZENIA zestawu treningowego (czysty Dart).
///
/// Etap: „Własne zestawy — ręcznie / z pomocą AI / w całości przez AI".
///
/// Model odpowiada na pytanie „skąd wziął się ten zestaw": czy użytkownik
/// ułożył go sam, czy AI tylko pomogło w wybranych miejscach, czy całość
/// wygenerowała AI. Zapisujemy też zakres pomocy AI, znaczniki czasu,
/// ulubione/archiwum i ślad rozmowy, z której zestaw powstał.
///
/// ZGODNOŚĆ WSTECZNA: starsze zapisy planów nie mają pola `origin`. Wtedy
/// [PlanOrigin.legacy] oznacza je jako `legacy` — warstwa aplikacji dopiero
/// potem (znając katalog programów) rozstrzyga, czy to program systemowy, czy
/// zestaw ułożony ręcznie. Żadne istniejące dane nie są kasowane ani zmieniane.
library;

/// Sposób powstania zestawu.
enum PlanCreationMode {
  /// Zestaw ułożony w całości przez użytkownika.
  manual('manual', 'Ręczny', 'Utworzone ręcznie'),

  /// Użytkownik ułożył podstawę, AI pomogło w wybranych zakresach.
  manualWithAi('manualWithAi', 'AI wspomagane', 'Utworzone z pomocą AI'),

  /// Cały zestaw wygenerowany przez AI (użytkownik zatwierdził podgląd).
  fullyAiGenerated(
      'fullyAiGenerated', 'Wygenerowane przez AI', 'Wygenerowane przez AI'),

  /// Program wbudowany (katalog 30-dniowy, rozgrzewki, cardio, rozciąganie).
  systemProgram('systemProgram', 'Program', 'Programy 30-dniowe'),

  /// Zestaw wczytany z kopii/importu.
  imported('imported', 'Import', 'Zaimportowane'),

  /// Starszy zapis bez metadanych — do rozstrzygnięcia przez migrację.
  legacy('legacy', 'Starszy zestaw', 'Starsze zestawy');

  const PlanCreationMode(this.key, this.badgeLabel, this.categoryLabel);

  /// Stabilny klucz zapisu (nie zmieniać — trafia do JSON-a i chmury).
  final String key;

  /// Krótka etykieta na chip/kafelek.
  final String badgeLabel;

  /// Nazwa kategorii na liście zestawów.
  final String categoryLabel;

  bool get isAiInvolved =>
      this == PlanCreationMode.manualWithAi ||
      this == PlanCreationMode.fullyAiGenerated;

  static PlanCreationMode fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final mode in PlanCreationMode.values) {
      if (mode.key == normalized || mode.name == normalized) return mode;
    }
    return PlanCreationMode.legacy;
  }
}

/// Pojedynczy zakres, w którym użytkownik pozwala AI pomóc.
///
/// Użytkownik zaznacza dowolny podzbiór — AI wolno ruszać WYŁĄCZNIE zaznaczone
/// obszary. Nic poza tą listą nie jest dla AI otwarte.
enum AiAssistanceScope {
  fillMissingExercises('fillMissingExercises', 'Uzupełnij brakujące ćwiczenia'),
  fillMissingDays('fillMissingDays', 'Uzupełnij brakujące dni'),
  weekSplit('weekSplit', 'Zaproponuj podział tygodnia'),
  exerciseOrder('exerciseOrder', 'Ustaw kolejność ćwiczeń'),
  setsAndReps('setsAndReps', 'Dopasuj serie i powtórzenia'),
  weight('weight', 'Dopasuj ciężar'),
  rest('rest', 'Dopasuj przerwy'),
  warmup('warmup', 'Dodaj rozgrzewkę'),
  cooldown('cooldown', 'Dodaj schłodzenie'),
  mobility('mobility', 'Dodaj mobilność'),
  cardio('cardio', 'Dodaj cardio'),
  accessoryExercises('accessoryExercises', 'Uzupełnij ćwiczenia pomocnicze'),
  muscleBalance('muscleBalance', 'Wyrównaj trenowane partie'),
  movementPatterns('movementPatterns', 'Wykryj brakujące wzorce ruchowe'),
  recoveryCheck('recoveryCheck', 'Sprawdź kolizje z regeneracją'),
  equipmentCheck('equipmentCheck', 'Sprawdź zgodność ze sprzętem'),
  limitationCheck('limitationCheck', 'Sprawdź ograniczenia'),
  weeklyVolume('weeklyVolume', 'Sprawdź objętość tygodnia'),
  progression('progression', 'Zaproponuj bezpieczną progresję'),
  removeRedundant('removeRedundant', 'Usuń zbędne ćwiczenia'),
  substitutions('substitutions', 'Zaproponuj zamienniki'),
  timeFit('timeFit', 'Dopasuj do dostępnego czasu');

  const AiAssistanceScope(this.key, this.label);

  final String key;
  final String label;

  static AiAssistanceScope? fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final scope in AiAssistanceScope.values) {
      if (scope.key == normalized || scope.name == normalized) return scope;
    }
    return null;
  }

  static Set<AiAssistanceScope> setFromJson(Object? value) {
    if (value is! List) return const <AiAssistanceScope>{};
    final result = <AiAssistanceScope>{};
    for (final item in value) {
      final scope = AiAssistanceScope.fromKey(item);
      if (scope != null) result.add(scope);
    }
    return result;
  }
}

/// Zakresy oznaczone jako „bezpieczne" — zmiany, które nie usuwają ćwiczeń
/// wybranych przez użytkownika i nie zmieniają charakteru zestawu.
/// Używane przez przycisk „Zastosuj wszystkie bezpieczne zmiany".
const Set<AiAssistanceScope> kSafeAiAssistanceScopes = <AiAssistanceScope>{
  AiAssistanceScope.setsAndReps,
  AiAssistanceScope.rest,
  AiAssistanceScope.weight,
  AiAssistanceScope.exerciseOrder,
  AiAssistanceScope.warmup,
  AiAssistanceScope.cooldown,
  AiAssistanceScope.mobility,
  AiAssistanceScope.progression,
};

/// Skąd fizycznie wziął się zestaw albo ćwiczenie.
enum PlanSourceType {
  manual('manual', 'Utworzone ręcznie'),
  wizard('wizard', 'Kreator zestawu'),
  aiChat('aiChat', 'Rozmowa z Trenerem AI'),
  aiAnalysis('aiAnalysis', 'Analiza AI zestawu'),
  catalog('catalog', 'Katalog programów'),
  import('import', 'Import / kopia');

  const PlanSourceType(this.key, this.label);

  final String key;
  final String label;

  static PlanSourceType fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final type in PlanSourceType.values) {
      if (type.key == normalized || type.name == normalized) return type;
    }
    return PlanSourceType.manual;
  }
}

/// Komplet metadanych pochodzenia i stanu zestawu.
///
/// Wszystkie pola mają bezpieczne wartości domyślne — model da się dołożyć do
/// istniejącego planu bez migracji danych użytkownika.
class PlanOrigin {
  const PlanOrigin({
    this.creationMode = PlanCreationMode.manual,
    this.aiAssistanceScopes = const <AiAssistanceScope>{},
    this.sourceType = PlanSourceType.manual,
    this.createdAt,
    this.updatedAt,
    this.createdByUserId = '',
    this.sourceConversationId = '',
    this.sourceMessageId = '',
    this.sourceAiRecommendationId = '',
    this.version = 1,
    this.isFavorite = false,
    this.isArchived = false,
    this.lastUsedAt,
    this.basePlanId = '',
    this.basePlanName = '',
    this.analyzedAt,
    this.analysisProfileSummary = '',
    this.aiEngine = '',
    this.acceptedByUser = true,
  });

  final PlanCreationMode creationMode;

  /// Zakresy, w których użytkownik dopuścił pomoc AI (tryb „ręcznie z AI").
  final Set<AiAssistanceScope> aiAssistanceScopes;

  final PlanSourceType sourceType;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdByUserId;

  /// Ślad rozmowy z Trenerem AI, z której powstał zestaw (pozwala do niej wrócić).
  final String sourceConversationId;
  final String sourceMessageId;
  final String sourceAiRecommendationId;

  /// Numer wersji zestawu — rośnie przy każdej większej analizie/zmianie AI.
  final int version;

  final bool isFavorite;
  final bool isArchived;
  final DateTime? lastUsedAt;

  /// Dla spersonalizowanych wariantów: z jakiego zestawu bazowego powstał.
  final String basePlanId;
  final String basePlanName;

  /// Kiedy zestaw przeszedł analizę AI i na jakim profilu.
  final DateTime? analyzedAt;
  final String analysisProfileSummary;

  /// Nazwa silnika AI, który zestaw utworzył/przeanalizował (np. „Trener AI").
  final String aiEngine;

  /// Czy użytkownik świadomie zatwierdził propozycję AI (spec: punkt 16/17).
  final bool acceptedByUser;

  bool get createdManually => creationMode == PlanCreationMode.manual;
  bool get aiAssisted => creationMode == PlanCreationMode.manualWithAi;
  bool get aiGenerated => creationMode == PlanCreationMode.fullyAiGenerated;
  bool get isSystemProgram => creationMode == PlanCreationMode.systemProgram;

  /// Czy zestaw jest spersonalizowanym wariantem czegoś innego.
  bool get isPersonalizedVariant => basePlanId.trim().isNotEmpty;

  PlanOrigin copyWith({
    PlanCreationMode? creationMode,
    Set<AiAssistanceScope>? aiAssistanceScopes,
    PlanSourceType? sourceType,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdByUserId,
    String? sourceConversationId,
    String? sourceMessageId,
    String? sourceAiRecommendationId,
    int? version,
    bool? isFavorite,
    bool? isArchived,
    DateTime? lastUsedAt,
    String? basePlanId,
    String? basePlanName,
    DateTime? analyzedAt,
    String? analysisProfileSummary,
    String? aiEngine,
    bool? acceptedByUser,
  }) {
    return PlanOrigin(
      creationMode: creationMode ?? this.creationMode,
      aiAssistanceScopes: aiAssistanceScopes ?? this.aiAssistanceScopes,
      sourceType: sourceType ?? this.sourceType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      sourceConversationId: sourceConversationId ?? this.sourceConversationId,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      sourceAiRecommendationId:
          sourceAiRecommendationId ?? this.sourceAiRecommendationId,
      version: version ?? this.version,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      basePlanId: basePlanId ?? this.basePlanId,
      basePlanName: basePlanName ?? this.basePlanName,
      analyzedAt: analyzedAt ?? this.analyzedAt,
      analysisProfileSummary:
          analysisProfileSummary ?? this.analysisProfileSummary,
      aiEngine: aiEngine ?? this.aiEngine,
      acceptedByUser: acceptedByUser ?? this.acceptedByUser,
    );
  }

  /// Metadane dla starszych zapisów (brak pola `origin` w JSON-ie).
  static PlanOrigin legacy() =>
      const PlanOrigin(creationMode: PlanCreationMode.legacy);

  Map<String, dynamic> toJson() => {
        'creationMode': creationMode.key,
        if (aiAssistanceScopes.isNotEmpty)
          'aiAssistanceScopes': (aiAssistanceScopes.map((s) => s.key).toList()
            ..sort()),
        'sourceType': sourceType.key,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (createdByUserId.isNotEmpty) 'createdByUserId': createdByUserId,
        if (sourceConversationId.isNotEmpty)
          'sourceConversationId': sourceConversationId,
        if (sourceMessageId.isNotEmpty) 'sourceMessageId': sourceMessageId,
        if (sourceAiRecommendationId.isNotEmpty)
          'sourceAiRecommendationId': sourceAiRecommendationId,
        'version': version,
        if (isFavorite) 'isFavorite': true,
        if (isArchived) 'isArchived': true,
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
        if (basePlanId.isNotEmpty) 'basePlanId': basePlanId,
        if (basePlanName.isNotEmpty) 'basePlanName': basePlanName,
        if (analyzedAt != null) 'analyzedAt': analyzedAt!.toIso8601String(),
        if (analysisProfileSummary.isNotEmpty)
          'analysisProfileSummary': analysisProfileSummary,
        if (aiEngine.isNotEmpty) 'aiEngine': aiEngine,
        if (!acceptedByUser) 'acceptedByUser': false,
      };

  factory PlanOrigin.fromJson(Map<String, dynamic> json) => PlanOrigin(
        creationMode: PlanCreationMode.fromKey(json['creationMode']),
        aiAssistanceScopes:
            AiAssistanceScope.setFromJson(json['aiAssistanceScopes']),
        sourceType: PlanSourceType.fromKey(json['sourceType']),
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        createdByUserId: json['createdByUserId']?.toString() ?? '',
        sourceConversationId: json['sourceConversationId']?.toString() ?? '',
        sourceMessageId: json['sourceMessageId']?.toString() ?? '',
        sourceAiRecommendationId:
            json['sourceAiRecommendationId']?.toString() ?? '',
        version: (json['version'] as num?)?.toInt() ?? 1,
        isFavorite: json['isFavorite'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
        lastUsedAt: _date(json['lastUsedAt']),
        basePlanId: json['basePlanId']?.toString() ?? '',
        basePlanName: json['basePlanName']?.toString() ?? '',
        analyzedAt: _date(json['analyzedAt']),
        analysisProfileSummary:
            json['analysisProfileSummary']?.toString() ?? '',
        aiEngine: json['aiEngine']?.toString() ?? '',
        acceptedByUser: json['acceptedByUser'] as bool? ?? true,
      );
}

/// Migawka zestawu przed większą zmianą — podstawa wersjonowania i cofania.
///
/// Trzymamy pełny JSON planu, więc przywrócenie wersji odtwarza dokładnie ten
/// sam układ dni i ćwiczeń. Ukończone dni i historia treningów NIE są częścią
/// migawki treści (patrz `restorePlanVersion` w warstwie aplikacji).
class PlanVersionSnapshot {
  const PlanVersionSnapshot({
    required this.version,
    required this.label,
    required this.createdAt,
    required this.planJson,
    this.reason = '',
  });

  final int version;

  /// Krótki opis wersji, np. „dopasowanie do sprzętu".
  final String label;
  final DateTime createdAt;

  /// Pełny zapis planu (`WorkoutPlan.toJson`) sprzed zmiany.
  final Map<String, dynamic> planJson;

  /// Dłuższe uzasadnienie (np. lista zaakceptowanych zmian).
  final String reason;

  Map<String, dynamic> toJson() => {
        'version': version,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        'planJson': planJson,
        if (reason.isNotEmpty) 'reason': reason,
      };

  static PlanVersionSnapshot? fromJson(Map<String, dynamic> json) {
    final raw = json['planJson'];
    if (raw is! Map) return null;
    return PlanVersionSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 1,
      label: json['label']?.toString() ?? 'Wersja',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      planJson: Map<String, dynamic>.from(raw),
      reason: json['reason']?.toString() ?? '',
    );
  }
}

DateTime? _date(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}
