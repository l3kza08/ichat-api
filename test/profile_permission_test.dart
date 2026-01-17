import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// test_setup removed — relying on real platform plugins for integration / device tests
import 'package:ichat/screens/profile.dart';
import 'package:ichat/services/auth_service.dart';
import 'package:ichat/services/permission_service.dart';

void main() {
  setUp(() async {
    // initTestEnvironment removed
    // Ensure a user is "logged in" for ProfileScreen to load correctly
    AuthService.instance.updateCurrentUser(
      UserProfile(uid: 'test_uid', name: 'Test User', username: 'testuser'),
    );
  });

  tearDown(() async {
    // Clear the "logged in" user after each test
    await AuthService.instance.logout();
  });

  testWidgets('Profile shows request banner when permissions denied', (
    WidgetTester tester,
  ) async {
    // Arrange: set test check handler to return denied
    PermissionService.setTestHandlers(
      checkHandler: () async => PermissionRequestResult.denied,
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    // allow init to run
    await tester.pumpAndSettle();

    // Expect: banner text present with Request button
    expect(find.textContaining('permission'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);

    PermissionService.clearTestHandlers();
  });

  testWidgets('Profile shows open settings when permanently denied', (
    WidgetTester tester,
  ) async {
    PermissionService.setTestHandlers(
      checkHandler: () async => PermissionRequestResult.permanentlyDenied,
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('permanently denied'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);

    PermissionService.clearTestHandlers();
  });

  testWidgets('Profile shows Change avatar when granted', (
    WidgetTester tester,
  ) async {
    PermissionService.setTestHandlers(
      checkHandler: () async => PermissionRequestResult.granted,
    );
    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Change avatar'), findsOneWidget);

    PermissionService.clearTestHandlers();
  });
}
