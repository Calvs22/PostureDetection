import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart';

enum DumbbellDragCurlState { down, up }

class DumbbellDragCurlLogic implements RepExerciseLogic {
  int _repCount = 0;
  DumbbellDragCurlState _currentState = DumbbellDragCurlState.down;
  final FlutterTts _flutterTts = FlutterTts();

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 500);
  DateTime _lastFeedbackTime = DateTime.now();
  static const Duration _feedbackCooldown = Duration(seconds: 4);
  String _feedback = "";

  // --- ADJUSTED Angle/Distance Thresholds for Drag Curl (MORE TOLERANT) ---
  final double _elbowDownAngle = 170.0; // Arms extended downward
  // <<< ADJUSTED: Loosened up angle for peak completion (was 118.0)
  final double _elbowUpAngle = 125.0; 
  // <<< ADJUSTED: Loosened height requirement for peak position (was 0.55)
  final double _wristPeakHeightRatio = 0.50; 
  
  // Normalized elbow separation threshold (for feedback only)
  final double _maxElbowSeparationRatio = 0.22; 
  
  // Z-axis check (Elbow behind shoulder) - for feedback only
  final double _minElbowBehindShoulderZ = 0.015; 

  // POV Detection Thresholds
  final double _minShoulderSeparationRatio = 0.28; 
  
  final double _minLandmarkConfidence = 0.7;
  final double _hysteresisMargin = 5.0;

  // Angle smoothing
  final List<double> _elbowAngleBuffer = [];
  final int _bufferSize = 5;

  // Sensor stability
  bool _isSensorStable = true;
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  DumbbellDragCurlLogic() {
    _initializeTts();
  }

  void _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speak(String message) async {
    // Cooldown check for rapid repetitions
    if (DateTime.now().difference(_lastRepTime).inMilliseconds < 1000) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    // _lastRepTime is updated after a successful rep in the update method
  }

  Future<void> _speakFeedback(String message) async {
    // Cooldown check added for feedback
    if (DateTime.now().difference(_lastFeedbackTime) < _feedbackCooldown || message == _feedback) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFeedbackTime = DateTime.now();
    _feedback = message;
  }

  PoseLandmark _getLandmarkSafe(List<dynamic> landmarks, PoseLandmarkType type) {
    return landmarks.firstWhere(
      (l) => l.type == type,
      orElse: () => PoseLandmark(type: type, x: 0.0, y: 0.0, z: 0.0, likelihood: 0.0),
    );
  }

  double _getDistance(PoseLandmark p1, PoseLandmark p2) {
    final dx = p1.x - p2.x;
    final dy = p1.y - p2.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _smoothAngle(List<double> buffer, double newAngle) {
    buffer.add(newAngle);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
    return buffer.reduce((a, b) => a + b) / buffer.length;
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (landmarks.isEmpty) {
      _speakFeedback("No body detected. Position the camera correctly.");
      return;
    }

    _isSensorStable = _checkSensorStability(landmarks);
    if (!_isSensorStable) {
      _consecutivePoorFrames++;
      if (_consecutivePoorFrames >= _maxPoorFramesBeforeReset) {
        _handleSensorFailure();
      }
      return;
    }

    if (_consecutivePoorFrames > 0) {
      _consecutivePoorFrames = 0;
      if (_isRecoveringFromSensorIssue) {
        _speakFeedback("Tracking resumed. Continue your drag curls.");
      }
    }

    final poseLandmarks = landmarks.cast<PoseLandmark>();

    // Retrieve landmarks
    final leftShoulder = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftShoulder);
    final rightShoulder = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightShoulder);
    final leftElbow = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftElbow);
    final rightElbow = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightElbow);
    final leftWrist = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightWrist);
    final leftHip = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightHip);

    // Confidence check
    if (leftShoulder.likelihood < _minLandmarkConfidence ||
        rightShoulder.likelihood < _minLandmarkConfidence ||
        leftElbow.likelihood < _minLandmarkConfidence ||
        rightElbow.likelihood < _minLandmarkConfidence ||
        leftWrist.likelihood < _minLandmarkConfidence ||
        rightWrist.likelihood < _minLandmarkConfidence ||
        leftHip.likelihood < _minLandmarkConfidence ||
        rightHip.likelihood < _minLandmarkConfidence) {
      _speakFeedback("Ensure your upper body is clearly visible.");
      return;
    }

    // Core Measurements
    final double torsoLength = (_getDistance(leftShoulder, leftHip) + _getDistance(rightShoulder, rightHip)) / 2;
    if (torsoLength == 0) return;

    // Calculate smoothed elbow angles
    final double leftElbowAngle = _getAngle(leftShoulder, leftElbow, leftWrist);
    final double rightElbowAngle = _getAngle(rightShoulder, rightElbow, rightWrist);
    final double avgElbowAngle = _smoothAngle(_elbowAngleBuffer, (leftElbowAngle + rightElbowAngle) / 2);

    // Wrist height relative to torso
    // Note: Y-axis increases downward in computer vision
    final double leftWristToHipVerticalDist = (leftHip.y - leftWrist.y); 
    final double rightWristToHipVerticalDist = (rightHip.y - rightWrist.y);
    final double avgWristToHipVerticalDist = (leftWristToHipVerticalDist + rightWristToHipVerticalDist) / 2;
    final double normalizedWristHeight = avgWristToHipVerticalDist / torsoLength;
    
    // Determine point of view
    final double shoulderSeparation = _getDistance(leftShoulder, rightShoulder);
    final double normalizedShoulderSeparation = shoulderSeparation / torsoLength;
    final bool isSideView = normalizedShoulderSeparation < _minShoulderSeparationRatio;

    // DRAG CURL FORM CHECKS (FOR FEEDBACK ONLY)
    if (isSideView) {
      // Check for elbow flare (swinging)
      final double leftElbowHorizontalDelta = (leftShoulder.x - leftElbow.x).abs();
      final double rightElbowHorizontalDelta = (rightShoulder.x - rightElbow.x).abs();
      final double avgElbowHorizontalDelta = (leftElbowHorizontalDelta + rightElbowHorizontalDelta) / 2;
      final double normalizedElbowSeparation = avgElbowHorizontalDelta / torsoLength;
      
      if (normalizedElbowSeparation > _maxElbowSeparationRatio) {
        _speakFeedback("Keep your elbows tight. No swinging.");
      }

      // Check for Z-axis position (Elbow behind shoulder)
      final double leftElbowZRelativeToShoulder = leftShoulder.z - leftElbow.z;
      final double rightElbowZRelativeToShoulder = rightShoulder.z - rightElbow.z;
      final double avgElbowZRelativeToShoulder = (leftElbowZRelativeToShoulder + rightElbowZRelativeToShoulder) / 2;
      
      final bool isElbowBehindTorsoZ = avgElbowZRelativeToShoulder < -_minElbowBehindShoulderZ; 
      
      if (!isElbowBehindTorsoZ) {
          // This check is the hardest to pass, only provide feedback, don't block the rep count
          _speakFeedback("Focus on keeping your elbows back.");
      }
    }
    
    // STATE TRANSITIONS (MODIFIED TO COUNT REP AT PEAK)
    
    // Define key positions with hysteresis
    // isArmExtended requires avgElbowAngle >= 170.0 - 5.0 (165.0 degrees)
    final bool isArmExtended = avgElbowAngle >= _elbowDownAngle - _hysteresisMargin;
    // isCurledAngleMet requires avgElbowAngle <= 125.0 + 5.0 (130.0 degrees)
    final bool isCurledAngleMet = avgElbowAngle <= _elbowUpAngle + _hysteresisMargin;
    
    // PEAK CONDITION: Requires angle and wrist height
    final bool isAtPeakDrag = isCurledAngleMet && (normalizedWristHeight >= _wristPeakHeightRatio); 

    // Debug logging
    debugPrint(
        "State: $_currentState, Angle: ${avgElbowAngle.toStringAsFixed(1)}, "
        "NormWristHeight: ${normalizedWristHeight.toStringAsFixed(2)}, PeakConditionMet: $isAtPeakDrag, Reps: $_repCount");

    switch (_currentState) {
      case DumbbellDragCurlState.down:
        // Transition to UP (Curl up) - COUNT REP HERE
        if (isAtPeakDrag) {
          if (DateTime.now().difference(_lastRepTime) < _cooldownDuration) {
             _speakFeedback("Slow and controlled on the way up.");
          }
          
          _repCount++;
          _currentState = DumbbellDragCurlState.up;
          _lastRepTime = DateTime.now();
          _speak("Rep $_repCount.");

        } else if (avgElbowAngle < _elbowDownAngle - 15) {
          _speakFeedback("Fully extend your arms at the bottom.");
        }
        break;

      case DumbbellDragCurlState.up:
        // Transition back to DOWN (Lowering)
        if (isArmExtended) {
          _currentState = DumbbellDragCurlState.down;
        } else if (normalizedWristHeight < _wristPeakHeightRatio - 0.15) {
          _speakFeedback("Maintain control on the way down.");
        }
        break;
    }
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = DumbbellDragCurlState.down;
    _lastRepTime = DateTime.now();
    _lastFeedbackTime = DateTime.now();
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
    _elbowAngleBuffer.clear();
    _feedback = "";
    _speak("Exercise reset. Start your drag curls.");
  }

  @override
  String get progressLabel => 'Reps: $_repCount';

  @override
  int get reps => _repCount;

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0 || mag2 == 0) return 180.0;
    double cosine = dot / (mag1 * mag2);
    cosine = math.max(-1.0, math.min(1.0, cosine));
    return math.acos(cosine) * 180 / math.pi;
  }

  bool _checkSensorStability(List landmarks) {
    if (landmarks.isEmpty) return false;
    double avgConfidence = landmarks.fold(0.0, (sum, landmark) => sum + landmark.likelihood) / landmarks.length;
    return avgConfidence >= _minLandmarkConfidence * 0.8;
  }

  void _handleSensorFailure() {
    if (!_isRecoveringFromSensorIssue) {
      _isRecoveringFromSensorIssue = true;
      _speakFeedback("Camera tracking issue detected. Position the camera side-on.");
    }
    _currentState = DumbbellDragCurlState.down;
    _consecutivePoorFrames = 0;
  }
}