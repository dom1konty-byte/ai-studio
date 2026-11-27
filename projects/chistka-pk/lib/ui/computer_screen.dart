import 'package:material_ui/material_ui.dart';

import '../state/app_controller.dart';
import 'pult_tile.dart';

/// Экран «Компьютер» — пульт плиток. Пока все плитки — заглушки «Скоро».
class ComputerScreen extends StatelessWidget {
  const ComputerScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Компьютер', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          SizedBox(height: 16),
          TileGrid(children: [
            PultTile(
              icon: Icons.storage_outlined,
              color: Color(0xFF0F9D9A),
              title: 'Здоровье диска',
              caption: 'Состояние, температура, износ',
              kind: TileKind.soon,
            ),
            PultTile(
              icon: Icons.speed_outlined,
              color: Color(0xFF3D5A80),
              title: 'Что тормозит',
              caption: 'Нагрузка на процессор и память',
              kind: TileKind.soon,
            ),
            PultTile(
              icon: Icons.battery_std_outlined,
              color: Color(0xFF2E7D32),
              title: 'Батарея',
              caption: 'Износ и ёмкость',
              kind: TileKind.soon,
            ),
          ]),
        ],
      ),
    );
  }
}
