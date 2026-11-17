import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:android_host/shared/security_service.dart';

void main() {
  group('SecurityService', () {
    test('rejects empty password', () {
      expect(() => SecurityService(''), throwsArgumentError);
    });

    test('encrypts and decrypts JSON payloads', () {
      final service = SecurityService('super-secret-pass-123');
      final payload = {'address': '+79991234567', 'body': 'Привет!', 'subId': 1};

      final encrypted = service.encrypt(payload);
      final decrypted = service.decrypt(encrypted);

      expect(decrypted, equals(payload));
    });

    test('fails decryption with wrong password', () {
      final sender = SecurityService('password-a');
      final receiver = SecurityService('password-b');

      final encrypted = sender.encrypt({'msg': 'secret'});
      expect(() => receiver.decrypt(encrypted), throwsException);
    });

    test('detects ciphertext tampering via HMAC (Encrypt-then-MAC)', () {
      final service = SecurityService('tamper-test-pass');
      final encrypted = service.encrypt({'msg': 'hello'});
      final bytes = base64.decode(encrypted);

      // Flip a bit in the ciphertext region (after 16-byte IV, before 32-byte MAC)
      bytes[20] ^= 0x01;
      final tampered = base64.encode(bytes);

      expect(() => service.decrypt(tampered), throwsException);
    });

    test('verifies authToken consistently', () {
      final a = SecurityService('same-pass');
      final b = SecurityService('same-pass');
      final c = SecurityService('other-pass');

      expect(b.verifyAuthToken(a.authToken), isTrue);
      expect(c.verifyAuthToken(a.authToken), isFalse);
      expect(a.verifyAuthToken(null), isFalse);
      expect(a.verifyAuthToken(''), isFalse);
    });
  });
}
