import 'dart:convert';

class AnnotatedImage {
  //Filepath where we can access the image
  String filepath;
  DateTime? uploadedDate;
  List<BoundingBox> boundingBoxes;
  bool isFullyAnnotated; // Flag to indicate if the image has been completely annotated

  AnnotatedImage(this.filepath, {
    this.uploadedDate, 
    this.boundingBoxes = const [],
    this.isFullyAnnotated = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'filepath': filepath,
      'uploadedDate': uploadedDate?.toIso8601String(),
      'boundingBoxes': boundingBoxes.map((box) => box.toJson()).toList(),
      'isFullyAnnotated': isFullyAnnotated,
    };
  }

  factory AnnotatedImage.fromJson(Map<String, dynamic> json) {
    return AnnotatedImage(
      json['filepath'],
      uploadedDate: json['uploadedDate'] != null ? DateTime.parse(json['uploadedDate']) : null,
      boundingBoxes: json['boundingBoxes'] != null
          ? List<BoundingBox>.from(json['boundingBoxes'].map((x) => BoundingBox.fromJson(x)))
          : [],
      isFullyAnnotated: json['isFullyAnnotated'] ?? false,
    );
  }
}

enum AnnotationSource {
  human,
  ai
}

class BoundingBox {
  // Coordinates as percentage of the image dimensions (0.0 to 1.0)
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
    return BoundingBox(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      width: json['width'].toDouble(),
      height: json['height'].toDouble(),
      label: json['label'],
      source: json['source'] == 'ai' ? AnnotationSource.ai : AnnotationSource.human,
      confidence: json['confidence']?.toDouble() ?? 1.0,
      isVerified: json['isVerified'] ?? true,
    );
  }
}