import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../../shared/shared_models.dart';

class ContactStorage {
  static const String _fileName = 'sms_contacts.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<ContactDto>> loadContacts() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => ContactDto.fromJson(e)).toList();
    } catch (e) {
      debugPrint("Error loading contacts: $e");
      return [];
    }
  }

  Future<void> saveContacts(List<ContactDto> contacts) async {
    try {
      final file = await _getFile();
      final content = jsonEncode(contacts.map((e) => e.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint("Error saving contacts: $e");
    }
  }

  Future<void> addOrUpdateContact(ContactDto contact) async {
    final contacts = await loadContacts();
    final index = contacts.indexWhere((e) => e.phone == contact.phone);
    if (index != -1) {
      contacts[index] = contact;
    } else {
      contacts.add(contact);
    }
    await saveContacts(contacts);
  }

  Future<void> deleteContact(String phone) async {
    final contacts = await loadContacts();
    contacts.removeWhere((e) => e.phone == phone);
    await saveContacts(contacts);
  }
}
