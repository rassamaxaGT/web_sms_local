// lib/shared/shared_models.dart

class SmsMessageDto {
  final int? id;        // Уникальный ID сообщения в базе Android
  final int? threadId;  // ID цепочки (диалога)
  final String address;
  final String body;
  final int date;
  final bool isSent;
  final int? subId;

  SmsMessageDto({
    this.id,
    this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.isSent,
    this.subId,
  });

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
      id: json['id'],
      threadId: json['threadId'],
      address: json['address'] ?? "Unknown",
      body: json['body'] ?? "",
      date: json['date'] ?? 0,
      isSent: json['isSent'] ?? false,
      subId: json['subId'],
    );
  }
}

class SimCardDto {
  final int subscriptionId;
  final int slotIndex;
  final String carrierName;

  SimCardDto({
    required this.subscriptionId,
    required this.slotIndex,
    required this.carrierName,
  });

  Map<String, dynamic> toJson() => {
    'subscriptionId': subscriptionId,
    'slotIndex': slotIndex,
    'carrierName': carrierName,
  };

  factory SimCardDto.fromJson(Map<String, dynamic> json) {
    return SimCardDto(
      subscriptionId: json['subscriptionId'],
      slotIndex: json['slotIndex'],
      carrierName: json['carrierName'],
    );
  }
}

class SmsTemplateDto {
  final String id;
  final String title;
  final String body;

  SmsTemplateDto({
    required this.id,
    required this.title,
    required this.body,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
  };

  factory SmsTemplateDto.fromJson(Map<String, dynamic> json) {
    return SmsTemplateDto(
      id: json['id'],
      title: json['title'],
      body: json['body'],
    );
  }
}

class ContactDto {
  final String phone;
  final String name;
  final String notes;
  final int? callbackTimeMs;

  ContactDto({
    required this.phone,
    required this.name,
    required this.notes,
    this.callbackTimeMs,
  });

  DateTime? get callbackTime => callbackTimeMs != null
      ? DateTime.fromMillisecondsSinceEpoch(callbackTimeMs!)
      : null;

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'name': name,
        'notes': notes,
        'callbackTimeMs': callbackTimeMs,
      };

  factory ContactDto.fromJson(Map<String, dynamic> json) {
    return ContactDto(
      phone: json['phone'] ?? "",
      name: json['name'] ?? "",
      notes: json['notes'] ?? "",
      callbackTimeMs: json['callbackTimeMs'] as int?,
    );
  }
}