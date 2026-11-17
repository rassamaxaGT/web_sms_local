// lib/shared/shared_models.dart

class SmsMessageDto {
  final int? id;        // Уникальный ID сообщения в базе Android
  final int? threadId;  // ID цепочки (диалога)
  final String address;
  final String body;
  final int date;
  final bool isSent;
  final int? subId;

  const SmsMessageDto({
    this.id,
    this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.isSent,
    this.subId,
  });

  SmsMessageDto copyWith({
    int? id,
    int? threadId,
    String? address,
    String? body,
    int? date,
    bool? isSent,
    int? subId,
  }) {
    return SmsMessageDto(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      address: address ?? this.address,
      body: body ?? this.body,
      date: date ?? this.date,
      isSent: isSent ?? this.isSent,
      subId: subId ?? this.subId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'threadId': threadId,
    'address': address,
    'body': body,
    'date': date,
    'isSent': isSent,
    'subId': subId,
  };

  factory SmsMessageDto.fromJson(Map<String, dynamic> json) {
    return SmsMessageDto(
      id: (json['id'] as num?)?.toInt(),
      threadId: (json['threadId'] as num?)?.toInt(),
      address: json['address']?.toString() ?? 'Unknown',
      body: json['body']?.toString() ?? '',
      date: (json['date'] as num?)?.toInt() ?? 0,
      isSent: json['isSent'] == true,
      subId: (json['subId'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsMessageDto &&
          id == other.id &&
          threadId == other.threadId &&
          address == other.address &&
          body == other.body &&
          date == other.date &&
          isSent == other.isSent &&
          subId == other.subId;

  @override
  int get hashCode =>
      Object.hash(id, threadId, address, body, date, isSent, subId);
}

class SimCardDto {
  final int subscriptionId;
  final int slotIndex;
  final String carrierName;

  const SimCardDto({
    required this.subscriptionId,
    required this.slotIndex,
    required this.carrierName,
  });

  SimCardDto copyWith({
    int? subscriptionId,
    int? slotIndex,
    String? carrierName,
  }) {
    return SimCardDto(
      subscriptionId: subscriptionId ?? this.subscriptionId,
      slotIndex: slotIndex ?? this.slotIndex,
      carrierName: carrierName ?? this.carrierName,
    );
  }

  Map<String, dynamic> toJson() => {
    'subscriptionId': subscriptionId,
    'slotIndex': slotIndex,
    'carrierName': carrierName,
  };

  factory SimCardDto.fromJson(Map<String, dynamic> json) {
    return SimCardDto(
      subscriptionId: (json['subscriptionId'] as num?)?.toInt() ?? -1,
      slotIndex: (json['slotIndex'] as num?)?.toInt() ?? 0,
      carrierName: json['carrierName']?.toString() ?? 'Unknown SIM',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimCardDto &&
          subscriptionId == other.subscriptionId &&
          slotIndex == other.slotIndex &&
          carrierName == other.carrierName;

  @override
  int get hashCode => Object.hash(subscriptionId, slotIndex, carrierName);
}

class SmsTemplateDto {
  final String id;
  final String title;
  final String body;

  const SmsTemplateDto({
    required this.id,
    required this.title,
    required this.body,
  });

  SmsTemplateDto copyWith({String? id, String? title, String? body}) {
    return SmsTemplateDto(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
  };

  factory SmsTemplateDto.fromJson(Map<String, dynamic> json) {
    return SmsTemplateDto(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsTemplateDto &&
          id == other.id &&
          title == other.title &&
          body == other.body;

  @override
  int get hashCode => Object.hash(id, title, body);
}

class CallRecordDto {
  final int timestamp;
  final String comment;
  final String status; // 'Дозвон', 'ндз', 'перезвон', 'успех', 'пропущен', 'отклонен'
  final int? durationSeconds;
  final String direction; // 'incoming', 'outgoing'

  CallRecordDto({
    required this.timestamp,
    required this.comment,
    required this.status,
    this.durationSeconds,
    this.direction = 'outgoing',
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'comment': comment,
        'status': status,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        'direction': direction,
      };

  factory CallRecordDto.fromJson(Map<String, dynamic> json) {
    return CallRecordDto(
      timestamp: json['timestamp'] ?? 0,
      comment: json['comment'] ?? "",
      status: json['status'] ?? "успех",
      durationSeconds: json['durationSeconds'] as int?,
      direction: json['direction']?.toString() ?? 'outgoing',
    );
  }
}

class CallLogEntryDto {
  final String id;
  final String number;
  final String? name;
  final int date; // timestamp ms
  final int durationSeconds;
  final String direction; // 'incoming', 'outgoing'
  final String status; // 'успех', 'ндз', 'пропущен', 'отклонен', 'сброшен'
  final String? comment;

  CallLogEntryDto({
    required this.id,
    required this.number,
    this.name,
    required this.date,
    required this.durationSeconds,
    required this.direction,
    required this.status,
    this.comment,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        if (name != null) 'name': name,
        'date': date,
        'durationSeconds': durationSeconds,
        'direction': direction,
        'status': status,
        if (comment != null) 'comment': comment,
      };

  factory CallLogEntryDto.fromJson(Map<String, dynamic> json) {
    return CallLogEntryDto(
      id: json['id']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      name: json['name']?.toString(),
      date: json['date'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      direction: json['direction']?.toString() ?? 'incoming',
      status: json['status']?.toString() ?? 'успех',
      comment: json['comment']?.toString(),
    );
  }
}

class ContactDto {
  final String phone;
  final String name;
  final String notes;
  final int? callbackTimeMs;
  final List<CallRecordDto> callHistory;

  ContactDto({
    required this.phone,
    required this.name,
    required this.notes,
    this.callbackTimeMs,
    this.callHistory = const [],
  });

  DateTime? get callbackTime => callbackTimeMs != null
      ? DateTime.fromMillisecondsSinceEpoch(callbackTimeMs!)
      : null;

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'name': name,
        'notes': notes,
        'callbackTimeMs': callbackTimeMs,
        'callHistory': callHistory.map((e) => e.toJson()).toList(),
      };

  factory ContactDto.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? historyJson = json['callHistory'] as List<dynamic>?;
    final history = historyJson != null
        ? historyJson.map((e) => CallRecordDto.fromJson(e)).toList()
        : const <CallRecordDto>[];

    return ContactDto(
      phone: json['phone'] ?? "",
      name: json['name'] ?? "",
      notes: json['notes'] ?? "",
      callbackTimeMs: (json['callbackTimeMs'] as num?)?.toInt(),
      callHistory: history,
    );
  }
}

class CampaignItemDto {
  final String id;
  final String phone;
  final String? name;
  final Map<String, String> customFields;
  final String interpolatedText;
  final int partsCount;
  final String status; // 'pending', 'sending', 'sent', 'failed', 'skipped'
  final int? subId;
  final int? sentAtMs;
  final String? errorMessage;

  CampaignItemDto({
    required this.id,
    required this.phone,
    this.name,
    this.customFields = const {},
    required this.interpolatedText,
    this.partsCount = 1,
    this.status = 'pending',
    this.subId,
    this.sentAtMs,
    this.errorMessage,
  });

  CampaignItemDto copyWith({
    String? id,
    String? phone,
    String? name,
    Map<String, String>? customFields,
    String? interpolatedText,
    int? partsCount,
    String? status,
    int? subId,
    int? sentAtMs,
    String? errorMessage,
  }) {
    return CampaignItemDto(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      customFields: customFields ?? this.customFields,
      interpolatedText: interpolatedText ?? this.interpolatedText,
      partsCount: partsCount ?? this.partsCount,
      status: status ?? this.status,
      subId: subId ?? this.subId,
      sentAtMs: sentAtMs ?? this.sentAtMs,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'customFields': customFields,
        'interpolatedText': interpolatedText,
        'partsCount': partsCount,
        'status': status,
        'subId': subId,
        'sentAtMs': sentAtMs,
        'errorMessage': errorMessage,
      };

  factory CampaignItemDto.fromJson(Map<String, dynamic> json) {
    final rawFields = json['customFields'];
    Map<String, String> fields = {};
    if (rawFields is Map) {
      rawFields.forEach((key, value) {
        fields[key.toString()] = value.toString();
      });
    }

    return CampaignItemDto(
      id: json['id']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      name: json['name']?.toString(),
      customFields: fields,
      interpolatedText: json['interpolatedText']?.toString() ?? '',
      partsCount: json['partsCount'] as int? ?? 1,
      status: json['status']?.toString() ?? 'pending',
      subId: json['subId'] as int?,
      sentAtMs: json['sentAtMs'] as int?,
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}

class CampaignDto {
  final String id;
  final String title;
  final int createdAtMs;
  final int updatedAtMs;
  final String status; // 'draft', 'queued', 'running', 'paused', 'completed', 'cancelled'
  final String templateBody;
  final String simMode; // 'single', 'round_robin'
  final List<int> selectedSubIds;
  final int intervalSeconds;
  final int randomJitterSeconds;
  final bool skipDuplicates;
  final List<CampaignItemDto> items;
  final int currentIndex;
  final int totalCount;
  final int sentCount;
  final int failedCount;

  CampaignDto({
    required this.id,
    required this.title,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.status = 'draft',
    required this.templateBody,
    this.simMode = 'single',
    this.selectedSubIds = const [],
    this.intervalSeconds = 5,
    this.randomJitterSeconds = 2,
    this.skipDuplicates = true,
    this.items = const [],
    this.currentIndex = 0,
    int? totalCount,
    int? sentCount,
    int? failedCount,
  })  : totalCount = totalCount ?? items.length,
        sentCount = sentCount ?? items.where((i) => i.status == 'sent').length,
        failedCount = failedCount ?? items.where((i) => i.status == 'failed').length;

  int get pendingCount => items.where((i) => i.status == 'pending' || i.status == 'sending').length;
  double get progressPercentage => totalCount > 0 ? (sentCount + failedCount) / totalCount : 0.0;

  CampaignDto copyWith({
    String? id,
    String? title,
    int? createdAtMs,
    int? updatedAtMs,
    String? status,
    String? templateBody,
    String? simMode,
    List<int>? selectedSubIds,
    int? intervalSeconds,
    int? randomJitterSeconds,
    bool? skipDuplicates,
    List<CampaignItemDto>? items,
    int? currentIndex,
    int? totalCount,
    int? sentCount,
    int? failedCount,
  }) {
    return CampaignDto(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      status: status ?? this.status,
      templateBody: templateBody ?? this.templateBody,
      simMode: simMode ?? this.simMode,
      selectedSubIds: selectedSubIds ?? this.selectedSubIds,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      randomJitterSeconds: randomJitterSeconds ?? this.randomJitterSeconds,
      skipDuplicates: skipDuplicates ?? this.skipDuplicates,
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      totalCount: totalCount,
      sentCount: sentCount,
      failedCount: failedCount,
    );
  }

  Map<String, dynamic> toJson({bool includeItems = true}) => {
        'id': id,
        'title': title,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'status': status,
        'templateBody': templateBody,
        'simMode': simMode,
        'selectedSubIds': selectedSubIds,
        'intervalSeconds': intervalSeconds,
        'randomJitterSeconds': randomJitterSeconds,
        'skipDuplicates': skipDuplicates,
        'currentIndex': currentIndex,
        'totalCount': totalCount,
        'sentCount': sentCount,
        'failedCount': failedCount,
        if (includeItems) 'items': items.map((e) => e.toJson()).toList(),
      };

  factory CampaignDto.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>?;
    final parsedItems = rawItems != null
        ? rawItems.map((e) => CampaignItemDto.fromJson(e as Map<String, dynamic>)).toList()
        : <CampaignItemDto>[];

    final rawSubs = json['selectedSubIds'] as List<dynamic>?;
    final parsedSubs = rawSubs != null
        ? rawSubs.map((e) => (e as num).toInt()).toList()
        : <int>[];

    return CampaignDto(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Без названия',
      createdAtMs: json['createdAtMs'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: json['updatedAtMs'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      status: json['status']?.toString() ?? 'draft',
      templateBody: json['templateBody']?.toString() ?? '',
      simMode: json['simMode']?.toString() ?? 'single',
      selectedSubIds: parsedSubs,
      intervalSeconds: json['intervalSeconds'] as int? ?? 5,
      randomJitterSeconds: json['randomJitterSeconds'] as int? ?? 2,
      skipDuplicates: json['skipDuplicates'] as bool? ?? true,
      items: parsedItems,
      currentIndex: json['currentIndex'] as int? ?? 0,
      totalCount: json['totalCount'] as int? ?? parsedItems.length,
      sentCount: json['sentCount'] as int? ?? parsedItems.where((i) => i.status == 'sent').length,
      failedCount: json['failedCount'] as int? ?? parsedItems.where((i) => i.status == 'failed').length,
    );
  }
}

class DeviceVolumeDto {
  final int ringVolume;
  final int maxRingVolume;
  final int callVolume;
  final int maxCallVolume;
  final int ringerMode; // 0: Silent, 1: Vibrate, 2: Normal
  final bool isBluetoothConnected;
  final String bluetoothDeviceName;
  final bool isWiredHeadsetConnected;

  const DeviceVolumeDto({
    this.ringVolume = 0,
    this.maxRingVolume = 15,
    this.callVolume = 0,
    this.maxCallVolume = 5,
    this.ringerMode = 2,
    this.isBluetoothConnected = false,
    this.bluetoothDeviceName = '',
    this.isWiredHeadsetConnected = false,
  });

  bool get isMuted => ringVolume == 0 || ringerMode != 2;

  factory DeviceVolumeDto.fromJson(Map<String, dynamic> json) {
    return DeviceVolumeDto(
      ringVolume: json['ringVolume'] as int? ?? 0,
      maxRingVolume: json['maxRingVolume'] as int? ?? 15,
      callVolume: json['callVolume'] as int? ?? 0,
      maxCallVolume: json['maxCallVolume'] as int? ?? 5,
      ringerMode: json['ringerMode'] as int? ?? 2,
      isBluetoothConnected: json['isBluetoothConnected'] as bool? ?? false,
      bluetoothDeviceName: json['bluetoothDeviceName'] as String? ?? '',
      isWiredHeadsetConnected: json['isWiredHeadsetConnected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'ringVolume': ringVolume,
        'maxRingVolume': maxRingVolume,
        'callVolume': callVolume,
        'maxCallVolume': maxCallVolume,
        'ringerMode': ringerMode,
        'isBluetoothConnected': isBluetoothConnected,
        'bluetoothDeviceName': bluetoothDeviceName,
        'isWiredHeadsetConnected': isWiredHeadsetConnected,
      };

  DeviceVolumeDto copyWith({
    int? ringVolume,
    int? maxRingVolume,
    int? callVolume,
    int? maxCallVolume,
    int? ringerMode,
    bool? isBluetoothConnected,
    String? bluetoothDeviceName,
    bool? isWiredHeadsetConnected,
  }) {
    return DeviceVolumeDto(
      ringVolume: ringVolume ?? this.ringVolume,
      maxRingVolume: maxRingVolume ?? this.maxRingVolume,
      callVolume: callVolume ?? this.callVolume,
      maxCallVolume: maxCallVolume ?? this.maxCallVolume,
      ringerMode: ringerMode ?? this.ringerMode,
      isBluetoothConnected: isBluetoothConnected ?? this.isBluetoothConnected,
      bluetoothDeviceName: bluetoothDeviceName ?? this.bluetoothDeviceName,
      isWiredHeadsetConnected: isWiredHeadsetConnected ?? this.isWiredHeadsetConnected,
    );
  }
}

