import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const VpsTerminalApp());
}

class VpsTerminalApp extends StatelessWidget {
  const VpsTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VPS Terminal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.greenAccent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const StartupGate(),
    );
  }
}

/// Opens the terminal straight away when a VPS is configured (auto-connect),
/// otherwise shows the setup form first.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final config = await ConfigStore.load();
    if (!mounted) return;
    final Widget next = config == null
        ? const SettingsScreen(firstRun: true)
        : TerminalScreen(config: config);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
