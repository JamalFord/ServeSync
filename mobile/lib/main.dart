import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'screens/auth/pin_keypad_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ServeSyncApp());
}

class ServeSyncApp extends StatelessWidget {
  const ServeSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppState.instance;

    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'ServeSync Restaurant OS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeData,
          home: const PinKeypadScreen(),
        );
      },
    );
  }
}
