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
          final size = box.size;
          
          // Calculate the normalized coordinates (0-1)
          Offset topLeft = Offset(
            (_startPoint!.dx / size.width).clamp(0.0, 1.0),
            (_startPoint!.dy / size.height).clamp(0.0, 1.0),
          );
          
          Offset bottomRight = Offset(
            (_currentPoint!.dx / size.width).clamp(0.0, 1.0),
            (_currentPoint!.dy / size.height).clamp(0.0, 1.0),
          );
          
          // Ensure the coordinates are ordered properly
          double x = topLeft.dx < bottomRight.dx ? topLeft.dx : bottomRight.dx;
          double y = topLeft.dy < bottomRight.dy ? topLeft.dy : bottomRight.dy;
          double width = (bottomRight.dx - topLeft.dx).abs();
          double height = (bottomRight.dy - topLeft.dy).abs();
          
          // Only create a box if it has a minimum size
          if (width > 0.01 && height > 0.01) {
            // Create and pass the new bounding box to the parent
            final box = BoundingBox(
              x: x,
              y: y,
              width: width,
              height: height,
              label: "",
            );
            widget.onBoxDrawn?.call(box);
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
                  return Positioned(
                    left: box.x * constraints.maxWidth,
                    top: box.y * constraints.maxHeight,
                    width: box.width * constraints.maxWidth,
                    height: box.height * constraints.maxHeight,
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