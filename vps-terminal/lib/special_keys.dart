import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

enum ModState { off, once, locked }

/// Sticky Ctrl / Alt / Shift modifiers for the on-screen key bar.
///
/// Tap a modifier once: it applies to the next key and then releases.
/// Tap it twice: it stays locked until tapped again.
///
/// Works for both paths the soft keyboard can take in xterm:
/// - key events (arrows, letters mapped to keys) go through [call];
/// - plain text input bypasses the input handler, so [transformOutput]
///   applies the modifiers to it before it is sent to the server.
class StickyModifiers extends TerminalInputHandler with ChangeNotifier {
  StickyModifiers(this._inner);

  final TerminalInputHandler _inner;

  ModState ctrl = ModState.off;
  ModState alt = ModState.off;
  ModState shift = ModState.off;

  bool _appliedByHandler = false;

  bool get _anyActive =>
      ctrl != ModState.off || alt != ModState.off || shift != ModState.off;

  void cycle(String which) {
    ModState next(ModState s) => switch (s) {
          ModState.off => ModState.once,
          ModState.once => ModState.locked,
          ModState.locked => ModState.off,
        };
    switch (which) {
      case 'ctrl':
        ctrl = next(ctrl);
      case 'alt':
        alt = next(alt);
      case 'shift':
        shift = next(shift);
    }
    notifyListeners();
  }

  void _releaseOnce() {
    var changed = false;
    if (ctrl == ModState.once) {
      ctrl = ModState.off;
      changed = true;
    }
    if (alt == ModState.once) {
      alt = ModState.off;
      changed = true;
    }
    if (shift == ModState.once) {
      shift = ModState.off;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  String? call(TerminalKeyboardEvent event) {
    if (!_anyActive) return _inner.call(event);
    final out = _inner.call(event.copyWith(
      ctrl: event.ctrl || ctrl != ModState.off,
      alt: event.alt || alt != ModState.off,
      shift: event.shift || shift != ModState.off,
    ));
    if (out != null) _appliedByHandler = true;
    return out;
  }

  /// Called on everything the terminal is about to send to the server.
  String transformOutput(String data) {
    if (_appliedByHandler) {
      _appliedByHandler = false;
      _releaseOnce();
      return data;
    }
    if (!_anyActive) return data;

    var out = data;
    if (shift != ModState.off) out = out.toUpperCase();
    if (ctrl != ModState.off && out.length == 1) {
      out = _ctrlChar(out) ?? out;
    }
    if (alt != ModState.off) out = '\x1b$out';
    _releaseOnce();
    return out;
  }

  static String? _ctrlChar(String ch) {
    final c = ch.codeUnitAt(0);
    if (c >= 0x61 && c <= 0x7a) return String.fromCharCode(c - 0x60); // a-z
    if (c >= 0x40 && c <= 0x5f) return String.fromCharCode(c - 0x40); // @A-Z[\]^_
    if (ch == ' ' || ch == '2') return '\x00';
    if (ch == '?' || ch == '8') return '\x7f';
    if (ch == '/') return '\x1f';
    return null;
  }
}

/// A single button on the key bar.
class _K {
  const _K(this.label, {this.key, this.text, this.mod, this.icon});
  final String label;
  final TerminalKey? key;
  final String? text;
  final String? mod;
  final IconData? icon;
}

const _mainRow = <_K>[
  _K('ESC', key: TerminalKey.escape),
  _K('TAB', key: TerminalKey.tab),
  _K('CTRL', mod: 'ctrl'),
  _K('ALT', mod: 'alt'),
  _K('SHIFT', mod: 'shift'),
  _K('←', key: TerminalKey.arrowLeft, icon: Icons.keyboard_arrow_left),
  _K('↓', key: TerminalKey.arrowDown, icon: Icons.keyboard_arrow_down),
  _K('↑', key: TerminalKey.arrowUp, icon: Icons.keyboard_arrow_up),
  _K('→', key: TerminalKey.arrowRight, icon: Icons.keyboard_arrow_right),
  _K('HOME', key: TerminalKey.home),
  _K('END', key: TerminalKey.end),
  _K('PGUP', key: TerminalKey.pageUp),
  _K('PGDN', key: TerminalKey.pageDown),
  _K('DEL', key: TerminalKey.delete),
  _K('INS', key: TerminalKey.insert),
];

const _symbolRow = <_K>[
  _K('^C', text: '\x03'),
  _K('^D', text: '\x04'),
  _K('^Z', text: '\x1a'),
  _K('^L', text: '\x0c'),
  _K('^R', text: '\x12'),
  _K('|', text: '|'),
  _K('/', text: '/'),
  _K('-', text: '-'),
  _K('~', text: '~'),
  _K('_', text: '_'),
  _K(':', text: ':'),
  _K(';', text: ';'),
  _K('&', text: '&'),
  _K('*', text: '*'),
  _K(r'$', text: r'$'),
  _K('<', text: '<'),
  _K('>', text: '>'),
  _K('{', text: '{'),
  _K('}', text: '}'),
  _K('[', text: '['),
  _K(']', text: ']'),
  _K('`', text: '`'),
  _K('"', text: '"'),
  _K("'", text: "'"),
  _K(r'\', text: r'\'),
  _K('=', text: '='),
  _K('#', text: '#'),
  _K('!', text: '!'),
];

const _fnRow = <_K>[
  _K('F1', key: TerminalKey.f1),
  _K('F2', key: TerminalKey.f2),
  _K('F3', key: TerminalKey.f3),
  _K('F4', key: TerminalKey.f4),
  _K('F5', key: TerminalKey.f5),
  _K('F6', key: TerminalKey.f6),
  _K('F7', key: TerminalKey.f7),
  _K('F8', key: TerminalKey.f8),
  _K('F9', key: TerminalKey.f9),
  _K('F10', key: TerminalKey.f10),
  _K('F11', key: TerminalKey.f11),
  _K('F12', key: TerminalKey.f12),
];

/// Two-row extra key bar shown above the soft keyboard, Termux-style.
class SpecialKeysBar extends StatefulWidget {
  const SpecialKeysBar({
    super.key,
    required this.terminal,
    required this.modifiers,
    required this.onPaste,
  });

  final Terminal terminal;
  final StickyModifiers modifiers;
  final VoidCallback onPaste;

  @override
  State<SpecialKeysBar> createState() => _SpecialKeysBarState();
}

class _SpecialKeysBarState extends State<SpecialKeysBar> {
  bool _showFn = false;

  void _press(_K k) {
    HapticFeedback.selectionClick();
    if (k.mod != null) {
      widget.modifiers.cycle(k.mod!);
    } else if (k.key != null) {
      widget.terminal.keyInput(k.key!);
    } else if (k.text != null) {
      widget.terminal.textInput(k.text!);
    }
  }

  Widget _button(_K k) {
    final mods = widget.modifiers;
    final state = switch (k.mod) {
      'ctrl' => mods.ctrl,
      'alt' => mods.alt,
      'shift' => mods.shift,
      _ => ModState.off,
    };
    final color = switch (state) {
      ModState.off => Colors.white,
      ModState.once => Colors.greenAccent,
      ModState.locked => Colors.orangeAccent,
    };
    final isRepeatable = k.key != null &&
        const {
          TerminalKey.arrowLeft,
          TerminalKey.arrowRight,
          TerminalKey.arrowUp,
          TerminalKey.arrowDown,
          TerminalKey.delete,
        }.contains(k.key);

    return _RepeatButton(
      onPress: () => _press(k),
      repeat: isRepeatable,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: state == ModState.off
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: color, width: 2)),
              ),
        child: k.icon != null
            ? Icon(k.icon, color: color, size: 22)
            : Text(
                k.label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
      ),
    );
  }

  Widget _row(List<_K> keys, {Widget? leading}) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: keys.map(_button).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.modifiers,
      builder: (context, _) => Material(
        color: const Color(0xFF1E1E1E),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(_mainRow),
            const Divider(height: 1, color: Colors.white12),
            _row(
              _showFn ? _fnRow : _symbolRow,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RepeatButton(
                    onPress: () => setState(() => _showFn = !_showFn),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        _showFn ? 'SYM' : 'Fn',
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  _RepeatButton(
                    onPress: widget.onPaste,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.content_paste,
                          size: 18, color: Colors.lightBlueAccent),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: Colors.white24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Button that fires on tap and, optionally, auto-repeats while held.
class _RepeatButton extends StatefulWidget {
  const _RepeatButton({
    required this.onPress,
    required this.child,
    this.repeat = false,
  });

  final VoidCallback onPress;
  final Widget child;
  final bool repeat;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  bool _held = false;

  Future<void> _startRepeat() async {
    _held = true;
    await Future.delayed(const Duration(milliseconds: 350));
    while (_held && mounted) {
      widget.onPress();
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Never steal focus from the terminal, or the soft keyboard would close.
    return GestureDetector(
      onLongPress: widget.repeat ? _startRepeat : null,
      onLongPressEnd: widget.repeat ? (_) => _held = false : null,
      onLongPressCancel: widget.repeat ? () => _held = false : null,
      child: InkWell(
        canRequestFocus: false,
        onTap: widget.onPress,
        child: widget.child,
      ),
    );
  }
}
