import 'package:integration_test/integration_test.dart';

import '../test/integration/app_flow_test.dart' as flows;

/// the same flows as the headless suite, driven on a real device
///
///     flutter test integration_test -d linux
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  flows.main();
}
