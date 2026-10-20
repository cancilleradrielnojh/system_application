// Host-side driver. Required for `flutter drive` (profile-mode runs) and
// writes everything the tests pass to binding.reportData into
// build/integration_response_data.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();