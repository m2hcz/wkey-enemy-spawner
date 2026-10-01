import 'package:flutter_test/flutter_test.dart';
import 'package:vps_terminal/special_keys.dart';
import 'package:xterm/xterm.dart';

void main() {
  late StickyModifiers mods;
  late Terminal terminal;
  late List<String> sent;

  setUp(() {
    mods = StickyModifiers(defaultInputHandler);
    terminal = Terminal(inputHandler: mods);
    sent = [];
    terminal.onOutput = (d) => sent.add(mods.transformOutput(d));
  });

  test('plain text passes through', () {
    terminal.textInput('ls -la');
    expect(sent, ['ls -la']);
  });

  test('one-shot CTRL + typed letter sends control char then releases', () {
    mods.cycle('ctrl');
    terminal.textInput('c');
    terminal.textInput('c');
    expect(sent, ['\x03', 'c']);
    expect(mods.ctrl, ModState.off);
  });

  test('CTRL + key event (soft keyboard letter) goes through handler', () {
    mods.cycle('ctrl');
    terminal.keyInput(TerminalKey.keyD);
    expect(sent, ['\x04']);
    expect(mods.ctrl, ModState.off);
  });

  test('locked CTRL stays active', () {
    mods.cycle('ctrl');
    mods.cycle('ctrl');
    terminal.textInput('a');
    terminal.textInput('e');
    expect(sent, ['\x01', '\x05']);
    expect(mods.ctrl, ModState.locked);
  });

  test('ALT prefixes ESC', () {
    mods.cycle('alt');
    terminal.textInput('b');
    expect(sent, ['\x1bb']);
  });

  test('special keys produce escape sequences', () {
    terminal.keyInput(TerminalKey.arrowUp);
    terminal.keyInput(TerminalKey.escape);
    terminal.keyInput(TerminalKey.tab);
    expect(sent, ['\x1b[A', '\x1b', '\t']);
  });

  test('CTRL + arrow sends modified sequence', () {
    mods.cycle('ctrl');
    terminal.keyInput(TerminalKey.arrowRight);
    expect(sent, ['\x1b[1;5C']);
  });
}
