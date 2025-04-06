import 'package:flutter/material.dart';
import '../widgets/file_upload_button.dart';
import '../structs.dart';
import '../http-requests.dart';

class ImageViewer extends StatefulWidget {
  final Function(String)? onImageSelected;
  final bool showBoxes;

  ImageViewer({
    super.key,
    this.onImageSelected,
    this.showBoxes = false,
  });

  Future<List<AnnotatedImage>?> fetchImages() {
    return fetchLatestImages();
  }

  @override
  State<ImageViewer> createState() => ImageViewerState();
}

class ImageViewerState extends State<ImageViewer> {
  late Future<List<AnnotatedImage>?> _imagesFuture;
  int? _selectedIndex;
  
  @override
  void initState() {
    super.initState();
    // Initialize the future only once when the widget is created
    _imagesFuture = widget.fetchImages();
  }

  // Method to refresh images
  void refreshImages() {
    print("Checking for images!");
    setState(() {
      _imagesFuture = widget.fetchImages();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: 1, // This makes it take 1/3 of the available space (since ImageLabellerArea has flex: 2)
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Text("Select an Image to Label"),
                  SizedBox(width: 20),
                  FileUploadButton(onUploadComplete: refreshImages,),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AnnotatedImage>?>(
                future: _imagesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  
                  if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("No images available"),
                          Text("Upload some images to get started!"),
                        ],
                      ));
                  }
                  
                  // Data is available and not empty
                  List<AnnotatedImage> images = snapshot.data!;
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, // 2 images per row
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.2, // Adjust this value to change the height/width ratio
                      ),
                      itemCount: images.length,
                      itemBuilder: (BuildContext context, int index) {
                        final imageUrl = "http://localhost:5001/uploads/${images[index].filepath}";
                        final hasAnnotations = images[index].boundingBoxes.isNotEmpty;
                        return ClickableImage(
                          imageUrl: imageUrl,
                          isSelected: _selectedIndex == index,
                          showAnnotationIcon: widget.showBoxes && hasAnnotations,
                          annotationCount: images[index].boundingBoxes.length,
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                            });
                            if (widget.onImageSelected != null) {
                              widget.onImageSelected!(imageUrl);
                            }
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClickableImage extends StatelessWidget {
  const ClickableImage({
    super.key,
    required this.imageUrl,
    required this.onTap,
    this.isSelected = false,
    this.showAnnotationIcon = false,
    this.annotationCount = 0,
  });

  final String imageUrl;
  final VoidCallback onTap;
  final bool isSelected;
  final bool showAnnotationIcon;
  final int annotationCount;

  @override
  Widget build(BuildContext context) {
    var image = NetworkImage(imageUrl);
    return Card(
      margin: EdgeInsets.zero,
      elevation: isSelected ? 6 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected 
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: onTap,
            child: Ink.image(
              fit: BoxFit.cover,
              image: image,
            )
          ),
          if (showAnnotationIcon)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.crop_square, 
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      annotationCount.toString(),
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}