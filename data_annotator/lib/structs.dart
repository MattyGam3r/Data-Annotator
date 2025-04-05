import 'dart:convert';

class AnnotatedImage {
  //Filepath where we can access the image
  String filepath;
  DateTime? uploadedDate;
  List<BoundingBox> boundingBoxes;

  AnnotatedImage(this.filepath, {this.uploadedDate, this.boundingBoxes = const []});

  Map<String, dynamic> toJson() {
    return {
      'filepath': filepath,
      'uploadedDate': uploadedDate?.toIso8601String(),
      'boundingBoxes': boundingBoxes.map((box) => box.toJson()).toList(),
    };
  }

  factory AnnotatedImage.fromJson(Map<String, dynamic> json) {
    return AnnotatedImage(
      json['filepath'],
      uploadedDate: json['uploadedDate'] != null ? DateTime.parse(json['uploadedDate']) : null,
      boundingBoxes: json['boundingBoxes'] != null
          ? List<BoundingBox>.from(json['boundingBoxes'].map((x) => BoundingBox.fromJson(x)))
          : [],
    );
  }
}

class BoundingBox {
  // Coordinates as percentage of the image dimensions (0.0 to 1.0)
  final double x;
  final double y;
  final double width;
  final double height;
  final String label;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
  });

  // Clone with a new label
  BoundingBox copyWith({String? label}) {
    return BoundingBox(
      x: x,
      y: y,
      width: width,
      height: height,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'label': label,
    };
  }

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      width: json['width'].toDouble(),
      height: json['height'].toDouble(),
      label: json['label'],
    );
  }
}