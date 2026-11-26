import 'package:flame/game.dart';
import 'package:material_ui/material_ui.dart';

import 'game/my_game.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Проверка табло',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _game = MyGame();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: GameWidget(game: _game)),
    );
  }
}
