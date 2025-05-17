import 'dart:async';
import 'package:flutter/material.dart';
import '../yolo_service.dart';

class TrainingStatusWidget extends StatefulWidget {
  const TrainingStatusWidget({super.key});

  @override
  State<TrainingStatusWidget> createState() => _TrainingStatusWidgetState();
}

class _TrainingStatusWidgetState extends State<TrainingStatusWidget> {
  final YoloService _yoloService = YoloService();
  bool _isTraining = false;
  double _progress = 0.0;
  bool _modelAvailable = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
    // Start a periodic timer to update status
    _statusTimer = Timer.periodic(Duration(seconds: 3), (_) => _updateStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialStatus() async {
    _modelAvailable = await _yoloService.isModelAvailable();
    _isTraining = await _yoloService.isModelTraining();
    
    if (_isTraining || _modelAvailable) {
      final status = await _yoloService.getTrainingStatus();
      setState(() {
        _isTraining = status['training_in_progress'] ?? false;
        _progress = (status['progress'] ?? 0.0).toDouble();
        _modelAvailable = status['model_available'] ?? false;
      });
    }
  }

  Future<void> _updateStatus() async {
    if (mounted) {
      final status = await _yoloService.getTrainingStatus();
      setState(() {
        _isTraining = status['training_in_progress'] ?? false;
        _progress = (status['progress'] ?? 0.0).toDouble();
        _modelAvailable = status['model_available'] ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Model Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_isTraining) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('Training in progress: ${(_progress * 100).toStringAsFixed(1)}%'),
            ] else if (_modelAvailable) ...[
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(height: 8),
              Text('Model is ready for predictions'),
            ] else ...[
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(height: 8),
              Text('No trained model available'),
            ],
          ],
        ),
      ),
    );
  }
}