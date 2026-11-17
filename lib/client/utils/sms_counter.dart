// lib/client/utils/sms_counter.dart

class SmsCountResult {
  final int characterCount;
  final int partsCount;
  final int remainingInCurrentPart;
  final int maxPartSize;
  final bool isUnicode;
  final String encodingName;

  const SmsCountResult({
    required this.characterCount,
    required this.partsCount,
    required this.remainingInCurrentPart,
    required this.maxPartSize,
    required this.isUnicode,
    required this.encodingName,
  });
}

class SmsCounter {
  // Standard GSM 7-bit character set check
  static const String _gsmBasic =
      "@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\x1BÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà";
  static const String _gsmExtended = "^{}\\[~]|€";

  static bool isGsmCharacter(int codeUnit) {
    final char = String.fromCharCode(codeUnit);
    return _gsmBasic.contains(char) || _gsmExtended.contains(char);
  }

  static SmsCountResult count(String text) {
    if (text.isEmpty) {
      return const SmsCountResult(
        characterCount: 0,
        partsCount: 1,
        remainingInCurrentPart: 160,
        maxPartSize: 160,
        isUnicode: false,
        encodingName: "GSM-7",
      );
    }

    bool hasUnicode = false;
    int gsmCharLength = 0;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (_gsmExtended.contains(char)) {
        gsmCharLength += 2; // Extended GSM chars cost 2 bytes
      } else if (_gsmBasic.contains(char)) {
        gsmCharLength += 1;
      } else {
        hasUnicode = true;
        break;
      }
    }

    if (hasUnicode) {
      final charCount = text.length;
      final int singleLimit = 70;
      final int multiLimit = 67;

      if (charCount <= singleLimit) {
        return SmsCountResult(
          characterCount: charCount,
          partsCount: 1,
          remainingInCurrentPart: singleLimit - charCount,
          maxPartSize: singleLimit,
          isUnicode: true,
          encodingName: "Unicode (Кириллица)",
        );
      } else {
        final parts = (charCount / multiLimit).ceil();
        final remaining = (parts * multiLimit) - charCount;
        return SmsCountResult(
          characterCount: charCount,
          partsCount: parts,
          remainingInCurrentPart: remaining,
          maxPartSize: multiLimit,
          isUnicode: true,
          encodingName: "Unicode (Кириллица)",
        );
      }
    } else {
      final int singleLimit = 160;
      final int multiLimit = 153;

      if (gsmCharLength <= singleLimit) {
        return SmsCountResult(
          characterCount: gsmCharLength,
          partsCount: 1,
          remainingInCurrentPart: singleLimit - gsmCharLength,
          maxPartSize: singleLimit,
          isUnicode: false,
          encodingName: "GSM-7 (Латиница)",
        );
      } else {
        final parts = (gsmCharLength / multiLimit).ceil();
        final remaining = (parts * multiLimit) - gsmCharLength;
        return SmsCountResult(
          characterCount: gsmCharLength,
          partsCount: parts,
          remainingInCurrentPart: remaining,
          maxPartSize: multiLimit,
          isUnicode: false,
          encodingName: "GSM-7 (Латиница)",
        );
      }
    }
  }
}
