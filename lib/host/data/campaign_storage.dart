// lib/host/data/campaign_storage.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../shared/shared_models.dart';

class CampaignStorage {
  static const String _fileName = 'sms_campaigns.json';

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<CampaignDto>> loadCampaigns({bool summaryOnly = false}) async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        if (summaryOnly) {
          map.remove('items');
        }
        return CampaignDto.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint("Error loading campaigns: $e");
      return [];
    }
  }

  Future<CampaignDto?> getCampaign(String id) async {
    final campaigns = await loadCampaigns();
    try {
      return campaigns.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAll(List<CampaignDto> campaigns) async {
    try {
      final file = await _getFile();
      final content = jsonEncode(campaigns.map((e) => e.toJson(includeItems: true)).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint("Error saving campaigns: $e");
    }
  }

  Future<void> saveCampaign(CampaignDto campaign) async {
    final campaigns = await loadCampaigns();
    final index = campaigns.indexWhere((c) => c.id == campaign.id);
    if (index != -1) {
      campaigns[index] = campaign;
    } else {
      campaigns.insert(0, campaign);
    }
    await saveAll(campaigns);
  }

  Future<CampaignDto?> updateCampaignStatus(String campaignId, String status, {int? currentIndex}) async {
    final campaigns = await loadCampaigns();
    final index = campaigns.indexWhere((c) => c.id == campaignId);
    if (index == -1) return null;

    final updated = campaigns[index].copyWith(
      status: status,
      currentIndex: currentIndex,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    campaigns[index] = updated;
    await saveAll(campaigns);
    return updated;
  }

  Future<CampaignDto?> updateItemStatus(
    String campaignId,
    String itemId,
    String status, {
    int? subId,
    int? sentAtMs,
    String? errorMessage,
  }) async {
    final campaigns = await loadCampaigns();
    final cIndex = campaigns.indexWhere((c) => c.id == campaignId);
    if (cIndex == -1) return null;

    final campaign = campaigns[cIndex];
    final itemIndex = campaign.items.indexWhere((i) => i.id == itemId);
    if (itemIndex == -1) return null;

    final currentItem = campaign.items[itemIndex];
    final updatedItem = currentItem.copyWith(
      status: status,
      subId: subId ?? currentItem.subId,
      sentAtMs: sentAtMs ?? currentItem.sentAtMs,
      errorMessage: errorMessage,
    );

    final newItems = List<CampaignItemDto>.from(campaign.items);
    newItems[itemIndex] = updatedItem;

    final updatedCampaign = campaign.copyWith(
      items: newItems,
      sentCount: newItems.where((i) => i.status == 'sent').length,
      failedCount: newItems.where((i) => i.status == 'failed').length,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    campaigns[cIndex] = updatedCampaign;
    await saveAll(campaigns);
    return updatedCampaign;
  }

  Future<void> deleteCampaign(String id) async {
    final campaigns = await loadCampaigns();
    campaigns.removeWhere((c) => c.id == id);
    await saveAll(campaigns);
  }
}
