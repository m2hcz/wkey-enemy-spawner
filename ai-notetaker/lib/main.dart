import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter/services.dart';

import 'ai_settings.dart';
import 'screens/home_screen.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([NotesStore.instance.load(), SettingsStore.instance.load()]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MinutaApp());
}

class MinutaApp extends StatelessWidget {
  const MinutaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'Minuta',
      debugShowCheckedModeBanner: false,
      // Follows the phone's light/dark setting, like iOS.
      theme: CupertinoThemeData(primaryColor: AppColors.accent),
      localizationsDelegates: [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: HomeScreen(),
    );
  }
}
