// lib/body_posture/camera/pose_detection_camera_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';
import '/body_posture/camera/pose_painter.dart';

class PoseDetectionCameraScreen extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    List<PoseLandmark> landmarks,
    Size cameraViewSize,
    bool isFrontCamera,
  )
  builder;

  const PoseDetectionCameraScreen({super.key, required this.builder});

  @override
  State<PoseDetectionCameraScreen> createState() =>
      _PoseDetectionCameraScreenState();
}

class _PoseDetectionCameraScreenState extends State<PoseDetectionCameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  List<PoseLandmark> _landmarks = [];
  bool _isFrontCamera = false;
  bool _isProcessing = false;
  bool _isSwitchingCamera = false;
  String? _errorMessage;

  // Landmark smoothing
  final Map<PoseLandmarkType, List<Offset>> _landmarkHistory = {};
  final int _smoothingWindowSize = 8;

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.accurate,
    ),
  );

  @override
  void initState() {
    super.initState();
    _initializeCameras();
  }

  /// 🎯 **FIXED** - Ensures camera initialization is synchronous and robust.
  Future<void> _initializeCameras() async {
    // 1. Initial State Update (Clear previous error/status)
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _isSwitchingCamera = true;
      });
    }

    try {
      // 2. Discover cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // 3. Select camera
      final cameraIndex = _isFrontCamera && _cameras.length > 1 ? 1 : 0;
      final CameraDescription selectedCamera = _cameras[cameraIndex];

      // 4. Create and Initialize Controller
      final CameraController newController = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
      );

      // CRITICAL AWAIT: Wait for the new camera instance to initialize.
      await newController.initialize();

      if (!mounted) return;

      // 5. Start image stream
      newController.startImageStream((CameraImage image) {
        // Only process if not currently busy and not switching
        if (!_isProcessing && !_isSwitchingCamera) {
          _isProcessing = true;
          _processCameraImage(image);
        }
      });

      // 6. Final success state update
      if (mounted) {
        setState(() {
          _controller = newController;
          _isSwitchingCamera = false;
        });
      }
    } on CameraException catch (e) {
      debugPrint('Camera initialization failed: ${e.code} - ${e.description}');
      if (mounted) {
        setState(() {
          _errorMessage = 'Camera initialization error: ${e.description}';
          _isSwitchingCamera = false;
        });
      }
    } catch (e) {
      debugPrint('General camera error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'General error: ${e.toString()}';
          _isSwitchingCamera = false;
        });
      }
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    final InputImageRotation imageRotation = _isFrontCamera
        ? InputImageRotation.rotation270deg
        : InputImageRotation.rotation90deg;

    final int imageWidth = cameraImage.width;
    final int imageHeight = cameraImage.height;

    final InputImage inputImage = InputImage.fromBytes(
      bytes: _concatenatePlanes(cameraImage),
      metadata: InputImageMetadata(
        size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
        rotation: imageRotation,
        format: InputImageFormat.nv21,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      ),
    );

    try {
      final poses = await _poseDetector.processImage(inputImage);
      if (mounted) {
        final List<PoseLandmark> currentRawLandmarks = poses.isNotEmpty
            ? poses.first.landmarks.values.toList()
            : [];

        final List<PoseLandmark> smoothedLandmarks = [];

        final currentLandmarkTypes = currentRawLandmarks
            .map((lm) => lm.type)
            .toSet();

        final keysToRemove = _landmarkHistory.keys
            .where((type) => !currentLandmarkTypes.contains(type))
            .toList();

        // 🎯 LINT FIX (Line 213): Added curly braces to the for-loop body
        for (final type in keysToRemove) {
          _landmarkHistory.remove(type);
        }

        for (final rawLm in currentRawLandmarks) {
          _landmarkHistory
              .putIfAbsent(rawLm.type, () => [])
              .add(Offset(rawLm.x, rawLm.y));

          if (_landmarkHistory[rawLm.type]!.length > _smoothingWindowSize) {
            _landmarkHistory[rawLm.type]!.removeAt(0);
          }

          double sumX = 0;
          double sumY = 0;
          for (final histOffset in _landmarkHistory[rawLm.type]!) {
            sumX += histOffset.dx;
            sumY += histOffset.dy;
          }
          final double smoothedX = sumX / _landmarkHistory[rawLm.type]!.length;
          final double smoothedY = sumY / _landmarkHistory[rawLm.type]!.length;

          smoothedLandmarks.add(
            PoseLandmark(
              type: rawLm.type,
              x: smoothedX,
              y: smoothedY,
              z: rawLm.z,
              likelihood: rawLm.likelihood,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _landmarks = smoothedLandmarks;
          });
        }
      }
    } catch (e) {
      debugPrint('Pose detection error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Uint8List _concatenatePlanes(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  /// 🔄 **FIXED** - Tighter synchronization to prevent race conditions during switch.
  void _switchCamera() async {
    // Check if controller is initialized, already switching, or only one camera exists
    if (_controller == null || _isSwitchingCamera || _cameras.length < 2) {
      return;
    }

    // 1. Set switching state immediately to prevent rapid double-taps
    if (mounted) {
      setState(() {
        _isSwitchingCamera = true;
        _errorMessage = null; // Clear previous errors
      });
    }

    try {
      // CRITICAL AWAITS: Ensure the current camera is fully closed before proceeding.
      await _controller?.stopImageStream();
      await _controller?.dispose();
      _controller = null;
      _landmarkHistory.clear();

      // 2. Flip the camera and re-initialize
      _isFrontCamera = !_isFrontCamera;

      // Call the robust initialization function
      await _initializeCameras();
    } on CameraException catch (e) {
      debugPrint(
        'Camera switch failed with exception: ${e.code} - ${e.description}',
      );
      if (mounted) {
        setState(() {
          _errorMessage = 'Switch error: ${e.description}';
          _isSwitchingCamera = false;
        });
      }
    } catch (e) {
      debugPrint('Camera switch failed: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to switch camera';
          _isSwitchingCamera = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- Error UI ---
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: Text(
            _errorMessage!,
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // --- Loading UI ---
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isSwitchingCamera) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              // Show a specific message while switching vs initial load
              Text(
                'Camera is ${_isSwitchingCamera ? 'switching' : 'initializing'}...',
              ),
            ],
          ),
        ),
      );
    }

    // --- Main Camera View UI ---
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double cameraViewHeight = screenHeight * 0.4;

    return Scaffold(
      // The Scaffold does not have 'const' which is good.
      appBar: AppBar(
        // The AppBar does not have 'const' which is good.
        title: const Text('Exercise Tracker'),
        actions: [
          // The IconButton does not have 'const' which is required for the ternary 'onPressed'
          IconButton(
            icon: Icon(_isFrontCamera ? Icons.camera_rear : Icons.camera_front),
            // Line 297 is now dynamic and safe:
            onPressed: _isSwitchingCamera ? null : _switchCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            width: screenWidth,
            height: cameraViewHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),
                CustomPaint(
                  painter: PosePainter(
                    landmarks: _landmarks,
                    cameraSize: Size(screenWidth, cameraViewHeight),
                    imageSize: Size(
                      _controller!.value.previewSize!.height,
                      _controller!.value.previewSize!.width,
                    ),
                    isFrontCamera: _isFrontCamera,
                  ),
                  child: SizedBox(width: screenWidth, height: cameraViewHeight),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.builder(
              context,
              _landmarks,
              Size(screenWidth, cameraViewHeight),
              _isFrontCamera,
            ),
          ),
        ],
      ),
    );
  }
}
