import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../shared/app_logger.dart';
import '../../shared/contractor_models.dart';
import 'api_client.dart';

/// Service for querying contractor details and OKVED activities from T-Bank.
/// Automatically routes through Host ApiClient in Web mode to avoid browser CORS errors.
class TBankContractorService {
  static const String _suggestUrl =
      'https://www.tbank.ru/business/contractor/company-pages/papi/dadata/suggestions/api/4_1/rs/suggest/party?appName=company-pages';

  static const Map<String, String> _commonHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Referer': 'https://www.tbank.ru/business/contractor/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  final ApiClient? _apiClient;
  final http.Client _client;

  TBankContractorService({ApiClient? apiClient, http.Client? client})
      : _apiClient = apiClient,
        _client = client ?? http.Client();

  /// Searches companies and sole proprietors (ИП) by INN, OGRN, or name
  Future<List<ContractorDto>> search(String query, {int count = 10}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // When running in Web (or when host ApiClient is connected), route through host
    // to prevent browser CORS restrictions ("ClientException: Failed to fetch").
    if (_apiClient != null) {
      try {
        return await _apiClient.searchContractors(cleanQuery);
      } catch (e) {
        AppLogger.warning('TBankContractorService: host proxy search failed: $e');
        if (kIsWeb) rethrow;
      }
    }

    try {
      AppLogger.info('TBankContractorService: searching "$cleanQuery" directly');
      final response = await _client
          .post(
            Uri.parse(_suggestUrl),
            headers: _commonHeaders,
            body: jsonEncode({
              'count': count,
              'query': cleanQuery,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        AppLogger.warning(
            'TBankContractorService: suggest returned HTTP ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (json['resultCode'] != 'OK') {
        AppLogger.warning(
            'TBankContractorService: unexpected resultCode: ${json['resultCode']}');
        return [];
      }

      final payload = json['payload'] as Map<String, dynamic>?;
      final suggestions = payload?['suggestions'] as List?;
      if (suggestions == null || suggestions.isEmpty) {
        return [];
      }

      final results = <ContractorDto>[];
      for (final item in suggestions) {
        if (item is Map<String, dynamic>) {
          results.add(ContractorDto.fromDadataSuggestion(item));
        }
      }
      return results;
    } catch (e) {
      AppLogger.error('TBankContractorService: search failed', error: e);
      rethrow;
    }
  }

  /// Fetches the full breakdown of OKVED activities (main + all additional)
  Future<ContractorDto> fetchOkvedDetails(ContractorDto contractor) async {
    if (contractor.ogrn.isEmpty) {
      return contractor.copyWith(isOkvedLoaded: true);
    }

    if (_apiClient != null) {
      try {
        return await _apiClient.fetchContractorOkved(contractor);
      } catch (e) {
        AppLogger.warning('TBankContractorService: host proxy okved failed: $e');
        if (kIsWeb) rethrow;
      }
    }

    // T-Bank contractor service uses /legal/{ogrn}/okved/ for BOTH legal entities (ЮЛ) and individual entrepreneurs (ИП).
    // The /businessman/ path returns 404.
    final id = contractor.ogrn.isNotEmpty ? contractor.ogrn : contractor.inn;
    final url = 'https://www.tbank.ru/business/contractor/legal/$id/okved/';

    try {
      AppLogger.info('TBankContractorService: fetching OKVED from $url directly');
      final response = await _client.get(
        Uri.parse(url),
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'ru-RU,ru;q=0.9',
          'Referer': 'https://www.tbank.ru/business/contractor/',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) {
        AppLogger.warning(
            'TBankContractorService: OKVED page returned HTTP ${response.statusCode}');
        return contractor.copyWith(isOkvedLoaded: true);
      }

      final body = utf8.decode(response.bodyBytes);
      final okvedItems = _parseOkvedFromBody(body, defaultMainCode: contractor.mainOkvedCode);

      // If mainOkvedCode is still null, take it from the main item
      String? mainCode = contractor.mainOkvedCode;
      final mainItem = okvedItems.where((o) => o.isMain).firstOrNull;
      if (mainItem != null) {
        mainCode = mainItem.code;
      }

      return contractor.copyWith(
        okvedList: okvedItems,
        mainOkvedCode: mainCode,
        isOkvedLoaded: true,
      );
    } catch (e) {
      AppLogger.error('TBankContractorService: failed to fetch OKVED', error: e);
      return contractor.copyWith(isOkvedLoaded: true);
    }
  }

  /// Extracts all OKVED items (main + additional) with codes and descriptions from embedded SSR JSON in HTML
  List<OkvedItem> _parseOkvedFromBody(String html, {String? defaultMainCode}) {
    final List<OkvedItem> items = [];

    try {
      final scriptMatches =
          RegExp(r'<script[^>]*>(.*?)</script>', dotAll: true).allMatches(html);
      for (final sm in scriptMatches) {
        final content = sm.group(1) ?? '';
        if (content.contains('"okved":') &&
            (content.contains('"main":') || content.contains('"additional":'))) {
          try {
            String jsonStr = content.trim();
            final firstBrace = jsonStr.indexOf('{');
            final lastBrace = jsonStr.lastIndexOf('}');
            if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
              jsonStr = jsonStr.substring(firstBrace, lastBrace + 1);
            }

            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            final okvedSection = json['okved'];
            final List<dynamic> cards = [];
            if (okvedSection is List) {
              for (final secItem in okvedSection) {
                if (secItem is List) {
                  cards.addAll(secItem);
                } else if (secItem is Map) {
                  cards.add(secItem);
                }
              }
            } else if (okvedSection is Map) {
              cards.add(okvedSection);
            }

            for (final card in cards) {
              if (card is Map<String, dynamic>) {
                final data = card['data'] as Map<String, dynamic>?;
                if (data != null) {
                  final mainList = data['main'] as List? ?? [];
                  final addList = data['additional'] as List? ?? [];

                  for (final m in mainList) {
                    if (m is Map<String, dynamic>) {
                      final code = m['code']?.toString().trim() ?? '';
                      final desc = m['description']?.toString().trim() ?? '';
                      if (code.isNotEmpty && !items.any((i) => i.code == code)) {
                        items.add(OkvedItem(code: code, description: desc, isMain: true));
                      }
                    }
                  }

                  for (final a in addList) {
                    if (a is Map<String, dynamic>) {
                      final code = a['code']?.toString().trim() ?? '';
                      final desc = a['description']?.toString().trim() ?? '';
                      if (code.isNotEmpty && !items.any((i) => i.code == code)) {
                        items.add(OkvedItem(code: code, description: desc, isMain: false));
                      }
                    }
                  }
                }
              }
            }
            if (items.isNotEmpty) break;
          } catch (e) {
            AppLogger.warning('TBankContractorService: json parse error in okved script: $e');
          }
        }
      }
    } catch (e) {
      AppLogger.warning('TBankContractorService: error parsing okved html: $e');
    }

    // Fallback: If JSON parsing failed to yield items, use regex pattern matching on code and description
    if (items.isEmpty) {
      final codeDescRegex = RegExp(
        r'"code"\s*:\s*"([0-9\.]+)"\s*,\s*"description"\s*:\s*"([^"]+)"',
      );
      for (final match in codeDescRegex.allMatches(html)) {
        final code = match.group(1)?.trim() ?? '';
        final desc = match.group(2)?.trim() ?? '';
        if (code.isNotEmpty && !items.any((i) => i.code == code)) {
          final isMain = defaultMainCode != null &&
              (code == defaultMainCode || code.startsWith(defaultMainCode));
          items.add(OkvedItem(code: code, description: desc, isMain: isMain));
        }
      }
    }

    // Ensure at least one activity is designated as Main (with description)
    if (items.isNotEmpty && !items.any((i) => i.isMain)) {
      int mainIndex = -1;
      if (defaultMainCode != null && defaultMainCode.isNotEmpty) {
        mainIndex = items.indexWhere((i) => i.code == defaultMainCode);
        if (mainIndex == -1) {
          mainIndex = items.indexWhere((i) => i.code.startsWith(defaultMainCode));
        }
      }
      if (mainIndex == -1) {
        mainIndex = 0;
      }
      final promoted = items[mainIndex];
      items[mainIndex] = OkvedItem(
        code: promoted.code,
        description: promoted.description,
        isMain: true,
      );
    }

    return items;
  }
}
