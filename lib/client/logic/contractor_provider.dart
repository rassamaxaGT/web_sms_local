import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/contractor_models.dart';
import '../data/tbank_contractor_service.dart';
import 'providers.dart';

enum ContractorFilterType {
  all('Все'),
  legal('Юрлица (ООО/АО)'),
  individual('ИП');

  final String label;
  const ContractorFilterType(this.label);
}

class ContractorSearchState {
  final String query;
  final ContractorFilterType filter;
  final bool isLoading;
  final List<ContractorDto> results;
  final String? error;
  final ContractorDto? selectedContractor;
  final bool isLoadingOkved;

  const ContractorSearchState({
    this.query = '',
    this.filter = ContractorFilterType.all,
    this.isLoading = false,
    this.results = const [],
    this.error,
    this.selectedContractor,
    this.isLoadingOkved = false,
  });

  List<ContractorDto> get filteredResults {
    switch (filter) {
      case ContractorFilterType.all:
        return results;
      case ContractorFilterType.legal:
        return results.where((c) => !c.isIndividual).toList();
      case ContractorFilterType.individual:
        return results.where((c) => c.isIndividual).toList();
    }
  }

  ContractorSearchState copyWith({
    String? query,
    ContractorFilterType? filter,
    bool? isLoading,
    List<ContractorDto>? results,
    String? error,
    ContractorDto? selectedContractor,
    bool? isLoadingOkved,
    bool clearSelected = false,
  }) {
    return ContractorSearchState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: error,
      selectedContractor: clearSelected ? null : (selectedContractor ?? this.selectedContractor),
      isLoadingOkved: isLoadingOkved ?? this.isLoadingOkved,
    );
  }
}

final contractorServiceProvider = Provider<TBankContractorService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TBankContractorService(apiClient: apiClient);
});

class ContractorSearchNotifier extends Notifier<ContractorSearchState> {
  late final TBankContractorService _service;

  @override
  ContractorSearchState build() {
    _service = ref.watch(contractorServiceProvider);
    return const ContractorSearchState();
  }

  void setFilter(ContractorFilterType filter) {
    state = state.copyWith(filter: filter);
  }

  Future<void> search(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      state = state.copyWith(query: '', results: [], error: null, clearSelected: true);
      return;
    }

    state = state.copyWith(
      query: clean,
      isLoading: true,
      error: null,
      clearSelected: true,
    );

    try {
      final results = await _service.search(clean, count: 15);
      state = state.copyWith(
        isLoading: false,
        results: results,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Ошибка поиска: $e',
      );
    }
  }

  Future<void> selectContractor(ContractorDto contractor) async {
    state = state.copyWith(
      selectedContractor: contractor,
      isLoadingOkved: !contractor.isOkvedLoaded,
    );

    if (!contractor.isOkvedLoaded) {
      try {
        final enriched = await _service.fetchOkvedDetails(contractor);
        final updatedResults = state.results.map((c) {
          if ((c.ogrn.isNotEmpty && c.ogrn == contractor.ogrn) ||
              (c.inn.isNotEmpty && c.inn == contractor.inn)) {
            return enriched;
          }
          return c;
        }).toList();

        if (state.selectedContractor?.ogrn == contractor.ogrn &&
            state.selectedContractor?.inn == contractor.inn) {
          state = state.copyWith(
            selectedContractor: enriched,
            results: updatedResults,
            isLoadingOkved: false,
          );
        } else {
          state = state.copyWith(
            results: updatedResults,
            isLoadingOkved: false,
          );
        }
      } catch (e) {
        state = state.copyWith(isLoadingOkved: false);
      }
    }
  }

  void clear() {
    state = const ContractorSearchState();
  }
}

final contractorSearchProvider =
    NotifierProvider<ContractorSearchNotifier, ContractorSearchState>(
  ContractorSearchNotifier.new,
);
