import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:vector_math/vector_math_64.dart' show Vector4;
import '../structs.dart';

// Cache for image dimensions to avoid recalculating
final _imageDimensionCache = <String, Size>{};

class ZoomableImage extends StatefulWidget {
  final String imageUrl;
  final List<BoundingBox> boxes;
  final Function(BoundingBox)? onBoxDrawn;
  final String? selectedTag;

  const ZoomableImage({
    super.key,
    required this.imageUrl,
    this.boxes = const [],
    this.onBoxDrawn,
    this.selectedTag,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> with SingleTickerProviderStateMixin {
  // Drawing state
  bool _isDrawing = false;
  Offset? _startPoint;
  Offset? _currentPoint;
  
  // Image dimensions
  Size _imageSize = Size.zero;
  Size _containerSize = Size.zero;
  bool _imageLoaded = false;
  
  // Mouse and gesture tracking
  bool _isMiddleMouseDown = false;
  Offset? _lastPanPosition;
  
  // Transformation controller for zoom and pan
  final TransformationController _transformationController = TransformationController();
  
  // Use a RepaintBoundary key to optimize rendering
  final GlobalKey _imageKey = GlobalKey();
  
  // Cache for expensive calculations
  Size? _cachedDisplayDimensions;
  Matrix4? _cachedInverseMatrix;
  
  // Local state for boxes
  List<BoundingBox> _localBoxes = [];
  
  @override
  void initState() {
    super.initState();
    _loadImage();
    _localBoxes = widget.boxes;
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
    if (oldWidget.boxes != widget.boxes) {
      setState(() {
        _localBoxes = widget.boxes;
      });
    }
  }
  
  void _loadImage() {
    // Check cache first
    if (_imageDimensionCache.containsKey(widget.imageUrl)) {
      setState(() {
        _imageSize = _imageDimensionCache[widget.imageUrl]!;
        _imageLoaded = true;
      });
      return;
    }

    final imageProvider = NetworkImage(widget.imageUrl);
    final imageStream = imageProvider.resolve(ImageConfiguration());
    
    imageStream.addListener(
      ImageStreamListener((info, _) {
        if (mounted) {
          final size = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
          _imageDimensionCache[widget.imageUrl] = size;
          setState(() {
            _imageSize = size;
            _imageLoaded = true;
          });
        }
      })
    );
  }
  
  // Convert normalized coordinates (0-1) to container coordinates
  Rect _normalizedToContainer(BoundingBox box, Size containerSize) {
    // Calculate display dimensions
    final displayDimensions = _calculateDisplayDimensions(containerSize);
    final displayWidth = displayDimensions.width;
    final displayHeight = displayDimensions.height;
    
    // Calculate offset
    final horizontalOffset = (containerSize.width - displayWidth) / 2;
    final verticalOffset = (containerSize.height - displayHeight) / 2;
    
    // Calculate base rectangle
    final baseRect = Rect.fromLTWH(
      horizontalOffset + box.x * displayWidth,
      verticalOffset + box.y * displayHeight,
      box.width * displayWidth,
      box.height * displayHeight,
    );
    
    // Apply transformation
    final topLeft = _transformPoint(baseRect.topLeft);
    final bottomRight = _transformPoint(baseRect.bottomRight);
    
    return Rect.fromPoints(topLeft, bottomRight);
  }
  
  // Helper function to calculate display dimensions with caching
  Size _calculateDisplayDimensions(Size containerSize) {
    if (_cachedDisplayDimensions != null) {
      return _cachedDisplayDimensions!;
    }

    double displayWidth = containerSize.width;
    double displayHeight = containerSize.height;
    
    if (_imageLoaded && _imageSize != Size.zero) {
      final imageAspectRatio = _imageSize.width / _imageSize.height;
      final containerAspectRatio = containerSize.width / containerSize.height;
      
      if (imageAspectRatio > containerAspectRatio) {
        displayHeight = containerSize.width / imageAspectRatio;
      } else {
        displayWidth = containerSize.height * imageAspectRatio;
      }
    }
    
    _cachedDisplayDimensions = Size(displayWidth, displayHeight);
    return _cachedDisplayDimensions!;
  }
  
  // Transform a point using the current transformation matrix
  Offset _transformPoint(Offset point) {
    final matrix = _transformationController.value;
    final transformedPoint = matrix.transform(Vector4(point.dx, point.dy, 0.0, 1.0));
    return Offset(
      transformedPoint.x / transformedPoint.w, 
      transformedPoint.y / transformedPoint.w
    );
  }
  
  // Apply inverse transformation to convert from screen to untransformed coordinates
  Offset _inverseTransformPoint(Offset point) {
    final matrix = _transformationController.value;
    
    // Check if we can use cached inverse matrix
    if (_cachedInverseMatrix != null && _cachedInverseMatrix == matrix) {
      final untransformedPoint = _cachedInverseMatrix!.transform(Vector4(point.dx, point.dy, 0.0, 1.0));
      return Offset(
        untransformedPoint.x / untransformedPoint.w, 
        untransformedPoint.y / untransformedPoint.w
      );
    }
    
    try {
      final invertedMatrix = Matrix4.inverted(matrix);
      _cachedInverseMatrix = invertedMatrix;
      final untransformedPoint = invertedMatrix.transform(Vector4(point.dx, point.dy, 0.0, 1.0));
      return Offset(
        untransformedPoint.x / untransformedPoint.w, 
        untransformedPoint.y / untransformedPoint.w
      );
    } catch (e) {
      return point;
    }
  }
  
  // Convert container coordinates to normalized coordinates (0-1)
  BoundingBox _containerToNormalized(Offset topLeft, Offset bottomRight, Size containerSize) {
    // Invert the transformation first
    final untransformedTopLeft = _inverseTransformPoint(topLeft);
    final untransformedBottomRight = _inverseTransformPoint(bottomRight);
    
    // Calculate display dimensions
    final displayDimensions = _calculateDisplayDimensions(containerSize);
    final displayWidth = displayDimensions.width;
    final displayHeight = displayDimensions.height;
    
    // Calculate offset
    final horizontalOffset = (containerSize.width - displayWidth) / 2;
    final verticalOffset = (containerSize.height - displayHeight) / 2;
    
    // Calculate normalized coordinates
    double x = (untransformedTopLeft.dx - horizontalOffset) / displayWidth;
    double y = (untransformedTopLeft.dy - verticalOffset) / displayHeight;
    double width = (untransformedBottomRight.dx - untransformedTopLeft.dx) / displayWidth;
    double height = (untransformedBottomRight.dy - untransformedTopLeft.dy) / displayHeight;
    
    // Clamp values to 0-1 range
    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);
    width = width.clamp(0.0, 1.0 - x);
    height = height.clamp(0.0, 1.0 - y);
    
    // Create a temporary box with empty label
    final tempBox = BoundingBox(
      x: x,
      y: y,
      width: width,
      height: height,
      label: "", // Empty label by default
    );
    
    // If a tag is selected, use it automatically
    if (widget.selectedTag != null) {
      return tempBox.copyWith(label: widget.selectedTag!);
    }
    
    return tempBox;
  }
  
  // Handle mouse wheel events for zooming
  void _handleMouseWheel(PointerScrollEvent event) {
    // Get current scale
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    
    // Scale factor - adjust for sensitivity
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
    _transformationController.value = newMatrix;
    
    // Clear cached values
    _cachedInverseMatrix = null;
  }

  // Handle pointer events for both drawing and panning
  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons & kMiddleMouseButton != 0) {
      setState(() {
        _isMiddleMouseDown = true;
        _lastPanPosition = event.localPosition;
      });
    } else if (event.buttons & kPrimaryMouseButton != 0) {
      if (!_isMiddleMouseDown) {
        setState(() {
          _isDrawing = true;
          _startPoint = event.localPosition;
          _currentPoint = event.localPosition;
        });
      }
    }
  }
  
  void _handlePointerMove(PointerMoveEvent event) {
    if (_isMiddleMouseDown && _lastPanPosition != null) {
      final dx = event.localPosition.dx - _lastPanPosition!.dx;
      final dy = event.localPosition.dy - _lastPanPosition!.dy;
      
      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      final adjustedDx = dx / currentScale;
      final adjustedDy = dy / currentScale;
      
      final Matrix4 newMatrix = Matrix4.copy(_transformationController.value);
      newMatrix.translate(adjustedDx, adjustedDy);
      
      _transformationController.value = newMatrix;
      _lastPanPosition = event.localPosition;
      
      // Clear cached values
      _cachedInverseMatrix = null;
    } else if (_isDrawing) {
      setState(() {
        _currentPoint = event.localPosition;
      });
    }
  }
  
  void _handlePointerUp(PointerUpEvent event) {
    if (_isMiddleMouseDown) {
      setState(() {
        _isMiddleMouseDown = false;
        _lastPanPosition = null;
      });
    }
    
    if (_isDrawing && _startPoint != null && _currentPoint != null && widget.onBoxDrawn != null) {
      final containerSize = _containerSize;
      
      Offset topLeft = Offset(
        _startPoint!.dx < _currentPoint!.dx ? _startPoint!.dx : _currentPoint!.dx,
        _startPoint!.dy < _currentPoint!.dy ? _startPoint!.dy : _currentPoint!.dy,
      );
      
      Offset bottomRight = Offset(
        _startPoint!.dx > _currentPoint!.dx ? _startPoint!.dx : _currentPoint!.dx,
        _startPoint!.dy > _currentPoint!.dy ? _startPoint!.dy : _currentPoint!.dy,
      );
      
      final normalizedBox = _containerToNormalized(topLeft, bottomRight, containerSize);
      
      if (normalizedBox.width > 0.01 && normalizedBox.height > 0.01) {
        widget.onBoxDrawn?.call(normalizedBox);
      }
      
      setState(() {
        _isDrawing = false;
        _startPoint = null;
        _currentPoint = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          _handleMouseWheel(signal);
        }
      },
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (event) {
        setState(() {
          _isDrawing = false;
          _isMiddleMouseDown = false;
          _startPoint = null;
          _currentPoint = null;
          _lastPanPosition = null;
        });
      },
      child: Container(
        color: Colors.black12,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _containerSize = Size(constraints.maxWidth, constraints.maxHeight);
            _cachedDisplayDimensions = null; // Clear cache when size changes
            
            return Stack(
              children: [
                // Image with RepaintBoundary for optimization
                Positioned.fill(
                  child: RepaintBoundary(
                    key: _imageKey,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      maxScale: 5.0,
                      minScale: 0.8,
                      panEnabled: true,
                      scaleEnabled: true,
                      boundaryMargin: EdgeInsets.all(20),
                      child: Image.network(
                        widget.imageUrl,
                        fit: BoxFit.contain,
                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                          if (frame != null) {
                            return child;
                          }
                          return Center(child: CircularProgressIndicator());
                        },
                      ),
                    ),
                  ),
                ),
                
                // Existing bounding boxes with RepaintBoundary
                ClipRect(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: ExistingBoxesPainter(
                        boxes: _localBoxes.where((box) => box.label.isNotEmpty).toList(),
                        containerSize: _containerSize,
                        transformPoint: _normalizedToContainer,
                        transformationController: _transformationController,
                      ),
                    ),
                  ),
                ),
                
                // Currently drawing box
                if (_isDrawing && _startPoint != null && _currentPoint != null)
                  ClipRect(
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: BoxPainter(
                        startPoint: _startPoint!,
                        currentPoint: _currentPoint!,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Custom painter for all existing boxes - improves performance by batching rendering
class ExistingBoxesPainter extends CustomPainter {
  final List<BoundingBox> boxes;
  final Size containerSize;
  final Rect Function(BoundingBox box, Size size) transformPoint;
  final TransformationController transformationController;
  
  // Cache for paint objects
  final Map<Color, Paint> _paintCache = {};
  final Map<Color, Paint> _labelPaintCache = {};
  
  ExistingBoxesPainter({
    required this.boxes,
    required this.containerSize,
    required this.transformPoint,
    required this.transformationController,
  }) : super(repaint: transformationController);
  
  Paint _getPaint(Color color) {
    return _paintCache.putIfAbsent(color, () => Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke);
  }
  
  Paint _getLabelPaint(Color color) {
    return _labelPaintCache.putIfAbsent(color, () => Paint()
      ..color = color.withOpacity(0.7)
      ..style = PaintingStyle.fill);
  }
  
  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    
    for (final box in boxes) {
      final color = _getBoxColor(box);
      final boxRect = transformPoint(box, containerSize);
      
      // Draw box border
      canvas.drawRect(boxRect, _getPaint(color));
      
      // Draw label background
      final labelText = box.label.isEmpty ? "No label" : box.label;
      
      textPainter.text = TextSpan(
        text: labelText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      
      textPainter.layout(maxWidth: boxRect.width);
      
      final labelHeight = 20.0;
      final labelRect = Rect.fromLTWH(
        boxRect.left,
        boxRect.top,
        textPainter.width + 8,
        labelHeight,
      );
      
      canvas.drawRect(labelRect, _getLabelPaint(color));
      
      // Draw label text
      textPainter.paint(
        canvas,
        Offset(boxRect.left + 4, boxRect.top + (labelHeight - textPainter.height) / 2),
      );
      
      // Draw confidence for AI source
      if (box.source == AnnotationSource.ai) {
        final confidenceWidth = 80.0;
        final progressWidth = 40.0;
        final confidenceHeight = 20.0;
        
        final confidenceRect = Rect.fromLTWH(
          boxRect.left,
          boxRect.top + labelHeight,
          confidenceWidth,
          confidenceHeight,
        );
        
        canvas.drawRect(confidenceRect, _getLabelPaint(color));
        
        // Draw progress bar background
        final progressBackgroundPaint = Paint()
          ..color = Colors.grey.shade800
          ..style = PaintingStyle.fill;
        
        final progressRect = Rect.fromLTWH(
          boxRect.left + 4,
          boxRect.top + labelHeight + (confidenceHeight - 6) / 2,
          progressWidth,
          6,
        );
        
        canvas.drawRect(progressRect, progressBackgroundPaint);
        
        // Draw progress bar value
        final progressValuePaint = Paint()
          ..color = _getConfidenceColor(box.confidence)
          ..style = PaintingStyle.fill;
        
        final progressValueRect = Rect.fromLTWH(
          boxRect.left + 4,
          boxRect.top + labelHeight + (confidenceHeight - 6) / 2,
          progressWidth * box.confidence,
          6,
        );
        
        canvas.drawRect(progressValueRect, progressValuePaint);
        
        // Draw confidence percentage text
        final confidenceText = "${(box.confidence * 100).toStringAsFixed(0)}%";
        
        textPainter.text = TextSpan(
          text: confidenceText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
          ),
        );
        
        textPainter.layout();
        
        textPainter.paint(
          canvas,
          Offset(
            boxRect.left + 4 + progressWidth + 4,
            boxRect.top + labelHeight + (confidenceHeight - textPainter.height) / 2,
          ),
        );
      }
    }
  }
  
  Color _getBoxColor(BoundingBox box) {
    if (box.source == AnnotationSource.ai) {
      if (!box.isVerified) {
        return Colors.orange;
      } else {
        return Colors.green;
      }
    } else {
      return Colors.blue;
    }
  }
  
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.yellow;
    return Colors.red;
  }
  
  @override
  bool shouldRepaint(ExistingBoxesPainter oldDelegate) {
    if (oldDelegate.boxes.length != boxes.length) return true;
    if (oldDelegate.containerSize != containerSize) return true;
    if (oldDelegate.transformationController.value != transformationController.value) return true;
    
    for (int i = 0; i < boxes.length; i++) {
      if (boxes[i] != oldDelegate.boxes[i]) return true;
    }
    
    return false;
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