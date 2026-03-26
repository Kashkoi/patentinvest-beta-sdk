import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';

import '../models/beta_report.dart';
import '../report_submitter.dart';

/// Full-screen dialog for submitting a beta tester report.
class ReportDialog extends StatefulWidget {
  const ReportDialog({
    super.key,
    required this.reportSubmitter,
    required this.screenshotController,
  });

  final ReportSubmitter reportSubmitter;
  final ScreenshotController screenshotController;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _commentCtrl = TextEditingController();
  ReportCategory _category = ReportCategory.general;
  ReportSeverity _severity = ReportSeverity.medium;
  final List<String> _screenshotPaths = [];
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureScreen() async {
    try {
      final image = await widget.screenshotController.capture();
      if (image == null) return;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/beta_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(image);

      setState(() => _screenshotPaths.add(path));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to capture screenshot')),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile != null) {
      setState(() => _screenshotPaths.add(xFile.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_screenshotPaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one screenshot is required')),
      );
      return;
    }

    setState(() => _submitting = true);

    final ok = await widget.reportSubmitter.submit(
      commentText: _commentCtrl.text,
      screenshotPaths: _screenshotPaths,
      category: _category,
      severity: _severity,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submission failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compliance = widget.reportSubmitter.todayCompliance;

    return Scaffold(
      appBar: AppBar(title: const Text('Submit Beta Report')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Daily stats bar
              Card(
                color: compliance.isQualifiedDay
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatChip(
                        label: 'Time',
                        value: '${compliance.totalActiveMinutes}/60 min',
                        done: compliance.meetsTimeRequirement,
                      ),
                      _StatChip(
                        label: 'Reports',
                        value: '${compliance.reportsSubmitted}/5',
                        done: compliance.meetsReportRequirement,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Category
              DropdownButtonFormField<ReportCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: ReportCategory.values.map((c) {
                  return DropdownMenuItem(
                    value: c,
                    child: Text(_categoryLabel(c)),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 12),

              // Severity
              DropdownButtonFormField<ReportSeverity>(
                initialValue: _severity,
                decoration: const InputDecoration(
                  labelText: 'Severity',
                  border: OutlineInputBorder(),
                ),
                items: ReportSeverity.values.map((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(s.name),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _severity = v!),
              ),
              const SizedBox(height: 12),

              // Comment
              TextFormField(
                controller: _commentCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Describe the issue or feedback',
                  hintText: 'Minimum 20 characters',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 20) {
                    return 'Please enter at least 20 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Screenshots
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _captureScreen,
                    icon: const Icon(Icons.screenshot),
                    label: const Text('Capture Screen'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_screenshotPaths.isEmpty)
                const Text(
                  'At least 1 screenshot required',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _screenshotPaths.asMap().entries.map((e) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(e.value),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _screenshotPaths.removeAt(e.key)),
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.red,
                            child:
                                Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Submit
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(ReportCategory c) {
    switch (c) {
      case ReportCategory.bug:
        return 'Bug';
      case ReportCategory.uxFeedback:
        return 'UX Feedback';
      case ReportCategory.featureRequest:
        return 'Feature Request';
      case ReportCategory.performance:
        return 'Performance';
      case ReportCategory.accessibility:
        return 'Accessibility';
      case ReportCategory.general:
        return 'General';
    }
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.done,
  });

  final String label;
  final String value;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done ? Colors.green : Colors.orange,
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
