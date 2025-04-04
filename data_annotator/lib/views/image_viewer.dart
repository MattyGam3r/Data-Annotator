import 'package:flutter/material.dart';
import '../widgets/file_upload_button.dart';
import '../structs.dart';
import '../http-requests.dart';

class ImageViewer extends StatefulWidget {
  ImageViewer({
    super.key,
  });

  Future<List<AnnotatedImage>?> fetchImages() {
    return fetchLatestImages();
  }

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late Future<List<AnnotatedImage>?> _imagesFuture;

  
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
                  return SizedBox(
                    width: double.infinity, // Constrain width to parent
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: images.length,
                      itemBuilder: (BuildContext context, int index) {
                        return ClickableImage(
                          imageUrl: "http://localhost:5001/uploads/${images[index].filepath}"
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
  });

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    var image = NetworkImage(imageUrl);
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () {      
          print("clicked!");
        },
        child: Ink.image(
          fit: BoxFit.cover,
          width: double.infinity,
          height: 100,
          image: image,
        )
      ),
    );
  }
}