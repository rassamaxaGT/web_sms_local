import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'dart:typed_data';

class SecurityService {
  late final Key _key;
  late final Encrypter _encrypter;

  SecurityService(String password) {
    final passBytes = utf8.encode(password);

    // Ключ 32 байта из SHA-256
    final keyDigest = sha256.convert(passBytes);
    _key = Key(Uint8List.fromList(keyDigest.bytes));

    _encrypter = Encrypter(AES(_key, mode: AESMode.cbc));
  }

  String encrypt(dynamic json) {
    final jsonString = jsonEncode(json);
    final iv = IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(jsonString, iv: iv);
    
    // Склеиваем IV и шифротекст для передачи
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setAll(0, iv.bytes);
    combined.setAll(iv.bytes.length, encrypted.bytes);
    
    return base64.encode(combined);
  }

  dynamic decrypt(String encryptedBase64) {
    try {
      final combined = base64.decode(encryptedBase64);
      if (combined.length < 16) throw Exception("Invalid data");

      // Извлекаем IV (первые 16 байт) и данные
      final iv = IV(combined.sublist(0, 16));
      final ciphertext = base64.encode(combined.sublist(16));

      final decrypted = _encrypter.decrypt64(ciphertext, iv: iv);
      return jsonDecode(decrypted);
    } catch (e) {
      throw Exception("Decryption failed. Check session/password.");
    }
  }
}
