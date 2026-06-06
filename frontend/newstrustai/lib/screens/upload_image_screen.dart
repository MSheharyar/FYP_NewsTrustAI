import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../services/api_service.dart';
import './result/result_screen.dart';

class UploadImageScreen extends StatefulWidget {
  const UploadImageScreen({super.key});

  @override
  State<UploadImageScreen> createState() => _UploadImageScreenState();
}

class _UploadImageScreenState extends State<UploadImageScreen> {
  File? _selectedImage;
  Size? _imageNaturalSize; // actual pixel dimensions of picked image
  bool _isScanning = false;
  bool _isVerifying = false;

  final TextEditingController _extractedTextController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _hasExtracted = false;
  List<Rect> _boundingBoxes = [];
  int _blockCount = 0;
  int _wordCount = 0;
  double _recognitionScore = 0.0; // 0–100 based on text density per block

  @override
  void dispose() {
    _extractedTextController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    const maxBytes = 10 * 1024 * 1024; // 10 MB
    final fileSize = await File(image.path).length();
    if (fileSize > maxBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image is too large. Please select an image under 10 MB.')),
        );
      }
      return;
    }

    setState(() {
      _selectedImage = File(image.path);
      _imageNaturalSize = null;
      _hasExtracted = false;
      _boundingBoxes.clear();
      _blockCount = 0;
      _wordCount = 0;
      _recognitionScore = 0.0;
      _extractedTextController.clear();
    });

    _scanImage();
  }

  // Decode natural pixel dimensions — runs in parallel with OCR
  Future<void> _loadImageSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      if (mounted) {
        setState(() {
          _imageNaturalSize = Size(img.width.toDouble(), img.height.toDouble());
        });
      }
    } catch (_) {}
  }

  Future<void> _scanImage() async {
    if (_selectedImage == null) return;
    setState(() => _isScanning = true);

    // Start size decode in parallel — boxes render once both complete
    _loadImageSize(_selectedImage!);

    try {
      final inputImage = InputImage.fromFile(_selectedImage!);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognized = await recognizer.processImage(inputImage);
      await recognizer.close();

      final List<Rect> boxes = [];
      final StringBuffer buffer = StringBuffer();
      int totalChars = 0;

      for (final block in recognized.blocks) {
        boxes.add(block.boundingBox);
        buffer.writeln(block.text);
        totalChars += block.text.trim().length;
      }

      final int blockCount = recognized.blocks.length;
      final String extracted = buffer.toString().trim();
      final int wordCount = extracted.isEmpty
          ? 0
          : extracted.split(RegExp(r'\s+')).where((w) => w.length >= 2).length;

      // Recognition quality: based on average characters per block (text density)
      double score = 0;
      if (blockCount > 0) {
        final avg = totalChars / blockCount;
        if (avg >= 60) {
          score = 95;
        } else if (avg >= 30) {
          score = 80;
        } else if (avg >= 10) {
          score = 60;
        } else {
          score = 30;
        }
      }

      if (!mounted) return;
      setState(() {
        _boundingBoxes = boxes;
        _blockCount = blockCount;
        _wordCount = wordCount;
        _recognitionScore = score;
        _extractedTextController.text =
            extracted.isEmpty ? 'No readable text found.' : extracted;
        _hasExtracted = true;
        _isScanning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OCR failed — please try another image.')),
      );
    }
  }

  Future<void> _verifyExtractedText() async {
    final text = _extractedTextController.text.trim();
    if (text.length < 20 || text == 'No readable text found.') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Text too short to verify')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final result = await ApiService.verifyText(text);
      if (!mounted) return;

      result['ocr_meta'] = {
        'confidence': _recognitionScore,
        'imagePath': _selectedImage?.path ?? '',
        'blocks': _blockCount,
        'words': _wordCount,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            data: result,
            originalText: text,
            usedQuery: text,
            resultMode: 'image',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  // Convert ML Kit bounding box (original image pixels) → display coords (BoxFit.cover)
  Rect _scaleBox(Rect box, double containerW, double containerH) {
    final size = _imageNaturalSize;
    if (size == null) return box;
    final scale = max(containerW / size.width, containerH / size.height);
    final offsetX = (containerW - size.width * scale) / 2;
    final offsetY = (containerH - size.height * scale) / 2;
    return Rect.fromLTWH(
      box.left * scale + offsetX,
      box.top * scale + offsetY,
      box.width * scale,
      box.height * scale,
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _sourceOption(LucideIcons.camera, 'Camera',
                () => _pickImage(ImageSource.camera)),
            _sourceOption(LucideIcons.image, 'Gallery',
                () => _pickImage(ImageSource.gallery)),
          ],
        ),
      ),
    );
  }

  Widget _sourceOption(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.blue[50],
            child: Icon(icon, color: Colors.blue[700], size: 28),
          ),
          const SizedBox(height: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const containerH = 300.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text('Scan Image',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // English-only notice
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info, size: 16, color: Colors.amber[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'OCR supports English/Latin text only. Urdu images are not supported.',
                      style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                    ),
                  ),
                ],
              ),
            ),

            // IMAGE + BOUNDING BOXES
            GestureDetector(
              onTap: _selectedImage == null ? _showImageSourceSheet : null,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final containerW = constraints.maxWidth;
                  return Container(
                    height: containerH,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 8)
                      ],
                    ),
                    child: _selectedImage == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.uploadCloud, size: 48),
                                SizedBox(height: 10),
                                Text('Tap to upload image'),
                              ],
                            ),
                          )
                        : Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.file(
                                  _selectedImage!,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),

                              // Correctly scaled bounding boxes
                              if (_imageNaturalSize != null)
                                ..._boundingBoxes.map((r) {
                                  final s = _scaleBox(r, containerW, containerH);
                                  // Skip boxes fully outside the visible area
                                  if (s.right < 0 ||
                                      s.bottom < 0 ||
                                      s.left > containerW ||
                                      s.top > containerH) {
                                    return const SizedBox.shrink();
                                  }
                                  final l = s.left.clamp(0.0, containerW - 2);
                                  final t = s.top.clamp(0.0, containerH - 2);
                                  return Positioned(
                                    left: l,
                                    top: t,
                                    width: max(2.0, min(s.width, containerW - l)),
                                    height: max(2.0, min(s.height, containerH - t)),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: Colors.orange, width: 2),
                                      ),
                                    ),
                                  );
                                }),

                              // Scanning overlay (only during OCR, not verification)
                              if (_isScanning)
                                Container(
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            if (_hasExtracted) ...[
              // Stats row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statChip(Icons.layers_outlined, '$_blockCount blocks'),
                  _statChip(Icons.text_fields_rounded, '$_wordCount words'),
                  _statChip(Icons.analytics_outlined,
                      '${_recognitionScore.toStringAsFixed(0)}% quality'),
                ],
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _extractedTextController,
                maxLines: 6,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                  hintText: 'Extracted text appears here — you can edit it.',
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _isVerifying ? null : _verifyExtractedText,
                  icon: _isVerifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.shieldCheck),
                  label: Text(_isVerifying
                      ? 'Verifying...'
                      : 'Verify Extracted Text'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],

            // Change image button
            if (_selectedImage != null && !_isScanning) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _showImageSourceSheet,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Change Image'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
