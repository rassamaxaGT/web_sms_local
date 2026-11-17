import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'copy_helper.dart';

/// Global manager to track the currently selected plain text across Flutter's
/// SelectionArea and Web DOM selection.
class WebSelectionManager {
  static String? _selectedText;

  /// Returns the current selected text, falling back to Web DOM selection if present.
  static String? get selectedText {
    if (_selectedText != null && _selectedText!.isNotEmpty) {
      return _selectedText;
    }
    final dom = getDomSelectedText();
    if (dom != null && dom.isNotEmpty) {
      return dom;
    }
    return null;
  }

  /// Callback to be passed to [SelectionArea.onSelectionChanged].
  static void onSelectionChanged(SelectedContent? content) {
    final text = content?.plainText;
    if (text != null && text.trim().isNotEmpty) {
      _selectedText = text;
    } else {
      _selectedText = null;
    }
  }

  /// Clears any tracked selected text.
  static void clear() {
    _selectedText = null;
  }
}

/// Checks if the currently focused widget is an [EditableText] (e.g. TextField)
/// and whether the user has a non-collapsed (highlighted) selection inside it.
bool isFocusedOnEditableTextWithSelection() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null) return false;
  final context = focus.context;
  if (context == null) return false;

  EditableTextState? editableState;
  if (context.widget is EditableText) {
    editableState = (context as StatefulElement).state as EditableTextState;
  } else {
    editableState = context.findAncestorStateOfType<EditableTextState>();
  }

  if (editableState != null) {
    final selection = editableState.textEditingValue.selection;
    if (!selection.isCollapsed && selection.start != selection.end) {
      return true;
    }
  }
  return false;
}
