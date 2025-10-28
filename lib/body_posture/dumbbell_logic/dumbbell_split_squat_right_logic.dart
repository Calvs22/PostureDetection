import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart'; // Assuming this points to your ExerciseLogic interface

enum DumbbellSplitSquatRightState { up, down }

class DumbbellSplitSquatRightLogic implements RepExerciseLogic {
  int _repCount = 0;
  DumbbellSplitSquatRightState _currentState = DumbbellSplitSquatRightState.up;
  final FlutterTts _flutterTts = FlutterTts();

  // Timing settings
  final Duration _cooldownDuration = const Duration(milliseconds: 100); 
  DateTime _lastRepTime = DateTime.now();
  
  bool _hasStarted = false;
  
  DateTime? _lastFeedbackTime;
  // Significantly increased cooldown for general speech
  final Duration _feedbackCooldown = Duration(milliseconds: 2000); 

  // **SIMPLIFIED FORGIVENESS THRESHOLDS** (Right leg is the working leg - the forward leg)
  final double _kneeUpAngle = 160.0; 
  final double _kneeDownAngle = 90.0; 
  final double _minLandmarkConfidence = 0.7;
  final double _hysteresisMargin = 5.0; 

  // Smoothing
  final List<double> _kneeAngleBuffer = [];
  final int _bufferSize = 5; 
  
  // Movement Direction Tracking
  double _lastKneeAngle = 0.0;
  bool _isMovingDown = false; // Kept as it's used for the 'Go lower!' prompt
  // Removed unused field: bool _isMovingUp = false; 
  
  // Feedback flags to control speaking
  bool _spokeGoLower = false;
  bool _spokeStandUp = false;
  bool _hitDownPosition = false; // Tracks if the required depth was achieved this rep cycle

  // Error handling
  DateTime? _lastInvalidLandmarksTime;
  final Duration _gracePeriod = Duration(milliseconds: 750); 
  bool _isInGracePeriod = false;

  // Internal feedback strings
  String _feedback = "Start Squatting...";

  DumbbellSplitSquatRightLogic() {
    _initializeTts();
  }

  void _initializeTts() async {
    if (!kIsWeb) {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
    }
  }

  Future<void> _speak(String message) async {
    // General speaking function with cooldown
    if (kIsWeb) return; 
    final now = DateTime.now();
    if (_lastFeedbackTime != null && now.difference(_lastFeedbackTime!) < _feedbackCooldown) {
      return;
    }
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFeedbackTime = now; 
  }

  Future<void> _speakRep(String message) async {
    // Rep count speaking function (bypasses general cooldown, but updates it)
    if (kIsWeb) return;
    await _flutterTts.stop();
    await _flutterTts.speak(message);
    _lastFeedbackTime = DateTime.now(); 
  }

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

  // ----------------------------------------------------
  // --- Core Update Logic (FIXED FOR FORGIVENESS) ---
  // ----------------------------------------------------

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    if (!_hasStarted) {
      _speak("Get into split squat position with right leg forward.");
      _hasStarted = true;
      _spokeGoLower = false;
      _spokeStandUp = false;
    }

    final poseLandmarks = landmarks.cast<PoseLandmark>();

    // Retrieve landmarks for the working leg (Right side)
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final rightKnee = _getLandmark(poseLandmarks, PoseLandmarkType.rightKnee);
    final rightAnkle = _getLandmark(poseLandmarks, PoseLandmarkType.rightAnkle);
    

    // Validation and Grace Period (unchanged)
    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      rightHip, rightKnee, rightAnkle, 
    ]);

    if (!allNecessaryLandmarksValid) {
      if (!_isInGracePeriod) {
        _lastInvalidLandmarksTime = DateTime.now();
        _isInGracePeriod = true;
        _feedback = "Position check...";
      } else if (_lastInvalidLandmarksTime != null &&
          DateTime.now().difference(_lastInvalidLandmarksTime!) > _gracePeriod) {
        _currentState = DumbbellSplitSquatRightState.up;
        _isInGracePeriod = false;
        _feedback = "Position lost. Recalibrating.";
        _speak(_feedback);
      }
      return;
    }

    _isInGracePeriod = false;
    _lastInvalidLandmarksTime = null;

    // Calculate and smooth the Right Knee angle
    final double rightKneeAngle = _smoothAngle(_kneeAngleBuffer, _getAngle(rightHip!, rightKnee!, rightAnkle!));

    // Movement Direction Check (Calculate local variable for _isMovingUp)
    _isMovingDown = rightKneeAngle < _lastKneeAngle; // Update persistent field
    _lastKneeAngle = rightKneeAngle;

    // Position checks with Hysteresis
    final bool isUp = rightKneeAngle >= _kneeUpAngle - _hysteresisMargin; // >= 155 deg
    final bool isDown = rightKneeAngle <= _kneeDownAngle + _hysteresisMargin; // <= 95 deg

    // Rep counting logic
    switch (_currentState) {
      case DumbbellSplitSquatRightState.up:
        _feedback = "Squat down.";
        // Reset flags for the start of a new rep cycle
        _spokeGoLower = false;
        _spokeStandUp = false;
        _hitDownPosition = false; // Reset depth tracker
        
        // Feedback if they are not fully standing up before starting
        if (rightKneeAngle < _kneeUpAngle - _hysteresisMargin && !_spokeStandUp) {
          _feedback = "Stand up fully.";
          _speak("Stand up!");
          _spokeStandUp = true;
        }

        // Transition UP -> DOWN: ONLY requires hitting depth.
        if (isDown) {
          _currentState = DumbbellSplitSquatRightState.down;
          _hitDownPosition = true; // Mark that depth was reached
          _feedback = "Push up to complete the rep.";
        } 
        // Feedback: If they're moving down but not deep enough
        else if (_isMovingDown && rightKneeAngle > _kneeDownAngle + _hysteresisMargin && !_spokeGoLower) {
          _feedback = "Go lower!";
          _speak("Go lower!");
          _spokeGoLower = true;
        }
        break;

      case DumbbellSplitSquatRightState.down:
        _feedback = "Push up to complete the rep.";

        // CONTINUOUSLY check if depth is maintained (allows users to adjust at the bottom)
        if (isDown) {
          _hitDownPosition = true; 
          _feedback = "Hold depth, now push up!";
        }

        // Rep Completion: A rep is counted if the UP position is reached
        // AND depth was definitely achieved earlier in this cycle.
        if (isUp && _hitDownPosition) {
          if (DateTime.now().difference(_lastRepTime) >= _cooldownDuration) {
            _repCount++;
            _currentState = DumbbellSplitSquatRightState.up;
            _lastRepTime = DateTime.now();
            _feedback = "Rep $_repCount! Squat down for the next rep.";
            _speakRep("Rep $_repCount!"); // Use fast-speaking for rep count
          }
        } 
        // FAIL-SAFE: If they rise up to the UP position BUT DID NOT hit depth (bounced too shallow)
        else if (isUp && !_hitDownPosition) {
          _currentState = DumbbellSplitSquatRightState.up;
          _feedback = "Go deeper! Rep not counted. Resetting.";
          _speak("Go deeper!");
        }
        
        break;
    }
  }
    
  // ----------------------------------------------------
  // --- Interface Implementation ---
  // ----------------------------------------------------

  @override
  void reset() {
    _repCount = 0;
    _currentState = DumbbellSplitSquatRightState.up;
    _lastRepTime = DateTime.now();
    _hasStarted = false;
    _lastInvalidLandmarksTime = null;
    _isInGracePeriod = false;
    _lastKneeAngle = 0.0;
    // _isMovingUp removed
    _isMovingDown = false; 
    _spokeGoLower = false;
    _spokeStandUp = false;
    _hitDownPosition = false;
    _kneeAngleBuffer.clear();
    _feedback = "Exercise reset. Get into split squat position with right leg forward.";
    _speak(_feedback);
  }

  @override
  String get progressLabel => "Reps: $_repCount";

  @override
  int get reps => _repCount;

  // Public getter for the UI to display the feedback text
  String get feedbackText => _feedback; 
}