import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrobblr_mobile/auth/auth_controller.dart';
import 'package:scrobblr_mobile/background/service_client.dart';
import 'package:scrobblr_mobile/ui/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _loginApp() => MaterialApp(
  home: LoginScreen(
    auth: AuthController(),
    service: const ScrobbleServiceClient(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login screen renders and toggles registration mode', (
    tester,
  ) async {
    await tester.pumpWidget(_loginApp());
    await tester.pump();

    expect(find.text('Scrobblr'), findsOneWidget);
    // Debug builds open the advanced section with the dev server pre-filled.
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await tester.pump();

    expect(find.text('Email'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
  });

  testWidgets('empty submit shows validation error', (tester) async {
    await tester.pumpWidget(_loginApp());
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Username and password are required.'), findsOneWidget);
  });

  testWidgets('advanced toggle hides and shows the server field', (
    tester,
  ) async {
    await tester.pumpWidget(_loginApp());
    await tester.pump();

    expect(find.text('Server URL'), findsOneWidget);

    await tester.tap(find.text('Hide advanced options'));
    await tester.pump();
    expect(find.text('Server URL'), findsNothing);

    await tester.tap(find.text('Advanced options · self-hosting'));
    await tester.pump();
    expect(find.text('Server URL'), findsOneWidget);
  });

  testWidgets('remembered custom server re-opens the advanced section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'scrobblr.last_server_url': 'http://my-nas.local:8080',
    });

    await tester.pumpWidget(_loginApp());
    await tester.pump();

    expect(find.text('Server URL'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'http://my-nas.local:8080'),
      findsOneWidget,
    );
  });
}
