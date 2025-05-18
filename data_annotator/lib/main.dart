import 'package:data_annotator/yolo_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import "views/image_viewer.dart";
import "structs.dart";
import 'widgets/zoomable_image.dart';
import 'widgets/frequent_tags_panel.dart';
import 'http-requests.dart';
import 'widgets/training_status_widget.dart';
import 'widgets/augmented_images_viewer.dart';

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
  AnnotatedImage? selectedImage;
  List<BoundingBox> currentBoxes = [];
  final GlobalKey<ImageViewerState> _imageViewerKey = GlobalKey();
  // Added for tracking tag frequencies
  Map<String, int> tagFrequencies = {};
  String? selectedTag;
  final YoloService _yoloService = YoloService();

  @override
  void initState() {
    super.initState();
    // Set up keyboard listener for number keys
    HardwareKeyboard.instance.addHandler(_handleKeyPress);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyPress);
    super.dispose();
  }
  

  bool _handleKeyPress(KeyEvent event) {
  if (event is KeyDownEvent && selectedImageUrl != null) {
    // Check if a number key (1-9, 0) was pressed
    if (event.logicalKey.keyLabel.length == 1) {
      final keyValue = event.logicalKey.keyLabel;
      if (RegExp(r'[1-9]|0').hasMatch(keyValue)) {
        final keyIndex = keyValue == '0' ? 9 : int.parse(keyValue) - 1;
        
        // Get top 10 tags
        final sortedTags = tagFrequencies.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        
        // Only proceed if there are tags available
        if (keyIndex < sortedTags.length) {
          final tagKey = sortedTags[keyIndex].key;
          
          // Toggle selection - if it's already selected, deselect it
          if (selectedTag == tagKey) {
            setState(() {
              selectedTag = null;
            });
          } else {
            setState(() {
              selectedTag = tagKey;
            });
          }
        }
      }
    }
  }
  return false;
}

 Future<void> loadImageAnnotations(String imageUrl) async {
  // Extract filename from URL
  String filename = imageUrl.split('/').last;
  
  // Get images to find matching one
  List<AnnotatedImage>? images = await fetchLatestImages();
  if (images == null) return;
  
  // Find the image that matches the URL
  AnnotatedImage? matchingImage = images.firstWhere(
    (img) => img.filepath == filename,
    orElse: () => AnnotatedImage(filename),
  );
  
  // Update tag frequencies
  _updateTagFrequencies(images);
  
  // Set state with existing annotations and predictions
  setState(() {
    selectedImage = matchingImage;
    selectedImageUrl = imageUrl;  // Use the full URL directly
    
    // Start with user annotations
    currentBoxes = List<BoundingBox>.from(matchingImage.boundingBoxes);
    
    // Add YOLO predictions if they exist
    if (matchingImage.yoloPredictions != null) {
      currentBoxes.addAll(matchingImage.yoloPredictions);
    }
    
    // Add ONE-SHOT predictions if they exist
    if (matchingImage.oneShotPredictions != null) {
      currentBoxes.addAll(matchingImage.oneShotPredictions);
    }
  });
}

  void _updateTagFrequencies(List<AnnotatedImage> images) {
    // Reset tag frequencies
    final newFrequencies = <String, int>{};
    
    // Count all tag occurrences across all images
    for (var image in images) {
      for (var box in image.boundingBoxes) {
        if (box.label.isNotEmpty) {
          newFrequencies[box.label] = (newFrequencies[box.label] ?? 0) + 1;
        }
      }
    }
    
    setState(() {
      tagFrequencies = newFrequencies;
    });
  }

  void onImageSelected(String filename) {
    loadImageAnnotations('http://localhost:5001/uploads/$filename');
  }

  void onBoxAdded(BoundingBox box) {
    setState(() {
      currentBoxes.add(box);
      
      // Update frequency for the tag
      if (box.label.isNotEmpty) {
        tagFrequencies[box.label] = (tagFrequencies[box.label] ?? 0) + 1;
      }
    });
  }
  
  void refreshImages() {
    _imageViewerKey.currentState?.refreshImages();
  }

  void selectTag(String tag) {
  setState(() {
    // If the tag is already selected, deselect it
    if (selectedTag == tag) {
      selectedTag = null;
    } else {
      selectedTag = tag;
    }
  });
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Data Annotator"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'reset') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Reset Annotator'),
                    content: Text('Are you sure you want to reset the annotator? This will delete all images, annotations, and trained models.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Reset'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Resetting annotator...')),
                  );
                  final success = await _yoloService.resetAnnotator();
                  if (success) {
                    refreshImages();
                    setState(() {
                      selectedImageUrl = null;
                      selectedImage = null;
                      currentBoxes = [];
                      tagFrequencies = {};
                      selectedTag = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Annotator has been reset.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to reset annotator.'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Reset Annotator', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Row(
        children: [
          ImageViewer(
            key: _imageViewerKey,
            onImageSelected: onImageSelected,
            showBoxes: true,
          ),
          ImageLabellerArea(
            selectedImageUrl: selectedImageUrl,
            currentBoxes: currentBoxes,
            onBoxAdded: onBoxAdded,
            onSaveSuccess: refreshImages,
            tagFrequencies: tagFrequencies,
            selectedTag: selectedTag,
            onTagSelected: selectTag,
            selectedImage: selectedImage,
            onBoxesChanged: (boxes) {
              setState(() {
                currentBoxes = List<BoundingBox>.from(boxes);
              });
            },
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
  final Function()? onSaveSuccess;
  final Map<String, int> tagFrequencies;
  final String? selectedTag;
  final Function(String) onTagSelected;
  final AnnotatedImage? selectedImage;
  final Function(List<BoundingBox>)? onBoxesChanged;

  const ImageLabellerArea({
    super.key,
    this.selectedImageUrl,
    this.currentBoxes = const [],
    this.onBoxAdded,
    this.onSaveSuccess,
    required this.tagFrequencies,
    this.selectedTag,
    required this.onTagSelected,
    this.selectedImage,
    this.onBoxesChanged,
  });

  @override
  State<ImageLabellerArea> createState() => _ImageLabellerAreaState();
}

class _ImageLabellerAreaState extends State<ImageLabellerArea> {
  late TextEditingController _labelController;
  final YoloService _yoloService = YoloService();
  bool _isSaving = false;
  bool _isMarkingComplete = false;
  
  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _markImageComplete() async {
    if (widget.selectedImageUrl == null) return;
    
    setState(() {
      _isMarkingComplete = true;
    });
    
    // Extract just the filename
    String filename = widget.selectedImageUrl!.split('/').last;
    
    // First save annotations with isFullyAnnotated set to true
    final saved = await saveAnnotations(filename, widget.currentBoxes, isFullyAnnotated: true);
    
    if (saved) {
      // Start training using the backend
      final success = await startModelTraining();
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image marked as complete. Model training started!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start model training'), backgroundColor: Colors.red),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark image as complete'), backgroundColor: Colors.red),
      );
    }
    
    setState(() {
      _isMarkingComplete = false;
    });
    
    if (widget.onSaveSuccess != null) {
      widget.onSaveSuccess!();
    }
  }

  Future<void> _saveAnnotations() async {
    if (widget.selectedImageUrl == null) return;
    
    setState(() {
      _isSaving = true;
    });
    
    String filename = widget.selectedImageUrl!;
    
    // Save annotations to backend
    final success = await saveAnnotations(filename, widget.currentBoxes);
    
    setState(() {
      _isSaving = false;
    });
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Annotations saved successfully!')),
      );
      if (widget.onSaveSuccess != null) {
        widget.onSaveSuccess!();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save annotations'), backgroundColor: Colors.red),
      );
    }
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      widget.selectedImageUrl == null 
                          ? "Select an image from the left panel" 
                          : "Selected Image:",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (widget.selectedImageUrl != null) ...[
                      SizedBox(width: 16),
                      DropdownButton<ModelType>(
                        value: _yoloService.currentModelType,
                        items: ModelType.values.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type == ModelType.yolo ? 'YOLO' : 'Few-Shot'),
                          );
                        }).toList(),
                        onChanged: (type) {
                          if (type != null) {
                            setState(() {
                              _yoloService.currentModelType = type;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
                if (widget.selectedImageUrl != null)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AugmentedImagesViewer(
                              imageUrl: widget.selectedImageUrl!,
                              onClose: () => Navigator.pop(context),
                            ),
                          );
                        },
                        icon: Icon(Icons.auto_awesome),
                        label: Text('View Augmented'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isMarkingComplete ? null : _markImageComplete,
                        icon: _isMarkingComplete 
                            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.check_circle),
                        label: Text('Mark Complete'),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: widget.currentBoxes.isEmpty || _isSaving 
                            ? null 
                            : _saveAnnotations,
                        icon: _isSaving 
                            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.save),
                        label: Text('Save Annotations'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (widget.selectedImageUrl != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side - Image and Annotations pane
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // Image area - takes upper part
                          Container(
                            height: screenHeight * 0.5,
                            child: ZoomableImage(
                              imageUrl: widget.selectedImageUrl!,
                              boxes: widget.currentBoxes,
                              selectedTag: widget.selectedTag,
                              onBoxDrawn: (box) {
                                if (widget.onBoxAdded != null) {
                                  // If a tag is selected, use it automatically
                                  if (widget.selectedTag != null) {
                                    final labeledBox = box.copyWith(label: widget.selectedTag!);
                                    widget.onBoxAdded?.call(labeledBox);
                                  } else {
                                    // Otherwise show the label dialog
                                    _showLabelDialog(box);
                                  }
                                }
                              },
                            ),
                          ),
                          SizedBox(height: 16),
                          // Annotations list - takes lower part
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              padding: EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // User Annotations Section
                                  Text(
                                    "User Annotations:",
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: 8),
                                  Expanded(
                                    flex: 1,
                                    child: widget.currentBoxes.isEmpty
                                      ? Center(child: Text("No annotations yet. Draw a box on the image."))
                                      : ListView.builder(
                                          itemCount: widget.currentBoxes.length,
                                          itemBuilder: (context, index) {
                                            final box = widget.currentBoxes[index];
                                            return Card(
                                              margin: EdgeInsets.only(bottom: 8),
                                              child: ListTile(
                                                leading: Icon(
                                                  box.source == AnnotationSource.ai 
                                                    ? Icons.smart_toy
                                                    : Icons.person,
                                                  color: box.isVerified ? Colors.green : Colors.orange,
                                                ),
                                                title: Text(box.label.isEmpty ? "No label" : box.label),
                                                subtitle: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      box.source == AnnotationSource.ai
                                                        ? "AI Prediction (${(box.confidence * 100).toStringAsFixed(1)}% confidence)"
                                                        : "Human Annotation",
                                                    ),
                                                    Text(
                                                      "Coordinates: (${(box.x * 100).toStringAsFixed(1)}%, ${(box.y * 100).toStringAsFixed(1)}%), " +
                                                      "Size: ${(box.width * 100).toStringAsFixed(1)}% × ${(box.height * 100).toStringAsFixed(1)}%",
                                                      style: TextStyle(fontSize: 10),
                                                    ),
                                                  ],
                                                ),
                                                trailing: box.source == AnnotationSource.ai && !box.isVerified
                                                  ? Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          icon: Icon(Icons.check_circle_outline, color: Colors.green),
                                                          onPressed: () {
                                                            setState(() {
                                                              // Create a new box with isVerified set to true
                                                              final verifiedBox = box.copyWith(isVerified: true);
                                                              // Replace the old box with the verified one
                                                              final boxIndex = widget.currentBoxes.indexOf(box);
                                                              if (boxIndex != -1) {
                                                                widget.currentBoxes[boxIndex] = verifiedBox;
                                                              }
                                                            });
                                                            // Save the updated annotations
                                                            _saveAnnotations();
                                                          },
                                                          tooltip: 'Verify prediction',
                                                        ),
                                                        IconButton(
                                                          icon: Icon(Icons.cancel_outlined, color: Colors.red),
                                                          onPressed: () {
                                                            setState(() {
                                                              // Remove the rejected prediction
                                                              widget.currentBoxes.remove(box);
                                                            });
                                                            // Save the updated annotations
                                                            _saveAnnotations();
                                                          },
                                                          tooltip: 'Reject prediction',
                                                        ),
                                                      ],
                                                    )
                                                  : IconButton(
                                                      icon: Icon(Icons.delete_outline, color: Colors.red),
                                                      onPressed: () async {
                                                        setState(() {
                                                          // Remove the annotation
                                                          widget.currentBoxes.remove(box);
                                                          // Notify parent of the change
                                                          widget.onBoxesChanged?.call(widget.currentBoxes);
                                                        });
                                                        // Save the updated annotations
                                                        await _saveAnnotations();
                                                        // Refresh the image list to update the UI
                                                        if (widget.onSaveSuccess != null) {
                                                          widget.onSaveSuccess!();
                                                        }
                                                      },
                                                      tooltip: 'Delete annotation',
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                  ),
                                  
                                  // AI Predictions Section
                                  if (widget.currentBoxes.any((box) => box.source == AnnotationSource.ai))
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(height: 16),
                                        Text(
                                          "AI Predictions:",
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        SizedBox(height: 8),
                                        // YOLO Predictions
                                        if (widget.currentBoxes.any((box) => 
                                            box.source == AnnotationSource.ai && 
                                            box.label.contains("YOLO"))) ...[
                                          Text(
                                            "YOLO Model:",
                                            style: TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                          SizedBox(height: 4),
                                          Expanded(
                                            flex: 1,
                                            child: ListView.builder(
                                              itemCount: widget.currentBoxes.where((box) => 
                                                box.source == AnnotationSource.ai && 
                                                box.label.contains("YOLO")).length,
                                              itemBuilder: (context, index) {
                                                final box = widget.currentBoxes.where((box) => 
                                                  box.source == AnnotationSource.ai && 
                                                  box.label.contains("YOLO")).toList()[index];
                                                return Card(
                                                  margin: EdgeInsets.only(bottom: 8),
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.smart_toy,
                                                      color: Colors.blue,
                                                    ),
                                                    title: Text(box.label.isEmpty ? "No label" : box.label),
                                                    subtitle: Text(
                                                      "YOLO (${(box.confidence * 100).toStringAsFixed(1)}% confidence)",
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                        // ONE-SHOT Predictions
                                        if (widget.currentBoxes.any((box) => 
                                            box.source == AnnotationSource.ai && 
                                            box.label.contains("ONE-SHOT"))) ...[
                                          Text(
                                            "ONE-SHOT Model:",
                                            style: TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                          SizedBox(height: 4),
                                          Expanded(
                                            flex: 1,
                                            child: ListView.builder(
                                              itemCount: widget.currentBoxes.where((box) => 
                                                box.source == AnnotationSource.ai && 
                                                box.label.contains("ONE-SHOT")).length,
                                              itemBuilder: (context, index) {
                                                final box = widget.currentBoxes.where((box) => 
                                                  box.source == AnnotationSource.ai && 
                                                  box.label.contains("ONE-SHOT")).toList()[index];
                                                return Card(
                                                  margin: EdgeInsets.only(bottom: 8),
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons.smart_toy,
                                                      color: Colors.purple,
                                                    ),
                                                    title: Text(box.label.isEmpty ? "No label" : box.label),
                                                    subtitle: Text(
                                                      "ONE-SHOT (${(box.confidence * 100).toStringAsFixed(1)}% confidence)",
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16),
                    // Right side - Frequent Tags panel and Training Status
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          // Add the training status widget here
                          TrainingStatusWidget(),
                          SizedBox(height: 16),
                          Expanded(
                            child: FrequentTagsPanel(
                              tagFrequency: widget.tagFrequencies,
                              onTagSelected: widget.onTagSelected,
                              selectedTag: widget.selectedTag,
                            ),
                          ),
                        ],
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
  Widget _buildConfidenceIndicator(double confidence) {
  Color color;
  if (confidence >= 0.8) {
    color = Colors.green;
  } else if (confidence >= 0.5) {
    color = Colors.orange;
  } else {
    color = Colors.red;
  }
  
  return Container(
    width: 50,
    height: 8,
    child: LinearProgressIndicator(
      value: confidence,
      backgroundColor: Colors.grey.shade300,
      valueColor: AlwaysStoppedAnimation<Color>(color),
    ),
  );
}

Future<void> startTraining() async {
  // Get all images
  List<AnnotatedImage>? images = await fetchLatestImages();
  if (images == null) return;

  // Filter for images that have at least one verified annotation
  List<AnnotatedImage> trainingImages = images.where((img) {
    return img.boundingBoxes.any((box) => box.isVerified);
  }).toList();

  print('Debug - Starting training with ${trainingImages.length} images');
  for (var img in trainingImages) {
    print('Debug - Image: ${img.filepath}');
    print('Debug - Verified boxes: ${img.boundingBoxes.where((box) => box.isVerified).length}');
  }

  if (trainingImages.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No images with verified annotations found. Please verify some annotations first.')),
    );
    return;
  }

  // Start training
  bool success = await startModelTraining();
  if (success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Training started successfully')),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to start training')),
    );
  }
}
}