import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../shared/shared_models.dart';
import '../../shared/theme.dart';
import '../data/api_client.dart';
import '../utils/recipient_importer.dart';

ProviderContainer? globalContainer;

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

// === Helper: Reliable SMS Message Deduplication & Equality ===
bool isSameSmsMessage(SmsMessageDto a, SmsMessageDto b) {
  // 1. If both have database IDs, exact ID match is definitive
  if (a.id != null && b.id != null) {
    return a.id == b.id;
  }

  // 2. Direction must match (both outgoing or both incoming)
  if (a.isSent != b.isSent) {
    return false;
  }

  // 3. Normalized phone numbers must match
  if (!RecipientImporter.isSamePhone(a.address, b.address)) {
    return false;
  }

  // 4. Message text bodies must match
  if (a.body.trim() != b.body.trim()) {
    return false;
  }

  // 5. Timestamps within 25 seconds of each other (handles server/telephony clock delta)
  final timeDiff = (a.date - b.date).abs();
  return timeDiff <= 25000;
}

// === 5. Messages List Notifier ===
class MessagesNotifier extends Notifier<List<SmsMessageDto>> {
  @override
  List<SmsMessageDto> build() => [];

  void set(List<SmsMessageDto> messages) {
    // Preserve any optimistic / real-time WebSocket messages not yet present in fetched batch
    final merged = List<SmsMessageDto>.from(messages);
    for (var existing in state) {
      final exists = merged.any((m) => isSameSmsMessage(m, existing));
      if (!exists) {
        merged.add(existing);
      }
    }
    merged.sort((a, b) => a.date.compareTo(b.date));
    state = merged;
  }

  void add(SmsMessageDto msg) {
    final index = state.indexWhere((m) => isSameSmsMessage(m, msg));
    if (index != -1) {
      final existing = state[index];
      // If existing had no ID (optimistic/WS) and incoming has real DB ID, update in place
      if (existing.id == null && msg.id != null) {
        final updated = List<SmsMessageDto>.from(state);
        updated[index] = msg;
        state = updated;
      }
      return;
    }
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
  void select(String? phone) {
    if (phone == null || phone.isEmpty) {
      state = null;
    } else {
      final normalized = RecipientImporter.normalizePhone(phone);
      state = normalized.isNotEmpty ? normalized : phone;
    }
  }
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
    // 1. Pre-populate immediately with any known messages in allMessagesProvider for this phone
    final allKnown = ref.read(allMessagesProvider);
    final initial = allKnown
        .where((m) => RecipientImporter.isSamePhone(m.address, arg))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    _messages = initial;

    // 2. Fetch full history from server
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

      // Merge and deduplicate fetched messages
      final updatedList = List<SmsMessageDto>.from(_messages);
      for (var incoming in newMsgs) {
        final idx = updatedList.indexWhere((m) => isSameSmsMessage(m, incoming));
        if (idx != -1) {
          if (updatedList[idx].id == null && incoming.id != null) {
            updatedList[idx] = incoming;
          }
        } else {
          updatedList.add(incoming);
        }
      }
      updatedList.sort((a, b) => a.date.compareTo(b.date));
      _messages = updatedList;
      _offset += newMsgs.length;
    } catch (e) {
      debugPrint("Error loading more messages: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addMessage(SmsMessageDto msg) {
    if (!RecipientImporter.isSamePhone(arg, msg.address)) return;

    final index = _messages.indexWhere((m) => isSameSmsMessage(m, msg));
    if (index != -1) {
      final existing = _messages[index];
      if (existing.id == null && msg.id != null) {
        _messages[index] = msg;
        notifyListeners();
      }
      return;
    }
    _messages.add(msg);
    _messages.sort((a, b) => a.date.compareTo(b.date));
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

// === APP VIEW MODE ===
enum AppViewMode { chats, broadcast, callLog }

class ActiveViewNotifier extends Notifier<AppViewMode> {
  @override
  AppViewMode build() => AppViewMode.chats;
  void set(AppViewMode mode) => state = mode;
}

final activeViewModeProvider = NotifierProvider<ActiveViewNotifier, AppViewMode>(
  ActiveViewNotifier.new,
);

// === CAMPAIGNS NOTIFIER ===
class CampaignsNotifier extends Notifier<List<CampaignDto>> {
  @override
  List<CampaignDto> build() => [];

  void set(List<CampaignDto> list) => state = list;

  Future<void> load() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    try {
      state = await api.fetchCampaigns();
    } catch (e) {
      debugPrint("Error loading campaigns: $e");
    }
  }

  void addOrUpdate(CampaignDto campaign) {
    final index = state.indexWhere((c) => c.id == campaign.id);
    if (index != -1) {
      final updated = List<CampaignDto>.from(state);
      updated[index] = campaign;
      state = updated;
    } else {
      state = [campaign, ...state];
    }
  }

  void updateItem(String campaignId, CampaignItemDto item) {
    final cIndex = state.indexWhere((c) => c.id == campaignId);
    if (cIndex == -1) return;

    final campaign = state[cIndex];
    final itemIndex = campaign.items.indexWhere((i) => i.id == item.id);
    if (itemIndex == -1) return;

    final newItems = List<CampaignItemDto>.from(campaign.items);
    newItems[itemIndex] = item;

    final updatedCampaign = campaign.copyWith(
      items: newItems,
      sentCount: newItems.where((i) => i.status == 'sent').length,
      failedCount: newItems.where((i) => i.status == 'failed').length,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final updated = List<CampaignDto>.from(state);
    updated[cIndex] = updatedCampaign;
    state = updated;
  }

  Future<void> create(CampaignDto campaign) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.createCampaign(campaign);
    await load();
  }

  Future<void> start(String id) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.startCampaign(id);
    await load();
  }

  Future<void> pause(String id) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.pauseCampaign(id);
    await load();
  }

  Future<void> stop(String id) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.stopCampaign(id);
    await load();
  }

  Future<void> retryFailed(String id) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.retryFailedCampaign(id);
    await load();
  }

  Future<void> delete(String id) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.deleteCampaign(id);
    state = state.where((c) => c.id != id).toList();
  }
}

final campaignsProvider =
    NotifierProvider<CampaignsNotifier, List<CampaignDto>>(
      CampaignsNotifier.new,
    );

class SelectedCampaignNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedCampaignIdProvider =
    NotifierProvider<SelectedCampaignNotifier, String?>(
      SelectedCampaignNotifier.new,
    );

final activeCampaignProvider = Provider<CampaignDto?>((ref) {
  final selectedId = ref.watch(selectedCampaignIdProvider);
  final all = ref.watch(campaignsProvider);
  if (selectedId == null) return all.firstOrNull;
  try {
    return all.firstWhere((c) => c.id == selectedId);
  } catch (_) {
    return all.firstOrNull;
  }
});

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

  Future<void> clearCallback(ContactDto contact) async {
    final updated = ContactDto(
      phone: contact.phone,
      name: contact.name,
      notes: contact.notes,
      callbackTimeMs: null,
      callHistory: contact.callHistory,
    );
    await save(updated);
  }

  Future<void> logMissedCallback(ContactDto contact) async {
    final List<CallRecordDto> updatedHistory = List.from(contact.callHistory);
    final callbackTime = contact.callbackTimeMs ?? DateTime.now().millisecondsSinceEpoch;

    updatedHistory.add(CallRecordDto(
      timestamp: callbackTime,
      comment: "Пропущен запланированный перезвон",
      status: "пропущен",
    ));

    final updated = ContactDto(
      phone: contact.phone,
      name: contact.name,
      notes: contact.notes,
      callbackTimeMs: null,
      callHistory: updatedHistory,
    );
    await save(updated);
  }
}

final contactsProvider =
    NotifierProvider<ContactsNotifier, List<ContactDto>>(
      ContactsNotifier.new,
    );

// === 11b. ACTIVE CALL STATE & NOTIFIER ===
class ActiveCallState {
  final bool isInCall;
  final String? phoneNumber;
  final String? contactName;
  final int? startedAt;
  final int durationSeconds;
  final String callStatus; // 'OFFHOOK', 'RINGING', 'IDLE'
  final bool isIncoming;

  const ActiveCallState({
    this.isInCall = false,
    this.phoneNumber,
    this.contactName,
    this.startedAt,
    this.durationSeconds = 0,
    this.callStatus = 'IDLE',
    this.isIncoming = false,
  });

  ActiveCallState copyWith({
    bool? isInCall,
    String? phoneNumber,
    String? contactName,
    int? startedAt,
    int? durationSeconds,
    String? callStatus,
    bool? isIncoming,
  }) {
    return ActiveCallState(
      isInCall: isInCall ?? this.isInCall,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactName: contactName ?? this.contactName,
      startedAt: startedAt ?? this.startedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      callStatus: callStatus ?? this.callStatus,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }
}

class ActiveCallNotifier extends Notifier<ActiveCallState> {
  Timer? _ticker;

  @override
  ActiveCallState build() {
    ref.onDispose(() {
      _ticker?.cancel();
    });
    return const ActiveCallState();
  }

  void startCall(String phone, {String? contactName}) {
    _ticker?.cancel();
    String? resolvedName = contactName;
    if (resolvedName == null || resolvedName.isEmpty) {
      final contacts = ref.read(contactsProvider);
      for (var c in contacts) {
        if (RecipientImporter.isSamePhone(c.phone, phone)) {
          resolvedName = c.name;
          break;
        }
      }
    }

    state = ActiveCallState(
      isInCall: true,
      phoneNumber: phone,
      contactName: resolvedName,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      durationSeconds: 0,
      callStatus: 'OFFHOOK',
      isIncoming: false,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.isInCall && state.callStatus == 'OFFHOOK') {
        state = state.copyWith(durationSeconds: state.durationSeconds + 1);
      }
    });
  }

  void handleEvent(Map<String, dynamic> data) {
    final rawState = data['state']?.toString().toUpperCase() ?? '';
    final phone = data['phoneNumber']?.toString() ?? '';

    if (rawState == 'OFFHOOK') {
      if (!state.isInCall) {
        startCall(phone);
      } else {
        // If incoming call was answered, start the timer now
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (state.isInCall && state.callStatus == 'OFFHOOK') {
            state = state.copyWith(durationSeconds: state.durationSeconds + 1);
          }
        });
        state = state.copyWith(callStatus: 'OFFHOOK');
      }
    } else if (rawState == 'RINGING') {
      String? resolvedName;
      if (phone.isNotEmpty) {
        final contacts = ref.read(contactsProvider);
        for (var c in contacts) {
          if (RecipientImporter.isSamePhone(c.phone, phone)) {
            resolvedName = c.name;
            break;
          }
        }
      }
      state = state.copyWith(
        isInCall: true,
        callStatus: 'RINGING',
        isIncoming: true,
        phoneNumber: phone.isNotEmpty ? phone : state.phoneNumber,
        contactName: resolvedName ?? state.contactName,
        startedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } else if (rawState == 'IDLE') {
      if (state.isInCall) {
        _ticker?.cancel();
        state = state.copyWith(
          isInCall: false,
          callStatus: 'IDLE',
          isIncoming: false,
        );

        // Sync with Android's system call log once Android flushes the finished call
        Future.delayed(const Duration(milliseconds: 1500), () {
          ref.read(callLogsProvider.notifier).load();
        });
      }
    }
  }

  Future<void> hangup() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    try {
      await api.hangupCall();
    } catch (e) {
      debugPrint("hangupCall error: $e");
    }
  }

}

final activeCallProvider =
    NotifierProvider<ActiveCallNotifier, ActiveCallState>(
      ActiveCallNotifier.new,
    );

// === 11.2 CALL LOGS NOTIFIER ===
class CallLogNotifier extends Notifier<List<CallLogEntryDto>> {
  @override
  List<CallLogEntryDto> build() => [];

  void set(List<CallLogEntryDto> logs) {
    state = logs;
  }

  Future<void> load() async {
    final api = ref.read(apiClientProvider);
    final contacts = ref.read(contactsProvider);

    List<CallLogEntryDto> serverLogs = [];
    if (api != null) {
      try {
        serverLogs = await api.fetchCallLogs(limit: 250);
      } catch (e) {
        debugPrint("fetchCallLogs error: $e");
      }
    }

    // Direct synchronization with Android system call log.
    // No independent accounting: take calls from Android and only enrich contact name
    // if Android CallLog did not provide a name and the app has one.
    final resolved = serverLogs.map((entry) {
      if (entry.name == null || entry.name!.trim().isEmpty) {
        for (var c in contacts) {
          if (RecipientImporter.isSamePhone(c.phone, entry.number) && c.name.trim().isNotEmpty) {
            return CallLogEntryDto(
              id: entry.id,
              number: entry.number,
              name: c.name.trim(),
              date: entry.date,
              durationSeconds: entry.durationSeconds,
              direction: entry.direction,
              status: entry.status,
              comment: entry.comment,
            );
          }
        }
      }
      return entry;
    }).toList();

    resolved.sort((a, b) => b.date.compareTo(a.date));
    state = resolved;
  }
}

final callLogsProvider =
    NotifierProvider<CallLogNotifier, List<CallLogEntryDto>>(
      CallLogNotifier.new,
    );

// === 11.3 DEVICE VOLUME NOTIFIER ===
class DeviceVolumeNotifier extends Notifier<DeviceVolumeDto> {
  @override
  DeviceVolumeDto build() => const DeviceVolumeDto();

  Future<void> load() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    try {
      final vol = await api.fetchDeviceVolume();
      state = vol;
    } catch (e) {
      debugPrint("DeviceVolume load error: $e");
    }
  }

  Future<void> ringVolumeUp() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    final next = (state.ringVolume + 1).clamp(0, state.maxRingVolume);
    state = state.copyWith(ringVolume: next);
    try {
      final updated = await api.setDeviceVolume(stream: 'ring', direction: 'up');
      state = updated;
    } catch (e) {
      debugPrint("ringVolumeUp error: $e");
    }
  }

  Future<void> ringVolumeDown() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    final next = (state.ringVolume - 1).clamp(0, state.maxRingVolume);
    state = state.copyWith(ringVolume: next);
    try {
      final updated = await api.setDeviceVolume(stream: 'ring', direction: 'down');
      state = updated;
    } catch (e) {
      debugPrint("ringVolumeDown error: $e");
    }
  }

  Future<void> setRingVolume(int volume) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    state = state.copyWith(ringVolume: volume.clamp(0, state.maxRingVolume));
    try {
      final updated = await api.setDeviceVolume(stream: 'ring', volume: volume);
      state = updated;
    } catch (e) {
      debugPrint("setRingVolume error: $e");
    }
  }

  Future<void> callVolumeUp() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    final next = (state.callVolume + 1).clamp(0, state.maxCallVolume);
    state = state.copyWith(callVolume: next);
    try {
      final updated = await api.setDeviceVolume(stream: 'call', direction: 'up');
      state = updated;
    } catch (e) {
      debugPrint("callVolumeUp error: $e");
    }
  }

  Future<void> callVolumeDown() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    final next = (state.callVolume - 1).clamp(0, state.maxCallVolume);
    state = state.copyWith(callVolume: next);
    try {
      final updated = await api.setDeviceVolume(stream: 'call', direction: 'down');
      state = updated;
    } catch (e) {
      debugPrint("callVolumeDown error: $e");
    }
  }

  void set(DeviceVolumeDto dto) {
    state = dto;
  }
}

final deviceVolumeProvider =
    NotifierProvider<DeviceVolumeNotifier, DeviceVolumeDto>(
      DeviceVolumeNotifier.new,
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

// Базовая группировка сообщений по чатам с нормализацией телефонов
final threadsProvider = Provider<Map<String, List<SmsMessageDto>>>((ref) {
  final messages = ref.watch(allMessagesProvider);
  final grouped = <String, List<SmsMessageDto>>{};
  for (var msg in messages) {
    final norm = RecipientImporter.normalizePhone(msg.address);
    String threadKey = norm.isNotEmpty ? norm : msg.address;
    for (var existingKey in grouped.keys) {
      if (RecipientImporter.isSamePhone(existingKey, threadKey)) {
        threadKey = existingKey;
        break;
      }
    }
    if (!grouped.containsKey(threadKey)) grouped[threadKey] = [];
    grouped[threadKey]!.add(msg);
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
      (c) => RecipientImporter.isSamePhone(c.phone, phone),
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

// === UNIFIED CLIENTS (NEW) ===
class SidebarClientItem {
  final String phone;
  final ContactDto? contact;
  final SmsMessageDto? lastMessage;
  final int unreadCount;

  SidebarClientItem({
    required this.phone,
    this.contact,
    this.lastMessage,
    this.unreadCount = 0,
  });
}

final sidebarClientsProvider = Provider<List<SidebarClientItem>>((ref) {
  final contacts = ref.watch(contactsProvider);
  final threads = ref.watch(threadsProvider);
  final unreadCounts = ref.watch(unreadCountsProvider);

  final allPhones = <String>{};
  for (var c in contacts) {
    if (c.phone.isNotEmpty) {
      allPhones.add(c.phone);
    }
  }
  allPhones.addAll(threads.keys);

  final items = <SidebarClientItem>[];
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  bool isPendingCallback(ContactDto? c) {
    if (c == null || c.callbackTimeMs == null) return false;
    final cbTime = c.callbackTime!;
    return cbTime.isBefore(now) || (cbTime.isAfter(todayStart) && cbTime.isBefore(todayEnd));
  }

  for (var phone in allPhones) {
    final contact = contacts.firstWhere(
      (c) => RecipientImporter.isSamePhone(c.phone, phone),
      orElse: () => ContactDto(phone: phone, name: "", notes: ""),
    );
    final isSaved = contacts.any((c) => RecipientImporter.isSamePhone(c.phone, phone));
    
    // Find matching thread
    SmsMessageDto? lastMsg;
    for (var entry in threads.entries) {
      if (RecipientImporter.isSamePhone(entry.key, phone)) {
        lastMsg = entry.value.lastOrNull;
        break;
      }
    }
    
    int unread = unreadCounts[phone] ?? 0;
    if (unread == 0) {
      for (var entry in unreadCounts.entries) {
        if (RecipientImporter.isSamePhone(entry.key, phone)) {
          unread = entry.value;
          break;
        }
      }
    }

    items.add(SidebarClientItem(
      phone: phone,
      contact: isSaved ? contact : null,
      lastMessage: lastMsg,
      unreadCount: unread,
    ));
  }

  // Sort:
  // 1. Unread count (descending)
  // 2. Pending callback (yes first)
  // 3. Last message date (descending, if exists)
  // 4. Alphabetical by name / phone (fallback)
  items.sort((a, b) {
    if (a.unreadCount != b.unreadCount) {
      return b.unreadCount.compareTo(a.unreadCount);
    }

    final aPending = isPendingCallback(a.contact);
    final bPending = isPendingCallback(b.contact);
    if (aPending != bPending) {
      return aPending ? -1 : 1;
    }

    if (a.lastMessage != null && b.lastMessage != null) {
      return b.lastMessage!.date.compareTo(a.lastMessage!.date);
    } else if (a.lastMessage != null) {
      return -1;
    } else if (b.lastMessage != null) {
      return 1;
    }

    final nameA = a.contact?.name ?? '';
    final nameB = b.contact?.name ?? '';
    if (nameA.isNotEmpty || nameB.isNotEmpty) {
      if (nameA.isEmpty) return 1;
      if (nameB.isEmpty) return -1;
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    }

    return a.phone.compareTo(b.phone);
  });

  return items;
});

final filteredSidebarClientsProvider = Provider<List<SidebarClientItem>>((ref) {
  final allClients = ref.watch(sidebarClientsProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase().trim();
  final threads = ref.watch(threadsProvider);

  if (query.isEmpty) {
    return allClients;
  }

  return allClients.where((item) {
    final phoneMatch = item.phone.toLowerCase().contains(query);
    
    final nameMatch = item.contact != null && 
        item.contact!.name.toLowerCase().contains(query);
        
    final notesMatch = item.contact != null && 
        item.contact!.notes.toLowerCase().contains(query);

    bool msgMatch = false;
    for (var entry in threads.entries) {
      if (RecipientImporter.isSamePhone(entry.key, item.phone)) {
        msgMatch = entry.value.any((m) => m.body.toLowerCase().contains(query));
        break;
      }
    }

    return phoneMatch || nameMatch || notesMatch || msgMatch;
  }).toList();
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

      // 1. Загружаем цепочки (до 500 уникальных чатов со смартфона)
      try {
        final threadsMsgs = await api.fetchThreads(limit: 500);
        for (var tm in threadsMsgs) {
          ref.read(allMessagesProvider.notifier).add(tm);
        }
      } catch (e) {
        debugPrint("fetchThreads error: $e");
      }

      // 2. Загружаем последние 200 сообщений для детализации
      final msgs = await api.fetchMessages(limit: 200);
      ref.read(allMessagesProvider.notifier).set(msgs);

      // Загружаем контакты
      await ref.read(contactsProvider.notifier).load();

      // Загружаем рассылки
      await ref.read(campaignsProvider.notifier).load();

      // Загружаем журнал звонков
      try {
        await ref.read(callLogsProvider.notifier).load();
      } catch (e) {
        debugPrint("load callLogs error: $e");
      }

      // Загружаем громкость телефона
      try {
        await ref.read(deviceVolumeProvider.notifier).load();
      } catch (e) {
        debugPrint("load deviceVolume error: $e");
      }

      ref.read(isConnectedProvider.notifier).set(true);

      wsSub = api.connectWs().listen(
        (data) async {
          if (data['type'] == 'NEW_SMS') {
            final msg = SmsMessageDto.fromJson(data['data']);

            // Обновляем общий список (для сайдбара и счетчиков)
            ref.read(allMessagesProvider.notifier).add(msg);

            // Обновляем текущий открытый чат с нормализацией телефонов
            final currentChat = ref.read(selectedChatIdProvider);
            if (currentChat != null && RecipientImporter.isSamePhone(currentChat, msg.address)) {
              ref.read(chatMessagesProvider(currentChat)).addMessage(msg);
            }
            ref.read(chatMessagesProvider(msg.address)).addMessage(msg);

            if (!msg.isSent) {
              if (currentChat == null || !RecipientImporter.isSamePhone(currentChat, msg.address)) {
                ref.read(unreadCountsProvider.notifier).increment(msg.address);
                try {
                  await SfxService.playReceived();
                } catch (_) {}
              }
            }
          } else if (data['type'] == 'CAMPAIGN_UPDATE') {
            try {
              final campaign = CampaignDto.fromJson(Map<String, dynamic>.from(data['data']));
              ref.read(campaignsProvider.notifier).addOrUpdate(campaign);
            } catch (e) {
              debugPrint("WS CAMPAIGN_UPDATE parse error: $e");
            }
          } else if (data['type'] == 'CAMPAIGN_ITEM_PROCESSED') {
            try {
              final campaignId = data['data']['campaignId']?.toString() ?? '';
              final item = CampaignItemDto.fromJson(Map<String, dynamic>.from(data['data']['item']));
              ref.read(campaignsProvider.notifier).updateItem(campaignId, item);
            } catch (e) {
              debugPrint("WS CAMPAIGN_ITEM_PROCESSED parse error: $e");
            }
          } else if (data['type'] == 'CALL_STATE_CHANGED') {
            try {
              final callData = Map<String, dynamic>.from(data['data'] as Map);
              ref.read(activeCallProvider.notifier).handleEvent(callData);
              final rawState = callData['state']?.toString().toUpperCase() ?? '';
              if (rawState == 'IDLE' || rawState == 'DISCONNECTED') {
                Future.delayed(const Duration(milliseconds: 1500), () {
                  ref.read(callLogsProvider.notifier).load();
                });
              }
            } catch (e) {
              debugPrint("WS CALL_STATE_CHANGED parse error: $e");
            }
          } else if (data['type'] == 'DEVICE_VOLUME_CHANGED') {
            try {
              final volData = Map<String, dynamic>.from(data['data'] as Map);
              final vol = DeviceVolumeDto.fromJson(volData);
              ref.read(deviceVolumeProvider.notifier).set(vol);
            } catch (e) {
              debugPrint("WS DEVICE_VOLUME_CHANGED parse error: $e");
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

  // Reconnection, Health check & Smart Delta Sync timer (every 4 seconds)
  final healthTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
    final isConnected = ref.read(isConnectedProvider);
    try {
      await api.fetchSims();
      if (!isConnected) {
        // Если восстановили связь по HTTP, пробуем переподключить WS
        await connect();
      }

      // Smart Delta Sync: подтягиваем свежие сообщения с сервера с надежной дедупликацией
      try {
        final recentMsgs = await api.fetchMessages(limit: 50);
        final currentMessages = ref.read(allMessagesProvider);
        final currentChat = ref.read(selectedChatIdProvider);

        for (var rm in recentMsgs) {
          final alreadyKnown = currentMessages.any((m) => isSameSmsMessage(m, rm));

          ref.read(allMessagesProvider.notifier).add(rm);

          if (currentChat != null && RecipientImporter.isSamePhone(currentChat, rm.address)) {
            ref.read(chatMessagesProvider(currentChat)).addMessage(rm);
          }

          if (!alreadyKnown && !rm.isSent) {
            if (currentChat == null || !RecipientImporter.isSamePhone(currentChat, rm.address)) {
              ref.read(unreadCountsProvider.notifier).increment(rm.address);
              try {
                await SfxService.playReceived();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
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
