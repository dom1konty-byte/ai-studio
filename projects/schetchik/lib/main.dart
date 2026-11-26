import 'package:material_ui/material_ui.dart';

import 'counter_store.dart';

void main() => runApp(const App());

const _seed = Color(0xFF3F51B5);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Счётчик',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _counter = CounterController(CounterStore());

  @override
  void initState() {
    super.initState();
    _counter.load();
  }

  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: _counter,
            builder: (context, _) {
              final loaded = _counter.loaded;
              final value = _counter.value;
              final canDown = loaded && value > 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: loaded
                          ? Semantics(
                              liveRegion: true,
                              label: 'Счёт: $value',
                              child: ExcludeSemantics(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$value',
                                    key: const Key('value'),
                                    style: theme.textTheme.displayLarge
                                        ?.copyWith(
                                      fontSize: 96,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const CircularProgressIndicator(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: Tooltip(
                            message: 'Убавить один',
                            child: FilledButton.tonal(
                              key: const Key('minus'),
                              onPressed: canDown ? _counter.decrement : null,
                              child: Text(
                                '−1',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: Tooltip(
                            message: 'Сбросить счёт',
                            child: OutlinedButton(
                              key: const Key('reset'),
                              onPressed: canDown ? _counter.reset : null,
                              child: Text(
                                'Сброс',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 96,
                    child: Tooltip(
                      message: 'Прибавить один',
                      child: FilledButton(
                        key: const Key('plus'),
                        onPressed: loaded ? _counter.increment : null,
                        child: Text(
                          '+1',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
