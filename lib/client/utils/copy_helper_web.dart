import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;
import 'selection_manager.dart';

String? getDomSelectedText() {
  try {
    final selection = web.window.getSelection();
    if (selection != null && selection.rangeCount > 0) {
      final text = selection.toString();
      if (text.isNotEmpty) return text;
    }
  } catch (_) {}
  return null;
}

void initWebCopyHandler() {
  try {
    web.EventStreamProviders.copyEvent.forTarget(web.document).listen((web.ClipboardEvent event) {
      if (isFocusedOnEditableTextWithSelection()) {
        return;
      }

      final text = WebSelectionManager.selectedText;
      if (text != null && text.isNotEmpty) {
        event.clipboardData?.setData('text/plain', text);
        event.preventDefault();
      }
    });
  } catch (_) {}
}

Future<void> copyToClipboard(String text) async {
  // 1. Try standard Flutter clipboard first
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {}

  // 2. Try Web Clipboard API if in a secure context (HTTPS or localhost)
  if (web.window.isSecureContext) {
    try {
      await web.window.navigator.clipboard.writeText(text).toDart;
      return;
    } catch (_) {
      // navigator.clipboard is disabled or blocked
    }
  }

  // 3. Fallback: Temporary DOM textarea copy
  try {
    final activeEl = web.document.activeElement;
    final textArea = web.HTMLTextAreaElement()
      ..value = text
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '2em'
      ..style.height = '2em'
      ..style.padding = '0'
      ..style.border = 'none'
      ..style.outline = 'none'
      ..style.boxShadow = 'none'
      ..style.background = 'transparent';

    web.document.body?.append(textArea);
    textArea.focus();
    textArea.select();

    web.document.execCommand('copy');
    textArea.remove();

    if (activeEl != null && activeEl.isA<web.HTMLElement>()) {
      (activeEl as web.HTMLElement).focus();
    }
  } catch (e) {
    debugPrint('Fallback clipboard copy failed: $e');
  }
}
