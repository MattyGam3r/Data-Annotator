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
  Timer? _timer;
  bool _isTraining = false;
  bool _isModelAvailable = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
    // Update status every 2 seconds
    _timer = Timer.periodic(Duration(seconds: 2), (_) => _updateTrainingStatus());
  }

  Future<void> _checkInitialStatus() async {
    final isTraining = await _yoloService.isModelTraining();
    final isAvailable = await _yoloService.isModelAvailable();
    
    if (mounted) {
      setState(() {
        _isTraining = isTraining;
        _isModelAvailable = isAvailable;
      });
    }
    
    if (_isTraining) {
      _updateTrainingStatus();
    }
  }

  Future<void> _updateTrainingStatus() async {
    final status = await _yoloService.getTrainingStatus();
    
    if (mounted) {
      setState(() {
        _isTraining = status['training_in_progress'] ?? false;
        _progress = status['progress']?.toDouble() ?? 0.0;
        _isModelAvailable = status['model_available'] ?? false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Model Status',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _isModelAvailable ? Icons.check_circle : Icons.error_outline,
                color: _isModelAvailable ? Colors.green : Colors.orange,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                _isModelAvailable 
                    ? 'AI model available' 
                    : 'No model available yet',
              ),
            ],
          ),
          SizedBox(height: 8),
          if (_isTraining) ...[
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _progress > 0 ? _progress : null,
                  ),
                ),
                SizedBox(width: 8),
                Text('Training in progress'),
              ],
            ),
            SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
            SizedBox(height: 4),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}