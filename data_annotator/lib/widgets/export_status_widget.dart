import 'package:flutter/material.dart';

class ExportStatusWidget extends StatelessWidget {
  final String message;
  final bool isExporting;
  
  const ExportStatusWidget({
    Key? key,
    required this.message,
    required this.isExporting,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: isExporting ? Colors.blue[100] : Colors.green[100],
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isExporting)
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(right: 8.0),
              child: const CircularProgressIndicator(
                strokeWidth: 2.0,
              ),
            ),
          if (!isExporting)
            Container(
              margin: const EdgeInsets.only(right: 8.0),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 16,
              ),
            ),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
} 