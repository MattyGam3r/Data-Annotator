import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Image Annotator",
      theme: appTheme,
      home: HomePage(),
    );
  }

  static ThemeData appTheme = ThemeData(
      //Default brightness and colours
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.cyanAccent,
        brightness: Brightness.light,
      ).copyWith(
        primary: Colors.amber,
      ),
      //Text themes
      textTheme: TextTheme(
        displayLarge: const TextStyle(
          fontSize: 72,
          fontWeight: FontWeight.bold,
        ),

        titleLarge: GoogleFonts.roboto(
          fontSize: 30,
          fontStyle: FontStyle.italic,
        ),
        bodyMedium: GoogleFonts.roboto(),
        displaySmall: GoogleFonts.pacifico(),
      )
    );
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      
        title: Text("Data Annotator"),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Row(
        children: [
          ImageViewer(),
          ImageLabellerArea()
        ],
      ),
    );
  }
}

class ImageViewer extends StatelessWidget {
  const ImageViewer({
    super.key,
  });



  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Text("Select an Image to Label Here"),
          SizedBox(width: 20),
          FileUploadButton(),
        ],),
        ClickableImage(),
        
        Placeholder(),
      ],
    );
  }
}

class ImageLabellerArea extends StatelessWidget {
  const ImageLabellerArea({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Column(
        children: [
          Center(child: Text("Hello 2!")),
          SizedBox(height: 10),
          Image.asset("/home/matthew/Github/Data-Annotator/data_annotator/assets/DogSample1.png"),
        ],
        ),
    );
  }
}

class ClickableImage extends StatelessWidget {
  const ClickableImage({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var image = NetworkImage("https://picsum.photos/350/200");
    return InkWell(
      onTap: () {      
        print("clicked!");
      },
      child: Ink.image(
        fit: BoxFit.cover,
        width: 100,
        height: 100,
        image: image,
      )
    );
  }
}

class FileUploadButton extends StatefulWidget {
  const FileUploadButton({super.key});  


  @override
  State<FileUploadButton> createState() => _FileUploadButtonState();
}

class _FileUploadButtonState extends State<FileUploadButton> {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      child: Text('Upload Image(s)'),
      onPressed: () async {
        FilePickerResult? picked = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );

        if (picked != null) {
          uploadImages(picked.files);
        }
        else {
          //The user canceled the file picker
        }
      },
    );
  }
}

Future<void> uploadImages(List<PlatformFile> files) async {
  var dio = Dio();
  var formData = FormData();

  for (var file in files) {
    formData.files.add(
      MapEntry(
        'image',
        await MultipartFile.fromBytes(file.bytes!, filename: file.name),
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
  //
  //
  //
  //var request = http.MultipartRequest('POST', Uri.parse('localhost:5001/upload'));


}