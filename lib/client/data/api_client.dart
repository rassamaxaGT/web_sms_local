import 'dart:async';
import 'package:android_host/shared/security_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../shared/shared_models.dart';
import '../../shared/contractor_models.dart';
import '../utils/recipient_importer.dart';

class ApiClient {
  static const Duration _timeout = Duration(seconds: 10);

  final String baseUrl;
  final SecurityService _security;
  final http.Client _client = http.Client();
  WebSocketChannel? _wsChannel;

  ApiClient(this.baseUrl, String password)
    : _security = SecurityService(password);

  Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer ${_security.authToken}',
  };

  String get effectiveBaseUrl {
    if (baseUrl.isEmpty) return "";
    if (baseUrl.endsWith('/')) {
      return baseUrl.substring(0, baseUrl.length - 1);
    }
    return baseUrl;
  }

  Future<List<SimCardDto>> fetchSims() async {
    final res = await _client
        .get(Uri.parse('$effectiveBaseUrl/api/sims'), headers: _authHeaders)
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode} ${res.body}');
    }

    final List data = _security.decrypt(res.body);
    return data.map((e) => SimCardDto.fromJson(e)).toList();
  }

  Future<List<SmsMessageDto>> fetchMessages({
    int limit = 50,
    int offset = 0,
    String? address,
  }) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/messages').replace(
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'address': ?address,
      },
    );
    final res = await _client
        .get(uri, headers: _authHeaders)
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode}');
    }

    final List data = _security.decrypt(res.body);
    return data.map((e) => SmsMessageDto.fromJson(e)).toList();
  }

  Future<List<SmsMessageDto>> fetchThreads({int limit = 50}) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/threads').replace(queryParameters: {
      'limit': limit.toString(),
    });
    final res = await _client.get(uri, headers: _authHeaders).timeout(_timeout);
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

    final res = await _client
        .post(
          Uri.parse('$effectiveBaseUrl/api/send'),
          headers: _authHeaders,
          body: encryptedPayload,
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception("Failed to send: ${res.body}");
    }
  }

  Future<void> deleteThread(int threadId) async {
    final url = Uri.parse('$effectiveBaseUrl/api/threads/$threadId');
    final res = await _client
        .delete(url, headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception("Failed to delete thread: ${res.body}");
    }
  }

  Future<List<SmsTemplateDto>> fetchTemplates() async {
    final res = await _client
        .get(Uri.parse('$effectiveBaseUrl/api/templates'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to load templates');

    final List data = _security.decrypt(res.body);
    return data.map((e) => SmsTemplateDto.fromJson(e)).toList();
  }

  Future<void> saveTemplate(SmsTemplateDto template) async {
    final encrypted = _security.encrypt(template.toJson());
    final res = await _client
        .post(
          Uri.parse('$effectiveBaseUrl/api/templates'),
          headers: _authHeaders,
          body: encrypted,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to save template');
  }

  Future<void> deleteTemplate(String id) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/templates')
        .replace(queryParameters: {'id': id});
    final res = await _client
        .delete(uri, headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to delete template');
  }

  Future<List<ContactDto>> fetchContacts() async {
    final res = await _client
        .get(Uri.parse('$effectiveBaseUrl/api/contacts'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to load contacts');

    final List data = _security.decrypt(res.body);
    return data.map((e) => ContactDto.fromJson(e)).toList();
  }

  Future<void> saveContact(ContactDto contact) async {
    final encrypted = _security.encrypt(contact.toJson());
    final res = await _client
        .post(
          Uri.parse('$effectiveBaseUrl/api/contacts'),
          headers: _authHeaders,
          body: encrypted,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to save contact');
  }

  Future<void> deleteContact(String phone) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/contacts')
        .replace(queryParameters: {'phone': phone});
    final res = await _client
        .delete(uri, headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to delete contact');
  }

  Future<void> makeCall(String phone, int subId) async {
    final normalized = RecipientImporter.normalizePhone(phone);
    final targetPhone = normalized.isNotEmpty ? normalized : phone;
    final encrypted = _security.encrypt({'phone': targetPhone, 'subId': subId});
    final res = await _client.post(Uri.parse('$effectiveBaseUrl/api/call'), headers: _authHeaders, body: encrypted,
    ).timeout(_timeout);
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
    final res = await _client
        .post(Uri.parse('$effectiveBaseUrl/api/call/hangup'), headers: _authHeaders)
        .timeout(_timeout);
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
    final res = await _client
        .get(
          Uri.parse('$effectiveBaseUrl/api/calls?limit=$limit&offset=$offset'),
          headers: _authHeaders,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to load call logs');
    final List data = _security.decrypt(res.body);
    return data.map((e) => CallLogEntryDto.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  // === DEVICE VOLUME ===

  Future<DeviceVolumeDto> fetchDeviceVolume() async {
    final res = await _client
        .get(Uri.parse('$effectiveBaseUrl/api/device/volume'), headers: _authHeaders)
        .timeout(_timeout);
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
    final res = await _client
        .post(
          Uri.parse('$effectiveBaseUrl/api/device/volume'),
          headers: _authHeaders,
          body: encrypted,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to update device volume');
    final Map<String, dynamic> data = Map<String, dynamic>.from(_security.decrypt(res.body));
    return DeviceVolumeDto.fromJson(data);
  }

  // === МАССОВЫЕ РАССЫЛКИ (CAMPAIGNS) ===

  Future<List<CampaignDto>> fetchCampaigns() async {
    final res = await _client
        .get(Uri.parse('$effectiveBaseUrl/api/campaigns'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to load campaigns');

    final List data = _security.decrypt(res.body);
    return data.map((e) => CampaignDto.fromJson(e)).toList();
  }

  Future<CampaignDto> fetchCampaign(String id) async {
    final res = await _client
        .get(Uri.parse('$effectiveBaseUrl/api/campaigns/$id'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to load campaign $id');

    final Map<String, dynamic> data = Map<String, dynamic>.from(_security.decrypt(res.body));
    return CampaignDto.fromJson(data);
  }

  Future<String> createCampaign(CampaignDto campaign) async {
    final encrypted = _security.encrypt(campaign.toJson(includeItems: true));
    final res = await _client
        .post(
          Uri.parse('$effectiveBaseUrl/api/campaigns'),
          headers: _authHeaders,
          body: encrypted,
        )
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to create campaign');
    final resData = _security.decrypt(res.body);
    return resData['id']?.toString() ?? campaign.id;
  }

  Future<void> startCampaign(String id) async {
    final res = await _client
        .post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/start'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to start campaign');
  }

  Future<void> pauseCampaign(String id) async {
    final res = await _client
        .post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/pause'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to pause campaign');
  }

  Future<void> stopCampaign(String id) async {
    final res = await _client
        .post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/stop'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to stop campaign');
  }

  Future<void> retryFailedCampaign(String id) async {
    final res = await _client
        .post(Uri.parse('$effectiveBaseUrl/api/campaigns/$id/retry-failed'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to retry campaign');
  }

  Future<void> deleteCampaign(String id) async {
    final res = await _client
        .delete(Uri.parse('$effectiveBaseUrl/api/campaigns/$id'), headers: _authHeaders)
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Failed to delete campaign');
  }

  // === Contractor (T-Bank) Proxy API ===

  Future<List<ContractorDto>> searchContractors(String query) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/contractor/search').replace(queryParameters: {
      'query': query,
    });
    final res = await _client.get(uri, headers: _authHeaders).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode}');
    }
    final List data = _security.decrypt(res.body);
    return data.map((e) => ContractorDto.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<ContractorDto> fetchContractorOkved(ContractorDto contractor) async {
    final uri = Uri.parse('$effectiveBaseUrl/api/contractor/okved');
    final encryptedPayload = _security.encrypt(contractor.toJson());
    final res = await _client.post(uri, headers: _authHeaders, body: encryptedPayload).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Server Error: ${res.statusCode}');
    }
    final Map<String, dynamic> data = _security.decrypt(res.body);
    return ContractorDto.fromJson(data);
  }

  Stream<dynamic> connectWs() {
    _wsChannel?.sink.close();

    final String wsUrl;
    if (effectiveBaseUrl.isEmpty) {
      final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
      final host = Uri.base.hasPort
          ? '${Uri.base.host}:${Uri.base.port}'
          : Uri.base.host;
      wsUrl = '$scheme://$host/ws';
    } else {
      wsUrl = '${effectiveBaseUrl.replaceFirst('http', 'ws')}/ws';
    }

    final tokenParam = Uri.encodeQueryComponent(_security.authToken);
    final channel = WebSocketChannel.connect(Uri.parse('$wsUrl?token=$tokenParam'));
    _wsChannel = channel;

    return channel.stream
        .map((event) {
          try {
            return _security.decrypt(event);
          } catch (e) {
            debugPrint('WebSocket decrypt error: $e');
            return null;
          }
        })
        .where((element) => element != null);
  }

  void dispose() {
    _wsChannel?.sink.close();
    _wsChannel = null;
    _client.close();
  }
}
