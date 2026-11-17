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

class ContactDto {
  final String phone;
  final String name;
  final String notes;
  final int? callbackTimeMs;

  const ContactDto({
    required this.phone,
    required this.name,
    required this.notes,
    this.callbackTimeMs,
  });

  DateTime? get callbackTime => callbackTimeMs != null
      ? DateTime.fromMillisecondsSinceEpoch(callbackTimeMs!)
      : null;

  ContactDto copyWith({
    String? phone,
    String? name,
    String? notes,
    int? callbackTimeMs,
  }) {
    return ContactDto(
      phone: phone ?? this.phone,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      callbackTimeMs: callbackTimeMs ?? this.callbackTimeMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'name': name,
        'notes': notes,
        'callbackTimeMs': callbackTimeMs,
      };

  factory ContactDto.fromJson(Map<String, dynamic> json) {
    return ContactDto(
      phone: json['phone']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      callbackTimeMs: (json['callbackTimeMs'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactDto &&
          phone == other.phone &&
          name == other.name &&
          notes == other.notes &&
          callbackTimeMs == other.callbackTimeMs;

  @override
  int get hashCode => Object.hash(phone, name, notes, callbackTimeMs);
}
