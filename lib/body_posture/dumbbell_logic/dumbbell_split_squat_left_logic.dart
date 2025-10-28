import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
// Assuming this points to your ExerciseLogic interface
import '../camera/exercises_logic.dart'; 

enum DumbbellSplitSquatLeftState { up, down }

// Implements the RepExerciseLogic interface.
class DumbbellSplitSquatLeftLogic implements RepExerciseLogic {
  int _repCount = 0;
  DumbbellSplitSquatLeftState _currentState = DumbbellSplitSquatLeftState.up;
  final FlutterTts _flutterTts = FlutterTts();

  // Timing settings
  final Duration _cooldownDuration = const Duration(milliseconds: 100); 
  DateTime _lastRepTime = DateTime.now();
  
  DateTime? _lastFeedbackTime;
  // Significantly increased cooldown for general speech
  final Duration _feedbackCooldown = Duration(milliseconds: 2000); 

  bool _hasStarted = false;

  // **SIMPLIFIED FORGIVENESS PARAMETERS (Focusing on Left Knee)**
  // Max angle when standing up (fully extended leg is ~180).
  final double _kneeUpAngle = 160.0; 
  // Target depth angle (90 degrees or below)
  final double _kneeDownAngle = 90.0; 
  final double _minLandmarkConfidence = 0.7; 
  // Increased margin for smoother transitions
  final double _hysteresisMargin = 5.0; 

  // Smoothing
  final List<double> _kneeAngleBuffer = [];
  final int _bufferSize = 5; 

  // Movement Direction Tracking
  double _lastKneeAngle = 0.0;
  bool _isMovingUp = false;
  bool _isMovingDown = false;
  
  // Feedback flags to control speaking
  bool _spokeGoLower = false;
  bool _spokeStandUp = false;

  // Error handling (unchanged)
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(milliseconds: 750); 
  bool _isInGracePeriod = false;

  // Internal feedback strings
  String _feedback = "Start Squatting...";

  DumbbellSplitSquatLeftLogic() {
    _initializeTts();
  }

  void _initializeTts() async {
    // Omitted for brevity: TTS initialization logic
    if (!kIsWeb) {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
    }
  }

  Future<void> _speak(String message) async {
    // Only speak if enough time has passed since the last general message
    if (kIsWeb) return; 
    final now = DateTime.now();
    if (_lastFeedbackTime != null &&
        now.difference(_lastFeedbackTime!) < _feedbackCooldown) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFeedbackTime = now;
  }
  
  Future<void> _speakRep(String message) async {
    // Override cooldown for rep count
    if (kIsWeb) return;
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFeedbackTime = DateTime.now(); // Update general cooldown to prevent immediate follow-up
  }

  // Helper to safely retrieve landmarks (unchanged)
  PoseLandmark? _getLandmark(List<PoseLandmark> landmarks, PoseLandmarkType type) {
    for (final landmark in landmarks) {
      if (landmark.type == type && landmark.likelihood >= _minLandmarkConfidence) {
        return landmark;
      }
    }
    return null;
  }

  bool _areLandmarksValid(List<PoseLandmark?> landmarks) {
    return landmarks.every((landmark) => landmark != null);
  }

  // Smoothing function using a rolling average (unchanged)
  double _smoothAngle(List<double> buffer, double newAngle) {
    buffer.add(newAngle);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
    return buffer.reduce((a, b) => a + b) / buffer.length;
  }

  // Angle calculation function (unchanged)
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
  
  // ----------------------------------------------------
  // --- Core Update Logic (FIXED FOR FORGIVING REP COUNT) ---
  // ----------------------------------------------------

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (!_hasStarted) {
      _speak("Get into split squat position with left leg forward.");
      _hasStarted = true;
      _spokeGoLower = false;
      _spokeStandUp = false;
    }

    final poseLandmarks = landmarks.cast<PoseLandmark>();
    
    // Only need landmarks for the working (left) leg
    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final leftKnee = _getLandmark(poseLandmarks, PoseLandmarkType.leftKnee);
    final leftAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.leftAnkle);
    
    // Landmark check and Grace Period logic (unchanged)
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      leftHip, leftKnee, leftAnkle,
    ]);
    if (!allNecessaryLandmarksValid) {
      if (!_isInGracePeriod) {
        _lastInvalidLandmarksTime = DateTime.now();
        _isInGracePeriod = true;
        _feedback = "Position check...";
      } else if (_lastInvalidLandmarksTime != null &&
          DateTime.now().difference(_lastInvalidLandmarksTime!) > _gracePeriod) {
        _currentState = DumbbellSplitSquatLeftState.up;
        _isInGracePeriod = false;
        _feedback = "Position lost. Recalibrating.";
        _speak(_feedback);
      }
      return;
    }

    _isInGracePeriod = false;
    _lastInvalidLandmarksTime = null;
    
    // Calculate and smooth the left knee angle
    final double leftKneeAngle = _smoothAngle(_kneeAngleBuffer, _getAngle(leftHip!, leftKnee!, leftAnkle!));

    // Movement Direction Check
    _isMovingDown = leftKneeAngle < _lastKneeAngle;
    _isMovingUp = leftKneeAngle > _lastKneeAngle;
    _lastKneeAngle = leftKneeAngle;

    // Position checks with Hysteresis
    final bool isUp = leftKneeAngle >= _kneeUpAngle - _hysteresisMargin; // >= 155 deg
    final bool isDown = leftKneeAngle <= _kneeDownAngle + _hysteresisMargin; // <= 95 deg
    
    // Rep counting state machine logic
    switch (_currentState) {
      case DumbbellSplitSquatLeftState.up:
        _feedback = "Squat down.";
        _spokeGoLower = false; // Reset the flag for the next rep cycle
        _spokeStandUp = false; // Reset the flag for the next rep cycle
        
        // Feedback if they are not fully standing up before starting
        if (leftKneeAngle < _kneeUpAngle - _hysteresisMargin && !_spokeStandUp) {
          _feedback = "Stand up fully.";
          _speak("Stand up!");
          _spokeStandUp = true;
        }
        
        // Transition UP -> DOWN: ONLY requires hitting depth.
        // This is the beginning of a successful rep attempt.
        if (isDown) {
          _currentState = DumbbellSplitSquatLeftState.down;
          _feedback = "Push up to complete the rep.";
        } 
        // Feedback: If they're moving down but not deep enough
        else if (_isMovingDown && leftKneeAngle > _kneeDownAngle + _hysteresisMargin && !_spokeGoLower) {
          _feedback = "Go lower!";
          _speak("Go lower!");
          _spokeGoLower = true;
        }
        break;

      case DumbbellSplitSquatLeftState.down:
        // Now that they've hit depth, the only requirement is to return to the UP position.
        _feedback = "Push up to complete the rep.";
        
        // Rep Completion: Transition DOWN -> UP
        // A rep is counted only if they return to the 'up' position (isUp is true).
        // The check for _isMovingUp is removed to allow for a slight pause at the top.
        if (isUp) {
          if (DateTime.now().difference(_lastRepTime) >= _cooldownDuration) {
            _repCount++;
            _currentState = DumbbellSplitSquatLeftState.up;
            _lastRepTime = DateTime.now();
            _feedback = "Rep $_repCount!";
            _speakRep("Rep $_repCount!"); // Use fast-speaking for rep count
          }
        }
        
        // FAIL-SAFE: If they start bouncing up but haven't hit the UP position yet, prompt them.
        else if (_isMovingUp) {
            _feedback = "Continue standing up!";
        }
        
        // FAIL-SAFE: If they drop back down without completing the rep (should transition back to DOWN naturally, but this is a safety check)
        else if (_isMovingDown && !isDown) {
            _feedback = "Keep pushing up!";
        }
        
        break;
    }
  }
  
  // ----------------------------------------------------
  // --- Interface Implementation (unchanged) ---
  // ----------------------------------------------------

  @override
  void reset() {
    _repCount = 0;
    _currentState = DumbbellSplitSquatLeftState.up;
    _lastRepTime = DateTime.now();
    _hasStarted = false;
    _lastFeedbackTime = null;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;
    _lastKneeAngle = 0.0;
    _isMovingUp = false;
    _isMovingDown = false;
    _spokeGoLower = false;
    _spokeStandUp = false;
    _kneeAngleBuffer.clear();
    _feedback = "Exercise reset. Left leg forward.";
    _speak(_feedback);
  }

  @override
  // Returns the current progress label for the UI
  String get progressLabel => "Reps: $_repCount";

  @override
  // Returns the current rep count
  int get reps => _repCount;
  
  // Public getter for UI feedback
  String get feedbackText => _feedback;
}