import 'dart:async';

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
      title: 'Background Tracking',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const TrackingHomePage(),
    );
  }
}

class TrackingHomePage extends StatefulWidget {
  const TrackingHomePage({super.key});

  @override
  State<TrackingHomePage> createState() => _TrackingHomePageState();
}

class _TrackingHomePageState extends State<TrackingHomePage> {
  bool _isActive = false;
  List<BufferedPosition> _positions = const [];
  String? _lastError;
  StreamSubscription<int>? _bufferSubscription;

  @override
  void initState() {
    super.initState();
    _bufferSubscription = GeolocatorApple().getBufferUpdateStream().listen(
      (_) => _refresh(),
    );
    _refresh();
  }

  @override
  void dispose() {
    _bufferSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final isActive = await GeolocatorApple().isBackgroundTrackingActive();
    final positions = await GeolocatorApple().drainBufferedPositions();
    if (!mounted) return;
    setState(() {
      _isActive = isActive;
      _positions = positions;
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _lastError = null);
    try {
      final permission = await GeolocatorApple().requestPermission();
      setState(() => _lastError = 'Permissão atual: $permission');
    } catch (e) {
      setState(() => _lastError = '$e');
    }
  }

  Future<void> _requestAlwaysPermission() async {
    setState(() => _lastError = null);
    try {
      final permission = await GeolocatorApple().requestAlwaysPermission();
      setState(() => _lastError = 'Permissão atual: $permission');
    } catch (e) {
      setState(() => _lastError = '$e');
    }
  }

  Future<void> _openAppSettings() async {
    await GeolocatorApple().openAppSettings();
  }

  Future<void> _startTracking() async {
    setState(() => _lastError = null);
    try {
      await GeolocatorApple().startBackgroundTracking(
        settings: const AppleBackgroundSettings(
          mode: BackgroundTrackingMode.hybrid,
          minimumDistanceMeters: 10,
        ),
      );
    } catch (e) {
      setState(() => _lastError = '$e');
    }
    await _refresh();
  }

  Future<void> _stopTracking() async {
    await GeolocatorApple().stopBackgroundTracking();
    await _refresh();
  }

  Future<void> _acknowledgeAll() async {
    final ids = _positions.map((position) => position.id).toList();
    if (ids.isEmpty) return;
    await GeolocatorApple().acknowledgePositions(ids);
    await _refresh();
  }

  Future<void> _clearBuffer() async {
    await GeolocatorApple().clearBufferedPositions();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Background Tracking')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isActive ? 'Tracking ativo ✅' : 'Tracking inativo',
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
                      onPressed: _requestPermission,
                      child: const Text('Pedir permissão (When In Use)'),
                    ),
                    ElevatedButton(
                      onPressed: _requestAlwaysPermission,
                      child: const Text('Pedir permissão (Always)'),
                    ),
                    ElevatedButton(
                      onPressed: _openAppSettings,
                      child: const Text('Ajustes (Always)'),
                    ),
                    ElevatedButton(
                      onPressed: _startTracking,
                      child: const Text('Iniciar tracking'),
                    ),
                    ElevatedButton(
                      onPressed: _stopTracking,
                      child: const Text('Parar'),
                    ),
                    ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Atualizar'),
                    ),
                    ElevatedButton(
                      onPressed: _acknowledgeAll,
                      child: const Text('Confirmar tudo (ack)'),
                    ),
                    ElevatedButton(
                      onPressed: _clearBuffer,
                      child: const Text('Limpar buffer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _positions.isEmpty
                ? const Center(child: Text('Buffer vazio'))
                : ListView.builder(
                    itemCount: _positions.length,
                    itemBuilder: (context, index) {
                      final buffered = _positions[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '#${buffered.id} · ${buffered.source.name}',
                        ),
                        subtitle: Text(
                          '${buffered.recordedAt.toIso8601String()} · '
                          '${buffered.position.latitude}, '
                          '${buffered.position.longitude}',
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
