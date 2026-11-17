// lib/client/utils/recipient_importer.dart

import 'package:uuid/uuid.dart';
import '../../shared/shared_models.dart';
import 'sms_counter.dart';

class RawRecipientData {
  final String phone;
  final String? name;
  final Map<String, String> customFields;
  final bool isValid;
  final String? error;

  const RawRecipientData({
    required this.phone,
    this.name,
    this.customFields = const {},
    required this.isValid,
    this.error,
  });
}

class RecipientImporter {
  static const _uuid = Uuid();

  /// Normalizes phone number into E.164-like standard (+7XXXXXXXXXX or +XXXXXXXXXXX)
  static String normalizePhone(String raw) {
    String cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return '';

    // Handle Russian/Kazakhstan numbers: 8XXXXXXXXXX -> +7XXXXXXXXXX
    if (cleaned.startsWith('8') && cleaned.length == 11) {
      cleaned = '+7${cleaned.substring(1)}';
    } else if (cleaned.startsWith('7') && cleaned.length == 11) {
      cleaned = '+$cleaned';
    } else if (!cleaned.startsWith('+') && cleaned.length >= 10) {
      // Default to plus if valid length
      cleaned = '+$cleaned';
    }

    return cleaned;
  }

  /// Validates normalized phone
  static bool isValidPhone(String phone) {
    if (phone.isEmpty) return false;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7 && digits.length <= 15;
  }

  /// Checks if two phone number strings refer to the same phone number
  static bool isSamePhone(String a, String b) {
    if (a == b) return true;
    final nA = normalizePhone(a);
    final nB = normalizePhone(b);
    if (nA.isNotEmpty && nA == nB) return true;
    final dA = a.replaceAll(RegExp(r'\D'), '');
    final dB = b.replaceAll(RegExp(r'\D'), '');
    if (dA.isNotEmpty && dB.isNotEmpty) {
      if (dA == dB) return true;
      if (dA.length >= 10 && dB.length >= 10) {
        return dA.substring(dA.length - 10) == dB.substring(dB.length - 10);
      }
    }
    return false;
  }

  /// Parses multi-line text input (e.g. "+79991234567, Иван" or one number per line)
  static List<RawRecipientData> parseTextInput(String text) {
    if (text.trim().isEmpty) return [];

    final lines = text.split(RegExp(r'[\r\n]+'));
    final results = <RawRecipientData>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Check if line contains a comma or semicolon separator
      String phonePart = trimmed;
      String? namePart;

      if (trimmed.contains(',') || trimmed.contains(';') || trimmed.contains('\t')) {
        final parts = trimmed.split(RegExp(r'[,;\t]'));
        if (parts.isNotEmpty) {
          phonePart = parts[0].trim();
          if (parts.length > 1 && parts[1].trim().isNotEmpty) {
            namePart = parts[1].trim();
          }
        }
      }

      final normalized = normalizePhone(phonePart);
      final valid = isValidPhone(normalized);

      results.add(RawRecipientData(
        phone: normalized.isNotEmpty ? normalized : phonePart,
        name: namePart,
        isValid: valid,
        error: valid ? null : "Неверный формат номера",
      ));
    }

    return results;
  }

  /// Parses CSV or TSV string into structured recipient rows
  static List<RawRecipientData> parseCsv(String csvContent) {
    if (csvContent.trim().isEmpty) return [];

    final lines = csvContent.split(RegExp(r'[\r\n]+')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return [];

    // Detect separator: comma, semicolon, tab
    final firstLine = lines.first;
    String separator = ',';
    if (firstLine.contains(';') && !firstLine.contains(',')) {
      separator = ';';
    } else if (firstLine.contains('\t')) {
      separator = '\t';
    }

    // Check if first line is a header
    final headerCandidates = firstLine.split(separator).map((e) => e.replaceAll('"', '').trim().toLowerCase()).toList();
    int phoneColIdx = -1;
    int nameColIdx = -1;

    for (int i = 0; i < headerCandidates.length; i++) {
      final h = headerCandidates[i];
      if (h == 'phone' || h == 'телефон' || h == 'номер' || h == 'mobile' || h == 'tel' || h == 'тел') {
        phoneColIdx = i;
      } else if (h == 'name' || h == 'имя' || h == 'фио' || h == 'клиент' || h == 'client') {
        nameColIdx = i;
      }
    }

    bool hasHeader = phoneColIdx != -1 || nameColIdx != -1;
    List<String> headers = hasHeader
        ? firstLine.split(separator).map((e) => e.replaceAll('"', '').trim()).toList()
        : [];

    final startIndex = hasHeader ? 1 : 0;
    if (!hasHeader) {
      // Guess phone is col 0, name is col 1
      phoneColIdx = 0;
      nameColIdx = 1;
    }

    final results = <RawRecipientData>[];

    for (int i = startIndex; i < lines.length; i++) {
      final row = lines[i].split(separator).map((e) => e.replaceAll('"', '').trim()).toList();
      if (row.isEmpty || (row.length == 1 && row[0].isEmpty)) continue;

      String rawPhone = (phoneColIdx >= 0 && phoneColIdx < row.length) ? row[phoneColIdx] : '';
      String? name = (nameColIdx >= 0 && nameColIdx < row.length && row[nameColIdx].isNotEmpty) ? row[nameColIdx] : null;

      final customFields = <String, String>{};
      if (hasHeader) {
        for (int c = 0; c < row.length && c < headers.length; c++) {
          final headerKey = headers[c];
          if (c != phoneColIdx && c != nameColIdx && row[c].isNotEmpty) {
            customFields[headerKey] = row[c];
          }
        }
      }

      final normalized = normalizePhone(rawPhone);
      final valid = isValidPhone(normalized);

      results.add(RawRecipientData(
        phone: normalized.isNotEmpty ? normalized : rawPhone,
        name: name,
        customFields: customFields,
        isValid: valid,
        error: valid ? null : "Неверный номер",
      ));
    }

    return results;
  }

  /// Interpolates template tags like `{name}`, `{phone}`, `{field}` with recipient values
  static String interpolate(String template, RawRecipientData recipient) {
    var text = template;

    // Standard tags
    text = text.replaceAll('{phone}', recipient.phone);
    text = text.replaceAll('{номер}', recipient.phone);
    text = text.replaceAll('{name}', recipient.name ?? '');
    text = text.replaceAll('{имя}', recipient.name ?? '');

    // Custom variable tags
    recipient.customFields.forEach((key, val) {
      text = text.replaceAll('{$key}', val);
      text = text.replaceAll('{$key}'.toLowerCase(), val);
    });

    return text;
  }

  /// Builds a list of finalized CampaignItemDto models from raw recipients and template
  static List<CampaignItemDto> buildCampaignItems({
    required List<RawRecipientData> rawList,
    required String template,
    bool skipDuplicates = true,
  }) {
    final seenPhones = <String>{};
    final items = <CampaignItemDto>[];

    for (final raw in rawList) {
      if (!raw.isValid) continue;

      if (skipDuplicates) {
        if (seenPhones.contains(raw.phone)) {
          continue;
        }
        seenPhones.add(raw.phone);
      }

      final interpolated = interpolate(template, raw);
      final countResult = SmsCounter.count(interpolated);

      items.add(CampaignItemDto(
        id: _uuid.v4(),
        phone: raw.phone,
        name: raw.name,
        customFields: raw.customFields,
        interpolatedText: interpolated,
        partsCount: countResult.partsCount,
        status: 'pending',
      ));
    }

    return items;
  }
}
