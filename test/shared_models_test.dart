import 'package:flutter_test/flutter_test.dart';
import 'package:android_host/shared/shared_models.dart';

void main() {
  group('shared_models DTOs', () {
    test('SmsMessageDto handles missing/null fields safely and supports equality', () {
      final msg = SmsMessageDto.fromJson({});
      expect(msg.address, 'Unknown');
      expect(msg.body, '');
      expect(msg.date, 0);
      expect(msg.isSent, isFalse);

      final copy = msg.copyWith(body: 'Hi', isSent: true);
      expect(copy.body, 'Hi');
      expect(copy.isSent, isTrue);
      expect(copy == msg, isFalse);
      expect(copy == msg.copyWith(body: 'Hi', isSent: true), isTrue);
    });

    test('SimCardDto handles missing/null fields safely', () {
      final sim = SimCardDto.fromJson({});
      expect(sim.subscriptionId, -1);
      expect(sim.slotIndex, 0);
      expect(sim.carrierName, 'Unknown SIM');
    });

    test('SmsTemplateDto handles missing/null fields safely', () {
      final tpl = SmsTemplateDto.fromJson({});
      expect(tpl.id, '');
      expect(tpl.title, '');
      expect(tpl.body, '');
    });

    test('ContactDto handles numeric types safely', () {
      final contact = ContactDto.fromJson({
        'phone': '+79990001122',
        'name': 'Alex',
        'notes': 'VIP',
        'callbackTimeMs': 1700000000000.0,
      });
      expect(contact.phone, '+79990001122');
      expect(contact.callbackTimeMs, 1700000000000);
      expect(contact.callbackTime, isNotNull);
    });
  });
}
