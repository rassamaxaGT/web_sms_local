import 'package:flutter/material.dart';

/// Single OKVED activity entry with code and Russian description
class OkvedItem {
  final String code;
  final String description;
  final bool isMain;

  const OkvedItem({
    required this.code,
    required this.description,
    this.isMain = false,
  });

  factory OkvedItem.fromJson(Map<String, dynamic> json, {bool isMain = false}) {
    return OkvedItem(
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      isMain: isMain,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'description': description,
    'isMain': isMain,
  };
}

/// Management info (director / president)
class ContractorManagement {
  final String name;
  final String post;

  const ContractorManagement({
    required this.name,
    required this.post,
  });

  factory ContractorManagement.fromJson(Map<String, dynamic> json) {
    return ContractorManagement(
      name: json['name']?.toString() ?? '',
      post: json['post']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'post': post,
  };
}

/// Organization or Individual Entrepreneur model from T-Bank contractor service
class ContractorDto {
  final String name;
  final String fullName;
  final String inn;
  final String ogrn;
  final String kpp;
  final String type; // 'LEGAL' (Юрлицо) or 'INDIVIDUAL' (ИП)
  final String status; // 'ACTIVE', 'LIQUIDATED', etc.
  final String address;
  final ContractorManagement? management;
  final String? mainOkvedCode;
  final List<OkvedItem> okvedList;
  final bool isOkvedLoaded;

  const ContractorDto({
    required this.name,
    required this.fullName,
    required this.inn,
    required this.ogrn,
    required this.kpp,
    required this.type,
    required this.status,
    required this.address,
    this.management,
    this.mainOkvedCode,
    this.okvedList = const [],
    this.isOkvedLoaded = false,
  });

  bool get isIndividual => type.toUpperCase() == 'INDIVIDUAL' || inn.length == 12;

  String get typeLabel => isIndividual ? 'ИП' : 'Юрлицо';

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  String get statusText {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return 'Действующая организация';
      case 'LIQUIDATING':
        return 'В процессе ликвидации';
      case 'LIQUIDATED':
        return 'Ликвидирована';
      case 'BANKRUPT':
        return 'Банкротство';
      default:
        return status.isNotEmpty ? status : 'Статус не указан';
    }
  }

  Color get statusColor {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return const Color(0xFF10B981); // Emerald / green
      case 'LIQUIDATING':
        return const Color(0xFFF59E0B); // Amber / orange
      case 'LIQUIDATED':
      case 'BANKRUPT':
        return const Color(0xFFEF4444); // Red
      default:
        return Colors.grey;
    }
  }

  /// Returns true if this contractor operates under OKVED 47.91 (Retail trade via mail or Internet / eCommerce seller)
  bool get isSeller {
    if (mainOkvedCode != null &&
        (mainOkvedCode == '47.91' || mainOkvedCode!.startsWith('47.91.'))) {
      return true;
    }
    return okvedList.any((item) =>
        item.code == '47.91' || item.code.startsWith('47.91.'));
  }

  ContractorDto copyWith({
    String? name,
    String? fullName,
    String? inn,
    String? ogrn,
    String? kpp,
    String? type,
    String? status,
    String? address,
    ContractorManagement? management,
    String? mainOkvedCode,
    List<OkvedItem>? okvedList,
    bool? isOkvedLoaded,
  }) {
    return ContractorDto(
      name: name ?? this.name,
      fullName: fullName ?? this.fullName,
      inn: inn ?? this.inn,
      ogrn: ogrn ?? this.ogrn,
      kpp: kpp ?? this.kpp,
      type: type ?? this.type,
      status: status ?? this.status,
      address: address ?? this.address,
      management: management ?? this.management,
      mainOkvedCode: mainOkvedCode ?? this.mainOkvedCode,
      okvedList: okvedList ?? this.okvedList,
      isOkvedLoaded: isOkvedLoaded ?? this.isOkvedLoaded,
    );
  }

  factory ContractorDto.fromDadataSuggestion(Map<String, dynamic> json) {
    final value = json['value']?.toString() ?? '';
    final data = (json['data'] as Map<String, dynamic>?) ?? {};
    
    final nameObj = data['name'] as Map<String, dynamic>?;
    final shortName = nameObj?['short_with_opf']?.toString() ?? value;
    final fullName = nameObj?['full_with_opf']?.toString() ?? shortName;
    
    final inn = data['inn']?.toString() ?? '';
    final ogrn = data['ogrn']?.toString() ?? '';
    final kpp = data['kpp']?.toString() ?? '';
    final type = data['type']?.toString() ?? (inn.length == 12 ? 'INDIVIDUAL' : 'LEGAL');
    
    final stateObj = data['state'] as Map<String, dynamic>?;
    final status = stateObj?['status']?.toString() ?? 'ACTIVE';
    
    final addressObj = data['address'] as Map<String, dynamic>?;
    final address = addressObj?['value']?.toString() ?? '';
    
    ContractorManagement? management;
    final mgmtObj = data['management'] as Map<String, dynamic>?;
    if (mgmtObj != null && mgmtObj['name'] != null) {
      management = ContractorManagement.fromJson(mgmtObj);
    }
    
    final mainOkved = data['okved']?.toString();
    
    return ContractorDto(
      name: shortName,
      fullName: fullName,
      inn: inn,
      ogrn: ogrn,
      kpp: kpp,
      type: type,
      status: status,
      address: address,
      management: management,
      mainOkvedCode: mainOkved,
      okvedList: const [],
      isOkvedLoaded: false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'fullName': fullName,
    'inn': inn,
    'ogrn': ogrn,
    'kpp': kpp,
    'type': type,
    'status': status,
    'address': address,
    'management': management?.toJson(),
    'mainOkvedCode': mainOkvedCode,
    'okvedList': okvedList.map((e) => e.toJson()).toList(),
    'isOkvedLoaded': isOkvedLoaded,
  };

  factory ContractorDto.fromJson(Map<String, dynamic> json) {
    return ContractorDto(
      name: json['name']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      inn: json['inn']?.toString() ?? '',
      ogrn: json['ogrn']?.toString() ?? '',
      kpp: json['kpp']?.toString() ?? '',
      type: json['type']?.toString() ?? 'LEGAL',
      status: json['status']?.toString() ?? 'ACTIVE',
      address: json['address']?.toString() ?? '',
      management: json['management'] != null
          ? ContractorManagement.fromJson(Map<String, dynamic>.from(json['management']))
          : null,
      mainOkvedCode: json['mainOkvedCode']?.toString(),
      okvedList: (json['okvedList'] as List?)
              ?.map((e) => OkvedItem.fromJson(Map<String, dynamic>.from(e), isMain: e['isMain'] == true))
              .toList() ??
          const [],
      isOkvedLoaded: json['isOkvedLoaded'] == true,
    );
  }

  /// Formats all requisites and activities as a clean multi-line string for copying
  String toFormattedRequisites() {
    final buffer = StringBuffer();
    buffer.writeln(name);
    if (fullName != name && fullName.isNotEmpty) {
      buffer.writeln('($fullName)');
    }
    buffer.writeln('Статус: $statusText');
    if (isSeller) {
      buffer.writeln('Категория: Селлер (ОКВЭД 47.91)');
    }
    buffer.writeln('ИНН: $inn');
    if (ogrn.isNotEmpty) {
      buffer.writeln('${isIndividual ? "ОГРНИП" : "ОГРН"}: $ogrn');
    }
    if (kpp.isNotEmpty) {
      buffer.writeln('КПП: $kpp');
    }
    if (management != null && management!.name.isNotEmpty) {
      buffer.writeln('${management!.post.isNotEmpty ? management!.post : "Руководитель"}: ${management!.name}');
    }
    if (address.isNotEmpty) {
      buffer.writeln('Адрес: $address');
    }
    final mainItems = okvedList.where((o) => o.isMain).toList();
    if (mainItems.isNotEmpty) {
      for (final m in mainItems) {
        final desc = m.description.isNotEmpty ? ' - ${m.description}' : '';
        buffer.writeln('Основной ОКВЭД: ${m.code}$desc');
      }
    } else if (mainOkvedCode != null && mainOkvedCode!.isNotEmpty) {
      buffer.writeln('Основной ОКВЭД: $mainOkvedCode');
    }
    final additionalItems = okvedList.where((o) => !o.isMain).toList();
    if (additionalItems.isNotEmpty) {
      buffer.writeln('\nДополнительные виды деятельности (ОКВЭД):');
      for (final item in additionalItems) {
        final desc = item.description.isNotEmpty ? ' — ${item.description}' : '';
        buffer.writeln('• ${item.code}$desc');
      }
    }
    return buffer.toString().trim();
  }
}
