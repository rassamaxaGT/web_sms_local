import '../../shared/shared_models.dart';
import 'json_file_storage.dart';

class TemplateStorage {
  final JsonFileStorage<SmsTemplateDto> _storage = JsonFileStorage<SmsTemplateDto>(
    fileName: 'sms_templates.json',
    fromJson: SmsTemplateDto.fromJson,
    toJson: (item) => item.toJson(),
  );

  Future<List<SmsTemplateDto>> loadTemplates() => _storage.loadAllOrEmpty();

  Future<void> saveTemplates(List<SmsTemplateDto> templates) => _storage.saveAll(templates);

  Future<void> addOrUpdateTemplate(SmsTemplateDto template) {
    return _storage.mutate((templates) {
      final index = templates.indexWhere((e) => e.id == template.id);
      if (index != -1) {
        templates[index] = template;
      } else {
        templates.add(template);
      }
    });
  }

  Future<void> deleteTemplate(String id) {
    return _storage.mutate((templates) {
      templates.removeWhere((e) => e.id == id);
    });
  }
}
