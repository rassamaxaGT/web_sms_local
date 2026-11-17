import 'dart:async';
import 'package:android_host/shared/security_service.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../shared/shared_models.dart'; // Или ваш путь к shared_models
import '../../shared/contractor_models.dart';
import '../utils/recipient_importer.dart';

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
    final normalized = RecipientImporter.normalizePhone(phone);
    final targetPhone = normalized.isNotEmpty ? normalized : phone;
    final encryptedPayload = _security.encrypt({
      'address': targetPhone,
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

  Future<void> makeCall(String phone, int subId) async {
    final normalized = RecipientImporter.normalizePhone(phone);
    final targetPhone = normalized.isNotEmpty ? normalized : phone;
    final encrypted = _security.encrypt({'phone': targetPhone, 'subId': subId});
    final res = await http.post(
      Uri.parse('$effectiveBaseUrl/api/call'),
      body: encrypted,
    );
    if (res.statusCode != 200) {
      String details = '';
      try {
        final decrypted = _security.decrypt(res.body);
        details = ': $decrypted';
      } catch (_) {
        details = ' (status: ${res.statusCode}, body: ${res.body})';
      }
      throw Exception('Failed to trigger call$details');
    }
  }

  Future<bool> hangupCall() async {
    final res = await http.post(
      Uri.parse('$effectiveBaseUrl/api/call/hangup'),
    );
    if (res.statusCode != 200) {
      String details = '';
      try {
        final decrypted = _security.decrypt(res.body);
        details = ': $decrypted';
      } catch (_) {
        details = ' (status: ${res.statusCode}, body: ${res.body})';
      }
      throw Exception('Failed to hangup call$details');
    }
    try {
      final decrypted = _security.decrypt(res.body);
      return decrypted['terminated'] == true;
    } catch (_) {
      return true;
    }
  }

  Future<List<CallLogEntryDto>> fetchCallLogs({int limit = 100, int offset = 0}) async {
    final res = await http.get(
      Uri.parse('$effectiveBaseUrl/api/calls?limit=$limit&offset=$offset'),
    );
    if (res.statusCode != 200) throw Exception('Failed to load call logs');
    final List data = _security.decrypt(res.body);
    return data.map((e) => CallLogEntryDto.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  // === DEVICE VOLUME ===

  Future<DeviceVolumeDto> fetchDeviceVolume() async {
    final res = await http.get(Uri.parse('$effectiveBaseUrl/api/device/volume'));
    if (res.statusCode != 200) throw Exception('Failed to load device volume');
    final Map<String, dynamic> data = Map<String, dynamic>.from(_security.decrypt(res.body));
    return DeviceVolumeDto.fromJson(data);
  }

  Future<DeviceVolumeDto> setDeviceVolume({
    required String stream,
    int? volume,
    String? direction,
  }) async {
    final payload = <String, dynamic>{'stream': stream};
    if (direction != null) {
      payload['direction'] = direction;
    } else if (volume != null) {
      payload['volume'] = volume;
    }
    final encrypted = _security.encrypt(payload);
    final res = await http.post(
      Uri.parse('$effectiveBaseUrl/api/device/volume'),
      body: encrypted,
    );
    if (res.statusCode != 200) throw Exception('Failed to update device volume');
    final Map<String, dynamic> data = Map<String, dynamic>.from(_security.decrypt(res.body));
    return DeviceVolumeDto.fromJson(data);
  }

  // === МАССОВЫЕ РАССЫЛКИ (CAMPAIGNS) ===

  Future<List<CampaignDto>> fetchCampaigns() async {
    final res = await http.get(Uri.parse('$effectiveBaseUrl/api/campaigns'));
    if (res.statusCode != 200) throw Exception('Failed to load campaigns');

    final List data = _security.decrypt(res.body);
    return data.map((e) => CampaignDto.fromJson(e)).toList();
  }

  Future<CampaignDto> fetchCampaign(String id) async {
    final res = await http.get(Uri.parse('$effectiveBaseUrl/api/campaigns/$id'));
    if (res.statusCode != 200) throw Exception('Failed to load campaign $id');

    final Map<String, dynamic> data = Map<String, dynamic>.from(_security.decrypt(res.body));
    return CampaignDto.fromJson(data);
  }

  Future<String> createCampaign(CampaignDto campaign) async {
    final encrypted = _security.encrypt(campaign.toJson(includeItems: true));
    final res = await http.post(
      Uri.parse('$effectiveBaseUrl/api/campaigns'),
      body: encrypted,
    );
    if (res.statusCode != 200) throw Exception('Failed to create campaign');
    final resData = _security.decrypt(res.body);
    return resData['id']?.toString() ?? campaign.id;
  }

  Future<void> startCampaign(String id) async {
    final res = await http.post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/start'));
    if (res.statusCode != 200) throw Exception('Failed to start campaign');
  }

  Future<void> pauseCampaign(String id) async {
    final res = await http.post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/pause'));
    if (res.statusCode != 200) throw Exception('Failed to pause campaign');
  }

  Future<void> stopCampaign(String id) async {
    final res = await http.post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/stop'));
    if (res.statusCode != 200) throw Exception('Failed to stop campaign');
  }

  Future<void> retryFailedCampaign(String id) async {
    final res = await http.post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/retry-failed'));
    if (res.statusCode != 200) throw Exception('Failed to retry campaign');
  }

  Future<void> deleteCampaign(String id) async {
    final res = await http.delete(Uri.parse('$effectiveBaseUrl/api/campaigns/$id'));
    if (res.statusCode != 200) throw Exception('Failed to delete campaign');
  }

  // === Contractor (T-Bank) Proxy API ===

  Future<List<ContractorDto>> searchContractors(String query) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/contractor/search').replace(queryParameters: {
      'query': query,
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode}');
    }
    final List data = _security.decrypt(res.body);
    return data.map((e) => ContractorDto.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<ContractorDto> fetchContractorOkved(ContractorDto contractor) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/contractor/okved');
    final encryptedPayload = _security.encrypt(contractor.toJson());
    final res = await http.post(uri, body: encryptedPayload);
    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode}');
    }
    final Map<String, dynamic> data = _security.decrypt(res.body);
    return ContractorDto.fromJson(data);
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
