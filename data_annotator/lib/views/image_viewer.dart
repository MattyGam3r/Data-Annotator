import 'package:flutter/material.dart';
import '../widgets/file_upload_button.dart';
import '../structs.dart';
import '../http-requests.dart';
import '../yolo_service.dart';

class ImageViewer extends StatefulWidget {
  final Function(String) onImageSelected;
  final bool showBoxes;
  final GlobalKey? key;

  const ImageViewer({
    this.key,
    required this.onImageSelected,
    this.showBoxes = false,
  }) : super(key: key);

  @override
  State<ImageViewer> createState() => ImageViewerState();
}

class ImageViewerState extends State<ImageViewer> {
  List<AnnotatedImage> _images = [];
  bool _isLoading = true;
  bool _isUpdatingScores = false;
  String? _error;
  String _sortBy = 'upload_time';  // Default sort by upload time
  bool _sortAscending = false;  // Default sort descending
  final YoloService _yoloService = YoloService();

  @override
  void initState() {
    super.initState();
    refreshImages();
  }

  Future<void> refreshImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final images = await fetchLatestImages();
      if (images != null) {
        setState(() {
          _images = images;
          _sortImages();  // Apply current sort
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateAllUncertaintyScores() async {
    if (_isUpdatingScores) return;
    
    setState(() {
      _isUpdatingScores = true;
    });
    
    try {
      final success = await _yoloService.updateAllUncertaintyScores();
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uncertainty scores updated successfully')),
        );
        // Refresh the images to show updated scores
        await refreshImages();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update uncertainty scores'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isUpdatingScores = false;
      });
    }
  }

  void _sortImages() {
    switch (_sortBy) {
      case 'upload_time':
        _images.sort((a, b) {
          final aTime = a.uploadedDate ?? DateTime(1970);
          final bTime = b.uploadedDate ?? DateTime(1970);
          return _sortAscending ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
        });
        break;
      case 'uncertainty':
        _images.sort((a, b) {
          final aScore = a.uncertaintyScore ?? 0.0;
          final bScore = b.uncertaintyScore ?? 0.0;
          return _sortAscending ? aScore.compareTo(bScore) : bScore.compareTo(aScore);
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Text("Select an Image to Label"),
                SizedBox(width: 8),
                FileUploadButton(onUploadComplete: refreshImages),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _sortBy,
                    items: [
                      DropdownMenuItem(
                        value: 'upload_time',
                        child: Text('Sort by Upload Time'),
                      ),
                      DropdownMenuItem(
                        value: 'uncertainty',
                        child: Text('Sort by Uncertainty'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _sortBy = value;
                          _sortImages();
                        });
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                  onPressed: () {
                    setState(() {
                      _sortAscending = !_sortAscending;
                      _sortImages();
                    });
                  },
                ),
                if (_sortBy == 'uncertainty')
                  Tooltip(
                    message: 'Update uncertainty scores for all images',
                    child: IconButton(
                      icon: _isUpdatingScores 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.update),
                      onPressed: _isUpdatingScores ? null : _updateAllUncertaintyScores,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _images.isEmpty
                        ? Center(child: Text('No images available'))
                        : ListView.builder(
                            itemCount: _images.length,
                            itemBuilder: (context, index) {
                              final image = _images[index];
                              return ListTile(
                                leading: Image.network(
                                  'http://localhost:5001/uploads/${image.filepath}',
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      color: Colors.grey[300],
                                      child: Icon(Icons.error),
                                    );
                                  },
                                ),
                                title: Text(image.filepath),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('${image.boundingBoxes.length} annotations'),
                                        if (image.isFullyAnnotated)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 8.0),
                                            child: Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                              size: 16,
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (image.uncertaintyScore != null)
                                      Text(
                                        'Uncertainty: ${(image.uncertaintyScore! * 100).toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          color: image.uncertaintyScore! > 0.7
                                              ? Colors.red
                                              : image.uncertaintyScore! > 0.4
                                                  ? Colors.orange
                                                  : Colors.green,
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () {
                                  if (widget.onImageSelected != null) {
                                    widget.onImageSelected(image.filepath);
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
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
    this.isComplete = false,
  });

  final String imageUrl;
  final VoidCallback onTap;
  final bool isSelected;
  final bool showAnnotationIcon;
  final int annotationCount;
  final bool isComplete;

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
          if (isComplete)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}