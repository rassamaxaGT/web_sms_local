import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../../shared/shared_models.dart';

class TemplateStorage {
  static const String _fileName = 'sms_templates.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<SmsTemplateDto>> loadTemplates() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) => SmsTemplateDto.fromJson(e)).toList();
    } catch (e) {
      debugPrint("Error loading templates: $e");
      return [];
    }
  }

  Future<void> saveTemplates(List<SmsTemplateDto> templates) async {
    try {
      final file = await _getFile();
      final content = jsonEncode(templates.map((e) => e.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint("Error saving templates: $e");
    }
  }

  Future<void> addOrUpdateTemplate(SmsTemplateDto template) async {
    final templates = await loadTemplates();
    final index = templates.indexWhere((e) => e.id == template.id);
    if (index != -1) {
      templates[index] = template;
    } else {
      templates.add(template);
    }
    await saveTemplates(templates);
  }

  Future<void> deleteTemplate(String id) async {
    final templates = await loadTemplates();
    templates.removeWhere((e) => e.id == id);
    await saveTemplates(templates);
  }
}
