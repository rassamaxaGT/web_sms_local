import 'package:flutter_test/flutter_test.dart';
import 'package:android_host/shared/contractor_models.dart';
import 'package:android_host/client/data/tbank_contractor_service.dart';

void main() {
  group('Contractor Models & Formatting', () {
    test('ContractorDto formatted requisites includes OKVED codes', () {
      const contractor = ContractorDto(
        name: 'ПАО СБЕРБАНК',
        fullName: 'ПУБЛИЧНОЕ АКЦИОНЕРНОЕ ОБЩЕСТВО "СБЕРБАНК РОССИИ"',
        inn: '7707083893',
        ogrn: '1027700132195',
        kpp: '773601001',
        type: 'LEGAL',
        status: 'ACTIVE',
        address: 'г Москва, ул Вавилова, д 19',
        management: ContractorManagement(
          name: 'Греф Герман Оскарович',
          post: 'ПРЕЗИДЕНТ, ПРЕДСЕДАТЕЛЬ ПРАВЛЕНИЯ',
        ),
        mainOkvedCode: '64.19',
        okvedList: [
          OkvedItem(
            code: '64.19',
            description: 'Денежное посредничество прочее',
            isMain: true,
          ),
          OkvedItem(
            code: '62.09',
            description: 'Деятельность по вычислительной технике',
            isMain: false,
          ),
        ],
        isOkvedLoaded: true,
      );

      expect(contractor.isIndividual, isFalse);
      expect(contractor.isActive, isTrue);
      expect(contractor.typeLabel, equals('Юрлицо'));

      final formatted = contractor.toFormattedRequisites();
      expect(formatted, contains('ПАО СБЕРБАНК'));
      expect(formatted, contains('ИНН: 7707083893'));
      expect(formatted, contains('ОГРН: 1027700132195'));
      expect(formatted, contains('Греф Герман Оскарович'));
      expect(formatted, contains('Основной ОКВЭД: 64.19 - Денежное посредничество прочее'));
      expect(formatted, contains('62.09 — Деятельность по вычислительной технике'));
    });

    test('ContractorDto identifies Individual Entrepreneur correctly', () {
      const ip = ContractorDto(
        name: 'ИП Иванов Иван Иванович',
        fullName: 'Индивидуальный предприниматель Иванов Иван Иванович',
        inn: '770123456789',
        ogrn: '315774600000000',
        kpp: '',
        type: 'INDIVIDUAL',
        status: 'ACTIVE',
        address: 'г Москва',
      );

      expect(ip.isIndividual, isTrue);
      expect(ip.typeLabel, equals('ИП'));
      final formatted = ip.toFormattedRequisites();
      expect(formatted, contains('ОГРНИП: 315774600000000'));
    });

    test('ContractorDto automatically identifies Seller by OKVED 47.91', () {
      const nonSeller = ContractorDto(
        name: 'ООО Ромашка',
        fullName: 'ООО Ромашка',
        inn: '7701000000',
        ogrn: '1027700000000',
        kpp: '770101001',
        type: 'LEGAL',
        status: 'ACTIVE',
        address: 'г Москва',
        mainOkvedCode: '62.01',
      );
      expect(nonSeller.isSeller, isFalse);

      // Seller with 47.91 in okvedList
      final sellerAdditional = nonSeller.copyWith(
        okvedList: const [
          OkvedItem(code: '62.01', description: 'Разработка ПО', isMain: true),
          OkvedItem(code: '47.91', description: 'Торговля по почте или по сети Интернет', isMain: false),
        ],
      );
      expect(sellerAdditional.isSeller, isTrue);
      expect(sellerAdditional.toFormattedRequisites(), contains('Селлер (ОКВЭД 47.91)'));

      // Seller with 47.91.2 as main code
      final sellerMain = nonSeller.copyWith(
        mainOkvedCode: '47.91.2',
        okvedList: const [
          OkvedItem(code: '47.91.2', description: 'Торговля через интернет', isMain: true),
        ],
      );
      expect(sellerMain.isSeller, isTrue);
      expect(sellerMain.toFormattedRequisites(), contains('Селлер (ОКВЭД 47.91)'));
    });
  });

  group('TBankContractorService Live Integration Tests', () {
    test('Searches Sberbank by INN 7707083893 with T-Bank suggest endpoint', () async {
      final service = TBankContractorService();
      final results = await service.search('7707083893');

      expect(results, isNotEmpty);
      final sber = results.firstWhere((r) => r.inn == '7707083893');
      expect(sber.name, contains('СБЕРБАНК'));
      expect(sber.ogrn, equals('1027700132195'));
      expect(sber.isIndividual, isFalse);
      expect(sber.status, equals('ACTIVE'));

      // Test OKVED breakdown
      final enriched = await service.fetchOkvedDetails(sber);
      expect(enriched.isOkvedLoaded, isTrue);
      expect(enriched.okvedList, isNotEmpty);
      expect(enriched.okvedList.length, greaterThan(1));
      
      // Verify every OKVED code has a description
      for (final item in enriched.okvedList) {
        expect(item.code, isNotEmpty);
        expect(item.description, isNotEmpty, reason: 'Code ${item.code} missing description');
      }

      // Verify at least one main OKVED
      expect(enriched.okvedList.any((o) => o.isMain), isTrue);
      final mainItem = enriched.okvedList.firstWhere((o) => o.isMain);
      expect(mainItem.code, equals('64.19'));
      expect(mainItem.description, isNotEmpty);

      // Verify additional OKVEDs exist and all have descriptions
      final additionals = enriched.okvedList.where((o) => !o.isMain).toList();
      expect(additionals, isNotEmpty);
      for (final add in additionals) {
        expect(add.description, isNotEmpty);
      }
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('Searches and fetches OKVED for an Individual Entrepreneur (ИП)', () async {
      final service = TBankContractorService();
      // Search for a known ИП or query "ИП"
      final results = await service.search('ИП Иванов');
      expect(results, isNotEmpty);
      final ip = results.firstWhere((r) => r.isIndividual);
      expect(ip.isIndividual, isTrue);
      expect(ip.ogrn, isNotEmpty);

      final enriched = await service.fetchOkvedDetails(ip);
      expect(enriched.isOkvedLoaded, isTrue);
      expect(enriched.okvedList, isNotEmpty);
      // All codes must have descriptions
      for (final item in enriched.okvedList) {
        expect(item.code, isNotEmpty);
        expect(item.description, isNotEmpty, reason: 'IP code ${item.code} missing description');
      }
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
