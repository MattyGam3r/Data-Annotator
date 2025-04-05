import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../structs.dart';

class ZoomableImage extends StatefulWidget {
  final String imageUrl;
  final List<BoundingBox> boxes;
  final Function(BoundingBox)? onBoxDrawn;

  const ZoomableImage({
    Key? key,
    required this.imageUrl,
    this.boxes = const [],
    this.onBoxDrawn,
  }) : super(key: key);

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  final TransformationController _transformationController = TransformationController();
  bool _isDrawingBox = false;
  Offset? _startPosition;
  Offset? _currentPosition;
  GlobalKey _imageKey = GlobalKey();
  Size _imageSize = Size.zero;
  bool _isImageLoaded = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _updateImageSize() {
    if (_imageKey.currentContext != null) {
      final RenderBox renderBox = _imageKey.currentContext!.findRenderObject() as RenderBox;
      setState(() {
        _imageSize = renderBox.size;
        _isImageLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Zoomable and pannable image
        InteractiveViewer(
          transformationController: _transformationController,
          minScale: 0.5,
          maxScale: 4.0,
          boundaryMargin: EdgeInsets.all(20),
          onInteractionEnd: (_) {
            _updateImageSize();
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: GestureDetector(
              onPanStart: (details) {
                if (!_isDrawingBox) {
                  setState(() {
                    _isDrawingBox = true;
                    _startPosition = details.localPosition;
                    _currentPosition = details.localPosition;
                  });
                }
              },
              onPanUpdate: (details) {
                if (_isDrawingBox) {
                  setState(() {
                    _currentPosition = details.localPosition;
                  });
                }
              },
              onPanEnd: (details) {
                if (_isDrawingBox && _startPosition != null && _currentPosition != null) {
                  _updateImageSize();
                  
                  // Calculate the box dimensions relative to the image
                  double left = _startPosition!.dx.clamp(0, _imageSize.width);
                  double top = _startPosition!.dy.clamp(0, _imageSize.height);
                  double right = _currentPosition!.dx.clamp(0, _imageSize.width);
                  double bottom = _currentPosition!.dy.clamp(0, _imageSize.height);
                  
                  // Ensure left < right and top < bottom
                  if (left > right) {
                    double temp = left;
                    left = right;
                    right = temp;
                  }
                  if (top > bottom) {
                    double temp = top;
                    top = bottom;
                    bottom = temp;
                  }
                  
                  // Convert to percentages of image dimensions
                  double x = left / _imageSize.width;
                  double y = top / _imageSize.height;
                  double width = (right - left) / _imageSize.width;
                  double height = (bottom - top) / _imageSize.height;
                  
                  // Create a bounding box
                  final box = BoundingBox(
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    label: "New Box",  // Temporary label
                  );
                  
                  if (widget.onBoxDrawn != null) {
                    widget.onBoxDrawn!(box);
                  }
                  
                  setState(() {
                    _isDrawingBox = false;
                    _startPosition = null;
                    _currentPosition = null;
                  });
                }
              },
              child: Stack(
                children: [
                  // The base image
                  Image.network(
                    widget.imageUrl,
                    key: _imageKey,
                    fit: BoxFit.contain,
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (frame != null && !_isImageLoaded) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _updateImageSize();
                        });
                      }
                      return child;
                    },
                  ),
                  
                  // Existing bounding boxes
                  if (_isImageLoaded)
                    ...widget.boxes.map((box) => Positioned(
                      left: box.x * _imageSize.width,
                      top: box.y * _imageSize.height,
                      width: box.width * _imageSize.width,
                      height: box.height * _imageSize.height,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red, width: 2),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            color: Colors.red,
                            child: Text(
                              box.label,
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    )),
                  
                  // Currently drawing box
                  if (_isDrawingBox && _startPosition != null && _currentPosition != null)
                    Positioned(
                      left: math.min(_startPosition!.dx, _currentPosition!.dx),
                      top: math.min(_startPosition!.dy, _currentPosition!.dy),
                      width: (_currentPosition!.dx - _startPosition!.dx).abs(),
                      height: (_currentPosition!.dy - _startPosition!.dy).abs(),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue, width: 2),
                          color: Colors.blue.withOpacity(0.2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}