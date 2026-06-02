import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../shared/shared_models.dart';
import '../../shared/theme.dart';
import '../data/api_client.dart';

// === 1. Server URL Notifier ===
class ServerUrlNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? url) => state = url;
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String?>(
  ServerUrlNotifier.new,
);

// === 2. Password Notifier ===
class PasswordNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? pass) => state = pass;
}

final passwordProvider = NotifierProvider<PasswordNotifier, String?>(
  PasswordNotifier.new,
);

// === 3. Connection Status Notifier ===
class ConnectionNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool isConnected) => state = isConnected;
}

final isConnectedProvider = NotifierProvider<ConnectionNotifier, bool>(
  ConnectionNotifier.new,
);

// === 4. Sims List Notifier ===
class SimsNotifier extends Notifier<List<SimCardDto>> {
  @override
  List<SimCardDto> build() => [];
  void set(List<SimCardDto> sims) => state = sims;
}

final simsProvider = NotifierProvider<SimsNotifier, List<SimCardDto>>(
  SimsNotifier.new,
);

// === 5. Messages List Notifier ===
class MessagesNotifier extends Notifier<List<SmsMessageDto>> {
  @override
  List<SmsMessageDto> build() => [];

  void set(List<SmsMessageDto> messages) => state = messages;

  void add(SmsMessageDto msg) {
    state = [...state, msg];
  }
}

final allMessagesProvider =
    NotifierProvider<MessagesNotifier, List<SmsMessageDto>>(
      MessagesNotifier.new,
    );

// === 6. Selected Chat Notifier ===
class SelectedChatNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? phone) => state = phone;
}

final selectedChatIdProvider = NotifierProvider<SelectedChatNotifier, String?>(
  SelectedChatNotifier.new,
);

// === 7. Выбранная SIM ===
class SelectedSimNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final selectedSimProvider = NotifierProvider<SelectedSimNotifier, int?>(
  SelectedSimNotifier.new,
);

// === 8. ПОИСК ===
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => "";
  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

// === 9. СЧЕТЧИК НЕПРОЧИТАННЫХ (НОВОЕ) ===
class UnreadCountsNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => {};

  void increment(String phone) {
    final current = state[phone] ?? 0;
    state = {...state, phone: current + 1};
  }

  void clear(String phone) {
    if (!state.containsKey(phone)) return;
    final newState = Map<String, int>.from(state);
    newState.remove(phone);
    state = newState;
  }
}

final unreadCountsProvider =
    NotifierProvider<UnreadCountsNotifier, Map<String, int>>(
      UnreadCountsNotifier.new,
    );

// === 10. Paginated Chat Messages ===
class ChatMessagesNotifier extends ChangeNotifier {
  final String arg;
  final Ref ref;
  List<SmsMessageDto> _messages = [];
  bool _hasMore = true;
  bool _isLoading = false;
  int _offset = 0;
  static const int _limit = 30;

  ChatMessagesNotifier(this.ref, this.arg) {
    loadMore();
  }

  List<SmsMessageDto> get state => _messages;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Future<void> loadMore() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    final api = ref.read(apiClientProvider);
    if (api == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final newMsgs = await api.fetchMessages(
        limit: _limit,
        offset: _offset,
        address: arg,
      );

      if (newMsgs.length < _limit) {
        _hasMore = false;
      }

      _messages = [...newMsgs.reversed, ..._messages];
      _offset += newMsgs.length;
    } catch (e) {
      debugPrint("Error loading more messages: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addMessage(SmsMessageDto msg) {
    _messages = [..._messages, msg];
    notifyListeners();
  }
}

final chatMessagesProvider = Provider.family<ChatMessagesNotifier, String>(
  (ref, arg) => ChatMessagesNotifier(ref, arg),
);

// === 11. ШАБЛОНЫ (НОВОЕ) ===
class TemplatesNotifier extends Notifier<List<SmsTemplateDto>> {
  @override
  List<SmsTemplateDto> build() {
    load();
    return [];
  }

  Future<void> load() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    try {
      state = await api.fetchTemplates();
    } catch (e) {
      debugPrint("Error loading templates: $e");
    }
  }

  Future<void> save(SmsTemplateDto template) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.saveTemplate(template);
    await load();
  }

  Future<void> delete(String id) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.deleteTemplate(id);
    await load();
  }
}

final templatesProvider =
    NotifierProvider<TemplatesNotifier, List<SmsTemplateDto>>(
      TemplatesNotifier.new,
    );

// === 14. КОНТАКТЫ (НОВОЕ) ===
class ContactsNotifier extends Notifier<List<ContactDto>> {
  @override
  List<ContactDto> build() {
    return [];
  }

  Future<void> load() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    try {
      state = await api.fetchContacts();
    } catch (e) {
      debugPrint("Error loading contacts: $e");
    }
  }

  Future<void> save(ContactDto contact) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.saveContact(contact);
    await load();
  }

  Future<void> delete(String phone) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.deleteContact(phone);
    await load();
  }
}

final contactsProvider =
    NotifierProvider<ContactsNotifier, List<ContactDto>>(
      ContactsNotifier.new,
    );

// === 12. SMS БИЛЛИНГ И СЕГМЕНТАЦИЯ ===
class SmsBillingInfo {
  final int charCount;
  final int segmentCount;
  final int remainingChars;
  final int maxCharsPerSegment;
  final bool isUnicode;

  SmsBillingInfo({
    required this.charCount,
    required this.segmentCount,
    required this.remainingChars,
    required this.maxCharsPerSegment,
    required this.isUnicode,
  });
}

final smsBillingProvider = Provider.family<SmsBillingInfo, String>((ref, text) {
  if (text.isEmpty) {
    return SmsBillingInfo(
      charCount: 0,
      segmentCount: 0,
      remainingChars: 0,
      maxCharsPerSegment: 0,
      isUnicode: false,
    );
  }

  bool isUnicode = false;
  for (int i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) > 127) {
      isUnicode = true;
      break;
    }
  }

  final charCount = text.length;
  final int maxCharsPerSegment;
  final int segmentCount;
  final int remainingChars;

  if (isUnicode) {
    if (charCount <= 70) {
      maxCharsPerSegment = 70;
      segmentCount = 1;
      remainingChars = 70 - charCount;
    } else {
      maxCharsPerSegment = 67;
      segmentCount = (charCount / 67).ceil();
      remainingChars = (segmentCount * 67) - charCount;
    }
  } else {
    if (charCount <= 160) {
      maxCharsPerSegment = 160;
      segmentCount = 1;
      remainingChars = 160 - charCount;
    } else {
      maxCharsPerSegment = 153;
      segmentCount = (charCount / 153).ceil();
      remainingChars = (segmentCount * 153) - charCount;
    }
  }

  return SmsBillingInfo(
    charCount: charCount,
    segmentCount: segmentCount,
    remainingChars: remainingChars,
    maxCharsPerSegment: maxCharsPerSegment,
    isUnicode: isUnicode,
  );
});

// === 13. АВТОПРОВЕРКА ТЕКСТА (Улучшенная) ===
class ValidationIssue {
  final String message;
  final int start;
  final int end;
  final String? suggestion;
  final bool isSpamTrigger;

  ValidationIssue(
    this.message,
    this.start,
    this.end, {
    this.suggestion,
    this.isSpamTrigger = false,
  });
}

// Состояние для временного и постоянного игнорирования ошибок
class IgnoredIssuesState {
  final Set<String>
  ignoredAlwaysWords; // Содержит слова (например, "кредит"), которые игнорируются всегда
  final Set<String>
  ignoredNowSignatures; // Содержит временные уникальные сигнатуры ошибок на текущую сессию

  IgnoredIssuesState({
    required this.ignoredAlwaysWords,
    required this.ignoredNowSignatures,
  });

  IgnoredIssuesState copyWith({
    Set<String>? ignoredAlwaysWords,
    Set<String>? ignoredNowSignatures,
  }) {
    return IgnoredIssuesState(
      ignoredAlwaysWords: ignoredAlwaysWords ?? this.ignoredAlwaysWords,
      ignoredNowSignatures: ignoredNowSignatures ?? this.ignoredNowSignatures,
    );
  }
}

class IgnoredIssuesNotifier extends Notifier<IgnoredIssuesState> {
  @override
  IgnoredIssuesState build() =>
      IgnoredIssuesState(ignoredAlwaysWords: {}, ignoredNowSignatures: {});

  // Скрытие ошибки только для текущей сессии ввода
  void ignoreNow(String signature) {
    state = state.copyWith(
      ignoredNowSignatures: {...state.ignoredNowSignatures, signature},
    );
  }

  // Постоянное скрытие спам-триггера или конкретного слова
  void ignoreAlways(String word) {
    state = state.copyWith(
      ignoredAlwaysWords: {
        ...state.ignoredAlwaysWords,
        word.toLowerCase().trim(),
      },
    );
  }

  // Сброс временных скрытий (например, при переключении чата или отправке)
  void resetNow() {
    state = state.copyWith(ignoredNowSignatures: {});
  }
}

final ignoredIssuesProvider =
    NotifierProvider<IgnoredIssuesNotifier, IgnoredIssuesState>(
      IgnoredIssuesNotifier.new,
    );

const _abbreviationExceptions = {
  // Валюты и деньги
  'руб', 'коп', 'тыс', 'млн', 'млрд', 'долл', 'евро',
  // Адреса
  'ул', 'кв', 'обл', 'г', 'д', 'стр', 'корп', 'пр', 'просп', 'пер', 'пл', 'ш',
  // Время и даты
  'сек', 'мин', 'ч', 'мес', 'гг',
  // Ссылки и сравнения
  'см', 'ср', 'табл', 'рис', 'п', 'ст', 'вып', 'изд', 'т',
  // Другие сокращения
  'и', 'е', 'о', 'а', 'б', 'в', 'н', 'э',
  // Английские сокращения
  'etc',
  'eg',
  'ie',
  'mr',
  'mrs',
  'ms',
  'dr',
  'vs',
  'dept',
  'univ',
  'co',
  'ltd',
  'inc',
};

const _spamTriggerWords = {
  'кредит': 'вместо "кредит" попробуйте "рассрочка" или "оплата частями"',
  'займ': 'вместо "займ" попробуйте "договор" или "оплата частями"',
  'бесплатно': 'вместо "бесплатно" попробуйте "без дополнительной оплаты"',
  'выиграй': 'слова про розыгрыши часто блокируются операторами спам-фильтров',
  'выигрыш': 'слова про розыгрыши часто блокируются операторами спам-фильтров',
  'акция': 'вместо "акция" попробуйте "специальное предложение"',
  'скидка': 'вместо "скидка" попробуйте "персональная цена" или "дисконт"',
  'срочно': 'сообщения с призывом к срочности часто блокируются как спам',
  'подарок': 'вместо "подарок" попробуйте "бонус" или "поощрение"',
  'миллион': 'слова с обещаниями богатства блокируются спам-фильтрами',
  'доход': 'слова с обещаниями дохода блокируются спам-фильтрами',
};

bool _isWordChar(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 97 && code <= 122) || // a-z
      (code >= 65 && code <= 90) || // A-Z
      (code >= 48 && code <= 57) || // 0-9
      (code >= 1040 && code <= 1103) || // А-Я, а-я
      char == 'ё' ||
      char == 'Ё';
}

// Пунктуация и регистр (мгновенно) с учетом правил игнорирования
final textValidationProvider = Provider.family<List<ValidationIssue>, String>((
  ref,
  text,
) {
  if (text.isEmpty) return [];
  final issues = <ValidationIssue>[];

  // 1. Двойные пробелы
  final doubleSpaceRegex = RegExp(r' {2,}');
  for (var match in doubleSpaceRegex.allMatches(text)) {
    issues.add(
      ValidationIssue(
        "Лишние пробелы",
        match.start,
        match.end,
        suggestion: " ",
      ),
    );
  }

  // 2. Начало предложения с маленькой буквы
  final sentenceStartRegex = RegExp(r'(^|[.!?]\s+)([a-zа-яё])');
  for (var match in sentenceStartRegex.allMatches(text)) {
    final charIndex = match.end - 1;
    final char = text[charIndex];
    if (char == char.toLowerCase() && char != char.toUpperCase()) {
      // Исключаем аббревиатуры перед точкой
      final prefix = match.group(1) ?? '';
      final dotIndex = prefix.lastIndexOf('.');
      if (dotIndex != -1) {
        final absDotPos = match.start + dotIndex;
        int wordStart = absDotPos - 1;
        while (wordStart >= 0 && _isWordChar(text[wordStart])) {
          wordStart--;
        }
        wordStart++;
        if (wordStart < absDotPos) {
          final precedingWord = text
              .substring(wordStart, absDotPos)
              .toLowerCase()
              .trim();
          if (_abbreviationExceptions.contains(precedingWord)) {
            continue;
          }
        }
      }

      issues.add(
        ValidationIssue(
          "Начало предложения с заглавной",
          charIndex,
          charIndex + 1,
          suggestion: char.toUpperCase(),
        ),
      );
    }
  }

  // 3. Пробел перед знаком препинания
  final spaceBeforePunctuation = RegExp(r'\s+([,.!?;:])');
  for (var match in spaceBeforePunctuation.allMatches(text)) {
    issues.add(
      ValidationIssue(
        "Пробел перед знаком препинания",
        match.start,
        match.end - 1,
        suggestion: "",
      ),
    );
  }

  // 4. Поиск спам-триггеров
  _spamTriggerWords.forEach((trigger, hint) {
    final regex = RegExp(
      '(?:^|[^a-zA-Z0-9а-яА-ЯёЁ])($trigger[a-zA-Z0-9а-яА-ЯёЁ]*)(?:\$|[^a-zA-Z0-9а-яА-ЯёЁ])',
      caseSensitive: false,
    );
    for (var match in regex.allMatches(text)) {
      final matchedWord = match.group(1);
      if (matchedWord != null) {
        final matchIndex = match.start + match.group(0)!.indexOf(matchedWord);
        issues.add(
          ValidationIssue(
            "Подозрение на спам: слово '$matchedWord'. $hint",
            matchIndex,
            matchIndex + matchedWord.length,
            suggestion: null,
            isSpamTrigger: true,
          ),
        );
      }
    }
  });

  // === Фильтрация по списку проигнорированных ошибок ===
  final ignoredState = ref.watch(ignoredIssuesProvider);
  final filteredIssues = <ValidationIssue>[];

  for (var issue in issues) {
    final word = (issue.start >= 0 && issue.end <= text.length)
        ? text.substring(issue.start, issue.end)
        : "";

    final signature = "${issue.message}:$word";

    // А. Проверка на временный игнор ("игнорировать сейчас")
    if (ignoredState.ignoredNowSignatures.contains(signature)) {
      continue;
    }

    // Б. Проверка на постоянный игнор ("игнорировать всегда")
    bool isIgnoredAlways = false;
    final lowerWord = word.toLowerCase().trim();
    for (var ignoredWord in ignoredState.ignoredAlwaysWords) {
      if (lowerWord == ignoredWord ||
          (issue.isSpamTrigger && lowerWord.contains(ignoredWord))) {
        isIgnoredAlways = true;
        break;
      }
    }

    if (isIgnoredAlways) {
      continue;
    }

    filteredIssues.add(issue);
  }

  return filteredIssues;
});

// === COMPUTED PROVIDERS ===

final apiClientProvider = Provider<ApiClient?>((ref) {
  final url = ref.watch(serverUrlProvider);
  final pass = ref.watch(passwordProvider);
  if (url != null && pass != null) {
    return ApiClient(url, pass);
  }
  return null;
});

// Базовая группировка сообщений по чатам
final threadsProvider = Provider<Map<String, List<SmsMessageDto>>>((ref) {
  final messages = ref.watch(allMessagesProvider);
  final grouped = <String, List<SmsMessageDto>>{};
  for (var msg in messages) {
    if (!grouped.containsKey(msg.address)) grouped[msg.address] = [];
    grouped[msg.address]!.add(msg);
  }
  // Сортировка сообщений внутри чата по времени
  for (var k in grouped.keys) {
    grouped[k]!.sort((a, b) => a.date.compareTo(b.date));
  }
  return grouped;
});

// === ОТФИЛЬТРОВАННЫЕ ЧАТЫ (ДЛЯ ПОИСКА) ===
final filteredThreadsProvider = Provider<Map<String, List<SmsMessageDto>>>((
  ref,
) {
  final allThreads = ref.watch(threadsProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase().trim();
  final contacts = ref.watch(contactsProvider);

  if (query.isEmpty) {
    return allThreads;
  }

  final filtered = <String, List<SmsMessageDto>>{};

  for (var entry in allThreads.entries) {
    final phone = entry.key;
    final messages = entry.value;

    final contact = contacts.firstWhere(
      (c) => c.phone == phone,
      orElse: () => ContactDto(phone: phone, name: "", notes: ""),
    );
    bool matchName = contact.name.toLowerCase().contains(query);
    bool matchPhone = phone.toLowerCase().contains(query);
    bool matchBody = messages.any((m) => m.body.toLowerCase().contains(query));

    if (matchPhone || matchBody || matchName) {
      filtered[phone] = messages;
    }
  }
  return filtered;
});

// === SYNC LOGIC (FutureProvider) ===

final syncProvider = FutureProvider.autoDispose((ref) async {
  final api = ref.watch(apiClientProvider);
  if (api == null) return;

  final audioPlayer = AudioPlayer();
  StreamSubscription? wsSub;

  Future<void> connect() async {
    await wsSub?.cancel();
    try {
      final sims = await api.fetchSims();
      ref.read(simsProvider.notifier).set(sims);

      // Загружаем последние сообщения для формирования списка чатов
      final msgs = await api.fetchMessages(limit: 200);
      ref.read(allMessagesProvider.notifier).set(msgs);

      // Загружаем контакты
      await ref.read(contactsProvider.notifier).load();

      ref.read(isConnectedProvider.notifier).set(true);

      wsSub = api.connectWs().listen(
        (data) async {
          if (data['type'] == 'NEW_SMS') {
            final msg = SmsMessageDto.fromJson(data['data']);

            // Обновляем общий список (для сайдбара)
            ref.read(allMessagesProvider.notifier).add(msg);

            // Обновляем текущий открытый чат, если он совпадает
            final currentChat = ref.read(selectedChatIdProvider);
            if (currentChat == msg.address) {
              ref.read(chatMessagesProvider(msg.address)).addMessage(msg);
            }

            if (!msg.isSent) {
              if (currentChat != msg.address) {
                ref.read(unreadCountsProvider.notifier).increment(msg.address);
                try {
                  await SfxService.playReceived();
                } catch (_) {}
              }
            }
          }
        },
        onDone: () => ref.read(isConnectedProvider.notifier).set(false),
        onError: (_) => ref.read(isConnectedProvider.notifier).set(false),
      );
    } catch (e) {
      ref.read(isConnectedProvider.notifier).set(false);
    }
  }

  // Initial connect
  await connect();

  // Reconnection & Health check timer
  final healthTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
    final isConnected = ref.read(isConnectedProvider);
    try {
      await api.fetchSims();
      if (!isConnected) {
        // Если восстановили связь по HTTP, пробуем переподключить WS
        await connect();
      }
    } catch (e) {
      if (isConnected) ref.read(isConnectedProvider.notifier).set(false);
    }
  });

  ref.onDispose(() {
    healthTimer.cancel();
    wsSub?.cancel();
    audioPlayer.dispose();
  });
});
