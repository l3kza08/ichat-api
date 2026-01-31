// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// test_setup removed — relying on real platform plugins for integration / device tests
import 'package:ichat/screens/login.dart';
import 'package:ichat/screens/signup_screen.dart';
import 'package:ichat/screens/home.dart';
import 'package:ichat/screens/profile.dart';
import 'package:ichat/screens/search_screen.dart';
import 'package:ichat/services/p2p_service.dart'; // Import P2PService
import 'package:ichat/services/auth_service.dart'; // Import AuthService

import 'package:ichat/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // initTestEnvironment removed
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ChatApp());
    // App builds a MaterialApp
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('navigates to signup screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ChatApp());

    // The app starts on a splash screen, let it settle.
    await tester.pumpAndSettle();

    // Should be on the Login screen
    expect(find.byType(LoginScreen), findsOneWidget);

    // Find and tap the create account button
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    // Should be on the SignUp screen
    expect(find.byType(SignUpScreen), findsOneWidget);
  });

  group('ChatHome navigation tests', () {
    setUp(() async {
      // initTestEnvironment removed
      // Ensure a user is logged in for these tests
      // This is a simplified mock for AuthService and P2PService
      // In a real app, you would use proper mocking techniques
      await AuthService.instance.signUp(
        name: 'Test User',
        username: 'testuser',
        phrase: 'test recovery phrase',
      );
      // Ensure P2PService is aware of the current user
      await P2PService.instance.announce(AuthService.instance.currentUser!);
    });

    testWidgets('navigates to search screen', (WidgetTester tester) async {
      await tester.pumpWidget(const ChatApp());
      await tester
          .pumpAndSettle(); // Navigate through splash and login/authgate

      // Should be on the ChatHome screen
      expect(find.byType(ChatHome), findsOneWidget);

      // Find and tap the search icon
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // Should be on the SearchScreen
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('navigates to profile screen', (WidgetTester tester) async {
      await tester.pumpWidget(const ChatApp());
      await tester
          .pumpAndSettle(); // Navigate through splash and login/authgate

      // Should be on the ChatHome screen
      expect(find.byType(ChatHome), findsOneWidget);

      // Tap the profile tab (assuming it's the last one in LiquidNav)
      // This requires knowing the index of the profile tab.
      // From home.dart: _navIndex = 2 for chats, profile tab is likely 3 if there are 4 tabs
      // The _buildProfileTab is the 4th child in IndexedStack, so index 3.
      // If there are 4 tabs, and _navIndex defaults to 2 (Chats), we need to tap the 4th tab.
      // Assuming LiquidNav has 4 items
      await tester.tap(
        find.byIcon(Icons.person).last,
      ); // Assuming person icon is used for profile
      await tester.pumpAndSettle();

      // Find and tap the 'Edit profile' button
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();

      // Should be on the ProfileScreen
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });
}
