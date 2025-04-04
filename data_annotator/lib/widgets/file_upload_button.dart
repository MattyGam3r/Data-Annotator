import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../http-requests.dart';

class FileUploadButton extends StatefulWidget {
  const FileUploadButton({super.key, this.onUploadComplete});  
  final VoidCallback? onUploadComplete;

  @override
  State<FileUploadButton> createState() => _FileUploadButtonState();
}

class _FileUploadButtonState extends State<FileUploadButton> {
  
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      child: Text('Upload Image(s)'),
      onPressed: () async {
        FilePickerResult? picked = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );

        if (picked != null) {
          uploadImages(picked.files).then((_) => widget.onUploadComplete!());
        }
        else {
          //The user canceled the file picker
        }
      },
    );
  }
}