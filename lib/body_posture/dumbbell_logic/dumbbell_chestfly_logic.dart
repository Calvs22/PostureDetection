import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart';

enum DumbbellChestFlyState { 
  down, // Arms extended outward/lowered (End position)
  up // Arms together/raised (Peak contraction)
}

class DumbbellChestFlyLogic implements RepExerciseLogic {
  int _repCount = 0;
  DumbbellChestFlyState _currentState = DumbbellChestFlyState.down;
  final FlutterTts _flutterTts = FlutterTts();

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 500);
  DateTime _lastFeedbackTime = DateTime.now();
  static const Duration _feedbackCooldown = Duration(seconds: 4);

  // --- NEW FRONT POV MOVEMENT THRESHOLDS ---
  // This angle measures the spread of the arms (Wrist-Midpoint-Wrist)
  // At 'down' position (arms wide), the angle is small (close to 0)
  // At 'up' position (arms together), the angle is large (close to 180)
  final double _armDownAngleThreshold = 40.0; // Arms wide/lowered (Start of movement)
  final double _armUpAngleThreshold = 150.0;  // Arms together/raised (Peak contraction/End of Rep)
  
  // Elbow bend check is less critical for a front view, removed for simplicity
  final double _minLandmarkConfidence = 0.7;

  // Angle smoothing
  final List<double> _armSpreadAngleBuffer = []; // Renamed buffer
  final int _bufferSize = 5; // Smooth over 5 frames

  // Sensor stability
  bool _isSensorStable = true;
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  DumbbellChestFlyLogic() {
    _initializeTts();
  }

  void _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speakRepCount(int count) async {
    if (DateTime.now().difference(_lastRepTime).inMilliseconds < 1000) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak('$count');
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

  PoseLandmark _getLandmark(List<PoseLandmark> landmarks, PoseLandmarkType type) {
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

  // --- NEW HELPER: Calculate the midpoint between two landmarks ---
  PoseLandmark _getMidpoint(PoseLandmark p1, PoseLandmark p2) {
    return PoseLandmark(
      type: PoseLandmarkType.nose, // Placeholder type
      x: (p1.x + p2.x) / 2,
      y: (p1.y + p2.y) / 2,
      z: (p1.z + p2.z) / 2,
      likelihood: math.min(p1.likelihood, p2.likelihood),
    );
  }

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (landmarks.isEmpty) {
      _speakFeedback("No body detected. Position the camera for a clear front view.");
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
        _isRecoveringFromSensorIssue = false;
        _speakFeedback("Tracking resumed. Continue your chest flys.");
      }
    }
    
    final poseLandmarks = landmarks.cast<PoseLandmark>();

    // Get landmarks for the 'fly' movement: Wrists and Shoulders
    final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);
    final leftShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.leftShoulder);
    final rightShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.rightShoulder);

    // --- NEW CENTER POINT ---
    final centerShoulder = _getMidpoint(leftShoulder, rightShoulder);

    // Confidence check
    if ([leftWrist, rightWrist, leftShoulder, rightShoulder]
        .any((l) => l.likelihood < _minLandmarkConfidence)) {
      _speakFeedback("Ensure your hands and shoulders are clearly visible.");
      return;
    }

    // Calculate the spread angle: LeftWrist -> CenterShoulder -> RightWrist
    final double armSpreadAngle = _getAngle(leftWrist, centerShoulder, rightWrist);
    
    // Smooth the angle for stability
    final double smoothedArmSpreadAngle = _smoothAngle(_armSpreadAngleBuffer, armSpreadAngle);
    
    // Debug logging
    debugPrint(
        "State: $_currentState, ArmSpreadAngle: ${smoothedArmSpreadAngle.toStringAsFixed(1)}, Reps: $_repCount");

    // Form Check: The Chest Fly keeps elbows slightly bent and hands away from the body
    // A deep dip in the angle may indicate an accidental Press (Angle close to 0) or extreme bend (Angle close to 180).
    // We will focus on the spread for counting, but the general principle is:
    // In Down: Angle is small (arms wide).
    // In Up: Angle is large (arms together).
    
    // Check fly positions
    final bool inUpPosition = smoothedArmSpreadAngle >= _armUpAngleThreshold;
        
    final bool inDownPosition = smoothedArmSpreadAngle <= _armDownAngleThreshold;

    // --- REPETITION LOGIC ---
    switch (_currentState) {
      case DumbbellChestFlyState.down:
        // Transition to UP: Requires arms to be brought together
        if (inUpPosition) {
          _currentState = DumbbellChestFlyState.up;
          _speakFeedback("Squeeze your chest at the top.");
        } 
        // Feedback for not reaching the top
        else if (smoothedArmSpreadAngle > _armDownAngleThreshold + 10 && smoothedArmSpreadAngle < _armUpAngleThreshold) {
          _speakFeedback("Bring the weights closer together.");
        }
        break;

      case DumbbellChestFlyState.up:
        // Transition back to DOWN (Count Rep): Requires arms to be lowered (spread wide)
        if (inDownPosition) {
          if (DateTime.now().difference(_lastRepTime) > _cooldownDuration) {
            _repCount++;
            _lastRepTime = DateTime.now();
            _speakRepCount(_repCount);
            _currentState = DumbbellChestFlyState.down;
          } else {
            // Too fast
            _repCount++; 
            _lastRepTime = DateTime.now();
            _currentState = DumbbellChestFlyState.down;
            _speakFeedback("Control the descent. Don't rush the stretch.");
          }
        }
        // Feedback for not reaching the bottom
        else if (smoothedArmSpreadAngle < _armUpAngleThreshold - 10 && smoothedArmSpreadAngle > _armDownAngleThreshold) {
          _speakFeedback("Lower the weights further for a full stretch.");
        }
        break;
    }
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = DumbbellChestFlyState.down;
    _lastRepTime = DateTime.now();
    _lastFeedbackTime = DateTime.now();
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
    _armSpreadAngleBuffer.clear();
    _speakFeedback("Exercise reset. Start your chest flys.");
  }

  @override
  String get progressLabel => 'Reps: $_repCount';

  @override
  int get reps => _repCount;

  bool _checkSensorStability(List landmarks) {
    if (landmarks.isEmpty) return false;
    double avgConfidence = landmarks.fold(0.0, (sum, landmark) => sum + landmark.likelihood) / landmarks.length;
    return avgConfidence >= _minLandmarkConfidence * 0.8;
  }

  void _handleSensorFailure() {
    if (!_isRecoveringFromSensorIssue) {
      _isRecoveringFromSensorIssue = true;
      _speakFeedback("Camera tracking issue detected. Adjust your position.");
    }
    _currentState = DumbbellChestFlyState.down;
    _consecutivePoorFrames = 0;
  }
}