import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:indetail/main.dart';

void main() {
  testWidgets('launch screen is branded INDETAIL and exposes the preview entry', (tester) async {
    const channel = MethodChannel('com.indetail.office/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    await tester.pumpWidget(const InDetailApp());
    await tester.pumpAndSettle();

    expect(find.text('INDETAIL'), findsOneWidget);
    expect(find.text('Explore the interactive preview'), findsOneWidget);
    expect(find.text('One clear view of the work.'), findsOneWidget);
  });
}
