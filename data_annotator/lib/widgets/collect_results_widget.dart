import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CollectResultsWidget extends StatefulWidget {
  const CollectResultsWidget({super.key});

  @override
  State<CollectResultsWidget> createState() => _CollectResultsWidgetState();
}

class _CollectResultsWidgetState extends State<CollectResultsWidget> {
  bool _isCollectModeEnabled = false;
  List<Map<String, dynamic>> _results = [];
  bool _isLoadingResults = false;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadCollectModeStatus();
    _loadResults();
    
    // Start a periodic timer to update results
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadResults());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCollectModeStatus() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:5001/collect_results_settings'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isCollectModeEnabled = data['enabled'] ?? false;
        });
      }
    } catch (e) {
      print('Error loading collect mode status: $e');
    }
  }

  Future<void> _toggleCollectMode(bool enabled) async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:5001/collect_results_settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'enabled': enabled}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _isCollectModeEnabled = enabled;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? 'Collect results mode enabled' : 'Collect results mode disabled'),
            backgroundColor: Colors.green,
          ),
        );
        
        // If enabled, start fresh results collection
        if (enabled) {
          _loadResults();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update collect mode'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadResults() async {
    if (!_isCollectModeEnabled) return;
    
    setState(() {
      _isLoadingResults = true;
    });

    try {
      final response = await http.get(Uri.parse('http://localhost:5001/export_results'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _results = List<Map<String, dynamic>>.from(data['results']);
          _isLoadingResults = false;
        });
      }
    } catch (e) {
      print('Error loading results: $e');
      setState(() {
        _isLoadingResults = false;
      });
    }
  }

  Future<void> _clearResults() async {
    try {
      final response = await http.post(Uri.parse('http://localhost:5001/clear_results'));
      if (response.statusCode == 200) {
        setState(() {
          _results.clear();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Results cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear results'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showResultsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Collected Results Data'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _isLoadingResults
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(child: Text('No results data collected yet'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Training #${index + 1} - ${result['model_type'].toString().toUpperCase()}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildResultRow('Images Labeled', '${result['total_images_labeled']}'),
                                  _buildResultRow('Overall Confidence', '${(result['overall_confidence'] * 100).toStringAsFixed(1)}%'),
                                  _buildResultRow('Confidence Range', '${(result['confidence_range'] * 100).toStringAsFixed(1)}%'),
                                  if (result['time_since_last_training'] != null)
                                    _buildResultRow('Time Since Last', '${_formatDuration(result['time_since_last_training'])}'),
                                  _buildResultRow('Total Time Elapsed', '${_formatDuration(result['total_time_elapsed'])}'),
                                  _buildResultRow('Timestamp', result['timestamp'].toString().split('.')[0]),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (_results.isNotEmpty) ...[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _exportResultsAsJson();
                },
                child: const Text('Export JSON'),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${secs}s';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  void _exportResultsAsJson() {
    final jsonString = json.encode({
      'collect_results_data': _results,
      'exported_at': DateTime.now().toIso8601String(),
      'total_records': _results.length,
    });
    
    // In a real app, you'd save this to a file or copy to clipboard
    // For now, just show it in a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Results'),
        content: SingleChildScrollView(
          child: SelectableText(
            jsonString,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: _isCollectModeEnabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Collect Results',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Toggle collect mode
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isCollectModeEnabled 
                        ? 'Data collection is active' 
                        : 'Data collection is disabled',
                    style: TextStyle(
                      color: _isCollectModeEnabled ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
                Switch(
                  value: _isCollectModeEnabled,
                  onChanged: _toggleCollectMode,
                ),
              ],
            ),
            
            if (_isCollectModeEnabled) ...[
              const SizedBox(height: 16),
              
              // Results summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Training Sessions: ${_results.length}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (_results.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Latest: ${_results.last['model_type'].toString().toUpperCase()} model',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      Text(
                        'Confidence: ${(_results.last['overall_confidence'] * 100).toStringAsFixed(1)}%',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showResultsDialog,
                      icon: const Icon(Icons.visibility, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: const Text('View Data'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _results.isNotEmpty ? _clearResults : null,
                      icon: const Icon(Icons.clear, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: const Text('Clear'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade100,
                        foregroundColor: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
} 