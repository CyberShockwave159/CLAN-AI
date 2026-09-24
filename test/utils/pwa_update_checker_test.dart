import 'package:clan_ai/core/utils/pwa_update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PwaUpdateChecker', () {
    test('establishes baseline on first fetch, then notifies once on change',
        () async {
      var deployed = '1.2.0';
      final checker = PwaUpdateChecker(
        checkInterval: const Duration(days: 1),
        versionFetcher: () async => deployed,
      );
      var notifications = 0;
      checker.addListener(() => notifications++);

      await checker.checkNow();
      expect(checker.baselineVersion, '1.2.0');
      expect(checker.updateNotified, isFalse);
      expect(notifications, 0);

      deployed = '1.3.0';
      await checker.checkNow();
      expect(checker.updateNotified, isTrue);
      expect(notifications, 1);

      deployed = '1.4.0';
      await checker.checkNow();
      expect(notifications, 1);

      checker.dispose();
    });

    test('offline boot does not warn; baseline comes from first success',
        () async {
      String? deployed;
      final checker = PwaUpdateChecker(
        checkInterval: const Duration(days: 1),
        versionFetcher: () async => deployed,
      );
      var notifications = 0;
      checker.addListener(() => notifications++);

      await checker.checkNow();
      expect(checker.baselineVersion, isNull);
      expect(notifications, 0);

      deployed = '1.2.0';
      await checker.checkNow();
      expect(checker.baselineVersion, '1.2.0');
      expect(notifications, 0);

      deployed = '1.3.0';
      await checker.checkNow();
      expect(notifications, 1);

      checker.dispose();
    });

    test('same version after baseline never notifies', () async {
      final checker = PwaUpdateChecker(
        checkInterval: const Duration(days: 1),
        versionFetcher: () async => '1.2.0',
      );
      var notifications = 0;
      checker.addListener(() => notifications++);

      await checker.checkNow();
      await checker.checkNow();
      await checker.checkNow();
      expect(checker.updateNotified, isFalse);
      expect(notifications, 0);

      checker.dispose();
    });

    test('failed fetches are ignored', () async {
      final checker = PwaUpdateChecker(
        checkInterval: const Duration(days: 1),
        versionFetcher: () async => null,
      );
      var notifications = 0;
      checker.addListener(() => notifications++);

      await checker.checkNow();
      expect(checker.baselineVersion, isNull);
      expect(notifications, 0);

      checker.dispose();
    });
  });
}