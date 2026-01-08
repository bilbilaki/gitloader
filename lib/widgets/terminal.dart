import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:xterm/xterm.dart';

import 'terminal_controller.dart';
// Update your build method or create a wrapper
class MultiTabTerminalScreen extends StatelessWidget {
  final controller = Get.put(TerminalTabController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.activeSession?.title ?? "Terminal")),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Obx(() => _buildTabBar()),
        ),
        actions: [
          IconButton(icon: Icon(Icons.add), onPressed: controller.addNewTab),
        ],
      ),
      body: Obx(() {
        if (controller.activeSession == null) {
          return Center(child: Text("No Tabs"));
        }

        // Pass the terminal from the active session to your existing TerminalScreen class
        return TerminalScreen(
          key: ValueKey(controller.activeSession!.id),
          terminal: controller.activeSession!.terminal,
        );
      }),
    );
  }

  Widget _buildTabBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: controller.sessions.asMap().entries.map((entry) {
          int idx = entry.key;
          bool isActive = controller.currentIndex.value == idx;
          return GestureDetector(
            onTap: () => controller.currentIndex.value = idx,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isActive
                  ? Colors.blue.withOpacity(0.2)
                  : Colors.transparent,
              child: Row(
                children: [
                  Text(
                    entry.value.title,
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => controller.closeTab(idx),
                    child: Icon(Icons.close, size: 16, color: Colors.white54),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
class TerminalScreen extends StatefulWidget {
  final Terminal terminal;
  const TerminalScreen({super.key, required this.terminal});
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final TerminalController controller;
  final FocusNode focusNode = FocusNode();

  // Selection UX state
  OverlayEntry? _selectionToolbar;
  Offset? _lastPointerGlobal;

  // Soft modifiers
  bool _ctrl = false;
  bool _alt = false;

  static const int maxLines = 100000;

  @override
  void initState() {
    super.initState();
    // terminal = Terminal(maxLines: maxLines);
    controller = TerminalController();

    // Listen to terminal state changes (selection, scroll, etc.)
    controller.addListener(_onTerminalChange);

    _writeWelcomeMessage();
  }

  void _writeWelcomeMessage() {
    widget.terminal.write('Welcome to Flutter Terminal\r\n');
    widget.terminal.write(
      '\x1b[31mRed\x1b[0m \x1b[32mGreen\x1b[0m \x1b[34mBlue\x1b[0m\r\n',
    );
    widget.terminal.write(
      'Long-press to select text. The toolbar will appear automatically.\r\n\$ ',
    );
  }

  @override
  void dispose() {
    controller.removeListener(_onTerminalChange);
    _hideToolbar();
    focusNode.dispose();
    super.dispose();
  }

  // ---------------- Listeners ----------------

  void _onTerminalChange() {
    // Check if selection exists and is not empty
    if (controller.selection != null) {
      // If we have a selection but no toolbar, show it
      if (_selectionToolbar == null && _lastPointerGlobal != null) {
        _showToolbar(context, _lastPointerGlobal!);
      }
    } else {
      // If selection is gone, hide toolbar
      if (_selectionToolbar != null) {
        _hideToolbar();
      }
    }
  }

  // ---------------- Clipboard / Paste ----------------

  Future<void> _copySelection() async {
    final selection = controller.selection;
    if (selection == null ) return;

    // Correct API to get selected text
    final text = widget.terminal.buffer.getText(selection);
    await Clipboard.setData(ClipboardData(text: text));

    // Clear selection after copy
    controller.clearSelection();
    _hideToolbar();
  }

  Future<void> _pasteClipboard({bool bracketed = true}) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    // Bracketed paste mode (protects against accidental execution of newlines)
    final payload = bracketed ? '\x1b[200~$text\x1b[201~' : text;
    widget.terminal.paste(payload);
  }

  void _scrollToBottom() {
    // Reset scroll offset to 0 (which is the bottom in xterm logic often,
    // or use setScrollOffset to max).
    // The easiest way in modern xterm is usually clearing the offset override.
    //controller(0);
  }

  // ---------------- Selection Toolbar Overlay ----------------

  void _showToolbar(BuildContext context, Offset globalPos) {
    _hideToolbar();

    final overlay = Overlay.of(context);

    _selectionToolbar = OverlayEntry(
      builder: (ctx) {
        // Calculations to keep toolbar on screen
        final media = MediaQuery.of(ctx);
        const w = 200.0;
        const h = 44.0;
        // Position slightly above the touch point
        final x = globalPos.dx.clamp(8.0, media.size.width - w - 8.0);
        final y = (globalPos.dy - 60).clamp(
          media.padding.top + 8.0,
          media.size.height - h - 8.0,
        );

        return Positioned(
          left: x,
          top: y,
          width: w,
          height: h,
          child: Material(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
            elevation: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _toolbarBtn(label: 'Copy', onTap: _copySelection),
                _toolbarBtn(
                  label: 'Select All',
                  onTap: () {
                    // Select all visible buffer or everything?
                    // Typically complicated in infinite scroll,
                    // but we can select the visible range or clear.
                    // For now, let's just offer Clear.
                    controller.setSelection(CellAnchor(0), CellAnchor(100), mode: SelectionMode.block);
                   // _hideToolbar();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_selectionToolbar!);
  }

  Widget _toolbarBtn({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _hideToolbar() {
    _selectionToolbar?.remove();
    _selectionToolbar = null;
  }

  // ---------------- Input & Modifiers ----------------

  void _toggleCtrl() => setState(() => _ctrl = !_ctrl);
  void _toggleAlt() => setState(() => _alt = !_alt);

  void _sendWithModifiers({TerminalKey? key, String? char}) {
    // 1. Handle Special Keys (Arrows, Esc, etc.)
    if (key != null) {
      if ((_ctrl || _alt) &&
          [
            TerminalKey.arrowUp,
            TerminalKey.arrowDown,
            TerminalKey.arrowRight,
            TerminalKey.arrowLeft,
          ].contains(key)) {
        // ANSI Modifier logic: 1 + modifiers (Ctrl=4, Alt=2, Shift=1)
        // Simple mapping: Ctrl=5, Alt=3, Ctrl+Alt=7
        final mod = _ctrl && _alt ? 7 : (_ctrl ? 5 : 3);
        final code = switch (key) {
          TerminalKey.arrowUp => 'A',
          TerminalKey.arrowDown => 'B',
          TerminalKey.arrowRight => 'C',
          TerminalKey.arrowLeft => 'D',
          _ => '',
        };
        if (code.isNotEmpty) {
          widget.terminal.write('\x1b[1;$mod$code');
        }
        return;
      }
      widget.terminal.keyInput(key);
      return;
    }

    // 2. Handle Character Input
    if (char != null) {
      if (_ctrl && char.length == 1) {
        final code = char.codeUnitAt(0);
        // Map a-z to 1-26 (Ctrl+A .. Ctrl+Z)
        if (code >= 97 && code <= 122) {
          widget.terminal.textInput(String.fromCharCode(code - 96));
          return;
        }
        // Map A-Z to 1-26
        if (code >= 65 && code <= 90) {
          widget.terminal.textInput(String.fromCharCode(code - 64));
          return;
        }
      }
      if (_alt) {
        widget.terminal.write('\x1b'); // Send Escape before char for Alt
      }
      widget.terminal.textInput(char);
    }

    // Reset modifiers after single use if desired (Standard mobile keyboard behavior)
    // Or keep them enabled (Sticky keys). Let's keep them sticky for now as per UI state.
  }

  // ---------------- Build UI ----------------

  @override
  Widget build(BuildContext context) {
    // Detect keyboard height accurately
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      // We handle the bottom inset manually with the Stack
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Terminal'),
        backgroundColor: Colors.grey[900],
        actions: [
          IconButton(
            tooltip: 'Paste',
            onPressed: () => _pasteClipboard(bracketed: true),
            icon: const Icon(Icons.paste),
          ),
          IconButton(
            tooltip: 'Scroll to Bottom',
            onPressed: _scrollToBottom,
            icon: const Icon(Icons.vertical_align_bottom),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. TERMINAL VIEW
          Positioned.fill(
            // Push terminal up when keyboard + soft bar are visible
            bottom: isKeyboardVisible ? (keyboardHeight + 44) : 0,
            child: Listener(
              // Passive listener to track touch position for the toolbar
              // This does NOT steal gestures from TerminalView
              onPointerDown: (e) => _lastPointerGlobal = e.position,
              onPointerMove: (e) => _lastPointerGlobal = e.position,
              child: TerminalView(
                widget.terminal,
                controller: controller,
                focusNode: focusNode,
                autofocus: true,

                // Styling
                textStyle: const TerminalStyle(
                  fontSize: 14,
                  fontFamily: 'RobotoMono',
                ),
                // Allow xterm to handle gestures naturally
                // We listen to selection changes via widget.terminal.addListener
              ),
            ),
          ),

          // 2. SOFT KEYBOARD BAR
          // Only visible when the system keyboard is up
          if (isKeyboardVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboardHeight, // Sit exactly on top of keyboard
              height: 44,
              child: _SimpleSoftBar(
                ctrlOn: _ctrl,
                altOn: _alt,
                onCtrl: _toggleCtrl,
                onAlt: _toggleAlt,
                onCopy: _copySelection,
                onPaste: () => _pasteClipboard(bracketed: true),
                onKey: _sendWithModifiers,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- Soft Keyboard Widget ----------------

class _SimpleSoftBar extends StatelessWidget {
  const _SimpleSoftBar({
    required this.ctrlOn,
    required this.altOn,
    required this.onCtrl,
    required this.onAlt,
    required this.onCopy,
    required this.onPaste,
    required this.onKey,
  });

  final bool ctrlOn;
  final bool altOn;
  final VoidCallback onCtrl;
  final VoidCallback onAlt;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final void Function({TerminalKey? key, String? char}) onKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101010),
      elevation: 4,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        children: [
          _modifierKey('CTRL', ctrlOn, onCtrl),
          _modifierKey('ALT', altOn, onAlt),
          _actionKey('ESC', () => onKey(key: TerminalKey.escape)),
          _actionKey('TAB', () => onKey(key: TerminalKey.tab)),
          _actionKey('↑', () => onKey(key: TerminalKey.arrowUp)),
          _actionKey('↓', () => onKey(key: TerminalKey.arrowDown)),
          _actionKey('←', () => onKey(key: TerminalKey.arrowLeft)),
          _actionKey('→', () => onKey(key: TerminalKey.arrowRight)),
          _actionKey('/', () => onKey(char: '/')),
          _actionKey('-', () => onKey(char: '-')),
        ],
      ),
    );
  }

  Widget _actionKey(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF222222),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _modifierKey(String label, bool isOn, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minWidth: 44),
          decoration: BoxDecoration(
            color: isOn ? const Color(0xFF355CFF) : const Color(0xFF222222),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isOn ? const Color(0xFF5E7BFF) : const Color(0xFF333333),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
