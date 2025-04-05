import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import "views/image_viewer.dart";
import "structs.dart";
import 'widgets/zoomable_image.dart';

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
  List<BoundingBox> currentBoxes = [];

  void onImageSelected(String imageUrl) {
    setState(() {
      selectedImageUrl = imageUrl;
      // Reset current boxes when a new image is selected
      // In a more complete implementation, you'd load the boxes for this image
      currentBoxes = [];
    });
  }

  void onBoxAdded(BoundingBox box) {
    setState(() {
      currentBoxes.add(box);
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
          ImageLabellerArea(
            selectedImageUrl: selectedImageUrl,
            currentBoxes: currentBoxes,
            onBoxAdded: onBoxAdded,
          ),
        ],
      ),
    );
  }
}

class ImageLabellerArea extends StatefulWidget {
  final String? selectedImageUrl;
  final List<BoundingBox> currentBoxes;
  final Function(BoundingBox)? onBoxAdded;

  const ImageLabellerArea({
    super.key,
    this.selectedImageUrl,
    this.currentBoxes = const [],
    this.onBoxAdded,
  });

  @override
  State<ImageLabellerArea> createState() => _ImageLabellerAreaState();
}

class _ImageLabellerAreaState extends State<ImageLabellerArea> {
  final TextEditingController _labelController = TextEditingController();
  bool _isDrawingBox = false;
  Offset? _startPosition;
  Offset? _currentPosition;
  
  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Expanded(
      flex: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              widget.selectedImageUrl == null 
                  ? "Select an image from the left panel" 
                  : "Selected Image:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (widget.selectedImageUrl != null)
            Align(
              alignment: Alignment.center,
              child: Container(
                height: screenHeight * 0.5, // Fixed height of 50% of screen
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ZoomableImage(
                      imageUrl: widget.selectedImageUrl!,
                      boxes: widget.currentBoxes,
                      onBoxDrawn: (box) {
                        if (widget.onBoxAdded != null) {
                          _showLabelDialog(box);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (widget.selectedImageUrl != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 16),
                    Text(
                      "Annotations:",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: widget.currentBoxes.isEmpty
                          ? Center(child: Text("No annotations yet. Draw a box on the image."))
                          : ListView.builder(
                              itemCount: widget.currentBoxes.length,
                              itemBuilder: (context, index) {
                                final box = widget.currentBoxes[index];
                                return ListTile(
                                  title: Text(box.label),
                                  subtitle: Text(
                                      "x: ${box.x.toStringAsFixed(2)}, y: ${box.y.toStringAsFixed(2)}, " +
                                      "w: ${box.width.toStringAsFixed(2)}, h: ${box.height.toStringAsFixed(2)}"),
                                  trailing: IconButton(
                                    icon: Icon(Icons.delete),
                                    onPressed: () {
                                      // Delete box functionality would go here
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showLabelDialog(BoundingBox box) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add Label"),
        content: TextField(
          controller: _labelController,
          decoration: InputDecoration(hintText: "Enter label name"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              if (_labelController.text.isNotEmpty) {
                final labeledBox = box.copyWith(label: _labelController.text);
                widget.onBoxAdded?.call(labeledBox);
                _labelController.clear();
                Navigator.pop(context);
              }
            },
            child: Text("Save"),
          ),
        ],
      ),
    );
  }
}