import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'structs.dart';



Future<void> uploadImages(List<PlatformFile> files) async {
  CallbackHandle finished;
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
      AnnotatedImage image = AnnotatedImage(i['filename']);

      // Map the database data to our app's format
      if (i.containsKey('uploaded_date')) {
        var date = DateTime.parse(i['uploaded_date']);
        image.uploadedDate = date;
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

