// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'package:flutter/services.dart';
import 'dart:html' as html;

void copyToClipboard(String text) {
  // 1. Try standard Flutter clipboard first
  Clipboard.setData(ClipboardData(text: text));

  // 2. Perform robust Web-specific fallbacks (especially for WebView and HTTP)
  try {
    if (html.window.navigator.clipboard != null) {
      html.window.navigator.clipboard!.writeText(text);
      return;
    }
  } catch (_) {
    // navigator.clipboard is disabled or blocked in non-secure (HTTP) contexts
  }

  // 3. Ultimate Fallback: Temporary DOM textarea copy
  try {
    final html.TextAreaElement textArea = html.TextAreaElement()
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
    
    html.document.body?.append(textArea);
    textArea.focus();
    textArea.select();
    
    html.document.execCommand('copy');
    textArea.remove();
  } catch (e) {
    print("Fallback clipboard copy failed: $e");
  }
}
