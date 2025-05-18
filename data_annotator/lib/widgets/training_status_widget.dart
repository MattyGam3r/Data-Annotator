import 'dart:async';
import 'package:flutter/material.dart';
import '../yolo_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class TrainingStatusWidget extends StatefulWidget {
  const TrainingStatusWidget({super.key});

  @override
  State<TrainingStatusWidget> createState() => _TrainingStatusWidgetState();
}

class _TrainingStatusWidgetState extends State<TrainingStatusWidget> {
  final YoloService _yoloService = YoloService();
  bool _isYoloAvailable = false;
  bool _isFewShotAvailable = false;
  bool _isYoloTraining = false;
  bool _isFewShotTraining = false;
  double _yoloProgress = 0.0;
  double _fewShotProgress = 0.0;
  bool _isAugmenting = false;
  double _augmentationProgress = 0.0;
  int _numAugmentations = 1;
  final TextEditingController _augmentationController = TextEditingController();
  bool _hasAugmentations = false;
  int _totalAugmentations = 0;
  Timer? _statusTimer;
  Timer? _progressTimer;
  String _selectedModel = 'yolo'; // Default to YOLO
  
  @override
  void initState() {
    super.initState();
    _augmentationController.text = '1';
    _checkModelStatus();
    // Start a periodic timer to update status
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkModelStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _progressTimer?.cancel();
    _augmentationController.dispose();
    super.dispose();
  }

  Future<void> _checkModelStatus() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:5001/model_status'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isYoloAvailable = data['yolo']['is_available'] ?? false;
          _isFewShotAvailable = data['few_shot']['is_available'] ?? false;
          _isYoloTraining = data['yolo']['training_in_progress'] ?? false;
          _isFewShotTraining = data['few_shot']['training_in_progress'] ?? false;
          _yoloProgress = (data['yolo']['progress'] ?? 0.0).toDouble();
          _fewShotProgress = (data['few_shot']['progress'] ?? 0.0).toDouble();
          _hasAugmentations = data['has_augmentations'] ?? false;
          _totalAugmentations = data['num_augmentations'] ?? 0;
        });
      }
    } catch (e) {
      print('Error checking model status: $e');
    }
  }

  Future<void> _trainModel() async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:5001/train_model'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'model_type': _selectedModel}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Model training started'),
            backgroundColor: Colors.green,
          ),
        );
        _checkModelStatus(); // Refresh status immediately
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start model training'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _augmentImages() async {
    if (_isAugmenting) return;

    setState(() {
      _isAugmenting = true;
      _augmentationProgress = 0.0;
    });

    // Start progress animation
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _augmentationProgress = (_augmentationProgress + 0.01).clamp(0.0, 0.99);
        });
      }
    });

    try {
      final result = await _yoloService.augmentImages(_numAugmentations);
      
      _progressTimer?.cancel();
      
      if (result != null) {
        setState(() {
          _augmentationProgress = 1.0;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully created ${result['successful_augmentations']} augmentations'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Wait a bit before refreshing status to ensure files are written
        await Future.delayed(const Duration(seconds: 1));
        _checkModelStatus();
      } else {
        setState(() {
          _augmentationProgress = 0.0;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to augment images'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _augmentationProgress = 0.0;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isAugmenting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Model Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  _isYoloAvailable ? Icons.check_circle : Icons.cancel,
                  color: _isYoloAvailable ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                const Text('YOLO'),
                if (_isYoloTraining) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _yoloProgress,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isFewShotAvailable ? Icons.check_circle : Icons.cancel,
                  color: _isFewShotAvailable ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                const Text('Few-shot'),
                if (_isFewShotTraining) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _fewShotProgress,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _hasAugmentations ? Icons.check_circle : Icons.cancel,
                  color: _hasAugmentations ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text('Augmentations (${_totalAugmentations})'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedModel,
                    decoration: const InputDecoration(
                      labelText: 'Select Model',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'yolo',
                        child: Text('YOLO'),
                      ),
                      DropdownMenuItem(
                        value: 'few_shot',
                        child: Text('Few-shot'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedModel = value;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (_isYoloTraining || _isFewShotTraining) ? null : _trainModel,
                  child: Text(_isYoloTraining || _isFewShotTraining ? 'Training...' : 'Train Model'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _augmentationController,
                    decoration: const InputDecoration(
                      labelText: 'Number of augmentations',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _numAugmentations = int.tryParse(value) ?? 1;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isAugmenting ? null : _augmentImages,
                  child: Text(_isAugmenting ? 'Augmenting...' : 'Augment Images'),
                ),
              ],
            ),
            if (_isAugmenting) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _augmentationProgress,
              ),
            ],
          ],
        ),
      ),
    );
  }
}