import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart'; // Assuming this path is correct for RepExerciseLogic

enum DumbbellCrunchState { 
  down, // Back flat on floor (Start/End position)
  peak // Crunched position (Rep Counting Trigger)
}

class DumbbellCrunchLogic implements RepExerciseLogic {
  int _repCount = 0;
  DumbbellCrunchState _currentState = DumbbellCrunchState.down;
  final FlutterTts _flutterTts = FlutterTts();

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 500);
  DateTime _lastFeedbackTime = DateTime.now();
  static const Duration _feedbackCooldown = Duration(seconds: 4);

  // --- FURTHER ADJUSTED ANGLE THRESHOLDS FOR RELIABLE CRUNCHES ---
  // Torso Angle (Knee-Hip-Shoulder) - The smaller the angle, the more crunched the user is.
  final double _torsoDownAngle = 175.0; // **Less strict 'flat back'** for starting position
  final double _torsoUpAngle = 160.0; // **Less strict 'crunched' angle** (higher than 155.0 to trigger easier)
  
  // Arm Angle (Shoulder-Elbow-Wrist) - Must be extended/raised to confirm peak
  final double _armExtendedAngle = 150.0; // **Lowered angle** to confirm arm is straight or held up
  
  final double _minLandmarkConfidence = 0.7;
  final double _hysteresisMargin = 5.0; // Increased margin for easier state transitions

  // Angle smoothing
  final List<double> _torsoAngleBuffer = [];
  final List<double> _shoulderAngleBuffer = [];
  final int _bufferSize = 5;

  // Sensor stability
  bool _isSensorStable = true;
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  DumbbellCrunchLogic() {
    _initializeTts();
  }

  void _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(0.9); 
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speak(String message) async {
    if (DateTime.now().difference(_lastRepTime).inMilliseconds < 1000) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastRepTime = DateTime.now();
  }

  Future<void> _speakFeedback(String message) async {
    if (DateTime.now().difference(_lastFeedbackTime) < _feedbackCooldown) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFeedbackTime = DateTime.now();
  }

  PoseLandmark _getLandmarkSafe(List<dynamic> landmarks, PoseLandmarkType type) {
    return landmarks.firstWhere(
      (l) => l.type == type,
      orElse: () => PoseLandmark(type: type, x: 0.0, y: 0.0, z: 0.0, likelihood: 0.0),
    );
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
      _speakFeedback("No body detected. Position the camera side-on.");
      return;
    }

    // --- Sensor Stability Check ---
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
        _isRecoveringFromSensorIssue = false;
        _speakFeedback("Tracking resumed. Continue your crunches.");
      }
    }

    final poseLandmarks = landmarks.cast<PoseLandmark>();

    // Retrieve necessary landmarks
    final leftHip = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightHip);
    final leftShoulder = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftShoulder);
    final rightShoulder = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightShoulder);
    final leftKnee = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftKnee);
    final rightKnee = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightKnee);
    final leftElbow = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftElbow);
    final rightElbow = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightElbow);
    final leftWrist = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightWrist);

    // Confidence check
    if (leftHip.likelihood < _minLandmarkConfidence ||
        rightHip.likelihood < _minLandmarkConfidence ||
        leftShoulder.likelihood < _minLandmarkConfidence ||
        rightShoulder.likelihood < _minLandmarkConfidence ||
        leftElbow.likelihood < _minLandmarkConfidence) { // Added elbow check for arm tracking
      _speakFeedback("Ensure your upper body and arms are clearly visible.");
      return;
    }

    // Calculate and smooth angles
    final double leftTorsoAngle = _getAngle(leftKnee, leftHip, leftShoulder);
    final double rightTorsoAngle = _getAngle(rightKnee, rightHip, rightShoulder);
    final double avgTorsoAngle = _smoothAngle(_torsoAngleBuffer, (leftTorsoAngle + rightTorsoAngle) / 2);

    final double leftArmAngle = _getAngle(leftShoulder, leftElbow, leftWrist);
    final double rightArmAngle = _getAngle(rightShoulder, rightElbow, rightWrist);
    final double avgArmAngle = _smoothAngle(_shoulderAngleBuffer, (leftArmAngle + rightArmAngle) / 2);
    
    // --- Position Checks ---
    // Torso bent (Peak)
    final bool isTorsoCrunched = avgTorsoAngle <= _torsoUpAngle + _hysteresisMargin; 
    // Torso straight (Down)
    final bool isTorsoFlat = avgTorsoAngle >= _torsoDownAngle - _hysteresisMargin; 
    // Arm raised (Must be reasonably extended to confirm rep completion)
    final bool isArmExtended = avgArmAngle >= _armExtendedAngle - _hysteresisMargin;
    
    // PEAK: Torso is crunched AND Arm is extended
    final bool inPeakPosition = isTorsoCrunched && isArmExtended; 

    // Debug logging
    debugPrint(
        "State: $_currentState, TorsoAngle: ${avgTorsoAngle.toStringAsFixed(1)}, "
        "ArmAngle: ${avgArmAngle.toStringAsFixed(1)}, Reps: $_repCount, Peak: $inPeakPosition, Flat: $isTorsoFlat");


    // --- Rep counting logic ---
    switch (_currentState) {
      case DumbbellCrunchState.down:
        // Transition to PEAK (Full crunch) - COUNT REP HERE
        if (inPeakPosition) {
          if (DateTime.now().difference(_lastRepTime) >= _cooldownDuration) {
            // Count rep on reaching the peak position
            _repCount++;
            _currentState = DumbbellCrunchState.peak;
            _lastRepTime = DateTime.now();
            _speak("Rep $_repCount."); 
          } else {
            // Allow rep to count, but give feedback if too fast
            _repCount++; 
            _currentState = DumbbellCrunchState.peak;
            _lastRepTime = DateTime.now();
            _speakFeedback("Control the ascent.");
          }
        } else if (avgTorsoAngle > _torsoDownAngle + _hysteresisMargin) {
          // Feedback on starting position: "Go flat"
          _speakFeedback("Lie flatter to begin.");
        }
        break;

      case DumbbellCrunchState.peak:
        // Transition back to DOWN (Lying flat) - RESET STATE HERE
        // Must return to the flat torso position to reset for the next rep.
        if (isTorsoFlat) {
          _currentState = DumbbellCrunchState.down;
          // Feedback on descent
          if (DateTime.now().difference(_lastRepTime).inMilliseconds < 1000) {
            _speakFeedback("Control the descent."); 
          }
        } else if (!isTorsoCrunched) { 
          // Give feedback if the user drops the torso before going fully down
            _speakFeedback("Go deeper on the next rep.");
        }
        break;
    }
  }

  @override
  void reset() {
    _repCount = 0; 
    _currentState = DumbbellCrunchState.down;
    _lastRepTime = DateTime.now();
    _lastFeedbackTime = DateTime.now();
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
    _torsoAngleBuffer.clear();
    _shoulderAngleBuffer.clear();
    _speak("Exercise reset. Start your crunches.");
  }

  @override
  String get progressLabel => 'Reps: $_repCount';

  @override
  int get reps => _repCount;

  // Helper function to calculate the angle between three pose landmarks
  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final v1x = p1.x - p2.x;
    final v1y = p1.y - p2.y;
    final v2x = p3.x - p2.x;
    final v2y = p3.y - p2.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v2x + v1y * v2y);
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
    _currentState = DumbbellCrunchState.down;
    _consecutivePoorFrames = 0;
  }
}