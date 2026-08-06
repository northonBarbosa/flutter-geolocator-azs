import 'package:flutter/material.dart';
import 'package:geolocator_apple/geolocator_apple.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spike Background Tracking',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SpikeHomePage(),
    );
  }
}

class SpikeHomePage extends StatefulWidget {
  const SpikeHomePage({super.key});

  @override
  State<SpikeHomePage> createState() => _SpikeHomePageState();
}

class _SpikeHomePageState extends State<SpikeHomePage> {
  bool _wasLaunchedByLocation = false;
  List<Map<String, dynamic>> _events = const [];
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final wasLaunchedByLocation =
        await GeolocatorApple.spikeWasLaunchedByLocation();
    final events = await GeolocatorApple.spikeGetLoggedEvents();
    setState(() {
      _wasLaunchedByLocation = wasLaunchedByLocation;
      _events = events.reversed.toList();
    });
  }

  Future<void> _start() async {
    setState(() => _lastError = null);
    try {
      await GeolocatorApple.spikeStartBackgroundTracking();
    } catch (e) {
      setState(() => _lastError = '$e');
    }
    await _refresh();
  }

  Future<void> _stop() async {
    await GeolocatorApple.spikeStopBackgroundTracking();
    await _refresh();
  }

  Future<void> _clear() async {
    await GeolocatorApple.spikeClearLog();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spike: relaunch por SLC')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _wasLaunchedByLocation
                      ? 'Este processo foi relançado por evento de localização ✅'
                      : 'Este processo NÃO foi relançado por localização',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(_lastError!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _start,
                      child: const Text('Iniciar spike'),
                    ),
                    ElevatedButton(
                      onPressed: _stop,
                      child: const Text('Parar'),
                    ),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Atualizar log'),
                    ),
                    ElevatedButton(
                      onPressed: _clear,
                      child: const Text('Limpar log'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _events.isEmpty
                ? const Center(child: Text('Nenhum evento registrado ainda'))
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final recordedAtMs = event['recordedAtMs'] as int?;
                      final recordedAt = recordedAtMs != null
                          ? DateTime.fromMillisecondsSinceEpoch(recordedAtMs)
                          : null;
                      final lat = event['latitude'];
                      final lon = event['longitude'];
                      return ListTile(
                        dense: true,
                        title: Text('${event['source']}'),
                        subtitle: Text(
                          [
                            if (recordedAt != null)
                              recordedAt.toIso8601String(),
                            if (lat != null && lon != null) '$lat, $lon',
                            'appState: ${event['appState']}',
                          ].join(' · '),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
