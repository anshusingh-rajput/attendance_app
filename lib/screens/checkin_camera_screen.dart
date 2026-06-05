import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/face_match_service.dart';
import '../services/mobile_service.dart';
import '../theme/app_theme.dart';

class CheckInCameraScreen extends StatefulWidget {
  final PunchDirection direction;
  const CheckInCameraScreen({super.key, required this.direction});

  @override
  State<CheckInCameraScreen> createState() => _CheckInCameraScreenState();
}

class _CheckInCameraScreenState extends State<CheckInCameraScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  Position? _position;
  String? _locError;
  String? _cameraError;
  bool _busy = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _initFuture = _initCamera();
    _fetchLocation();
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

  Future<void> _fetchLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locError = 'Enable location services');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locError = 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() => _position = pos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locError = 'Location error: $e');
    }
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
    if (_position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for location...')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _statusText = 'Capturing selfie...';
    });

    try {
      final XFile shot = await controller.takePicture();
      final photoFile = File(shot.path);

      bool faceMatched = true;
      double faceScore = 1.0;

      final referenceUrl = await AuthService().getProfilePhotoUrl();

      if (referenceUrl == null || referenceUrl.isEmpty) {
        setState(() => _statusText = 'Saving your photo...');
        final updateResult =
            await MobileService().updateMe(profilePhoto: photoFile);
        if (!mounted) return;
        if (!updateResult.isSuccess) {
          _showError(updateResult.error ?? 'Photo upload failed');
          return;
        }
      } else {
        setState(() => _statusText = 'Verifying face...');
        final matchResult = await FaceMatchService.instance.compareWithUrl(
          selfie: photoFile,
          referenceUrl: referenceUrl,
        );
        if (!mounted) return;

        if (!matchResult.isSuccess) {
          _showError(matchResult.error ?? 'Face verification failed');
          return;
        }

        const double clientThreshold = 0.50;
        final sim = matchResult.similarity ?? 0;
        if (sim < clientThreshold) {
          await _showFaceMismatchDialog(sim);
          return;
        }
        faceMatched = true;
        faceScore = sim;
      }

      setState(() => _statusText =
          widget.direction == PunchDirection.checkIn
              ? 'Checking in...'
              : 'Checking out...');
      final punchResult = await AttendanceService().punch(
        direction: widget.direction,
        selfie: photoFile,
        faceMatchStatus: faceMatched,
        faceMatchScore: faceScore,
      );
      if (!mounted) return;
      if (!punchResult.isSuccess) {
        _showError(punchResult.error ?? 'Punch failed');
        return;
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Capture failed: $e');
    }
  }

  Future<void> _showFaceMismatchDialog(double similarity) async {
    setState(() {
      _busy = false;
      _statusText = '';
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: const Icon(
          Icons.face_retouching_off,
          color: Colors.redAccent,
          size: 56,
        ),
        title: const Text(
          'Face Not Matched',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Your face does not match the registered photo '
          '(${(similarity * 100).toStringAsFixed(0)}% similarity).\n\n'
          'Please try again with proper lighting or contact admin.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.subtitleGrey,
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showError(String msg) async {
    setState(() {
      _busy = false;
      _statusText = '';
    });
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFEF4444),
            size: 36,
          ),
        ),
        title: const Text(
          'Unable to Punch',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.darkText,
          ),
        ),
        content: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.subtitleGrey,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = widget.direction == PunchDirection.checkIn;
    final title = isCheckIn ? 'Check In' : 'Check Out';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 260,
                height: 260,
                child: _buildCameraCircle(),
              ),
              const SizedBox(height: 20),
              const Text(
                'Position your face in the circle',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.subtitleGrey,
                ),
              ),
              const Spacer(),
              _buildLocationCard(),
              const SizedBox(height: 14),
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
                      : const Icon(Icons.camera_alt_rounded),
                  label: Text(
                    _busy
                        ? (_statusText.isEmpty ? 'Please wait...' : _statusText)
                        : 'Capture Selfie',
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
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

  Widget _buildLocationCard() {
    final hasLocation = _position != null;
    final color = hasLocation ? Colors.green : Colors.orange;
    final text = hasLocation
        ? 'Location: ${_position!.latitude.toStringAsFixed(4)}, '
            '${_position!.longitude.toStringAsFixed(4)}'
        : (_locError ?? 'Fetching location...');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderGrey),
      ),
      child: Row(
        children: [
          Icon(
            hasLocation ? Icons.check_circle : Icons.location_searching,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
