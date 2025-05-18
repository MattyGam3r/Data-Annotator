import 'dart:convert';

class AnnotatedImage {
  //Filepath where we can access the image
  final String filepath;
  final DateTime? uploadedDate;  // Make this final
  final List<BoundingBox> boundingBoxes;
  final List<BoundingBox> yoloPredictions;
  final List<BoundingBox> oneShotPredictions;
  final bool isFullyAnnotated; // Flag to indicate if the image has been completely annotated
  final double? uncertaintyScore;  // Add uncertainty score field

  AnnotatedImage(
    this.filepath, {
    this.uploadedDate,
    List<BoundingBox>? boundingBoxes,
    List<BoundingBox>? yoloPredictions,
    List<BoundingBox>? oneShotPredictions,
    this.isFullyAnnotated = false,
    this.uncertaintyScore,
  }) : boundingBoxes = boundingBoxes ?? [],
       yoloPredictions = yoloPredictions ?? [],
       oneShotPredictions = oneShotPredictions ?? [];

  // Add copyWith method
  AnnotatedImage copyWith({
    String? filepath,
    DateTime? uploadedDate,
    List<BoundingBox>? boundingBoxes,
    List<BoundingBox>? yoloPredictions,
    List<BoundingBox>? oneShotPredictions,
    bool? isFullyAnnotated,
    double? uncertaintyScore,
  }) {
    return AnnotatedImage(
      filepath ?? this.filepath,
      uploadedDate: uploadedDate ?? this.uploadedDate,
      boundingBoxes: boundingBoxes ?? this.boundingBoxes,
      yoloPredictions: yoloPredictions ?? this.yoloPredictions,
      oneShotPredictions: oneShotPredictions ?? this.oneShotPredictions,
      isFullyAnnotated: isFullyAnnotated ?? this.isFullyAnnotated,
      uncertaintyScore: uncertaintyScore ?? this.uncertaintyScore,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filepath,
      'uploadedDate': uploadedDate?.toIso8601String(),
      'annotations': boundingBoxes.map((box) => box.toJson()).toList(),
      'yolo_predictions': yoloPredictions.map((box) => box.toJson()).toList(),
      'one_shot_predictions': oneShotPredictions.map((box) => box.toJson()).toList(),
      'isFullyAnnotated': isFullyAnnotated,
      'uncertainty_score': uncertaintyScore,
    };
  }

  factory AnnotatedImage.fromJson(Map<String, dynamic> json) {
    List<BoundingBox> boxes = [];
    List<BoundingBox> yoloBoxes = [];
    List<BoundingBox> oneShotBoxes = [];
    
    if (json['annotations'] != null) {
      boxes = (json['annotations'] as List)
          .map((box) => BoundingBox.fromJson(box))
          .toList();
    }
    
    if (json['yolo_predictions'] != null) {
      yoloBoxes = (json['yolo_predictions'] as List)
          .map((box) => BoundingBox.fromJson(box))
          .toList();
    }
    
    if (json['one_shot_predictions'] != null) {
      oneShotBoxes = (json['one_shot_predictions'] as List)
          .map((box) => BoundingBox.fromJson(box))
          .toList();
    }

    return AnnotatedImage(
      json['filename'],
      uploadedDate: json['uploadedDate'] != null ? DateTime.parse(json['uploadedDate']) : null,
      boundingBoxes: boxes,
      yoloPredictions: yoloBoxes,
      oneShotPredictions: oneShotBoxes,
      isFullyAnnotated: json['isFullyAnnotated'] ?? false,
      uncertaintyScore: json['uncertainty_score']?.toDouble(),
    );
  }
}

enum AnnotationSource {
  human,
  ai
}

class BoundingBox {
  // Coordinates as percentage of the image dimensions (0.0 to 1.0)
  // x, y represent the top-left corner of the bounding box
  final double x;
  final double y;
  final double width;
  final double height;
  final String label;
  final AnnotationSource source; // Track whether this was created by human or AI
  final double confidence; // Confidence score of the detection (for AI annotations)
  final bool isVerified; // Whether a human has verified this annotation

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
    this.source = AnnotationSource.human,
    this.confidence = 1.0, // Human annotations have 100% confidence by default
    this.isVerified = true, // Human annotations are verified by default
  });

  // Clone with new properties
  BoundingBox copyWith({
    String? label,
    AnnotationSource? source,
    double? confidence,
    bool? isVerified,
  }) {
    return BoundingBox(
      x: x,
      y: y,
      width: width,
      height: height,
      label: label ?? this.label,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      isVerified: isVerified ?? this.isVerified,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'label': label,
      'source': source.toString().split('.').last, // Store as string: "human" or "ai"
      'confidence': confidence,
      'isVerified': isVerified,
    };
  }

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    // Determine if this is an AI prediction
    bool isAI = json['source'] == 'ai' || json['source'] == 'AI';
    
    return BoundingBox(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      width: json['width'].toDouble(),
      height: json['height'].toDouble(),
      label: json['label'],
      source: isAI ? AnnotationSource.ai : AnnotationSource.human,
      confidence: json['confidence']?.toDouble() ?? (isAI ? 0.0 : 1.0),
      isVerified: json['isVerified'] ?? !isAI,  // AI predictions are unverified by default
    );
  }
}