// lib/body_posture/exercises/exercises_logic/plank_logic.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:collection/collection.dart'; // for firstWhereOrNull
import '../camera/exercises_logic.dart';

class PlankLogic implements TimeExerciseLogic {
  // CHANGED: implements TimeExerciseLogic instead of ExerciseLogic
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _isHoldingPose = false;

  // Thresholds
  final double _minLandmarkConfidence = 0.7; // Now using this field
  final double _angleTolerance = 10.0;

  // Calibration
  double? _baselineBodyAngle;
  double? _baselineArmAngle;
  int _calibrationFramesCount = 0;
  final int _calibrationFramesTarget = 60; // ~2 seconds at 30fps
  bool _isCalibrating = true;

  // TTS
  final FlutterTts _flutterTts = FlutterTts();

  PlankLogic() {
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setPitch(1.0);
    _speak("Get into plank position");
  }

  @override
  String get progressLabel => "Time: $_elapsedSeconds sec";

  @override
  int get seconds => _elapsedSeconds; // ADDED: Required getter for TimeExerciseLogic interface

  @override
  void update(List landmarks, bool isFrontCamera) {
    // Fix: Cast landmarks to List<PoseLandmark>
    processLandmarks(landmarks.cast<PoseLandmark>());
  }

  @override
  void reset() {
    _stopTimer();
    _elapsedSeconds = 0;
    _isHoldingPose = false;
    _isCalibrating = true;
    _calibrationFramesCount = 0;
    _baselineBodyAngle = null;
    _baselineArmAngle = null;
    _speak("Get into plank position");
  }

  void processLandmarks(List<PoseLandmark> landmarks) {
    final leftShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftShoulder,
    );
    final leftHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftHip,
    );
    final leftAnkle = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftAnkle,
    );
    final rightShoulder = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightShoulder,
    );
    final rightHip = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightHip,
    );
    final rightAnkle = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightAnkle,
    );
    final leftElbow = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftElbow,
    );
    final leftWrist = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.leftWrist,
    );
    final rightElbow = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightElbow,
    );
    final rightWrist = landmarks.firstWhereOrNull(
      (l) => l.type == PoseLandmarkType.rightWrist,
    );

    // Now using _minLandmarkConfidence to check landmark confidence
    final allValid = [
      leftShoulder,
      leftHip,
      leftAnkle,
      rightShoulder,
      rightHip,
      rightAnkle,
      leftElbow,
      leftWrist,
      rightElbow,
      rightWrist,
    ].every((lm) => lm != null && lm.likelihood >= _minLandmarkConfidence);

    if (!allValid) {
      _stopTimer();
      if (_isHoldingPose) {
        _isHoldingPose = false;
        _speak("Adjust your position");
      }
      return;
    }

    final bodyAngle =
        (_getAngle(leftShoulder!, leftHip!, leftAnkle!) +
            _getAngle(rightShoulder!, rightHip!, rightAnkle!)) /
        2;
    final armAngle =
        (_getAngle(leftShoulder, leftElbow!, leftWrist!) +
            _getAngle(rightShoulder, rightElbow!, rightWrist!)) /
        2;

    if (_isCalibrating) {
      if (_calibrationFramesCount == 0) {
        _speak("Hold your best plank pose");
      }

      if (_calibrationFramesCount < _calibrationFramesTarget) {
        _baselineBodyAngle = (_baselineBodyAngle ?? 0) + bodyAngle;
        _baselineArmAngle = (_baselineArmAngle ?? 0) + armAngle;
        _calibrationFramesCount++;
      } else {
        _baselineBodyAngle = _baselineBodyAngle! / _calibrationFramesTarget;
        _baselineArmAngle = _baselineArmAngle! / _calibrationFramesTarget;
        _isCalibrating = false;
        _speak("Calibration complete. Start holding");
      }
      return;
    }

    final isBackSagging = bodyAngle < (_baselineBodyAngle! - _angleTolerance);
    final isPosteriorRaised =
        bodyAngle > (_baselineBodyAngle! + _angleTolerance);
    final isArmCorrect =
        armAngle >= (_baselineArmAngle! - _angleTolerance) &&
        armAngle <= (_baselineArmAngle! + _angleTolerance);

    final isCorrectForm = !isBackSagging && !isPosteriorRaised && isArmCorrect;

    if (isCorrectForm) {
      if (!_isHoldingPose) {
        _isHoldingPose = true;
        _speak("Good form. Hold it");
        _startTimer();
      }
    } else {
      _stopTimer();
      if (_isHoldingPose) {
        _isHoldingPose = false;
        if (isBackSagging) {
          _speak("Lift your hips");
        } else if (isPosteriorRaised) {
          _speak("Lower your hips");
        } else {
          _speak("Adjust your arms");
        }
      }
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
    await _flutterTts.stop(); // Prevent overlap
    await _flutterTts.speak(message);
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;

    final dot = v1x * v2x + v1y * v2y;
    final mag1 = sqrt(v1x * v1x + v1y * v1y);
    final mag2 = sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return 180.0;

    var cosAngle = dot / (mag1 * mag2);
    cosAngle = max(-1.0, min(1.0, cosAngle));

    return acos(cosAngle) * 180 / pi;
  }
}
