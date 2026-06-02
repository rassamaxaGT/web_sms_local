import 'dart:async';
import 'package:android_host/shared/security_service.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../shared/shared_models.dart'; // Или ваш путь к shared_models

class ApiClient {
  final String baseUrl;
  final SecurityService _security;

  ApiClient(this.baseUrl, String password)
    : _security = SecurityService(password);

  // === ДОБАВЛЕН ЭТОТ ГЕТТЕР ===
  // Он нужен, чтобы корректно обрабатывать URL, даже если он пустой (при локальном запуске)
  // или содержит лишний слеш в конце.
  String get effectiveBaseUrl {
    if (baseUrl.isEmpty) return "";
    if (baseUrl.endsWith('/')) {
      return baseUrl.substring(0, baseUrl.length - 1);
    }
    return baseUrl;
  }
  // ============================

  Future<List<SimCardDto>> fetchSims() async {
    // Используем effectiveBaseUrl вместо baseUrl
    final res = await http.get(Uri.parse('$effectiveBaseUrl/api/sims'));

    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode} ${res.body}');
    }

    try {
      final List data = _security.decrypt(res.body);
      return data.map((e) => SimCardDto.fromJson(e)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<SmsMessageDto>> fetchMessages({int limit = 50, int offset = 0, String? address}) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/messages').replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
      'address': ?address,
    });
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode}');
    }

    try {
      final List data = _security.decrypt(res.body);
      return data.map((e) => SmsMessageDto.fromJson(e)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<SmsMessageDto>> fetchThreads({int limit = 50}) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/threads').replace(queryParameters: {
      'limit': limit.toString(),
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Failed to load threads');
    
    final List data = _security.decrypt(res.body);
    return data.map((e) => SmsMessageDto.fromJson(e)).toList();
  }

  Future<void> sendSms(String phone, String body, int subId) async {
    final encryptedPayload = _security.encrypt({
      'address': phone,
      'body': body,
      'subId': subId,
    });

    final res = await http.post(
      Uri.parse('$effectiveBaseUrl/api/send'),
      body: encryptedPayload,
    );

    if (res.statusCode != 200) {
      throw Exception("Failed to send: ${res.body}");
    }
  }

  // === МЕТОДЫ УДАЛЕНИЯ ===

  Future<void> deleteMessage(int id) async {
    // Теперь effectiveBaseUrl определен и ошибки не будет
    final url = Uri.parse('$effectiveBaseUrl/api/messages/$id');
    final res = await http.delete(url);
    if (res.statusCode != 200) {
      throw Exception("Failed to delete message: ${res.body}");
    }
  }

  Future<void> deleteThread(int threadId) async {
    final url = Uri.parse('$effectiveBaseUrl/api/threads/$threadId');
    final res = await http.delete(url);
    if (res.statusCode != 200) {
      throw Exception("Failed to delete thread: ${res.body}");
    }
  }

  // === ТЕХНИЧЕСКАЯ РЕАЛИЗАЦИЯ ШАБЛОНОВ ===

  Future<List<SmsTemplateDto>> fetchTemplates() async {
    final res = await http.get(Uri.parse('$effectiveBaseUrl/api/templates'));
    if (res.statusCode != 200) throw Exception('Failed to load templates');
    
    final List data = _security.decrypt(res.body);
    return data.map((e) => SmsTemplateDto.fromJson(e)).toList();
  }

  Future<void> saveTemplate(SmsTemplateDto template) async {
    final encrypted = _security.encrypt(template.toJson());
    final res = await http.post(
      Uri.parse('$effectiveBaseUrl/api/templates'),
      body: encrypted,
    );
    if (res.statusCode != 200) throw Exception('Failed to save template');
  }

  Future<void> deleteTemplate(String id) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/templates').replace(queryParameters: {'id': id});
    final res = await http.delete(uri);
    if (res.statusCode != 200) throw Exception('Failed to delete template');
  }

  // === КНИГА КОНТАКТОВ ===

  Future<List<ContactDto>> fetchContacts() async {
    final res = await http.get(Uri.parse('$effectiveBaseUrl/api/contacts'));
    if (res.statusCode != 200) throw Exception('Failed to load contacts');
    
    final List data = _security.decrypt(res.body);
    return data.map((e) => ContactDto.fromJson(e)).toList();
  }

  Future<void> saveContact(ContactDto contact) async {
    final encrypted = _security.encrypt(contact.toJson());
    final res = await http.post(
      Uri.parse('$effectiveBaseUrl/api/contacts'),
      body: encrypted,
    );
    if (res.statusCode != 200) throw Exception('Failed to save contact');
  }

  Future<void> deleteContact(String phone) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/contacts').replace(queryParameters: {'phone': phone});
    final res = await http.delete(uri);
    if (res.statusCode != 200) throw Exception('Failed to delete contact');
  }

  // ======================

  Stream<dynamic> connectWs() {
    // Для веб-сокетов нужно менять http на ws
    String wsUrl;
    if (effectiveBaseUrl.isEmpty) {
      // Если базовый URL пуст (относительный путь), формируем WS путь вручную
      // Но обычно connectWs вызывается, когда мы уже знаем хост
      // Для надежности берем переданный baseUrl
      wsUrl = "/ws";
    } else {
      wsUrl = '${effectiveBaseUrl.replaceFirst('http', 'ws')}/ws';
    }

    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    return channel.stream
        .map((event) {
          try {
            return _security.decrypt(event);
          } catch (e) {
            return null;
          }
        })
        .where((element) => element != null);
  }
}
