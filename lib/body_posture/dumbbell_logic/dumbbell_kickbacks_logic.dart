import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart'; // Assuming this path for ExerciseLogic

enum DumbbellKickbacksState { 
  down, // Elbows bent forward (starting position)
  up // Elbows extended backward (peak position)
}

enum BodyView { 
  side, // User is sideways to the camera (ideal for kickbacks)
  front, // User is facing the camera (less ideal)
  unknown // Could not determine
}

// NOTE: This logic simplifies rep counting to only rely on elbow angle 
// for more forgiving detection, while using BodyView only for form feedback.
class DumbbellKickbacksLogic implements RepExerciseLogic {
  int _repCount = 0;
  // Independent state tracking for each arm
  DumbbellKickbacksState _leftArmState = DumbbellKickbacksState.down;
  DumbbellKickbacksState _rightArmState = DumbbellKickbacksState.down;
  
  BodyView _currentView = BodyView.unknown;
  final FlutterTts _flutterTts = FlutterTts();

  DateTime _lastRepTime = DateTime.now();
  final Duration _cooldownDuration = const Duration(milliseconds: 500);
  DateTime _lastFeedbackTime = DateTime.now();
  static const Duration _feedbackCooldown = Duration(seconds: 4);

  // Angle thresholds for the elbow joint
  // Up position (extended) requires angle >= 150.0 degrees (with margin)
  final double _elbowUpAngle = 150.0; 
  // Down position (bent) requires angle <= 80.0 degrees (with margin)
  final double _elbowDownAngle = 80.0; 
  
  // Hysteresis margin for smoother state transitions
  final double _hysteresisMargin = 5.0; 
  
  // Torso angle to confirm bent-over position (for feedback only)
  // NOTE: This value is kept but used minimally for forgiving side-view detection.

  // Z-axis threshold for checking if wrist is behind elbow (Side View feedback only)
  final double _zAxisThreshold = 0.03; 

  final double _minLandmarkConfidence = 0.7;

  // Angle smoothing - one buffer for each arm
  final List<double> _leftElbowAngleBuffer = [];
  final List<double> _rightElbowAngleBuffer = [];
  final int _bufferSize = 5;

  // Sensor stability (Fields that were previously unused are now used below)
  bool _isSensorStable = true;
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  DumbbellKickbacksLogic() {
    _initializeTts();
  }

  // --- TTS and Utility Methods ---

  void _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speak(String message) async {
    if (DateTime.now().difference(_lastRepTime).inMilliseconds < 100) {
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
    if (landmarks.length < 8) return false; 
    double avgConfidence = landmarks.fold(0.0, (sum, landmark) => sum + landmark.likelihood) / landmarks.length;
    return avgConfidence >= _minLandmarkConfidence * 0.8;
  }

  void _handleSensorFailure() {
    if (!_isRecoveringFromSensorIssue) {
      _isRecoveringFromSensorIssue = true;
      _speakFeedback("Camera tracking issue detected. Please check your position.");
    }
    _leftArmState = DumbbellKickbacksState.down;
    _rightArmState = DumbbellKickbacksState.down;
    _consecutivePoorFrames = 0;
  }

  // ⭐ REVISED: Relaxing the bent-over requirement for BodyView detection.
  // We still use the torso angle, but the logic is now more about: "Are we side-on?" 
  // rather than "Are we perfectly bent-over?"
  BodyView _detectBodyOrientation(PoseLandmark shoulder, PoseLandmark hip, PoseLandmark ankle) {
    // If we can see the hip-ankle segment, and the shoulder is forward, assume side view.
    // Torso angle is used minimally now, allowing for a rounded back as long as the 
    // body is somewhat angled and side-on.
    final torsoAngle = _getAngle(shoulder, hip, ankle);
    
    // We only assume 'side' if the user is angled *and* hip/ankle landmarks are somewhat visible.
    // If the angle is very high (standing upright) or the landmarks are bad, it's 'front'.
    if (torsoAngle > 90.0 && shoulder.z != 0.0 && hip.z != 0.0) {
      return BodyView.side;
    } else {
      return BodyView.front;
    }
  }

  // --- Main Update Logic ---
  
  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (landmarks.isEmpty) {
      _speakFeedback("No body detected. Stand within the frame.");
      return;
    }

    final poseLandmarks = landmarks.cast<PoseLandmark>();
    
    // Get critical landmarks
    final leftShoulder = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftShoulder);
    final leftElbow = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftElbow);
    final leftWrist = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightShoulder = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightShoulder);
    final rightElbow = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightElbow);
    final rightWrist = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.rightWrist);
    final leftHip = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftHip);
    final leftAnkle = _getLandmarkSafe(poseLandmarks, PoseLandmarkType.leftAnkle);
    
    // Confidence check
    if (leftShoulder.likelihood < _minLandmarkConfidence ||
        rightShoulder.likelihood < _minLandmarkConfidence ||
        leftElbow.likelihood < _minLandmarkConfidence ||
        rightElbow.likelihood < _minLandmarkConfidence) {
      _speakFeedback("Ensure your upper arms are clearly visible for tracking.");
      return;
    }

    // ⭐ Sensor Stability Check ⭐
    _isSensorStable = _checkSensorStability(poseLandmarks);
    if (!_isSensorStable) {
      _consecutivePoorFrames++;
      if (_consecutivePoorFrames >= _maxPoorFramesBeforeReset) {
        _handleSensorFailure();
        return; 
      }
    } else if (_consecutivePoorFrames > 0) {
      _consecutivePoorFrames = 0; 
      if (_isRecoveringFromSensorIssue) {
        _isRecoveringFromSensorIssue = false;
        _speakFeedback("Tracking resumed.");
      }
    }

    // Determine the view angle based on the left side (for feedback only)
    _currentView = _detectBodyOrientation(leftShoulder, leftHip, leftAnkle);

    // Calculate and smooth angles
    final double leftElbowAngle = _getAngle(leftShoulder, leftElbow, leftWrist);
    final double rightElbowAngle = _getAngle(rightShoulder, rightElbow, rightWrist);
    
    final double smoothedLeftElbowAngle = _smoothAngle(_leftElbowAngleBuffer, leftElbowAngle);
    final double smoothedRightElbowAngle = _smoothAngle(_rightElbowAngleBuffer, rightElbowAngle);
    
    // --- SIMPLIFIED REPETITION LOGIC (Angle Only) ---
    
    final bool isLeftInUpPosition = smoothedLeftElbowAngle >= _elbowUpAngle - _hysteresisMargin;
    final bool isLeftInDownPosition = smoothedLeftElbowAngle <= _elbowDownAngle + _hysteresisMargin;
    
    final bool isRightInUpPosition = smoothedRightElbowAngle >= _elbowUpAngle - _hysteresisMargin;
    final bool isRightInDownPosition = smoothedRightElbowAngle <= _elbowDownAngle + _hysteresisMargin;
    
    // Z-axis check for *FORM FEEDBACK* only
    bool isLeftKickedBack = leftWrist.z > leftElbow.z + _zAxisThreshold;
    bool isRightKickedBack = rightWrist.z > rightElbow.z + _zAxisThreshold;


    // --- Process Rep Counting for each arm independently ---
    
    _leftArmState = _processArmState(
      _leftArmState, 
      isLeftInUpPosition, 
      isLeftInDownPosition, 
      smoothedLeftElbowAngle, 
      isLeftKickedBack, // Used for feedback
      "left"
    );

    _rightArmState = _processArmState(
      _rightArmState, 
      isRightInUpPosition, 
      isRightInDownPosition, 
      smoothedRightElbowAngle, 
      isRightKickedBack, // Used for feedback
      "right"
    );

    // Debug print for monitoring
    if (kDebugMode) {
        debugPrint(
        "View: $_currentView, L-State: $_leftArmState, R-State: $_rightArmState, L-Angle: ${smoothedLeftElbowAngle.toStringAsFixed(1)}, R-Angle: ${smoothedRightElbowAngle.toStringAsFixed(1)}, Reps: $_repCount");
    }
  }

  // New method to handle the state logic and counting for a single arm
  DumbbellKickbacksState _processArmState(
      DumbbellKickbacksState currentState,
      bool isUpPosition,
      bool isDownPosition,
      double smoothedAngle,
      bool isKickedBack, // Used only for form feedback
      String arm) {
          
    switch (currentState) {
      case DumbbellKickbacksState.down:
        // Rep count triggered here when moving from DOWN to UP
        if (isUpPosition) {
          // Check for rapid reps 
          if (DateTime.now().difference(_lastRepTime) >= _cooldownDuration) {
            _repCount++;
            // Only announce the rep number if it's an even number or first rep to avoid spamming for L/R
            if (_repCount == 1 || _repCount % 2 == 0) { 
                 _speak("Rep $_repCount.");
            }
            return DumbbellKickbacksState.up; // Transition to UP, rep counted
          } else {
            // Rep not counted (too fast), but state transitions to up
            _speakFeedback("Control the extension.");
            return DumbbellKickbacksState.up;
          }
        } 
        // ⭐ REVISED FEEDBACK: Only trigger 'kick back' feedback if we detect a side view 
        // AND the user is failing the Z-axis kickback check, ignoring torso straightness.
        else if (smoothedAngle > _elbowUpAngle - 20 && !isKickedBack && _currentView == BodyView.side) {
            _speakFeedback("Kick your $arm arm back further.");
        } 
        break;

      case DumbbellKickbacksState.up:
        // Feedback for incomplete extension 
        if (smoothedAngle < _elbowUpAngle - 5 && smoothedAngle > _elbowDownAngle + 20) {
            _speakFeedback("Hold the contraction at the top.");
        }
        
        // Transition to DOWN: when the arm is fully bent forward (prepares for the next rep)
        if (isDownPosition) {
          return DumbbellKickbacksState.down;
        } 
        
        // Feedback for incomplete bending (not returning to start position far enough)
        else if (smoothedAngle > _elbowDownAngle + 20) {
             _speakFeedback("Return $arm arm closer to a 90-degree bend.");
        }
        break;
    }
    return currentState; // Return the current state if no transition occurred
  }


  // --- Interface Implementation (Unchanged) ---
  
  @override
  void reset() {
    _repCount = 0;
    _leftArmState = DumbbellKickbacksState.down;
    _rightArmState = DumbbellKickbacksState.down;
    _currentView = BodyView.unknown;
    _lastRepTime = DateTime.now();
    _lastFeedbackTime = DateTime.now();
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
    _leftElbowAngleBuffer.clear();
    _rightElbowAngleBuffer.clear();
    _speak("Exercise reset. Turn side-on and start your kickbacks.");
  }

  @override
  String get progressLabel => 'Reps: $_repCount';

  @override
  int get reps => _repCount;
}