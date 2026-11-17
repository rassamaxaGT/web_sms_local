// lib/host/service/broadcast_engine.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/campaign_storage.dart';
import '../data/contact_storage.dart';
import '../data/native_sms_client.dart';
import '../../shared/shared_models.dart';

typedef CampaignEventCallback = void Function(String eventType, Map<String, dynamic> data);

class BroadcastEngine {
  final CampaignStorage _storage;
  final NativeSmsClient _smsClient;
  final ContactStorage _contactStorage = ContactStorage();
  final Random _random = Random();

  String? _activeCampaignId;
  bool _isPaused = false;
  bool _isStopped = false;
  bool _isProcessing = false;

  CampaignEventCallback? onEvent;

  BroadcastEngine(this._storage, this._smsClient);

  String? get activeCampaignId => _activeCampaignId;
  bool get isRunning => _isProcessing && !_isPaused && !_isStopped;
  bool get isPaused => _isPaused;

  Future<void> startCampaign(String campaignId) async {
    if (_isProcessing && _activeCampaignId == campaignId) {
      if (_isPaused) {
        return resumeCampaign(campaignId);
      }
      return;
    }

    _activeCampaignId = campaignId;
    _isPaused = false;
    _isStopped = false;

    await _storage.updateCampaignStatus(campaignId, 'running');
    _notifyCampaignUpdate(campaignId);

    _runQueue(campaignId);
  }

  Future<void> pauseCampaign(String campaignId) async {
    if (_activeCampaignId == campaignId) {
      _isPaused = true;
      await _storage.updateCampaignStatus(campaignId, 'paused');
      _notifyCampaignUpdate(campaignId);
    }
  }

  Future<void> resumeCampaign(String campaignId) async {
    if (_activeCampaignId == campaignId && _isPaused) {
      _isPaused = false;
      await _storage.updateCampaignStatus(campaignId, 'running');
      _notifyCampaignUpdate(campaignId);
      _runQueue(campaignId);
    } else {
      await startCampaign(campaignId);
    }
  }

  Future<void> stopCampaign(String campaignId) async {
    if (_activeCampaignId == campaignId) {
      _isStopped = true;
      _isPaused = false;
      await _storage.updateCampaignStatus(campaignId, 'cancelled');
      _notifyCampaignUpdate(campaignId);
      _activeCampaignId = null;
      _isProcessing = false;
    }
  }

  Future<void> retryFailed(String campaignId) async {
    final campaign = await _storage.getCampaign(campaignId);
    if (campaign == null) return;

    final updatedItems = campaign.items.map((item) {
      if (item.status == 'failed') {
        return item.copyWith(
          status: 'pending',
          errorMessage: null,
        );
      }
      return item;
    }).toList();

    final updated = campaign.copyWith(
      items: updatedItems,
      failedCount: 0,
      status: 'queued',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _storage.saveCampaign(updated);
    _notifyCampaignUpdate(campaignId);
    await startCampaign(campaignId);
  }

  Future<void> _runQueue(String campaignId) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (!_isPaused && !_isStopped) {
        final campaign = await _storage.getCampaign(campaignId);
        if (campaign == null || campaign.status != 'running') {
          break;
        }

        // Find next pending item
        final nextItemIndex = campaign.items.indexWhere((i) => i.status == 'pending');
        if (nextItemIndex == -1) {
          // All items processed
          await _storage.updateCampaignStatus(campaignId, 'completed');
          _notifyCampaignUpdate(campaignId);
          _activeCampaignId = null;
          break;
        }

        final item = campaign.items[nextItemIndex];

        // Determine SIM Subscription ID
        int chosenSubId = 0;
        if (campaign.selectedSubIds.isNotEmpty) {
          if (campaign.simMode == 'round_robin') {
            final sentSoFar = campaign.sentCount + campaign.failedCount;
            chosenSubId = campaign.selectedSubIds[sentSoFar % campaign.selectedSubIds.length];
          } else {
            chosenSubId = campaign.selectedSubIds.first;
          }
        } else {
          final sims = await _smsClient.getSimCards();
          if (sims.isNotEmpty) {
            chosenSubId = sims.first.subscriptionId;
          }
        }

        // Mark item as sending
        await _storage.updateItemStatus(
          campaignId,
          item.id,
          'sending',
          subId: chosenSubId,
        );
        _notifyItemUpdate(campaignId, item.copyWith(status: 'sending', subId: chosenSubId));

        // Attempt SMS send
        try {
          await _smsClient.sendSms(item.phone, item.interpolatedText, chosenSubId);
          
          final now = DateTime.now().millisecondsSinceEpoch;

          // Auto-save recipient to CRM ContactStorage so they are persisted as contacts
          try {
            await _contactStorage.addOrUpdateContact(ContactDto(
              phone: item.phone,
              name: item.name ?? '',
              notes: 'Добавлен из рассылки',
            ));
          } catch (_) {}

          final updated = await _storage.updateItemStatus(
            campaignId,
            item.id,
            'sent',
            subId: chosenSubId,
            sentAtMs: now,
          );

          final sentItem = item.copyWith(
            status: 'sent',
            subId: chosenSubId,
            sentAtMs: now,
          );
          _notifyItemUpdate(campaignId, sentItem);

          // Emit NEW_SMS so Web & Desktop clients immediately see the message in thread/sidebar
          if (onEvent != null) {
            final sentMsg = SmsMessageDto(
              address: item.phone,
              body: item.interpolatedText,
              date: now,
              isSent: true,
              subId: chosenSubId,
            );
            onEvent!('NEW_SMS', sentMsg.toJson());
          }

          if (updated != null) _notifyCampaignUpdate(campaignId);

        } catch (e) {
          debugPrint("Broadcast send error for ${item.phone}: $e");
          final updated = await _storage.updateItemStatus(
            campaignId,
            item.id,
            'failed',
            subId: chosenSubId,
            errorMessage: e.toString(),
          );

          final failedItem = item.copyWith(
            status: 'failed',
            subId: chosenSubId,
            errorMessage: e.toString(),
          );
          _notifyItemUpdate(campaignId, failedItem);
          if (updated != null) _notifyCampaignUpdate(campaignId);
        }

        // Check again if state changed during await
        if (_isPaused || _isStopped) break;

        // Apply delay with jitter
        final delaySec = campaign.intervalSeconds +
            (campaign.randomJitterSeconds > 0
                ? _random.nextInt(campaign.randomJitterSeconds + 1)
                : 0);

        await Future.delayed(Duration(seconds: delaySec));
      }
    } catch (e) {
      debugPrint("Broadcast queue fatal error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _notifyCampaignUpdate(String campaignId) async {
    final campaign = await _storage.getCampaign(campaignId);
    if (campaign != null && onEvent != null) {
      onEvent!('CAMPAIGN_UPDATE', campaign.toJson(includeItems: true));
    }
  }

  void _notifyItemUpdate(String campaignId, CampaignItemDto item) {
    if (onEvent != null) {
      onEvent!('CAMPAIGN_ITEM_PROCESSED', {
        'campaignId': campaignId,
        'item': item.toJson(),
      });
    }
  }
}
