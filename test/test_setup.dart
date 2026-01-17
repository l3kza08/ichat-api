import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichat/screens/splash_screen.dart';
import 'package:ichat/widgets/loading_spinner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void initTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Provide a mock SharedPreferences instance for tests
  SharedPreferences.setMockInitialValues({});

  // Mock flutter_secure_storage channel to avoid MissingPluginException
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  secureChannel.setMockMethodCallHandler((call) async {
    switch (call.method) {
      case 'read':
        return null;
      case 'write':
        return null;
      case 'delete':
        return null;
      case 'readAll':
        return <String, String>{};
      case 'containsKey':
        return false;
      default:
        return null;
    }
  });
  // Enable SplashScreen test mode so it doesn't create delayed timers
  SplashScreen.testMode = true;
  // Disable continuous spinner animation during tests so pumpAndSettle completes
  LoadingSpinner.testMode = true;
}
