import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/mobile_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class RegistrationSelfieScreen extends StatefulWidget {
  final String token;
  const RegistrationSelfieScreen({super.key, required this.token});

  @override
  State<RegistrationSelfieScreen> createState() =>
      _RegistrationSelfieScreenState();
}

class _RegistrationSelfieScreenState extends State<RegistrationSelfieScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  String? _cameraError;
  bool _busy = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _initFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras()
          .timeout(const Duration(seconds: 10));
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera detected on this device');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = e.toString());
    }
  }

  Future<void> _retryCamera() async {
    setState(() {
      _cameraError = null;
      _initFuture = _initCamera();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onCapture() async {
    if (_busy) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() {
      _busy = true;
      _statusText = 'Capturing selfie...';
    });

    try {
      final XFile shot = await controller.takePicture();
      final photoFile = File(shot.path);

      setState(() => _statusText = 'Saving as reference photo...');
      final result =
          await MobileService().updateMe(profilePhoto: photoFile);
      if (!mounted) return;

      if (!result.isSuccess) {
        _showError(result.error ?? 'Upload failed');
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(token: widget.token),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Capture failed: $e');
    }
  }

  void _showError(String msg) {
    setState(() {
      _busy = false;
      _statusText = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.darkText,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Set Up Your Face',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 6),
                const Text(
                  'Welcome! Please take a clear selfie.\n'
                  'This will be your reference photo for attendance verification.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.subtitleGrey,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 260,
                  height: 260,
                  child: _buildCameraCircle(),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Position your face clearly in the circle',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.subtitleGrey,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _onCapture,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      _busy
                          ? (_statusText.isEmpty
                              ? 'Please wait...'
                              : _statusText)
                          : 'Save & Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraCircle() {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        final controller = _controller;
        Widget content;
        if (_cameraError != null) {
          content = Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off,
                    color: Colors.redAccent, size: 36),
                const SizedBox(height: 8),
                Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  maxLines: 5,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _retryCamera,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        } else if (controller == null || !controller.value.isInitialized) {
          content = const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text(
                  'Loading camera...',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          );
        } else {
          content = CameraPreview(controller);
        }
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primaryBlue, width: 4),
            color: const Color(0xFFEFEFEF),
          ),
          child: ClipOval(child: content),
        );
      },
    );
  }
}
