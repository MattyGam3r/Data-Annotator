import 'dart:ui';
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

    List<AnnotatedImage> images = List.empty(growable: true);

    if (response == null) return null;

    for (var i in response.data) {
      AnnotatedImage image = AnnotatedImage(
        i['filename'],
        isFullyAnnotated: i['isFullyAnnotated'] ?? false,
      );

      // Map the database data to our app's format
      if (i.containsKey('upload_time')) {
        var date = DateTime.parse(i['upload_time']);
        image.uploadedDate = date;
      }

      // Load annotations if they exist
      if (i.containsKey('annotations') && i['annotations'] != null) {
        try {
          List<dynamic> annotations = jsonDecode(i['annotations']);
          image.boundingBoxes = annotations
              .map((box) => BoundingBox.fromJson(box))
              .toList();
        } catch (e) {
          print('Error parsing annotations: $e');
        }
      }

      // Add the image to the list
      images.add(image);
    }

    return images;
  } on DioException catch (e) {
    print('Dio Error: ${e.message}');
    return null;
  }
}

Future<bool> saveAnnotations(String filename, List<BoundingBox> boxes, {bool isFullyAnnotated = false}) async {
  var dio = Dio();
  
  // Extract just the filename from the URL
  String extractedFilename = filename.split('/').last;
  
  try {
    var response = await dio.post(
      'http://localhost:5001/save_annotations',
      data: {
        'filename': extractedFilename,
        'annotations': jsonEncode(boxes.map((box) => box.toJson()).toList()),
        'isFullyAnnotated': isFullyAnnotated,
      },
    );
    
    return response.statusCode == 200;
  } on DioException catch (e) {
    print('Dio Error: ${e.message}');
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

Future<bool> startModelTraining(List<AnnotatedImage> images) async {
  var dio = Dio();
  try {
    var response = await dio.post(
      'http://localhost:5001/train_model',
      data: {
        'images': images.map((img) => img.toJson()).toList(),
      },
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