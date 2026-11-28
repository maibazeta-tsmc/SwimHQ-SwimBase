import 'package:flutter_test/flutter_test.dart';

import 'package:swimbase/app.dart';

void main() {
  testWidgets('Shows setup instructions when Supabase is not connected',
      (tester) async {
    await tester.pumpWidget(const SwimBaseApp(configured: false));
    expect(find.text('Almost there'), findsOneWidget);
  });
}
