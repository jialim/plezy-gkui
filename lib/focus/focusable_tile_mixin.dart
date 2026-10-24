import 'package:flutter/material.dart';

import '../services/family_projector_profile.dart';
import '../utils/scroll_utils.dart';
import 'input_mode_tracker.dart';
import 'owned_focus_node_binding.dart';

/// Manages the internal/external FocusNode lifecycle for list-tile widgets and
/// auto-scrolls the tile into view when it gains focus.
mixin FocusableTileStateMixin<T extends StatefulWidget> on State<T> {
  final _focusNodeBinding = OwnedFocusNodeBinding();
  FocusNode? _boundExternalNode;
  bool _projectorFocused = false;

  FocusNode? get widgetFocusNode;

  FocusNode get effectiveFocusNode => _focusNodeBinding.node;

  @override
  void initState() {
    super.initState();
    _bindFocusNode();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_boundExternalNode != widgetFocusNode) {
      _bindFocusNode();
    }
  }

  @override
  void dispose() {
    _focusNodeBinding.dispose();
    super.dispose();
  }

  void _bindFocusNode() {
    _boundExternalNode = widgetFocusNode;
    _focusNodeBinding.bind(externalNode: widgetFocusNode, listener: _onFocusChange);
  }

  void _onFocusChange() {
    if (FamilyProjectorProfile.enabled && mounted && effectiveFocusNode.hasFocus != _projectorFocused) {
      setState(() => _projectorFocused = effectiveFocusNode.hasFocus);
    }
    // Reveal on focus is keyboard/D-pad-only: pointer-mode focus is
    // programmatic and invisible, so revealing it would yank the scroll view
    // (issue #2031).
    if (effectiveFocusNode.hasFocus && InputModeTracker.currentMode == InputMode.keyboard) {
      scrollContextToCenter(context);
    }
  }

  /// The family projector build shows the focused row as a solid amber bar
  /// with black text, icons and controls. A projected image in a lit room
  /// washes the charcoal background out to light grey, and the theme's faint
  /// focus tint disappears against it; a bright block stays visible.
  Widget projectorFocusFrame(BuildContext context, Widget tile) {
    if (!FamilyProjectorProfile.enabled || !_projectorFocused || !InputModeTracker.isKeyboardMode(context)) {
      return tile;
    }
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final ink = theme.colorScheme.onPrimary;
    bool on(Set<WidgetState> states) => states.contains(WidgetState.selected);
    // A Material, not a coloured box: ListTile paints its ink on the nearest
    // Material, which a DecoratedBox in between would cover.
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) => on(states) ? accent : ink),
            trackColor: WidgetStateProperty.resolveWith((states) => on(states) ? ink : accent),
            trackOutlineColor: WidgetStatePropertyAll(ink),
          ),
          checkboxTheme: CheckboxThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) => on(states) ? ink : Colors.transparent),
            checkColor: WidgetStatePropertyAll(accent),
            side: BorderSide(color: ink, width: 2),
          ),
        ),
        child: ListTileTheme.merge(textColor: ink, iconColor: ink, child: tile),
      ),
    );
  }
}
