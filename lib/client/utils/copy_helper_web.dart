import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

Future<void> copyToClipboard(String text) async {
  // 1. Try standard Flutter clipboard first
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {}

  // 2. Try Web Clipboard API
  try {
    await web.window.navigator.clipboard.writeText(text).toDart;
    return;
  } catch (_) {
    // navigator.clipboard is disabled or blocked in non-secure (HTTP) contexts
  }

  // 3. Fallback: Temporary DOM textarea copy
  try {
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
  } catch (e) {
    debugPrint('Fallback clipboard copy failed: $e');
  }
}
