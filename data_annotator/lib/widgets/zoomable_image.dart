import 'package:flutter/material.dart';
import '../structs.dart';

class ZoomableImage extends StatefulWidget {
  final String imageUrl;
  final List<BoundingBox> boxes;
  final Function(BoundingBox)? onBoxDrawn;

  const ZoomableImage({
    super.key,
    required this.imageUrl,
    this.boxes = const [],
    this.onBoxDrawn,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  double _scale = 1.0;
  Offset _position = Offset.zero;
  bool _isDrawing = false;
  Offset? _startPoint;
  Offset? _currentPoint;
  
  // Store the image size and container size for proper coordinate mapping
  Size _imageSize = Size.zero;
  Size _containerSize = Size.zero;
  bool _imageLoaded = false;
  
  @override
  void initState() {
    super.initState();
    // Preload the image to get its dimensions
    _loadImage();
  }
  
  @override
  void didUpdateWidget(ZoomableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageLoaded = false;
      _loadImage();
    }
  }
  
  void _loadImage() {
    final imageProvider = NetworkImage(widget.imageUrl);
    imageProvider.resolve(ImageConfiguration()).addListener(
      ImageStreamListener((info, _) {
        setState(() {
          _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
          _imageLoaded = true;
        });
      })
    );
  }
  
  // Convert normalized coordinates (0-1) to container coordinates
  Rect _normalizedToContainer(BoundingBox box, Size containerSize) {
    // Calculate image display size within container
    double displayWidth = containerSize.width;
    double displayHeight = containerSize.height;
    
    if (_imageLoaded && _imageSize != Size.zero) {
      final imageAspectRatio = _imageSize.width / _imageSize.height;
      final containerAspectRatio = containerSize.width / containerSize.height;
      
      if (imageAspectRatio > containerAspectRatio) {
        // Image is wider than container
        displayHeight = containerSize.width / imageAspectRatio;
      } else {
        // Image is taller than container
        displayWidth = containerSize.height * imageAspectRatio;
      }
    }
    
    // Calculate offset to center the image
    final horizontalOffset = (containerSize.width - displayWidth) / 2;
    final verticalOffset = (containerSize.height - displayHeight) / 2;
    
    return Rect.fromLTWH(
      horizontalOffset + box.x * displayWidth,
      verticalOffset + box.y * displayHeight,
      box.width * displayWidth,
      box.height * displayHeight,
    );
  }
  
  // Convert container coordinates to normalized coordinates (0-1)
  BoundingBox _containerToNormalized(Offset topLeft, Offset bottomRight, Size containerSize) {
    // Calculate image display size within container
    double displayWidth = containerSize.width;
    double displayHeight = containerSize.height;
    
    if (_imageLoaded && _imageSize != Size.zero) {
      final imageAspectRatio = _imageSize.width / _imageSize.height;
      final containerAspectRatio = containerSize.width / containerSize.height;
      
      if (imageAspectRatio > containerAspectRatio) {
        // Image is wider than container
        displayHeight = containerSize.width / imageAspectRatio;
      } else {
        // Image is taller than container
        displayWidth = containerSize.height * imageAspectRatio;
      }
    }
    
    // Calculate offset to center the image
    final horizontalOffset = (containerSize.width - displayWidth) / 2;
    final verticalOffset = (containerSize.height - displayHeight) / 2;
    
    // Adjust coordinates to account for image position
    double x = (topLeft.dx - horizontalOffset) / displayWidth;
    double y = (topLeft.dy - verticalOffset) / displayHeight;
    double width = (bottomRight.dx - topLeft.dx) / displayWidth;
    double height = (bottomRight.dy - topLeft.dy) / displayHeight;
    
    // Clamp values to be within 0-1 range
    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);
    width = width.clamp(0.0, 1.0 - x);
    height = height.clamp(0.0, 1.0 - y);
    
    return BoundingBox(
      x: x,
      y: y,
      width: width,
      height: height,
      label: "",
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (details) {
        setState(() {
          _isDrawing = true;
          _startPoint = details.localFocalPoint;
          _currentPoint = details.localFocalPoint;
        });
      },
      onScaleUpdate: (details) {
        if (_isDrawing) {
          setState(() {
            _currentPoint = details.localFocalPoint;
          });
        } else {
          setState(() {
            _position += details.focalPointDelta;
            _scale *= details.scale;
          });
        }
      },
      onScaleEnd: (details) {
        if (_isDrawing && _startPoint != null && _currentPoint != null && widget.onBoxDrawn != null) {
          // Get the size of the image container
          final RenderBox box = context.findRenderObject() as RenderBox;
          final containerSize = box.size;
          _containerSize = containerSize;
          
          // Ensure correct order of coordinates
          Offset topLeft = Offset(
            _startPoint!.dx < _currentPoint!.dx ? _startPoint!.dx : _currentPoint!.dx,
            _startPoint!.dy < _currentPoint!.dy ? _startPoint!.dy : _currentPoint!.dy,
          );
          
          Offset bottomRight = Offset(
            _startPoint!.dx > _currentPoint!.dx ? _startPoint!.dx : _currentPoint!.dx,
            _startPoint!.dy > _currentPoint!.dy ? _startPoint!.dy : _currentPoint!.dy,
          );
          
          // Convert to normalized coordinates
          final normalizedBox = _containerToNormalized(topLeft, bottomRight, containerSize);
          
          // Only create a box if it has a minimum size
          if (normalizedBox.width > 0.01 && normalizedBox.height > 0.01) {
            widget.onBoxDrawn?.call(normalizedBox);
          }
        }
        
        setState(() {
          _isDrawing = false;
          _startPoint = null;
          _currentPoint = null;
        });
      },
      child: Container(
        color: Colors.black12,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _containerSize = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                // The image itself
                Positioned.fill(
                  child: InteractiveViewer(
                    transformationController: TransformationController(),
                    maxScale: 5.0,
                    child: Image.network(
                      widget.imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                
                // Existing bounding boxes
                ...widget.boxes.map((box) {
                  final color = _getBoxColor(box);
                  final boxRect = _normalizedToContainer(box, _containerSize);
                  
                  return Positioned(
                    left: boxRect.left,
                    top: boxRect.top,
                    width: boxRect.width,
                    height: boxRect.height,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: color,
                          width: 2.0,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            color: color.withOpacity(0.7),
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Text(
                              box.label.isEmpty ? "No label" : box.label,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (box.source == AnnotationSource.ai)
                            Container(
                              color: color.withOpacity(0.7),
                              width: 80,
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 6,
                                    child: LinearProgressIndicator(
                                      value: box.confidence,
                                      backgroundColor: Colors.grey.shade800,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _getConfidenceColor(box.confidence)
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    "${(box.confidence * 100).toStringAsFixed(0)}%",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                
                // Currently drawing box
                if (_isDrawing && _startPoint != null && _currentPoint != null)
                  CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: BoxPainter(
                      startPoint: _startPoint!,
                      currentPoint: _currentPoint!,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
  
  Color _getBoxColor(BoundingBox box) {
    if (box.source == AnnotationSource.ai) {
      if (!box.isVerified) {
        // AI prediction not verified yet
        return Colors.orange;
      } else {
        // AI prediction that has been verified
        return Colors.green;
      }
    } else {
      // Human annotation
      return Colors.blue;
    }
  }
  
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.yellow;
    return Colors.red;
  }
}

class BoxPainter extends CustomPainter {
  final Offset startPoint;
  final Offset currentPoint;
  
  BoxPainter({
    required this.startPoint,
    required this.currentPoint,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final rect = Rect.fromPoints(startPoint, currentPoint);
    canvas.drawRect(rect, paint);
  }
  
  @override
  bool shouldRepaint(BoxPainter oldDelegate) {
    return startPoint != oldDelegate.startPoint || currentPoint != oldDelegate.currentPoint;
  }
}