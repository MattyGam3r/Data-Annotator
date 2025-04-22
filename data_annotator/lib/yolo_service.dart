import 'dart:convert';
import 'package:dio/dio.dart';
import 'structs.dart';

class YoloService {
  final Dio _dio = Dio();
  final String baseUrl = 'http://localhost:5001';
  static bool _isModelTraining = false;
  static bool _isModelAvailable = false;
  static double _trainingProgress = 0.0;

  Future<bool> isModelAvailable() async {
    try {
      final response = await _dio.get('$baseUrl/model_status');
      _isModelAvailable = response.data['model_available'] ?? false;
      return _isModelAvailable;
    } on DioException catch (e) {
      print('Error checking model status: ${e.message}');
      return false;
    }
  }

  Future<bool> isModelTraining() async {
    try {
      final response = await _dio.get('$baseUrl/model_status');
      _isModelTraining = response.data['training_in_progress'] ?? false;
      _trainingProgress = (response.data['progress'] ?? 0.0).toDouble();
      return _isModelTraining;
    } on DioException catch (e) {
      print('Error checking training status: ${e.message}');
      return false;
    }
  }

  // Train YOLO model with verified annotations
  Future<bool> trainModel(List<AnnotatedImage> annotatedImages) async {
    // Filter only images with verified annotations
    final trainingImages = annotatedImages.where((image) {
      // Only use images that have at least one verified annotation
      return image.boundingBoxes.any((box) => box.isVerified);
    }).toList();

    if (trainingImages.isEmpty) {
      print('No verified annotations available for training');
      return false;
    }

    try {
      // Start the training process
      final response = await _dio.post(
        '$baseUrl/train_model',
        data: {
          'images': trainingImages.map((img) => img.toJson()).toList(),
        },
      );
      
      _isModelTraining = true;
      _trainingProgress = 0.0;
      return response.statusCode == 200;
    } on DioException catch (e) {
      print('Error training model: ${e.message}');
      return false;
    }
  }

  // Get predictions for an image
  Future<List<BoundingBox>?> predictAnnotations(String imageFilename) async {
    if (!await isModelAvailable()) {
      print('No trained model available for prediction');
      return null;
    }

    try {
      // Extract just the filename from the URL
      String extractedFilename = imageFilename.split('/').last;
      
      final response = await _dio.post(
        '$baseUrl/predict',
        data: {'filename': extractedFilename},
      );
      
      if (response.statusCode == 200 && response.data['predictions'] != null) {
        List<dynamic> predictions = response.data['predictions'];
        return predictions.map((pred) {
          return BoundingBox(
            x: pred['x'].toDouble(),
            y: pred['y'].toDouble(),
            width: pred['width'].toDouble(),
            height: pred['height'].toDouble(),
            label: pred['label'],
            source: AnnotationSource.ai,
            confidence: pred['confidence'].toDouble(),
            isVerified: false, // AI predictions are not verified by default
          );
        }).toList();
      }
      return null;
    } on DioException catch (e) {
      print('Error getting predictions: ${e.message}');
      return null;
    }
  }

  // Check training status
  Future<Map<String, dynamic>> getTrainingStatus() async {
    try {
      final response = await _dio.get('$baseUrl/model_status');
      
      // Update our cached values
      _isModelTraining = response.data['training_in_progress'] ?? false;
      _trainingProgress = (response.data['progress'] ?? 0.0).toDouble();
      _isModelAvailable = response.data['model_available'] ?? false;
      
      return response.data;
    } on DioException catch (e) {
      print('Error checking training status: ${e.message}');
      return {
        'training_in_progress': _isModelTraining,
        'progress': _trainingProgress,
        'model_available': _isModelAvailable
      };
    }
  }
}