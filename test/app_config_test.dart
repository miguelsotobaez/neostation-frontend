import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/app_config.dart';

void main() {
  group('AppConfig', () {
    test('should have default auth base URL', () {
      expect(AppConfig.authBaseUrl, 'https://auth.neosync.cloud');
    });

    test('should have default neoSync base URL', () {
      expect(AppConfig.neoSyncBaseUrl, 'https://sync.neosync.cloud');
    });

    test('should have default billing base URL', () {
      expect(AppConfig.billingBaseUrl, 'https://billing.neosync.cloud');
    });

    test('should have default notify base URL', () {
      expect(AppConfig.notifyBaseUrl, 'ws://notify.neosync.cloud/ws');
    });
  });
}
