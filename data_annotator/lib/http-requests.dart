import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'structs.dart';

Future<void> uploadImages(List<PlatformFile> files) async {
  var dio = Dio();
  var formData = FormData();

  for (var file in files) {
    formData.files.add(
      MapEntry(
        'image',
        MultipartFile.fromBytes(file.bytes!, filename: file.name),
      ),
    );
  }

  try {
    var response = await dio.post(
      'http://localhost:5001/upload',
      data: formData,
      onSendProgress: (sent, total) {
        print('Progress: ${(sent/total * 100).toStringAsFixed(0)}%');
      },
    );
    print(response.data);
  } on DioException catch (e) {
      print('Dio Error: ${e.message}');
  }
}

Future<List<AnnotatedImage>?> fetchLatestImages() async {
  var dio = Dio();
  try {
    var response = await dio.get(
      'http://localhost:5001/images',
      options: Options(responseType: ResponseType.json),
    );

    print('Debug - Received response from /images: ${response.data}');  // Debug log

    List<AnnotatedImage> images = List.empty(growable: true);

    if (response == null) return null;

    for (var i in response.data) {
      print('Debug - Processing image: ${i['filename']}');  // Debug log
      print('Debug - Raw annotations data: ${i['annotations']}');  // Debug log
      print('Debug - Raw YOLO predictions: ${i['yolo_predictions']}');  // Debug log
      print('Debug - Raw ONE-SHOT predictions: ${i['one_shot_predictions']}');  // Debug log
      print('Debug - Is fully annotated: ${i['isFullyAnnotated']}');  // Debug log
      print('Debug - Uncertainty score: ${i['uncertainty_score']}');  // Debug log

      AnnotatedImage image = AnnotatedImage(
        i['filename'],
        isFullyAnnotated: i['isFullyAnnotated'] ?? false,
        uncertaintyScore: i['uncertainty_score']?.toDouble(),
      );

      // Map the database data to our app's format
      if (i.containsKey('upload_time')) {
        var date = DateTime.parse(i['upload_time']);
        image = image.copyWith(uploadedDate: date);
      }

      // Load annotations if they exist
      if (i.containsKey('annotations') && i['annotations'] != null) {
        try {
          List<dynamic> annotations = i['annotations'];  // Already a List, no need to parse
          print('Debug - Processing annotations for ${i['filename']}:');  // Debug log
          print('Debug - Number of annotations: ${annotations.length}');  // Debug log
          
          List<BoundingBox> boxes = annotations.map((box) {
            print('Debug - Converting box: $box');  // Debug log
            return BoundingBox.fromJson(box);
          }).toList();
          
          print('Debug - Successfully converted ${boxes.length} boxes');  // Debug log
          print('Debug - First box details: ${boxes.isNotEmpty ? boxes.first.toJson() : "No boxes"}');  // Debug log
          
          image = image.copyWith(boundingBoxes: boxes);
        } catch (e) {
          print('Error processing annotations for ${i['filename']}: $e');
          print('Error details: ${e.toString()}');
        }
      }

      // Load YOLO predictions if they exist
      if (i.containsKey('yolo_predictions') && i['yolo_predictions'] != null) {
        try {
          List<dynamic> predictions = i['yolo_predictions'];
          print('Debug - Processing YOLO predictions for ${i['filename']}:');
          print('Debug - Number of YOLO predictions: ${predictions.length}');
          
          List<BoundingBox> boxes = predictions.map((box) {
            print('Debug - Converting YOLO box: $box');
            return BoundingBox.fromJson(box);
          }).toList();
          
          image = image.copyWith(yoloPredictions: boxes);
        } catch (e) {
          print('Error processing YOLO predictions for ${i['filename']}: $e');
        }
      }

      // Load ONE-SHOT predictions if they exist
      if (i.containsKey('one_shot_predictions') && i['one_shot_predictions'] != null) {
        try {
          List<dynamic> predictions = i['one_shot_predictions'];
          print('Debug - Processing ONE-SHOT predictions for ${i['filename']}:');
          print('Debug - Number of ONE-SHOT predictions: ${predictions.length}');
          
          List<BoundingBox> boxes = predictions.map((box) {
            print('Debug - Converting ONE-SHOT box: $box');
            return BoundingBox.fromJson(box);
          }).toList();
          
          image = image.copyWith(oneShotPredictions: boxes);
        } catch (e) {
          print('Error processing ONE-SHOT predictions for ${i['filename']}: $e');
        }
      }

      // Add the image to the list
      images.add(image);
    }

    print('Debug - Total images processed: ${images.length}');  // Debug log
    return images;
  } on DioException catch (e) {
    print('Error fetching images: ${e.message}');
    return null;
  }
}

Future<bool> saveAnnotations(String imageUrl, List<BoundingBox> boxes, {bool isFullyAnnotated = false}) async {
  var dio = Dio();
  
  try {
    final filename = imageUrl.split('/').last;
    print('Debug - Saving annotations for $filename');  // Debug log
    print('Debug - Number of boxes: ${boxes.length}');  // Debug log
    print('Debug - Is fully annotated: $isFullyAnnotated');  // Debug log
    
    // Convert boxes to JSON-compatible format
    final annotations = boxes.map((box) {
      final json = box.toJson();
      print('Debug - Box JSON: $json');  // Debug log
      return json;
    }).toList();
    
    print('Debug - Final annotations: $annotations');  // Debug log
    
    final response = await dio.post(
      'http://localhost:5001/save_annotations',
      data: {
        'filename': filename,
        'annotations': annotations,
        'isFullyAnnotated': isFullyAnnotated
      },
    );
    
    print('Debug - Save response: ${response.data}');  // Debug log
    return response.statusCode == 200;
  } catch (e) {
    print('Error saving annotations: $e');
    print('Error details: ${e.toString()}');  // Debug log
    return false;
  }
}

Future<Map<String, dynamic>> getModelStatus() async {
  var dio = Dio();
  try {
    var response = await dio.get('http://localhost:5001/model_status');
    return response.data;
  } on DioException catch (e) {
    print('Error getting model status: ${e.message}');
    return {
      'training_in_progress': false,
      'progress': 0.0,
      'model_available': false
    };
  }
}

Future<bool> startModelTraining() async {
  var dio = Dio();
  try {
    var response = await dio.post(
      'http://localhost:5001/train_model',
      data: {},  // No need to send images anymore
    );
    return response.statusCode == 200;
  } on DioException catch (e) {
    print('Error starting model training: ${e.message}');
    return false;
  }
}

Future<List<BoundingBox>?> getPredictions(String filename) async {
  var dio = Dio();
  
  // Extract just the filename from the URL
  String extractedFilename = filename.split('/').last;
  
  try {
    var response = await dio.post(
      'http://localhost:5001/predict',
      data: {
        'filename': extractedFilename,
      },
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
          isVerified: false,
        );
      }).toList();
    }
    return null;
  } on DioException catch (e) {
    print('Error getting predictions: ${e.message}');
    return null;
  }
}

Future<bool> markImageComplete(String filename) async {
  var dio = Dio();
  
  // Extract just the filename from the URL
  String extractedFilename = filename.split('/').last;
  
  try {
    var response = await dio.post(
      'http://localhost:5001/mark_complete',
      data: {
        'filename': extractedFilename,
      },
    );
    
    return response.statusCode == 200;
  } on DioException catch (e) {
    print('Error marking image as complete: ${e.message}');
    return false;
  }
}