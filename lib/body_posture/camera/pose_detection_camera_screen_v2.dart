import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

// lib/body_posture/camera/pose_detection_camera_screen_v2.dart
// PoseDetectionCameraScreenV2 State with integrated PosePainter for Full-Screen
class PoseDetectionCameraScreenV2 extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    List<PoseLandmark> landmarks,
    Size cameraViewSize,
    bool isFrontCamera,
  ) builder;
  final bool initialIsFrontCamera;
  final Widget? appBar;

  const PoseDetectionCameraScreenV2({
    super.key,
    required this.builder,
    this.initialIsFrontCamera = true,
    this.appBar,
  });

  @override
  State<PoseDetectionCameraScreenV2> createState() =>
      PoseDetectionCameraScreenV2State();
}

class PoseDetectionCameraScreenV2State
    extends State<PoseDetectionCameraScreenV2> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  List<PoseLandmark> _landmarks = [];
  late bool _isFrontCamera;
  bool _isProcessing = false;
  bool _isSwitchingCamera = false;
  String? _errorMessage;

  // Smoothing
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
    _isFrontCamera = widget.initialIsFrontCamera;
    _initializeCameras();
  }

  Future<void> _initializeCameras() async {
    try {
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
        _isSwitchingCamera = true;
      });

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      final cameraIndex = _isFrontCamera
          ? _cameras.indexWhere(
              (camera) => camera.lensDirection == CameraLensDirection.front)
          : _cameras.indexWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back);

      final CameraDescription selectedCamera =
          cameraIndex != -1 ? _cameras[cameraIndex] : _cameras.first;

      // Note: ResolutionPreset.low is often used to improve performance, but may reduce detection accuracy.
      final CameraController newController = CameraController(
        selectedCamera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await newController.initialize();

      if (!mounted) return;

      newController.startImageStream((CameraImage image) {
        if (!_isProcessing && !_isSwitchingCamera) {
          _isProcessing = true;
          _processCameraImage(image).then((_) {
            _isProcessing = false;
          });
        }
      });

      setState(() {
        _controller = newController;
        _isSwitchingCamera = false;
      });
    } catch (e) {
      debugPrint('Camera initialization failed: $e');
      setState(() {
        _errorMessage = 'Camera error: ${e.toString()}';
        _isSwitchingCamera = false;
      });
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    final InputImage inputImage = InputImage.fromBytes(
      bytes: _concatenatePlanes(cameraImage),
      metadata: InputImageMetadata(
        size:
            Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        // The rotation is set based on how the camera frame is presented
        rotation: _isFrontCamera
            ? InputImageRotation.rotation270deg
            : InputImageRotation.rotation90deg,
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

        final List<PoseLandmark> smoothedLandmarks =
            _smoothLandmarks(currentRawLandmarks);

        setState(() {
          _landmarks = smoothedLandmarks;
        });
      }
    } catch (e) {
      debugPrint('Pose detection error: $e');
    }
  }

  List<PoseLandmark> _smoothLandmarks(List<PoseLandmark> currentRawLandmarks) {
    final List<PoseLandmark> smoothedLandmarks = [];
    final currentLandmarkTypes =
        currentRawLandmarks.map((lm) => lm.type).toSet();

    // Clean up history for landmarks that are no longer detected
    final keysToRemove = _landmarkHistory.keys
        .where((type) => !currentLandmarkTypes.contains(type))
        .toList();
    for (final type in keysToRemove) {
      _landmarkHistory.remove(type);
    }

    // Apply simple moving average smoothing
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
    return smoothedLandmarks;
  }

  Uint8List _concatenatePlanes(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  void switchCamera() async {
    if (_controller == null || _isSwitchingCamera) return;

    setState(() {
      _isSwitchingCamera = true;
    });

    try {
      await _controller?.stopImageStream();
      await _controller?.dispose();

      setState(() {
        _controller = null;
        _isFrontCamera = !_isFrontCamera;
        _landmarkHistory.clear(); // Clear history after camera switch
      });

      await _initializeCameras();
    } catch (e) {
      debugPrint('Camera switch failed: $e');
      setState(() {
        _errorMessage = 'Failed to switch camera';
        _isSwitchingCamera = false;
      });
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

    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isSwitchingCamera) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Initializing camera...'),
            ],
          ),
        ),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    // This is the size of the image/frame that the ML model processed (previewSize)
    // Note: The camera preview size's height/width is swapped due to rotation in the stream.
    final Size previewSize = Size(
      _controller!.value.previewSize!.height,
      _controller!.value.previewSize!.width,
    );

    // This is the aspect ratio of the camera's feed (width / height)
    final double cameraAspectRatio = _controller!.value.aspectRatio;

    // The size of the full screen for the CustomPaint widget's canvas
    final Size canvasSize = Size(screenWidth, screenHeight);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: widget.appBar ?? Container(),
      ),
      body: Stack(
        children: [
          // CameraPreview fills the screen while maintaining its aspect ratio
          // This creates a "fill/cover" effect, potentially cropping the camera edges.
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: cameraAspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),
          // CustomPaint is a Stack overlay, covering the whole screen
          CustomPaint(
            painter: PosePainter(
              landmarks: _landmarks,
              previewSize: previewSize,
              isFrontCamera: _isFrontCamera,
              aspectRatio: cameraAspectRatio,
            ),
            child: SizedBox(
              width: screenWidth,
              height: screenHeight,
            ),
          ),
          // Widget Builder for UI overlay (e.g., buttons, progress)
          widget.builder(
            context,
            _landmarks,
            canvasSize,
            _isFrontCamera,
          ),
        ],
      ),
    );
  }
}

// =================================================================================================
// PosePainter Class with Corrected Scaling and Mirroring for Full-Screen View
// The logic here correctly maps normalized landmarks to the 'AspectCover' screen-filling camera view.
// =================================================================================================

// =================================================================================================
// PosePainter Class with Corrected Scaling and Mirroring for Full-Screen View
// =================================================================================================

class PosePainter extends CustomPainter {
  final List<PoseLandmark> landmarks;
  // Dimensions of the original image frame that ML Kit processed (already swapped height/width)
  final Size previewSize; 
  final bool isFrontCamera;
  // Aspect ratio of the camera feed (width / height)
  final double aspectRatio; 

  PosePainter({
    required this.landmarks,
    required this.previewSize,
    required this.isFrontCamera,
    required this.aspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) {
      return;
    }

    // --- Retrieve Paint Styles from original working PosePainter ---
    final paintPoint = Paint()
      ..color = Colors.green
      ..strokeWidth = 6.0
      ..style = PaintingStyle.fill;

    final paintLine = Paint()
      ..color = Colors.red
      ..strokeWidth = 4.0;
    // -------------------------------------------------------------------

    // The size parameter 'size' here is the size of the CustomPaint widget (screenWidth, screenHeight).
    final double screenWidth = size.width;
    final double screenHeight = size.height;
    final double widgetAspect = screenWidth / screenHeight;

    // --- CORRECTION 1: Determine the actual scale and offset for the AspectRatio widget ---
    double scale;
    Offset offset;

    if (widgetAspect > aspectRatio) {
      // Screen is relatively TALLER than camera feed. The height is cropped (top/bottom).
      // Camera width is scaled to screen width (BoxFit.cover logic).
      scale = screenWidth / previewSize.width;
      double scaledHeight = previewSize.height * scale;
      // Calculate vertical offset to center the cropped camera view.
      offset = Offset(0, (screenHeight - scaledHeight) / 2);
    } else {
      // Screen is relatively WIDER than camera feed. The width is cropped (left/right).
      // Camera height is scaled to screen height (BoxFit.cover logic).
      scale = screenHeight / previewSize.height;
      double scaledWidth = previewSize.width * scale;
      // Calculate horizontal offset to center the cropped camera view.
      offset = Offset((screenWidth - scaledWidth) / 2, 0);
    }

    final Map<PoseLandmarkType, Offset> scaledLandmarks = {};
    for (final landmark in landmarks) {
      double x = landmark.x;
      double y = landmark.y;

      // 1. Scale coordinates from original image size to the screen-fitted size
      x = x * scale;
      y = y * scale;

      // 2. Apply the mirroring correction for the front camera
      if (isFrontCamera) {
        // The mirroring needs to be relative to the full scaled width of the camera image.
        double totalScaledWidth = previewSize.width * scale;
        x = totalScaledWidth - x;
      }

      // 3. Apply the final calculated offset
      x += offset.dx;
      y += offset.dy;

      scaledLandmarks[landmark.type] = Offset(x, y);

      // Draw the point (Green Dot)
      canvas.drawCircle(scaledLandmarks[landmark.type]!, 6, paintPoint);
    }

    // --- CORRECTION 2: Use the full body connections list from the previous PosePainter ---
    for (final connection in _fullBodyConnections) {
      final start = scaledLandmarks[connection[0]];
      final end = scaledLandmarks[connection[1]];
      if (start != null && end != null) {
        canvas.drawLine(start, end, paintLine);
      }
    }
  }

  // Use the full body connection list saved from your previous PosePainter.
  // Note: Your original PosePainter was external, but I'll replicate the list here for completeness.
  static final List<List<PoseLandmarkType>> _fullBodyConnections = [
    [PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner],
    [PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye],
    [PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter],
    [PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEar],
    [PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner],
    [PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye],
    [PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter],
    [PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar],
    [PoseLandmarkType.leftMouth, PoseLandmarkType.rightMouth],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex],
    [PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex],
    [PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
    [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex],
    [PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
    [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex],
    [PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex],
  ];

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}