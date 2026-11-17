import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/contractor_models.dart';
import '../../../../shared/theme.dart';
import '../../../logic/contractor_provider.dart';

/// Full-featured dialog for searching companies and sole proprietors (ИП)
/// via T-Bank contractor service with detailed OKVED breakdown.
class ContractorLookupDialog extends ConsumerStatefulWidget {
  final String? initialQuery;
  final void Function(ContractorDto contractor)? onApplyToContact;

  const ContractorLookupDialog({
    super.key,
    this.initialQuery,
    this.onApplyToContact,
  });

  static Future<ContractorDto?> show(
    BuildContext context, {
    String? initialQuery,
    void Function(ContractorDto contractor)? onApplyToContact,
  }) {
    return showDialog<ContractorDto>(
      context: context,
      barrierDismissible: true,
      builder: (context) => ContractorLookupDialog(
        initialQuery: initialQuery,
        onApplyToContact: onApplyToContact,
      ),
    );
  }

  @override
  ConsumerState<ContractorLookupDialog> createState() =>
      _ContractorLookupDialogState();
}

class _ContractorLookupDialogState
    extends ConsumerState<ContractorLookupDialog> {
  late final TextEditingController _searchController;
  final TextEditingController _okvedFilterController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
        ref.read(contractorSearchProvider.notifier).search(widget.initialQuery!);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _okvedFilterController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        ref.read(contractorSearchProvider.notifier).search(val);
      }
    });
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
    SfxService.playSent();
  }

  void _openInBrowser(ContractorDto contractor) async {
    final id = contractor.ogrn.isNotEmpty ? contractor.ogrn : contractor.inn;
    final uri = Uri.parse('https://www.tbank.ru/business/contractor/legal/$id/okved/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contractorSearchProvider);
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 860;

    return Dialog(
      backgroundColor: AppColors.cardBgSolid,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      child: Container(
        width: isWide ? 960 : 540,
        height: (screenSize.height * 0.88).clamp(500.0, 740.0),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildSearchBar(state),
            const SizedBox(height: 12),
            _buildFilterTabs(state),
            const SizedBox(height: 14),
            Expanded(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: _buildResultsList(state)),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 6,
                          child: _buildDetailsPanel(state.selectedContractor, state.isLoadingOkved),
                        ),
                      ],
                    )
                  : (state.selectedContractor != null
                      ? _buildDetailsPanel(
                          state.selectedContractor,
                          state.isLoadingOkved,
                          onBack: () => ref
                              .read(contractorSearchProvider.notifier)
                              .selectContractor(state.selectedContractor!) // keeps query
                        )
                      : _buildResultsList(state)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.domain_verification_rounded,
            color: AppColors.accentLight,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Проверка контрагента (Т-Банк)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Поиск по ИНН, ОГРН или названию • Виды деятельности (ОКВЭД)',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          tooltip: 'Закрыть',
        ),
      ],
    );
  }

  Widget _buildSearchBar(ContractorSearchState state) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onSubmitted: (val) =>
                  ref.read(contractorSearchProvider.notifier).search(val),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Введите ИНН (10 или 12 цифр), ОГРН или название...',
                hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textSecondary),
              onPressed: () {
                _searchController.clear();
                ref.read(contractorSearchProvider.notifier).clear();
              },
              tooltip: 'Очистить',
            ),
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(ContractorSearchState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ContractorFilterType.values.map((filter) {
          final isSelected = state.filter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                filter.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              selected: isSelected,
              onSelected: (_) =>
                  ref.read(contractorSearchProvider.notifier).setFilter(filter),
              backgroundColor: AppColors.surfaceLight,
              selectedColor: AppColors.accent,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? AppColors.accent : AppColors.border,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResultsList(ContractorSearchState state) {
    if (state.isLoading && state.results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accentLight),
            SizedBox(height: 12),
            Text(
              'Поиск в базе Т-Банка...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
              const SizedBox(height: 8),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final results = state.filteredResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.query.isEmpty ? Icons.business_rounded : Icons.search_off_rounded,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
              size: 42,
            ),
            const SizedBox(height: 8),
            Text(
              state.query.isEmpty
                  ? 'Введите ИНН организации или ИП для поиска'
                  : 'Ничего не найдено по запросу "${state.query}"',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: results.length,
        separatorBuilder: (context, index) => const Divider(color: AppColors.border, height: 8),
        itemBuilder: (context, index) {
          final item = results[index];
          final isSelected = state.selectedContractor?.ogrn == item.ogrn &&
              state.selectedContractor?.inn == item.inn;

          return InkWell(
            onTap: () =>
                ref.read(contractorSearchProvider.notifier).selectContractor(item),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.accent : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.isIndividual
                              ? Colors.indigoAccent.withValues(alpha: 0.2)
                              : Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.typeLabel,
                          style: TextStyle(
                            color: item.isIndividual
                                ? Colors.indigoAccent
                                : Colors.tealAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (item.isSeller) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, size: 10, color: Colors.purpleAccent),
                              SizedBox(width: 3),
                              Text(
                                'Селлер',
                                style: TextStyle(
                                  color: Colors.purpleAccent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: item.statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ИНН: ${item.inn}  •  ${item.isIndividual ? "ОГРНИП" : "ОГРН"}: ${item.ogrn}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  if (item.address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.address,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailsPanel(ContractorDto? contractor, bool isLoadingOkved, {VoidCallback? onBack}) {
    if (contractor == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Выберите компанию из списка слева\nдля просмотра реквизитов и ОКВЭД',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    // Filter okved items if user typed into okved search
    final filterQuery = _okvedFilterController.text.trim().toLowerCase();
    final allOkved = contractor.okvedList;
    final mainOkveds = allOkved.where((o) => o.isMain).toList();
    final additionalOkveds = allOkved.where((o) {
      if (o.isMain) return false;
      if (filterQuery.isEmpty) return true;
      return o.code.toLowerCase().contains(filterQuery) ||
          o.description.toLowerCase().contains(filterQuery);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Back button
          Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.accentLight),
                  tooltip: 'К списку',
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contractor.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contractor.fullName != contractor.name && contractor.fullName.isNotEmpty)
                      Text(
                        contractor.fullName,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (contractor.isSeller) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 13, color: Colors.purpleAccent),
                      SizedBox(width: 4),
                      Text(
                        'Селлер',
                        style: TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: contractor.statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: contractor.statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      contractor.statusText,
                      style: TextStyle(
                        color: contractor.statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          // Scrollable content (Requisites + OKVED)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Requisites table
                  _buildRequisiteRow('ИНН:', contractor.inn, copyable: true),
                  _buildRequisiteRow(
                    contractor.isIndividual ? 'ОГРНИП:' : 'ОГРН:',
                    contractor.ogrn,
                    copyable: true,
                  ),
                  if (contractor.kpp.isNotEmpty)
                    _buildRequisiteRow('КПП:', contractor.kpp, copyable: true),
                  if (contractor.management != null && contractor.management!.name.isNotEmpty)
                    _buildRequisiteRow(
                      contractor.management!.post.isNotEmpty
                          ? '${contractor.management!.post}:'
                          : 'Руководитель:',
                      contractor.management!.name,
                    ),
                  if (contractor.address.isNotEmpty)
                    _buildRequisiteRow('Адрес:', contractor.address, copyable: true),

                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 14),

                  // OKVED Activities Section
                  Row(
                    children: [
                      const Icon(Icons.work_outline_rounded, size: 16, color: AppColors.accentLight),
                      const SizedBox(width: 6),
                      Text(
                        allOkved.isNotEmpty
                            ? 'Виды деятельности (ОКВЭД • ${allOkved.length})'
                            : 'Виды деятельности (ОКВЭД)',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (isLoadingOkved)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Seller Alert Banner if OKVED 47.91 is present
                  if (contractor.isSeller) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.storefront_rounded, color: Colors.purpleAccent, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Селлер',
                            style: TextStyle(
                              color: Colors.purpleAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '• Торговля через интернет / маркетплейсы (ОКВЭД 47.91)',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Main OKVED items
                  if (mainOkveds.isNotEmpty)
                    for (final mainOk in mainOkveds)
                      InkWell(
                        onTap: () => _copyToClipboard(
                          '${mainOk.code} — ${mainOk.description}',
                          'Код ${mainOk.code} скопирован',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (mainOk.code == '47.91' || mainOk.code.startsWith('47.91.'))
                                ? Colors.deepPurpleAccent.withValues(alpha: 0.12)
                                : Colors.greenAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (mainOk.code == '47.91' || mainOk.code.startsWith('47.91.'))
                                  ? Colors.purpleAccent.withValues(alpha: 0.4)
                                  : Colors.greenAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (mainOk.code == '47.91' || mainOk.code.startsWith('47.91.'))
                                      ? Colors.deepPurpleAccent.withValues(alpha: 0.3)
                                      : Colors.greenAccent.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  mainOk.code,
                                  style: TextStyle(
                                    color: (mainOk.code == '47.91' || mainOk.code.startsWith('47.91.'))
                                        ? Colors.purpleAccent
                                        : Colors.greenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (mainOk.code == '47.91' || mainOk.code.startsWith('47.91.')) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Селлер',
                                    style: TextStyle(
                                      color: Colors.purpleAccent,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'ОСНОВНОЙ ВИД ДЕЯТЕЛЬНОСТИ',
                                      style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      mainOk.description.isNotEmpty
                                          ? mainOk.description
                                          : 'Код ОКВЭД: ${mainOk.code}',
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                  else if (contractor.mainOkvedCode != null && contractor.mainOkvedCode!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              contractor.mainOkvedCode!,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ОСНОВНОЙ ВИД ДЕЯТЕЛЬНОСТИ',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isLoadingOkved
                                      ? 'Загрузка расшифровки...'
                                      : 'Код ОКВЭД: ${contractor.mainOkvedCode}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Additional OKVEDs with mini-filter
                  if (allOkved.where((o) => !o.isMain).isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          'Дополнительные (${allOkved.where((o) => !o.isMain).length}):',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 28,
                            child: TextField(
                              controller: _okvedFilterController,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Фильтр по коду или слову...',
                                hintStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                prefixIcon: const Icon(Icons.filter_list_rounded, size: 14, color: AppColors.textSecondary),
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                filled: true,
                                fillColor: AppColors.cardBgSolid,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: additionalOkveds.length,
                      itemBuilder: (context, idx) {
                        final ok = additionalOkveds[idx];
                        return InkWell(
                          onTap: () => _copyToClipboard(
                            '${ok.code} — ${ok.description}',
                            'Код ${ok.code} скопирован',
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: (ok.code == '47.91' || ok.code.startsWith('47.91.'))
                                        ? Colors.deepPurpleAccent.withValues(alpha: 0.25)
                                        : AppColors.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: (ok.code == '47.91' || ok.code.startsWith('47.91.'))
                                          ? Colors.purpleAccent.withValues(alpha: 0.6)
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    ok.code,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: (ok.code == '47.91' || ok.code.startsWith('47.91.'))
                                          ? Colors.purpleAccent
                                          : AppColors.accentLight,
                                    ),
                                  ),
                                ),
                                if (ok.code == '47.91' || ok.code.startsWith('47.91.')) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.purpleAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Селлер',
                                      style: TextStyle(
                                        color: Colors.purpleAccent,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ok.description.isNotEmpty
                                        ? ok.description
                                        : 'Описание отсутствует',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textPrimary,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ] else if (isLoadingOkved) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Загрузка полного перечня видов деятельности...',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ] else if (contractor.isOkvedLoaded && allOkved.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Дополнительные виды деятельности отсутствуют',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ] else if (contractor.isOkvedLoaded && allOkved.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Сведения о видах деятельности (ОКВЭД) не найдены',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          // Action Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _copyToClipboard(
                  contractor.toFormattedRequisites(),
                  'Реквизиты скопированы в буфер обмена',
                ),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Скопировать'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openInBrowser(contractor),
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                label: const Text('На сайте Т-Банка'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              if (widget.onApplyToContact != null)
                ElevatedButton.icon(
                  onPressed: () {
                    widget.onApplyToContact!(contractor);
                    Navigator.of(context).pop(contractor);
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('В карточку клиента'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequisiteRow(String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (copyable)
                  InkWell(
                    onTap: () => _copyToClipboard(value, 'Скопировано: $value'),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
