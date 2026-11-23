import 'package:material_ui/material_ui.dart';

import 'screens/gate_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InDetailApp());
}

class InDetailApp extends StatelessWidget {
  const InDetailApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'INDETAIL',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const GateScreen(),
  );
}
