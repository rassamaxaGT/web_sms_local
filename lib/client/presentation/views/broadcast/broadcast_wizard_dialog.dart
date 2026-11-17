// lib/client/presentation/views/broadcast/broadcast_wizard_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../shared/shared_models.dart';
import '../../../../shared/theme.dart';
import '../../../logic/providers.dart';
import '../../../utils/sms_counter.dart';
import '../../../utils/recipient_importer.dart';

class BroadcastWizardDialog extends ConsumerStatefulWidget {
  const BroadcastWizardDialog({super.key});

  @override
  ConsumerState<BroadcastWizardDialog> createState() => _BroadcastWizardDialogState();
}

class _BroadcastWizardDialogState extends ConsumerState<BroadcastWizardDialog> {
  static const _uuid = Uuid();
  int _currentStep = 0;

  // Step 1: Recipients State
  int _recipientSourceTab = 0; // 0: Text, 1: Contacts, 2: CSV
  final TextEditingController _rawTextCtrl = TextEditingController();
  final TextEditingController _csvTextCtrl = TextEditingController();
  final TextEditingController _campaignTitleCtrl = TextEditingController(text: "Рассылка ${DateTime.now().day}.${DateTime.now().month.toString().padLeft(2, '0')}");
  final Set<String> _selectedContactPhones = {};
  String _contactSearchQuery = "";

  List<RawRecipientData> _parsedRecipients = [];

  // Step 2: Message & Template State
  final TextEditingController _templateCtrl = TextEditingController();
  int _previewRecipientIndex = 0;

  // Step 3: Settings State
  String _simMode = 'single'; // 'single' or 'round_robin'
  int? _selectedSingleSubId;
  final Set<int> _selectedRoundRobinSubIds = {};
  int _intervalSeconds = 6;
  int _randomJitterSeconds = 2;
  bool _skipDuplicates = true;

  @override
  void initState() {
    super.initState();
    _rawTextCtrl.addListener(_onRecipientsChanged);
    _csvTextCtrl.addListener(_onRecipientsChanged);
    _templateCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _rawTextCtrl.dispose();
    _csvTextCtrl.dispose();
    _campaignTitleCtrl.dispose();
    _templateCtrl.dispose();
    super.dispose();
  }

  void _onRecipientsChanged() {
    if (_recipientSourceTab == 0) {
      _parsedRecipients = RecipientImporter.parseTextInput(_rawTextCtrl.text);
    } else if (_recipientSourceTab == 2) {
      _parsedRecipients = RecipientImporter.parseCsv(_csvTextCtrl.text);
    }
    setState(() {});
  }

  void _updateRecipientsFromContacts(List<ContactDto> allContacts) {
    _parsedRecipients = allContacts
        .where((c) => _selectedContactPhones.contains(c.phone))
        .map((c) => RawRecipientData(
              phone: RecipientImporter.normalizePhone(c.phone),
              name: c.name.isNotEmpty ? c.name : null,
              customFields: c.notes.isNotEmpty ? {'notes': c.notes} : {},
              isValid: RecipientImporter.isValidPhone(RecipientImporter.normalizePhone(c.phone)),
            ))
        .toList();
    setState(() {});
  }

  List<CampaignItemDto> _buildFinalItems() {
    return RecipientImporter.buildCampaignItems(
      rawList: _parsedRecipients,
      template: _templateCtrl.text.trim(),
      skipDuplicates: _skipDuplicates,
    );
  }

  Future<void> _createAndLaunch({bool startImmediately = true}) async {
    final finalItems = _buildFinalItems();
    if (finalItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Нет валидных получателей для рассылки!"),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final sims = ref.read(simsProvider);
    List<int> chosenSubIds = [];
    if (_simMode == 'single') {
      if (_selectedSingleSubId != null) {
        chosenSubIds = [_selectedSingleSubId!];
      } else if (sims.isNotEmpty) {
        chosenSubIds = [sims.first.subscriptionId];
      }
    } else {
      if (_selectedRoundRobinSubIds.isNotEmpty) {
        chosenSubIds = _selectedRoundRobinSubIds.toList();
      } else {
        chosenSubIds = sims.map((s) => s.subscriptionId).toList();
      }
    }

    final campaignId = _uuid.v4();
    final newCampaign = CampaignDto(
      id: campaignId,
      title: _campaignTitleCtrl.text.trim().isNotEmpty
          ? _campaignTitleCtrl.text.trim()
          : "Рассылка ${DateTime.now().toLocal().toString().substring(0, 16)}",
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      status: startImmediately ? 'running' : 'draft',
      templateBody: _templateCtrl.text,
      simMode: _simMode,
      selectedSubIds: chosenSubIds,
      intervalSeconds: _intervalSeconds,
      randomJitterSeconds: _randomJitterSeconds,
      skipDuplicates: _skipDuplicates,
      items: finalItems,
      totalCount: finalItems.length,
      sentCount: 0,
      failedCount: 0,
    );

    try {
      await ref.read(campaignsProvider.notifier).create(newCampaign);
      if (startImmediately) {
        await ref.read(campaignsProvider.notifier).start(campaignId);
      }
      ref.read(selectedCampaignIdProvider.notifier).select(campaignId);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              startImmediately ? "Рассылка успешно запущена!" : "Черновик рассылки сохранен.",
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ошибка создания рассылки: $e"),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      child: Container(
        width: 820,
        height: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Top Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "МАСТЕР СОЗДАНИЯ РАССЫЛКИ",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontFamily: 'Outfit',
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getStepSubtitle(_currentStep),
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  hoverColor: Colors.white10,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Step Indicator Tabs
            _buildStepIndicator(),

            const SizedBox(height: 20),

            // Step Content Body
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: _buildCurrentStepContent(),
              ),
            ),

            const SizedBox(height: 20),

            // Navigation Bottom Bar
            Row(
              children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _currentStep--),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text("Назад"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                const Spacer(),
                if (_currentStep < 3)
                  ElevatedButton.icon(
                    onPressed: _canProceedNext() ? () => setState(() => _currentStep++) : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text("Далее"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                else ...[
                  OutlinedButton(
                    onPressed: () => _createAndLaunch(startImmediately: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Сохранить черновик"),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _createAndLaunch(startImmediately: true),
                    icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                    label: const Text("Запустить рассылку"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getStepSubtitle(int step) {
    switch (step) {
      case 0:
        return "Шаг 1 из 4: Задайте название и добавьте список получателей";
      case 1:
        return "Шаг 2 из 4: Напишите текст SMS или выберите шаблон";
      case 2:
        return "Шаг 3 из 4: Настройте интервалы и выбор SIM-карты";
      case 3:
        return "Шаг 4 из 4: Проверьте параметры и подтвердите запуск";
      default:
        return "";
    }
  }

  Widget _buildStepIndicator() {
    final steps = ["1. Получатели", "2. Сообщение", "3. Настройки", "4. Запуск"];
    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = index == _currentStep;
        final isPassed = index < _currentStep;
        return Expanded(
          child: InkWell(
            onTap: index < _currentStep ? () => setState(() => _currentStep = index) : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: EdgeInsets.only(right: index < steps.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : isPassed
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive
                      ? AppColors.accent
                      : isPassed
                          ? AppColors.success.withValues(alpha: 0.4)
                          : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isPassed ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 14,
                    color: isActive
                        ? AppColors.accent
                        : isPassed
                            ? AppColors.success
                            : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      steps[index],
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: isActive
                            ? AppColors.textPrimary
                            : isPassed
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  bool _canProceedNext() {
    if (_currentStep == 0) {
      return _parsedRecipients.any((r) => r.isValid);
    }
    if (_currentStep == 1) {
      return _templateCtrl.text.trim().isNotEmpty;
    }
    return true;
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Recipients();
      case 1:
        return _buildStep2Message();
      case 2:
        return _buildStep3Settings();
      case 3:
        return _buildStep4Summary();
      default:
        return const SizedBox.shrink();
    }
  }

  // === STEP 1: RECIPIENTS ===
  Widget _buildStep1Recipients() {
    final validCount = _parsedRecipients.where((r) => r.isValid).length;
    final invalidCount = _parsedRecipients.where((r) => !r.isValid).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _campaignTitleCtrl,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: "Название кампании",
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.black26,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Tabs: Text, Contacts, CSV
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _buildSubTabButton(0, "Список / Вручную", Icons.edit_note_rounded),
              _buildSubTabButton(1, "Из контактов", Icons.contacts_rounded),
              _buildSubTabButton(2, "Импорт CSV / TXT", Icons.upload_file_rounded),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // SubTab Content
        Expanded(
          child: _recipientSourceTab == 0
              ? _buildManualTextInput()
              : _recipientSourceTab == 1
                  ? _buildContactsPicker()
                  : _buildCsvInput(),
        ),

        const SizedBox(height: 10),

        // Stats strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.people_alt_rounded, size: 16, color: validCount > 0 ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                "Всего номеров: ${_parsedRecipients.length}",
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              Text(
                "Валидных: $validCount",
                style: const TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.bold),
              ),
              if (invalidCount > 0) ...[
                const SizedBox(width: 16),
                Text(
                  "С ошибкой: $invalidCount",
                  style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabButton(int index, String label, IconData icon) {
    final isSelected = _recipientSourceTab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _recipientSourceTab = index;
            _onRecipientsChanged();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualTextInput() {
    return TextField(
      controller: _rawTextCtrl,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontFamily: 'monospace'),
      decoration: InputDecoration(
        hintText: "Введите или вставьте номера (по одному на строку или через запятую):\n+79991234567, Иван\n+79031112233, Анна\n89265554433",
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        filled: true,
        fillColor: Colors.black12,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }

  Widget _buildContactsPicker() {
    final contacts = ref.watch(contactsProvider);
    final filtered = contacts.where((c) {
      if (_contactSearchQuery.isEmpty) return true;
      final q = _contactSearchQuery.toLowerCase();
      return c.phone.toLowerCase().contains(q) || c.name.toLowerCase().contains(q) || c.notes.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        // Search & Select All
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _contactSearchQuery = v),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Поиск по имени или номеру...",
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textSecondary),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.black12,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  if (_selectedContactPhones.length == filtered.length) {
                    _selectedContactPhones.clear();
                  } else {
                    _selectedContactPhones.addAll(filtered.map((c) => c.phone));
                  }
                  _updateRecipientsFromContacts(contacts);
                });
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                _selectedContactPhones.length == filtered.length ? "Снять все" : "Выбрать все (${filtered.length})",
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    "Контакты не найдены",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final contact = filtered[index];
                    final isChecked = _selectedContactPhones.contains(contact.phone);
                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedContactPhones.add(contact.phone);
                          } else {
                            _selectedContactPhones.remove(contact.phone);
                          }
                          _updateRecipientsFromContacts(contacts);
                        });
                      },
                      dense: true,
                      activeColor: AppColors.accent,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        contact.name.isNotEmpty ? contact.name : contact.phone,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: contact.name.isNotEmpty
                          ? Text(contact.phone, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCsvInput() {
    return Column(
      children: [
        Expanded(
          child: TextField(
            controller: _csvTextCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: "Вставьте данные в формате CSV (с заголовками или без):\nphone,name,order_id\n+79991234567,Иван,1045\n+79031112233,Анна,1046",
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              filled: true,
              fillColor: Colors.black12,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // === STEP 2: MESSAGE COMPOSER ===
  Widget _buildStep2Message() {
    final templates = ref.watch(templatesProvider);
    final countResult = SmsCounter.count(_templateCtrl.text);
    final validRecipients = _parsedRecipients.where((r) => r.isValid).toList();

    // Variable interpolation preview
    String previewText = "Предпросмотр сообщения появится здесь...";
    if (validRecipients.isNotEmpty && _templateCtrl.text.isNotEmpty) {
      if (_previewRecipientIndex >= validRecipients.length) _previewRecipientIndex = 0;
      final sample = validRecipients[_previewRecipientIndex];
      previewText = RecipientImporter.interpolate(_templateCtrl.text, sample);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Templates dropdown & Quick tag chips
        Row(
          children: [
            if (templates.isNotEmpty) ...[
              PopupMenuButton<SmsTemplateDto>(
                onSelected: (tpl) {
                  setState(() {
                    _templateCtrl.text = tpl.body;
                  });
                },
                color: AppColors.cardBgSolid,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                itemBuilder: (context) => templates
                    .map((t) => PopupMenuItem(
                          value: t,
                          child: Text(t.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                        ))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_outline_rounded, size: 16, color: AppColors.accent),
                      SizedBox(width: 6),
                      Text("Шаблоны", style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                      Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],

            const Text("Теги:", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(width: 8),
            _buildTagChip("{name}", "Имя"),
            const SizedBox(width: 6),
            _buildTagChip("{phone}", "Телефон"),
          ],
        ),

        const SizedBox(height: 12),

        // Text field
        Expanded(
          flex: 3,
          child: TextField(
            controller: _templateCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: "Здравствуйте, {name}! Напоминаем о вашей записи на завтра...",
              hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              filled: true,
              fillColor: Colors.black12,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // SMS Counter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(
                countResult.isUnicode ? Icons.translate_rounded : Icons.text_fields_rounded,
                size: 16,
                color: countResult.partsCount > 1 ? AppColors.warning : AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                "Символов: ${countResult.characterCount}",
                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 14),
              Text(
                "SMS частей: ${countResult.partsCount}",
                style: TextStyle(
                  fontSize: 12,
                  color: countResult.partsCount > 1 ? AppColors.accentLight : AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                countResult.encodingName,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Preview box
        if (validRecipients.isNotEmpty) ...[
          const Text(
            "Предпросмотр для получателя:",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.msgSent.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    previewText,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (validRecipients.length > 1) ...[
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _previewRecipientIndex = (_previewRecipientIndex + 1) % validRecipients.length;
                      });
                    },
                    icon: const Icon(Icons.sync_rounded, size: 18, color: AppColors.accent),
                    tooltip: "Показать следующего получателя",
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTagChip(String tag, String label) {
    return ActionChip(
      onPressed: () {
        final text = _templateCtrl.text;
        final selection = _templateCtrl.selection;
        if (selection.start >= 0) {
          final newText = text.replaceRange(selection.start, selection.end, tag);
          _templateCtrl.text = newText;
          _templateCtrl.selection = TextSelection.collapsed(offset: selection.start + tag.length);
        } else {
          _templateCtrl.text += tag;
        }
      },
      label: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
      avatar: const Icon(Icons.add_rounded, size: 14, color: AppColors.accent),
      backgroundColor: Colors.black26,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.zero,
    );
  }

  // === STEP 3: SETTINGS ===
  Widget _buildStep3Settings() {
    final sims = ref.watch(simsProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ВЫБОР SIM-КАРТЫ",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),

          // SIM Mode Selector
          Row(
            children: [
              Expanded(
                child: _buildSimModeOption(
                  value: 'single',
                  title: "Одна SIM-карта",
                  subtitle: "Отправка через выбранный слот",
                  icon: Icons.sim_card_rounded,
                ),
              ),
              if (sims.length > 1) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSimModeOption(
                    value: 'round_robin',
                    title: "Ротация SIM",
                    subtitle: "Чередование слотов SIM",
                    icon: Icons.sync_alt_rounded,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          if (_simMode == 'single') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedSingleSubId ?? (sims.isNotEmpty ? sims.first.subscriptionId : null),
                  isExpanded: true,
                  dropdownColor: AppColors.cardBgSolid,
                  items: sims
                      .map((s) => DropdownMenuItem<int>(
                            value: s.subscriptionId,
                            child: Text(
                              "SIM ${s.slotIndex + 1}: ${s.carrierName}",
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            ),
                          ))
                      .toList(),
                  onChanged: (subId) => setState(() => _selectedSingleSubId = subId),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          const Text(
            "ИНТЕРВАЛ ОТПРАВКИ (ЗАЩИТА ОТ СПАМ-БЛОКИРОВОК)",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            "Операторы связи могут блокировать частую непрерывную отправку. Рекомендуется интервал 5-10 сек.",
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),

          const SizedBox(height: 14),

          // Interval slider
          Row(
            children: [
              const Text("Базовая задержка:", style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              const Spacer(),
              Text("$_intervalSeconds сек", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.accent)),
            ],
          ),
          Slider(
            value: _intervalSeconds.toDouble(),
            min: 2,
            max: 30,
            divisions: 28,
            activeColor: AppColors.accent,
            onChanged: (v) => setState(() => _intervalSeconds = v.round()),
          ),

          // Random Jitter slider
          Row(
            children: [
              const Text("Случайный разброс (джиттер):", style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              const Spacer(),
              Text("+0...$_randomJitterSeconds сек", style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
          Slider(
            value: _randomJitterSeconds.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            activeColor: AppColors.accentLight,
            onChanged: (v) => setState(() => _randomJitterSeconds = v.round()),
          ),

          const SizedBox(height: 16),

          // Duplicate filter checkbox
          SwitchListTile(
            value: _skipDuplicates,
            onChanged: (val) => setState(() => _skipDuplicates = val),
            title: const Text("Исключать дубликаты номеров", style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            subtitle: const Text("Если один и тот же номер встречается несколько раз, отправить только один раз", style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            activeThumbColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildSimModeOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _simMode == value;
    return InkWell(
      onTap: () => setState(() => _simMode = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? AppColors.accent : AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.accent),
          ],
        ),
      ),
    );
  }

  // === STEP 4: SUMMARY & LAUNCH ===
  Widget _buildStep4Summary() {
    final finalItems = _buildFinalItems();
    final totalParts = finalItems.fold<int>(0, (sum, i) => sum + i.partsCount);
    final avgSecondsPerMsg = _intervalSeconds + (_randomJitterSeconds / 2);
    final totalDurationSec = (finalItems.length * avgSecondsPerMsg).round();
    final minutes = totalDurationSec ~/ 60;
    final seconds = totalDurationSec % 60;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, color: AppColors.accent, size: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _campaignTitleCtrl.text,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Все параметры проверены и готовы к отправке.",
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Key metrics grid
          Row(
            children: [
              _buildMetricCard("Получателей", "${finalItems.length}", Icons.people_rounded, AppColors.accent),
              const SizedBox(width: 12),
              _buildMetricCard("Всего частей SMS", "$totalParts", Icons.sms_rounded, AppColors.accentLight),
              const SizedBox(width: 12),
              _buildMetricCard("Примерное время", "$minutes м $seconds с", Icons.timer_rounded, AppColors.success),
            ],
          ),

          const SizedBox(height: 16),

          // Detail rows
          _buildSummaryRow("Режим отправки:", _simMode == 'single' ? "Одна SIM-карта" : "Ротация SIM (Round-Robin)"),
          _buildSummaryRow("Интервал между SMS:", "$_intervalSeconds сек (+0..$_randomJitterSeconds сек)"),
          _buildSummaryRow("Фильтр дубликатов:", _skipDuplicates ? "Включен" : "Выключен"),
          _buildSummaryRow("Фоновое выполнение:", "Android Host Background Service (автономно)"),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color, fontFamily: 'Outfit')),
            const SizedBox(height: 2),
            Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
