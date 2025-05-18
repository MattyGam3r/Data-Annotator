import 'package:flutter/material.dart';
import '../yolo_service.dart';
import '../structs.dart';
import 'dart:convert';
import 'zoomable_image.dart';

class AugmentedImagesViewer extends StatefulWidget {
  final String imageUrl;
  final VoidCallback? onClose;

  const AugmentedImagesViewer({
    super.key,
    required this.imageUrl,
    this.onClose,
  });

  @override
  State<AugmentedImagesViewer> createState() => _AugmentedImagesViewerState();
}

class _AugmentedImagesViewerState extends State<AugmentedImagesViewer> {
  final YoloService _yoloService = YoloService();
  List<Map<String, dynamic>>? _augmentedImages;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAugmentedImages();
  }

  Future<void> _loadAugmentedImages() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final images = await _yoloService.getAugmentedImages(widget.imageUrl);
      
      if (!mounted) return;
      
      setState(() {
        _augmentedImages = images;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _error = 'Failed to load augmented images: $e';
        _isLoading = false;
      });
    }
  }

  String _getFullImageUrl(String url) {
    // If the URL already starts with http, return it as is
    if (url.startsWith('http')) {
      return url;
    }
    // Otherwise, prepend the base URL
    return 'http://localhost:5001$url';
  }

  List<BoundingBox> _parseAnnotations(String? annotationsJson) {
    if (annotationsJson == null) return [];
    try {
      List<dynamic> annotations = json.decode(annotationsJson);
      return annotations.map((box) => BoundingBox.fromJson(box)).toList();
    } catch (e) {
      print('Error parsing annotations: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Augmented Images',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadAugmentedImages,
                      tooltip: 'Refresh augmented images',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadAugmentedImages,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (_augmentedImages == null || _augmentedImages!.isEmpty)
              const Center(
                child: Text('No augmented images found'),
              )
            else
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _augmentedImages!.length,
                  itemBuilder: (context, index) {
                    final image = _augmentedImages![index];
                    final boxes = _parseAnnotations(image['annotations']);
                    return Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ZoomableImage(
                              imageUrl: _getFullImageUrl(image['url']),
                              boxes: boxes,
                              onBoxDrawn: null, // Disable box drawing
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  image['is_original'] ? 'Original' : 'Augmented',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (boxes.isNotEmpty)
                                  Text(
                                    '${boxes.length} annotation${boxes.length == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
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

class BoundingBoxPainter extends CustomPainter {
  final List<BoundingBox> boxes;
  final Size imageSize;

  BoundingBoxPainter({
    required this.boxes,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var box in boxes) {
      final rect = Rect.fromLTWH(
        box.x * size.width,
        box.y * size.height,
        box.width * size.width,
        box.height * size.height,
      );
      canvas.drawRect(rect, paint);

      // Draw label
      final textPainter = TextPainter(
        text: TextSpan(
          text: box.label,
          style: const TextStyle(
            color: Colors.white,
            backgroundColor: Colors.red,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(rect.left, rect.top - textPainter.height),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
} 