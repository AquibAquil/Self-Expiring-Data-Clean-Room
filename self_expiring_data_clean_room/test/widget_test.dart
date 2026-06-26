import 'package:flutter_test/flutter_test.dart';

import 'package:self_expiring_data_clean_room/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const SelfExpiringDataCleanRoomApp());
  });
}
