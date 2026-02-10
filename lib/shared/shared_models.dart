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
      address: json['address'],
      body: json['body'],
      date: json['date'],
      isSent: json['isSent'],
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