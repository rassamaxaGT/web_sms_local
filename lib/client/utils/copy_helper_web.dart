// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, avoid_print

import 'package:flutter/services.dart';
import 'dart:html' as html;
import 'selection_manager.dart';

String? getDomSelectedText() {
  try {
    final selection = html.window.getSelection();
    if (selection != null && (selection.rangeCount ?? 0) > 0) {
      final text = selection.toString();
      if (text.isNotEmpty) return text;
    }
  } catch (_) {}
  return null;
}

void initWebCopyHandler() {
  try {
    html.document.onCopy.listen((html.ClipboardEvent event) {
      // If user has focused an editable input and highlighted text inside it, let native copy handle it
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

void copyToClipboard(String text) {
  // 1. Try standard Flutter clipboard first
  Clipboard.setData(ClipboardData(text: text));

  // 2. Try Web Clipboard API if in a secure context (HTTPS or localhost)
  if (html.window.isSecureContext == true) {
    try {
      html.window.navigator.clipboard?.writeText(text);
    } catch (_) {}
  }

  // 3. Robust synchronous DOM textarea copy fallback (essential for HTTP non-secure contexts)
  try {
    final activeEl = html.document.activeElement;
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

    if (activeEl is html.HtmlElement) {
      activeEl.focus();
    }
  } catch (e) {
    print("Fallback clipboard copy failed: $e");
  }
}
