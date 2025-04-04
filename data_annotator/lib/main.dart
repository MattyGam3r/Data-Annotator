import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import "views/image_viewer.dart";
import "structs.dart";

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

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? selectedImageUrl;

  void onImageSelected(String imageUrl) {
    setState(() {
      selectedImageUrl = imageUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Data Annotator"),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Row(
        children: [
          ImageViewer(onImageSelected: onImageSelected),
          ImageLabellerArea(selectedImageUrl: selectedImageUrl),
        ],
      ),
    );
  }
}

class ImageLabellerArea extends StatelessWidget {
  final String? selectedImageUrl;

  const ImageLabellerArea({
    super.key,
    this.selectedImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 2,
      child: Column(
        children: [
          Center(
            child: selectedImageUrl == null
                ? Text("Select an image from the left panel")
                : Text("Selected Image:"),
          ),
          SizedBox(height: 10),
          if (selectedImageUrl != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Image.network(
                  selectedImageUrl!,
                  fit: BoxFit.contain,
                ),
              ),
            ),
        ],
      ),
    );
  }
}