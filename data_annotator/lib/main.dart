import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

class FileUploadButton extends StatelessWidget {
  const FileUploadButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      child: Text('Upload Image(s)'),
      onPressed: () async {
        var picked = await FilePicker.platform.pickFiles(
          allowMultiple: true,
        );

        if (picked != null) {
          print(picked.files.first.name);
        }
        print(picked);
      },
    );
  }
}