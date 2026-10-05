import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:minuta_native/minuta_native.dart';
import 'package:record/record.dart';

import 'overlay/assistant_overlay.dart' show panelHeight;

/// Opens the floating assistant over other apps, asking for the permissions it
/// needs along the way. Returns false when the user backed out.
Future<bool> launchAssistant(BuildContext context) async {
  if (!Platform.isAndroid) {
    await _alert(context, 'Só no Android',
        'O iOS não permite janelas flutuantes sobre outros apps. Use "Só gravar" no iPhone.');
    return false;
  }
  if (await FlutterOverlayWindow.isActive()) {
    await MinutaNative.moveTaskToBack();
    return true;
  }

  // 1. Microphone.
  final recorder = AudioRecorder();
  final mic = await recorder.hasPermission();
  await recorder.dispose();
  if (!context.mounted) return false;
  if (!mic) {
    await _alert(context, 'Microfone bloqueado',
        'Permita o microfone para o Minuta nas configurações do Android.');
    return false;
  }

  // 2. Draw over other apps.
  if (!await FlutterOverlayWindow.isPermissionGranted()) {
    if (!context.mounted) return false;
    final go = await _confirm(
      context,
      'Mostrar sobre outros apps',
      'Para o assistente flutuar sobre o Meet, Zoom, WhatsApp ou qualquer app, ative '
          '"Sobrepor a outros apps" para o Minuta na próxima tela e depois volte.',
      'Abrir ajustes',
    );
    if (!go) return false;
    await FlutterOverlayWindow.requestPermission();
    if (!await FlutterOverlayWindow.isPermissionGranted()) return false;
  }

  // 3. Screen (optional; can also be granted later from "Analisar tela").
  if (!context.mounted) return false;
  final wantScreen = await _confirm(
    context,
    'Deixar o assistente ver a tela?',
    'Assim ele responde sobre o que aparece na tela quando você tocar em "Analisar tela". '
        'O Android vai pedir para você confirmar.',
    'Permitir',
    cancel: 'Agora não',
  );
  if (wantScreen) {
    try {
      await MinutaNative.requestScreenCapture();
    } catch (_) {}
  }

  if (!context.mounted) return false;
  final dpr = MediaQuery.devicePixelRatioOf(context);
  await FlutterOverlayWindow.showOverlay(
    height: (panelHeight * dpr).round(),
    width: WindowSize.matchParent,
    alignment: OverlayAlignment.topCenter,
    flag: OverlayFlag.focusPointer,
    enableDrag: false,
    positionGravity: PositionGravity.none,
    overlayTitle: 'Minuta está ouvindo',
    overlayContent: 'O assistente está ativo sobre os outros apps.',
    visibility: NotificationVisibility.visibilityPublic,
  );
  // Give the overlay engine a moment to attach before telling it to start.
  await Future.delayed(const Duration(milliseconds: 400));
  await MinutaNative.broadcast({'cmd': 'start'});
  await MinutaNative.moveTaskToBack();
  return true;
}

Future<void> stopAssistant() => MinutaNative.broadcast({'cmd': 'stop'});

Future<void> _alert(BuildContext context, String title, String msg) => showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg)),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );

Future<bool> _confirm(BuildContext context, String title, String msg, String ok,
    {String cancel = 'Cancelar'}) async {
  final r = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg)),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        CupertinoDialogAction(
            isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
