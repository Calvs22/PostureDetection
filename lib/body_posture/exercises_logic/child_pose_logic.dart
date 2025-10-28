// lib/body_posture/exercises_logic/child_pose_logic.dart

//NEED TESTING

import 'dart:async'; // For Timer
import 'dart:math'; // For sqrt, max, min, acos, pi
import 'package:collection/collection.dart'; // For firstWhereOrNull
import 'package:flutter_tts/flutter_tts.dart'; // For TTS
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart' show TimeExerciseLogic;
import 'package:flutter/foundation.dart'; // For debugPrint

class ChildPoseLogic implements TimeExerciseLogic {
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isHoldingPose = false;

  // Thresholds for pose detection
  final double _hipFoldThresholdAngle = 90.0;
  final double _kneeBendThresholdAngle = 60.0;
  final double _minLandmarkConfidence = 0.7;

  // TTS properties
  final FlutterTts _flutterTts = FlutterTts();
  String _lastSpokenFeedback = "";
  DateTime _lastFeedbackTime = DateTime.now().subtract(
    const Duration(seconds: 5),
  );
  final Duration _feedbackCooldown = const Duration(seconds: 3);

  // Form feedback
  String _formFeedback = "Get into Child's Pose";

  ChildPoseLogic() {
    _initTts();
  }

  void _initTts() {
    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.9);
    _flutterTts.setPitch(1.0);
  }

  @override
  String get progressLabel => "Time: ${_formatTime(_elapsedSeconds)}";

  @override
  int get seconds => _elapsedSeconds;

  @override
  void update(List landmarks, bool isFrontCamera) {
    final landmarksList = landmarks.cast<PoseLandmark>();
    _updatePoseState(landmarksList);
  }

  @override
  void reset() {
    _stopTimer();
    _elapsedSeconds = 0;
    _isHoldingPose = false;
    _formFeedback = "Get into Child's Pose";
    _lastSpokenFeedback = "";
    _lastFeedbackTime = DateTime.now().subtract(const Duration(seconds: 5));
    _speak("Get into Child's Pose");
  }

  void _updatePoseState(List<PoseLandmark> landmarks) {
    final leftHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftHip,
    );
    final rightHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightHip,
    );
    final leftKnee = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftKnee,
    );
    final rightKnee = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightKnee,
    );
    final leftAnkle = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftAnkle,
    );
    final rightAnkle = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightAnkle,
    );
    final leftShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftShoulder,
    );
    final rightShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightShoulder,
    );
    final nose = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.nose,
    );

    final bool allNecessaryLandmarksValid =
        leftHip != null &&
        rightHip != null &&
        leftKnee != null &&
        rightKnee != null &&
        leftAnkle != null &&
        rightAnkle != null &&
        leftShoulder != null &&
        rightShoulder != null &&
        nose != null &&
        leftHip.likelihood >= _minLandmarkConfidence &&
        rightHip.likelihood >= _minLandmarkConfidence &&
        leftKnee.likelihood >= _minLandmarkConfidence &&
        rightKnee.likelihood >= _minLandmarkConfidence &&
        leftAnkle.likelihood >= _minLandmarkConfidence &&
        rightAnkle.likelihood >= _minLandmarkConfidence &&
        leftShoulder.likelihood >= _minLandmarkConfidence &&
        rightShoulder.likelihood >= _minLandmarkConfidence &&
        nose.likelihood >= _minLandmarkConfidence;

    if (!allNecessaryLandmarksValid) {
      _stopTimer();
      if (_isHoldingPose) {
        _isHoldingPose = false;
        _formFeedback = "Adjust your position";
        _speak("Adjust your position");
      }
      return;
    }

    // Since we've validated that all landmarks are non-null, we can safely use them
    final double leftHipAngle = _getAngle(leftShoulder, leftHip, leftKnee);
    final double rightHipAngle = _getAngle(rightShoulder, rightHip, rightKnee);
    final double averageHipAngle = (leftHipAngle + rightHipAngle) / 2;

    final double leftKneeAngle = _getAngle(leftHip, leftKnee, leftAnkle);
    final double rightKneeAngle = _getAngle(rightHip, rightKnee, rightAnkle);
    final double averageKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    bool currentlyInChildPose = false;

    if (averageHipAngle < _hipFoldThresholdAngle &&
        averageKneeAngle < _kneeBendThresholdAngle) {
      currentlyInChildPose = true;
    }

    if (currentlyInChildPose && !_isHoldingPose) {
      _isHoldingPose = true;
      _formFeedback = "Good Child's Pose. Hold it";
      _speak("Good Child's Pose. Hold it");
      _startTimer();
    } else if (!currentlyInChildPose && _isHoldingPose) {
      _isHoldingPose = false;
      _formFeedback = _getFormFeedbackMessage(
        averageHipAngle,
        averageKneeAngle,
      );
      _speak(_formFeedback);
      _stopTimer();
    }
  }

  String _getFormFeedbackMessage(double hipAngle, double kneeAngle) {
    if (hipAngle >= _hipFoldThresholdAngle &&
        kneeAngle >= _kneeBendThresholdAngle) {
      return "Straighten your back and bend your knees more";
    } else if (hipAngle >= _hipFoldThresholdAngle) {
      return "Fold forward more from your hips";
    } else if (kneeAngle >= _kneeBendThresholdAngle) {
      return "Bend your knees deeper";
    } else {
      return "Adjust your Child's Pose";
    }
  }

  void _startTimer() {
    if (_timer != null && _timer!.isActive) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  void _speak(String message) async {
    if (message != _lastSpokenFeedback &&
        DateTime.now().difference(_lastFeedbackTime) > _feedbackCooldown) {
      try {
        await _flutterTts.stop();
        await _flutterTts.speak(message);
        _lastSpokenFeedback = message;
        _lastFeedbackTime = DateTime.now();
      } catch (e) {
        // Use debugPrint for logging instead of print
        debugPrint('TTS Error: $e');
      }
    }
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final double v1x = p1.x - p2.x;
    final double v1y = p1.y - p2.y;
    final double v2x = p3.x - p2.x;
    final double v2y = p3.y - p2.y;

    final double dotProduct = v1x * v2x + v1y * v2y;
    final double magnitude1 = sqrt(v1x * v1x + v1y * v1y);
    final double magnitude2 = sqrt(v2x * v2x + v2y * v2y);

    if (magnitude1 == 0 || magnitude2 == 0) {
      return 180.0;
    }

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));

    double angleRad = acos(cosineAngle);
    double angleDeg = angleRad * 180 / pi;

    return angleDeg;
  }

  String _formatTime(int totalSeconds) {
    final int minutes = (totalSeconds ~/ 60);
    final int seconds = (totalSeconds % 60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
