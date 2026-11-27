import 'package:material_ui/material_ui.dart';

/// Экран «Интернет» — заглушка до следующей версии.
class InternetScreen extends StatelessWidget {
  const InternetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.network_check, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          const Text('Интернет', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Скоро',
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
