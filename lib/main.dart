import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'services/navigation_service.dart';
import 'theme/app_theme.dart';
import 'screens/login.dart';
import 'screens/home.dart';
import 'screens/profile.dart';
import 'screens/splash_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/recovery_phrase_screen.dart';
import 'screens/confirm_recovery_phrase_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/search_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

  runApp(const ChatApp());

  // No Firebase messaging: notification taps handled via native glue if present.
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'ichat',
      theme: AppTheme.theme,
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/': (_) => const LoginScreen(),
        '/home': (_) => const ChatHome(),
        '/profile': (_) => const ProfileScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/recovery-phrase': (_) => const RecoveryPhraseScreen(),
        '/confirm-recovery-phrase': (_) => const ConfirmRecoveryPhraseScreen(),
        '/welcome': (_) => const WelcomeScreen(),
        '/search': (_) => const SearchScreen(),
      },
    );
  }
}
