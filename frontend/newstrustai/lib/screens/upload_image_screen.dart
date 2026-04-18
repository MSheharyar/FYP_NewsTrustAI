import 'dart:io';
import 'dart:math';

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
  bool _isScanning = false;

  final TextEditingController _extractedTextController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _hasExtracted = false;

  // ✅ OCR data
  List<Rect> _boundingBoxes = [];
  double _ocrConfidence = 0.0; // 0–100

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
      _hasExtracted = false;
      _boundingBoxes.clear();
      _ocrConfidence = 0.0;
      _extractedTextController.clear();
    });

    _scanImage();
  }

  // ==========================
  // REAL OCR WITH BOXES + CONFIDENCE
  // ==========================
  Future<void> _scanImage() async {
    if (_selectedImage == null) return;

    setState(() => _isScanning = true);

    try {
      final inputImage = InputImage.fromFile(_selectedImage!);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

      final RecognizedText recognizedText =
          await recognizer.processImage(inputImage);

      await recognizer.close();

      final List<Rect> boxes = [];
      final StringBuffer buffer = StringBuffer();

      int totalBlocks = 0;
      int confidentBlocks = 0;

      for (final block in recognizedText.blocks) {
        boxes.add(block.boundingBox);
      
        buffer.writeln(block.text);
        totalBlocks++;

        // ML Kit doesn't give confidence directly → estimate via length
        if (block.text.trim().length > 15) {
          confidentBlocks++;
        }
      }

      final confidence =
          totalBlocks == 0 ? 0.0 : (confidentBlocks / totalBlocks) * 100;

      if (!mounted) return;

      setState(() {
        _boundingBoxes = boxes;
        _ocrConfidence = confidence.clamp(0, 100);
        _extractedTextController.text =
            buffer.toString().trim().isEmpty
                ? "No readable text found."
                : buffer.toString().trim();
        _hasExtracted = true;
        _isScanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OCR failed")),
      );
    }
  }

  // ==========================
  // VERIFY OCR TEXT
  // ==========================
  Future<void> _verifyExtractedText() async {
    final text = _extractedTextController.text.trim();

    if (text.length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Text too short to verify")),
      );
      return;
    }

    setState(() => _isScanning = true);

    try {
      final result = await ApiService.verifyText(text);

      if (!mounted) return;

      // 🔥 Attach OCR metadata into rawResult
      result["ocr_meta"] = {
        "confidence": _ocrConfidence,
        "imagePath": _selectedImage?.path ?? "",
        "blocks": _boundingBoxes.length,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            data: result,
            originalText: text,
            usedQuery: text,
            resultMode: "image",
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Verification failed")),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ==========================
  // IMAGE SOURCE SHEET
  // ==========================
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
            _sourceOption(
              LucideIcons.camera,
              "Camera",
              () => _pickImage(ImageSource.camera),
            ),
            _sourceOption(
              LucideIcons.image,
              "Gallery",
              () => _pickImage(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceOption(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
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

  // ==========================
  // UI
  // ==========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("Scan Image", style: TextStyle(fontWeight: FontWeight.bold)),
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
            // IMAGE + BOXES
            GestureDetector(
              onTap: _selectedImage == null ? _showImageSourceSheet : null,
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 8)
                  ],
                ),
                child: _selectedImage == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(LucideIcons.uploadCloud, size: 48),
                            SizedBox(height: 10),
                            Text("Tap to upload image"),
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

                          // BOUNDING BOXES
                          ..._boundingBoxes.map(
                            (r) => Positioned(
                              left: r.left,
                              top: r.top,
                              width: max(1, r.width),
                              height: max(1, r.height),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.orange, width: 2),
                                ),
                              ),
                            ),
                          ),

                          if (_isScanning)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 20),

            if (_hasExtracted) ...[
              Text(
                "OCR Confidence: ${_ocrConfidence.toStringAsFixed(0)}%",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: _extractedTextController,
                maxLines: 6,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: _verifyExtractedText,
                  icon: const Icon(LucideIcons.shieldCheck),
                  label: const Text("Verify Extracted Text"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}