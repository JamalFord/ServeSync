import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/auth/pin_keypad_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (Gracefully handles offline or mock fallback)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase successfully initialized for ServeSync');
  } catch (e) {
    debugPrint('Firebase initialization notice: $e (running in local offline demo mode)');
  }

  runApp(const ServeSyncApp());
}

class ServeSyncApp extends StatelessWidget {
  const ServeSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ServeSync Restaurant OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const PinKeypadScreen(),
    );
  }
}
