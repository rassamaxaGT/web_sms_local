import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// Provides key derivation (PBKDF2-HMAC-SHA256), authenticated encryption
/// (AES-256-CBC + HMAC-SHA256 Encrypt-then-MAC), and bearer auth tokens.
class SecurityService {
  static const int _pbkdf2Iterations = 10000;
  static const int _ivLength = 16;
  static const int _macLength = 32;
  static const int _minCiphertextLength = 16;
  static final List<int> _kdfSalt = utf8.encode('web_sms_local_kdf_v1');

  late final Encrypter _encrypter;
  late final List<int> _macKey;
  late final String _authToken;

  SecurityService(String password) {
    if (password.isEmpty) {
      throw ArgumentError('Password cannot be empty');
    }

    final masterKey = _derivePbkdf2(utf8.encode(password), _kdfSalt, _pbkdf2Iterations, 32);
    final encKeyBytes = Hmac(sha256, masterKey).convert(utf8.encode('enc')).bytes;
    _macKey = Hmac(sha256, masterKey).convert(utf8.encode('mac')).bytes;
    final authBytes = Hmac(sha256, masterKey).convert(utf8.encode('auth')).bytes;
    _authToken = base64UrlEncode(authBytes);

    final key = Key(Uint8List.fromList(encKeyBytes));
    _encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  }

  String get authToken => _authToken;

  bool verifyAuthToken(String? token) {
    if (token == null || token.isEmpty) return false;
    return constantTimeEquals(utf8.encode(token), utf8.encode(_authToken));
  }

  String encrypt(dynamic json) {
    final jsonString = jsonEncode(json);
    final iv = IV.fromSecureRandom(_ivLength);
    final encrypted = _encrypter.encrypt(jsonString, iv: iv);

    final ivAndCipher = Uint8List(_ivLength + encrypted.bytes.length);
    ivAndCipher.setAll(0, iv.bytes);
    ivAndCipher.setAll(_ivLength, encrypted.bytes);

    final mac = Hmac(sha256, _macKey).convert(ivAndCipher).bytes;

    final combined = Uint8List(ivAndCipher.length + _macLength);
    combined.setAll(0, ivAndCipher);
    combined.setAll(ivAndCipher.length, mac);

    return base64.encode(combined);
  }

  dynamic decrypt(String encryptedBase64) {
    try {
      final combined = base64.decode(encryptedBase64);
      if (combined.length < _ivLength + _minCiphertextLength + _macLength) {
        throw const FormatException('Invalid encrypted payload length');
      }

      final macStart = combined.length - _macLength;
      final ivAndCipher = combined.sublist(0, macStart);
      final receivedMac = combined.sublist(macStart);
      final expectedMac = Hmac(sha256, _macKey).convert(ivAndCipher).bytes;

      if (!constantTimeEquals(receivedMac, expectedMac)) {
        throw const FormatException('MAC verification failed');
      }

      final iv = IV(Uint8List.fromList(ivAndCipher.sublist(0, _ivLength)));
      final ciphertext = Encrypted(Uint8List.fromList(ivAndCipher.sublist(_ivLength)));

      final decrypted = _encrypter.decrypt(ciphertext, iv: iv);
      return jsonDecode(decrypted);
    } catch (_) {
      throw Exception('Decryption failed. Check session/password.');
    }
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Uint8List _derivePbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    const hashLen = 32;
    final numBlocks = (keyLength + hashLen - 1) ~/ hashLen;
    final result = BytesBuilder(copy: false);

    for (var block = 1; block <= numBlocks; block++) {
      final blockInput = Uint8List(salt.length + 4)
        ..setAll(0, salt)
        ..[salt.length] = (block >> 24) & 0xff
        ..[salt.length + 1] = (block >> 16) & 0xff
        ..[salt.length + 2] = (block >> 8) & 0xff
        ..[salt.length + 3] = block & 0xff;

      var u = Uint8List.fromList(hmac.convert(blockInput).bytes);
      final t = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < hashLen; j++) {
          t[j] ^= u[j];
        }
      }
      result.add(t);
    }

    return Uint8List.fromList(result.toBytes().sublist(0, keyLength));
  }
}
