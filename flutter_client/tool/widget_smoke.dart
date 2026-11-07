// Manual native-widget smoke test. Use only with --debug --target tool/widget_smoke.dart.
// The QR is a synthetic fixture, not a campus access pass. No Rocket.Chat calls.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:campus_pass/home_screen_widgets.dart';
import 'package:campus_pass/pass_theme.dart';
import 'package:campus_pass/widget_settings.dart';

final widgets = HomeScreenWidgets();
final image = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAZoAAAGaAQAAAAAefbjOAAACJ0lEQVR42u2cS27DMAxEieoAPpKvniP5AAYYSfw66KLtrpjxQkgjcxM/DIcUXdHfXy9hEIMYxCAGMYhBDIog8WvMT8f887xE5t5ajrV/xQ3nDvqSP1wM+h9BTsR+0nqN+biP22BwQNZyro26j0QgELFUYD/4giEp2RvtOxKBRMTMGlMjtlqopQ4Sga4RkwjzEds9nLZLInB9xFYGDQ4sidBH4BFRtcZ5fbew1gAjotejq/qUKDhs+byFvx4AEekU1uIWwrKG9ygMFWoEjrPsprL85LzuhCbwIREAGvGymjOcgnOwUseiRJ75g0SAaMSEodyDV5oBSBaoJAJFI6zIjIMMs5fVuNRwm9QIpKxhh1ySbFTqoEZgasTOFXGQ4UR4HXqw+sQjYjyTg5vK7jKoEVhZQ1vHOpqU/TQ8zCeJQOpQWbtSW5nRvAWdJVT1KVFctOPvShN6PYpREgGSNUIj7jCVpSCPqoNEoDjLmK4c2cIcbYaKp+FgPkKjH3HWsGW1J9QBIREwPmI98z4GUQdfWgs1Aq76PD4m6IIDsUPRwQ4VkEbkQES1qbyzffe7qRE4PkK7dyxKTB4eGyQCoh9hV47I5DtdOU1FH4HmLPvbOjFNNbRyRdkKEgHlI2ymMnUjBjBFqr1NIsCc5ZUcHNG6SiLoIxA1QmI0ogDxt4PZoUL0EfGCeHYhPpoSJAKy1mgTl81HUCMg+xH8fywMYhCDGMQgBjHop0FveygBsvIOZH4AAAAASUVORK5CYII=',
);
Future<bool> sync() async {
  await widgets.publish(
    WidgetPass(
      image: image,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      boostBrightness: true,
    ),
  );
  return true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await sync();
  runApp(
    MaterialApp(
      theme: passTheme(),
      home: HomeWidgetSettings(widgets: widgets, onSync: sync),
    ),
  );
}
