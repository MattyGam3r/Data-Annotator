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
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "AI Model Status",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _modelAvailable ? Icons.check_circle : Icons.info_outline,
                color: _modelAvailable ? Colors.green : Colors.orange,
              ),
              SizedBox(width: 8),
              Text(
                _modelAvailable 
                    ? "Model is available for predictions" 
                    : "No trained model available yet",
              ),
            ],
          ),
          if (_isTraining) ...[
            SizedBox(height: 12),
            Text("Training in progress:"),
            SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            SizedBox(height: 4),
            Text("${(_progress * 100).toStringAsFixed(1)}%"),
          ],
        ],
      ),
    );
  }
}