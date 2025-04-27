import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:vector_math/vector_math_64.dart' show Vector4;
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
  bool _isDrawing = false;
  Offset? _startPoint;
  Offset? _currentPoint;
  
  // Store the image size and container size for proper coordinate mapping
  Size _imageSize = Size.zero;
  Size _containerSize = Size.zero;
  bool _imageLoaded = false;
  
  // Flag to track middle mouse button state
  bool _isMiddleMouseDown = false;
  
  // Transformation controller to track zoom and pan
  final TransformationController _transformationController = TransformationController();
  
  @override
  void initState() {
    super.initState();
    // Preload the image to get its dimensions
    _loadImage();
  }
  
  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
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
  
  // Convert normalized coordinates (0-1) to container coordinates with transformation
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
    
    // Calculate box position in untransformed space
    final baseRect = Rect.fromLTWH(
      horizontalOffset + box.x * displayWidth,
      verticalOffset + box.y * displayHeight,
      box.width * displayWidth,
      box.height * displayHeight,
    );
    
    // Apply the current transformation to get the actual position on screen
    final topLeft = _transformPoint(baseRect.topLeft);
    final bottomRight = _transformPoint(baseRect.bottomRight);
    
    return Rect.fromPoints(topLeft, bottomRight);
  }
  
  // Apply transformation matrix to a point
  Offset _transformPoint(Offset point) {
    // Get the current matrix
    final matrix = _transformationController.value;
    
    // Apply transformation - Matrix4.transform returns Vector4
    final Vector4 transformedPoint = matrix.transform(Vector4(point.dx, point.dy, 0.0, 1.0));
    
    // Convert back to 2D coordinates by dividing by w component (perspective division)
    return Offset(transformedPoint.x / transformedPoint.w, transformedPoint.y / transformedPoint.w);
  }
  
  // Apply inverse transformation to convert from screen coordinates to untransformed coordinates
  Offset _inverseTransformPoint(Offset point) {
    // Get the current matrix
    final matrix = _transformationController.value;
    
    try {
      // Calculate inverse transformation
      final Matrix4 invertedMatrix = Matrix4.inverted(matrix);
      final Vector4 untransformedPoint = invertedMatrix.transform(Vector4(point.dx, point.dy, 0.0, 1.0));
      
      // Convert back to 2D coordinates with perspective division
      return Offset(untransformedPoint.x / untransformedPoint.w, untransformedPoint.y / untransformedPoint.w);
    } catch (e) {
      // If matrix can't be inverted, return original point
      return point;
    }
  }
  
  // Convert container coordinates to normalized coordinates (0-1)
  BoundingBox _containerToNormalized(Offset topLeft, Offset bottomRight, Size containerSize) {
    // First, invert the transformation to get untransformed coordinates
    final untransformedTopLeft = _inverseTransformPoint(topLeft);
    final untransformedBottomRight = _inverseTransformPoint(bottomRight);
    
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
    double x = (untransformedTopLeft.dx - horizontalOffset) / displayWidth;
    double y = (untransformedTopLeft.dy - verticalOffset) / displayHeight;
    double width = (untransformedBottomRight.dx - untransformedTopLeft.dx) / displayWidth;
    double height = (untransformedBottomRight.dy - untransformedTopLeft.dy) / displayHeight;
    
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
  
  // Handle mouse wheel events for zooming
  void _handleMouseWheel(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // Get current scale
      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      
      // Scale factor - adjust as needed for sensitivity
      double scaleFactor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
      
      // Limit scaling
      final newScale = (currentScale * scaleFactor).clamp(0.8, 5.0);
      scaleFactor = newScale / currentScale;
      
      // Calculate the focal point for zooming
      final focalPoint = event.localPosition;
      
      // Create a transform that applies scaling around the focal point
      final Matrix4 newMatrix = Matrix4.copy(_transformationController.value);
      
      // Translate to the focal point, scale, then translate back
      final double dx = focalPoint.dx;
      final double dy = focalPoint.dy;
      
      newMatrix.translate(dx, dy);
      newMatrix.scale(scaleFactor, scaleFactor);
      newMatrix.translate(-dx, -dy);
      
      // Apply the new transformation
      setState(() {
        _transformationController.value = newMatrix;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handleMouseWheel,
      onPointerDown: (event) {
        // Check if middle mouse button is pressed
        if (event.buttons & kMiddleMouseButton != 0) {
          setState(() {
            _isMiddleMouseDown = true;
          });
        }
      },
      onPointerMove: (event) {
        // Handle panning with middle mouse button
        if (_isMiddleMouseDown) {
          final Matrix4 newMatrix = Matrix4.copy(_transformationController.value);
          newMatrix.translate(
            event.delta.dx,
            event.delta.dy,
          );
          setState(() {
            _transformationController.value = newMatrix;
          });
        }
      },
      onPointerUp: (event) {
        if (_isMiddleMouseDown) {
          setState(() {
            _isMiddleMouseDown = false;
          });
        }
      },
      onPointerCancel: (event) {
        if (_isMiddleMouseDown) {
          setState(() {
            _isMiddleMouseDown = false;
          });
        }
      },
      child: GestureDetector(
        // Drawing with left mouse button
        onPanStart: (details) {
          // Only start drawing if middle mouse button is not down
          if (!_isMiddleMouseDown) {
            setState(() {
              _isDrawing = true;
              _startPoint = details.localPosition;
              _currentPoint = details.localPosition;
            });
          }
        },
        onPanUpdate: (details) {
          if (_isDrawing) {
            setState(() {
              _currentPoint = details.localPosition;
            });
          }
        },
        onPanEnd: (details) {
          if (_isDrawing && _startPoint != null && _currentPoint != null && widget.onBoxDrawn != null) {
            // Get the size of the image container
            final containerSize = _containerSize;
            
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
                  // The image with InteractiveViewer
                  Positioned.fill(
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      maxScale: 5.0,
                      // Disable interactive viewer gestures and handle them manually
                      panEnabled: false,
                      scaleEnabled: false,
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