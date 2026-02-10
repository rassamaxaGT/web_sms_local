import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../shared/shared_models.dart';
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
final unreadCountsProvider = NotifierProvider<UnreadCountsNotifier, Map<String, int>>(
  UnreadCountsNotifier.new,
);


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

  if (query.isEmpty) {
    return allThreads;
  }

  final filtered = <String, List<SmsMessageDto>>{};

  for (var entry in allThreads.entries) {
    final phone = entry.key;
    final messages = entry.value;

    bool matchPhone = phone.toLowerCase().contains(query);
    bool matchBody = messages.any((m) => m.body.toLowerCase().contains(query));

    if (matchPhone || matchBody) {
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

  try {
    final sims = await api.fetchSims();
    ref.read(simsProvider.notifier).set(sims);

    final msgs = await api.fetchMessages();
    ref.read(allMessagesProvider.notifier).set(msgs);

    ref.read(isConnectedProvider.notifier).set(true);
  } catch (e) {
    ref.read(isConnectedProvider.notifier).set(false);
    rethrow;
  }

  final healthTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
    try {
      await api.fetchSims();
    } catch (e) {
      ref.read(isConnectedProvider.notifier).set(false);
      timer.cancel();
    }
  });

  ref.onDispose(() {
    healthTimer.cancel();
    audioPlayer.dispose();
  });

  final sub = api.connectWs().listen(
    (data) async {
      if (data['type'] == 'NEW_SMS') {
        final msg = SmsMessageDto.fromJson(data['data']);
        
        // Добавляем сообщение в общий список
        ref.read(allMessagesProvider.notifier).add(msg);

        // === ЛОГИКА УВЕДОМЛЕНИЙ ===
        // Если сообщение входящее (не от меня)
        if (!msg.isSent) {
          // Проверяем, открыт ли сейчас этот чат
          final currentChat = ref.read(selectedChatIdProvider);
          
          if (currentChat != msg.address) {
            // Если чат закрыт или открыт другой - увеличиваем счетчик
            ref.read(unreadCountsProvider.notifier).increment(msg.address);
            
            // Играем звук
            try {
              await audioPlayer.play(AssetSource('sounds/notification.mp3'));
            } catch (_) {}
          }
        }
      }
    },
    onDone: () {
      ref.read(isConnectedProvider.notifier).set(false);
    },
    onError: (e) {
      ref.read(isConnectedProvider.notifier).set(false);
    },
  );

  ref.onDispose(() => sub.cancel());
});