import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FrequentTagsPanel extends StatefulWidget {
  final Map<String, int> tagFrequency;
  final Function(String) onTagSelected;
  final String? selectedTag;

  const FrequentTagsPanel({
    Key? key,
    required this.tagFrequency,
    required this.onTagSelected,
    this.selectedTag,
  }) : super(key: key);

  @override
  State<FrequentTagsPanel> createState() => _FrequentTagsPanelState();
}

class _FrequentTagsPanelState extends State<FrequentTagsPanel> {
  @override
  Widget build(BuildContext context) {
    // Get top 10 frequent tags sorted by frequency
    final sortedTags = widget.tagFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final top10Tags = sortedTags.take(10).toList();
    
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Frequent Tags",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (widget.selectedTag != null)
                InkWell(
                  onTap: () => widget.onTagSelected(widget.selectedTag!), // This will deselect
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      children: [
                        Text('Clear', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        Icon(Icons.close, size: 16, color: Colors.grey.shade700),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          if (top10Tags.isEmpty)
            Text("No tags yet. Create some annotations.")
          else
            // Make the tags list scrollable with constrained height
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 300, // Maximum height before scrolling
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(top10Tags.length, (index) {
                    final tag = top10Tags[index];
                    final isSelected = widget.selectedTag == tag.key;
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: InkWell(
                        onTap: () => widget.onTagSelected(tag.key),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 10, 
                                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tag.key,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                '${tag.value}',
                                style: TextStyle(
                                  color: isSelected ? Colors.white70 : Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              if (isSelected)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          SizedBox(height: 16),
          Text(
            widget.selectedTag == null 
                ? "Press 1-0 keys to select tags" 
                : "Press ${widget.hashCode} key again to deselect",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}