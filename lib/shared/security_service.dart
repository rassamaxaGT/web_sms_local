import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';

class SecurityService {
  late final Key _key;
  late final IV _iv;
  late final Encrypter _encrypter;

  SecurityService(String password) {
    final passBytes = utf8.encode(password);

    // Ключ 32 байта из SHA-256
    final keyDigest = sha256.convert(passBytes);
    _key = Key(Uint8List.fromList(keyDigest.bytes));

    // IV 16 байт из MD5 (теперь он всегда одинаковый для одного пароля)
    final ivDigest = md5.convert(passBytes);
    _iv = IV(Uint8List.fromList(ivDigest.bytes));

    _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));
  }

  String encrypt(dynamic json) {
    final jsonString = jsonEncode(json);
    return _encrypter.encrypt(jsonString, iv: _iv).base64;
  }

  dynamic decrypt(String encryptedBase64) {
    try {
      final decrypted = _encrypter.decrypt64(encryptedBase64, iv: _iv);
      return jsonDecode(decrypted);
    } catch (e) {
      throw Exception("Decryption failed. Check session/password.");
    }
  }
}
