import 'dart:convert';
import 'package:dio/dio.dart';
import 'structs.dart';
import 'http-requests.dart';

enum ModelType {
  yolo,
  fewShot,
}

class YoloService {
  final Dio _dio = Dio();
  final String baseUrl = 'http://localhost:5001';
  static bool _isModelTraining = false;
  static bool _isModelAvailable = false;
  static double _trainingProgress = 0.0;
  static ModelType _currentModelType = ModelType.yolo;
  static int _autoTrainingThreshold = 0; // Default to disabled (0)

  ModelType get currentModelType => _currentModelType;
  set currentModelType(ModelType type) {
    _currentModelType = type;
  }

  int get autoTrainingThreshold => _autoTrainingThreshold;
  set autoTrainingThreshold(int value) {
    _autoTrainingThreshold = value;
    // Save the threshold to backend
    saveAutoTrainingThreshold(value);
  }

  // Initialize service by fetching the current threshold setting
  Future<void> initialize() async {
    try {
      final response = await _dio.get('$baseUrl/auto_training_settings');
      if (response.statusCode == 200) {
        _autoTrainingThreshold = response.data['threshold'] ?? 0;
      }
    } catch (e) {
      print('Error initializing YoloService: $e');
    }
  }

  // Save the auto-training threshold to the backend
  Future<bool> saveAutoTrainingThreshold(int threshold) async {
    try {
      final response = await _dio.post(
        '$baseUrl/auto_training_settings',
        data: {
          'threshold': threshold,
        },
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error saving auto-training threshold: $e');
      return false;
    }
  }

  Future<bool> isModelAvailable() async {
    try {
      final response = await _dio.get(
        '$baseUrl/model_status',
        queryParameters: {'model_type': _currentModelType == ModelType.yolo ? 'yolo' : 'few_shot'},
      );
      _isModelAvailable = _currentModelType == ModelType.yolo 
          ? response.data['yolo']['is_available'] ?? false
          : response.data['few_shot']['is_available'] ?? false;
      return _isModelAvailable;
    } on DioException catch (e) {
      print('Error checking model status: ${e.message}');
      return false;
    }
  }

  Future<bool> isModelTraining() async {
    try {
      final response = await _dio.get(
        '$baseUrl/model_status',
        queryParameters: {'model_type': _currentModelType == ModelType.yolo ? 'yolo' : 'few_shot'},
      );
      _isModelTraining = response.data['training_in_progress'] ?? false;
      _trainingProgress = (response.data['progress'] ?? 0.0).toDouble();
      return _isModelTraining;
    } on DioException catch (e) {
      print('Error checking training status: ${e.message}');
      return false;
    }
  }

  // Train model with verified annotations
  Future<bool> trainModel() async {
    try {
      print('Debug - Starting model training');
      final success = await startModelTraining();
      print('Debug - Training request result: $success');
      return success;
    } catch (e) {
      print('Error in trainModel: $e');
      return false;
    }
  }

  // Get predictions for an image
  Future<List<BoundingBox>?> predictAnnotations(String imageFilename) async {
    // First check if model is available and not training
    final status = await getTrainingStatus();
    final modelData = _currentModelType == ModelType.yolo ? status['yolo'] : status['few_shot'];
    
    if (modelData['training_in_progress']) {
      print('Model is currently training. Cannot predict until training is complete.');
      return null;
    }
    
    if (!modelData['is_available']) {
      print('Model not available. Train a model first.');
      return null;
    }

    try {
      // Extract just the filename from the URL
      String extractedFilename = imageFilename.split('/').last;
      
      print('Getting predictions for $extractedFilename using ${_currentModelType == ModelType.yolo ? "YOLO" : "Few-Shot"} model');
      
      final response = await _dio.post(
        '$baseUrl/predict',
        data: {
          'filename': extractedFilename,
          'model_type': _currentModelType == ModelType.yolo ? 'yolo' : 'few_shot',
        },
      );
      
      if (response.statusCode == 200 && response.data['predictions'] != null) {
        List<dynamic> predictions = response.data['predictions'];
        print('Received ${predictions.length} predictions');
        
        return predictions.map((pred) {
          // Check if this is a few-shot prediction (label-only format without bounding box coordinates)
          if (_currentModelType == ModelType.fewShot && 
              !pred.containsKey('x') && 
              !pred.containsKey('width')) {
            // Create a dummy bounding box for display, centered in the image
            // with a tag indicating it's a label-only prediction
            return BoundingBox(
              x: 0.1, // Small box in the top-left
              y: 0.1,
              width: 0.2,
              height: 0.1,
              label: "Few-Shot Label: ${pred['label']}",
              source: AnnotationSource.ai,
              confidence: pred['confidence'].toDouble(),
              isVerified: false,
            );
          } else {
            // Normal YOLO-style prediction with coordinates
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
          }
        }).toList();
      } else if (response.statusCode == 400) {
        // Handle specific error messages
        final errorMessage = response.data['error'] as String?;
        if (errorMessage?.contains('still training') == true) {
          print('Model is still training: $errorMessage');
        } else if (errorMessage?.contains('not available') == true) {
          print('Model not available: $errorMessage');
        } else {
          print('Prediction error: ${response.data}');
        }
      }
      return null;
    } on DioException catch (e) {
      print('Error getting predictions: ${e.message}');
      if (e.response != null) {
        print('Response data: ${e.response?.data}');
        print('Response status: ${e.response?.statusCode}');
      }
      return null;
    }
  }

  // Check training status
  Future<Map<String, dynamic>> getTrainingStatus() async {
    try {
      final response = await _dio.get(
        '$baseUrl/model_status',
        queryParameters: {'model_type': _currentModelType == ModelType.yolo ? 'yolo' : 'few_shot'},
      );
      
      // Update our cached values
      final modelData = _currentModelType == ModelType.yolo ? response.data['yolo'] : response.data['few_shot'];
      _isModelTraining = modelData['training_in_progress'] ?? false;
      _trainingProgress = (modelData['progress'] ?? 0.0).toDouble();
      _isModelAvailable = modelData['is_available'] ?? false;
      
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

  // Get augmented versions of an image
  Future<List<Map<String, dynamic>>?> getAugmentedImages(String imageFilename) async {
    try {
      // Extract just the filename from the URL
      String extractedFilename = imageFilename.split('/').last;
      
      final response = await _dio.get(
        '$baseUrl/get_augmented_images/$extractedFilename',
      );
      
      if (response.statusCode == 200 && response.data['images'] != null) {
        List<dynamic> images = response.data['images'];
        return images.map((img) => {
          'url': img['url'],
          'is_original': img['is_original'],
          'annotations': img['annotations']  // Include annotations in the response
        }).toList();
      }
      return null;
    } on DioException catch (e) {
      print('Error getting augmented images: ${e.message}');
      return null;
    }
  }

  // Augment all images
  Future<Map<String, dynamic>?> augmentImages(int numAugmentations) async {
    try {
      print('Sending augmentation request to ${baseUrl}/augment_images');
      print('Number of augmentations: $numAugmentations');
      
      final response = await _dio.post(
        '$baseUrl/augment_images',
        data: {
          'num_augmentations': numAugmentations,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (status) => status! < 500,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );
      
      print('Response status code: ${response.statusCode}');
      print('Response data: ${response.data}');
      
      if (response.statusCode == 200) {
        return response.data;
      } else {
        print('Error augmenting images: ${response.statusCode} - ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      print('Error augmenting images: ${e.message}');
      if (e.response != null) {
        print('Response data: ${e.response?.data}');
        print('Response status: ${e.response?.statusCode}');
        print('Response headers: ${e.response?.headers}');
      }
      if (e.type == DioExceptionType.connectionTimeout) {
        print('Connection timeout');
      } else if (e.type == DioExceptionType.receiveTimeout) {
        print('Receive timeout');
      } else if (e.type == DioExceptionType.sendTimeout) {
        print('Send timeout');
      }
      return null;
    }
  }

  // Get predictions from both models with uncertainty score
  Future<Map<String, dynamic>?> getPredictionsWithUncertainty(String imageFilename) async {
    try {
      // Extract just the filename from the URL
      String extractedFilename = imageFilename.split('/').last;
      
      final response = await _dio.post(
        '$baseUrl/get_predictions_with_uncertainty',
        data: {
          'filename': extractedFilename,
        },
      );
      
      if (response.statusCode == 200) {
        // Process few-shot predictions to handle label-only format
        if (response.data.containsKey('few_shot_predictions')) {
          List<dynamic> fewShotPreds = response.data['few_shot_predictions'];
          if (fewShotPreds.isNotEmpty && fewShotPreds[0] is Map) {
            // Check if these are label-only predictions
            if (!fewShotPreds[0].containsKey('x') && !fewShotPreds[0].containsKey('width')) {
              // Convert to display format with dummy bounding boxes
              List<Map<String, dynamic>> displayPreds = fewShotPreds.map((pred) => {
                'x': 0.1,
                'y': 0.1,
                'width': 0.2,
                'height': 0.1,
                'label': "Few-Shot Label: ${pred['label']}",
                'confidence': pred['confidence'],
                'source': 'ai',
                'isVerified': false
              }).toList();
              
              // Replace the original with the display version
              response.data['few_shot_predictions'] = displayPreds;
            }
          }
        }
        return response.data;
      }
      return null;
    } on DioException catch (e) {
      print('Error getting predictions with uncertainty: ${e.message}');
      return null;
    }
  }

  // Reset the annotator (delete all images, annotations, and models)
  Future<bool> resetAnnotator() async {
    try {
      final response = await _dio.post(
        '$baseUrl/reset_annotator',
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        print('Annotator reset successfully');
        return true;
      } else {
        print('Failed to reset annotator: \\${response.data}');
        return false;
      }
    } on DioException catch (e) {
      print('Error resetting annotator: \\${e.message}');
      return false;
    }
  }

  // Update uncertainty scores for all images
  Future<bool> updateAllUncertaintyScores() async {
    try {
      final response = await _dio.post(
        '$baseUrl/update_all_uncertainty_scores',
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );
      
      if (response.statusCode == 200) {
        print('Updated uncertainty scores: ${response.data}');
        return true;
      } else {
        print('Failed to update uncertainty scores: ${response.data}');
        return false;
      }
    } on DioException catch (e) {
      print('Error updating uncertainty scores: ${e.message}');
      return false;
    }
  }

  // Batch prediction for multiple images at once
  Future<Map<String, List<BoundingBox>>?> predictBatchAnnotations(List<String> imageFilenames) async {
    // First check if model is available and not training
    final status = await getTrainingStatus();
    final modelData = _currentModelType == ModelType.yolo ? status['yolo'] : status['few_shot'];
    
    if (modelData['training_in_progress']) {
      print('Model is currently training. Cannot predict until training is complete.');
      return null;
    }
    
    if (!modelData['is_available']) {
      print('Model not available. Train a model first.');
      return null;
    }

    try {
      // Extract just the filenames from URLs
      List<String> extractedFilenames = imageFilenames.map((filename) => filename.split('/').last).toList();
      
      print('Getting batch predictions for ${extractedFilenames.length} images using ${_currentModelType == ModelType.yolo ? "YOLO" : "Few-Shot"} model');
      
      final response = await _dio.post(
        '$baseUrl/predict_batch',
        data: {
          'filenames': extractedFilenames,
          'model_type': _currentModelType == ModelType.yolo ? 'yolo' : 'few_shot',
        },
      );
      
      if (response.statusCode == 200 && response.data['predictions'] != null) {
        Map<String, dynamic> batchPredictions = response.data['predictions'];
        print('Received batch predictions for ${batchPredictions.length} images');
        print('Total predictions: ${response.data['total_predictions']}');
        
        // Convert to Map<String, List<BoundingBox>>
        Map<String, List<BoundingBox>> result = {};
        
        for (String filename in extractedFilenames) {
          List<dynamic> predictions = batchPredictions[filename] ?? [];
          
          List<BoundingBox> boundingBoxes = predictions.map((pred) {
            // Check if this is a few-shot prediction (label-only format without bounding box coordinates)
            if (_currentModelType == ModelType.fewShot && 
                !pred.containsKey('x') && 
                !pred.containsKey('width')) {
              // Create a dummy bounding box for display, centered in the image
              return BoundingBox(
                x: 0.1, // Small box in the top-left
                y: 0.1,
                width: 0.2,
                height: 0.1,
                label: "Few-Shot Label: ${pred['label']}",
                source: AnnotationSource.ai,
                confidence: pred['confidence'].toDouble(),
                isVerified: false,
              );
            } else {
              // Normal YOLO-style prediction with coordinates
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
            }
          }).toList();
          
          result[filename] = boundingBoxes;
        }
        
        return result;
      } else {
        // Handle specific error messages
        final errorMessage = response.data['error'] as String?;
        if (errorMessage?.contains('still training') == true) {
          print('Model is still training: $errorMessage');
        } else if (errorMessage?.contains('not available') == true) {
          print('Model not available: $errorMessage');
        } else {
          print('Batch prediction error: ${response.data}');
        }
      }
      return null;
    } on DioException catch (e) {
      print('Error getting batch predictions: ${e.message}');
      if (e.response != null) {
        print('Response data: ${e.response?.data}');
        print('Response status: ${e.response?.statusCode}');
      }
      return null;
    }
  }
}