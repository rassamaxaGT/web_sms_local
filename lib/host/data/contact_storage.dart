import '../../shared/shared_models.dart';
import 'json_file_storage.dart';

class ContactStorage {
  final JsonFileStorage<ContactDto> _storage = JsonFileStorage<ContactDto>(
    fileName: 'sms_contacts.json',
    fromJson: ContactDto.fromJson,
    toJson: (item) => item.toJson(),
  );

  Future<List<ContactDto>> loadContacts() => _storage.loadAllOrEmpty();

  Future<void> saveContacts(List<ContactDto> contacts) => _storage.saveAll(contacts);

  Future<void> addOrUpdateContact(ContactDto contact) {
    return _storage.mutate((contacts) {
      final index = contacts.indexWhere((e) => e.phone == contact.phone);
      if (index != -1) {
        contacts[index] = contact;
      } else {
        contacts.add(contact);
      }
    });
  }

  Future<void> deleteContact(String phone) {
    return _storage.mutate((contacts) {
      contacts.removeWhere((e) => e.phone == phone);
    });
  }
}
