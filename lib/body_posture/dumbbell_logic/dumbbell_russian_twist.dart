import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart'; 

enum DumbbellRussianTwistState {
  initial,
  twistedLeft, 
  twistedRight, 
  passedCenter 
}

class DumbbellRussianTwistLogic implements RepExerciseLogic {
  int _repCount = 0;
  DumbbellRussianTwistState _currentState = DumbbellRussianTwistState.initial;
  final FlutterTts _tts = FlutterTts();

  // --- Thresholds ---
  final double _normalizedTwistThreshold = 0.20; // Rep count trigger
  final double _minLandmarkConfidence = 0.7;
  
  // Threshold to determine if the user is in a side view (Hip Z-diff)
  final double _sideViewThresholdZ = 0.35; 
  
  // NEW: Required amount of return from the peak to count as 'passedCenter'.
  // The user must return to 60% of the peak range (0.20 * 0.4 = 0.08)
  final double _centerReturnThreshold = 0.4; 
  
  // --- Smoothing & State ---
  final List<double> _normalizedTwistBuffer = [];
  final int _bufferSize = 5; 

  // Error handling/TTS
  DateTime _lastRepTime = DateTime.now();
  
  // Feedback variable
  String _currentFeedback = "Get into position.";

  DumbbellRussianTwistLogic() {
    _initializeTts();
  }

  void _initializeTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _speak(String text) async {
    if (DateTime.now().difference(_lastRepTime).inMilliseconds < 1000) {
      return;
    }
    await _tts.stop();
    await _tts.speak(text);
    _lastRepTime = DateTime.now();
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

  double _smoothValue(List<double> buffer, double newValue) {
    buffer.add(newValue);
    if (buffer.length > _bufferSize) {
      buffer.removeAt(0);
    }
    return buffer.reduce((a, b) => a + b) / buffer.length;
  }
  
  // Removed unused _getDistance method as per previous diagnostic.
  

  @override
  void update(List<dynamic> landmarks, bool isFrontCamera) {
    final poseLandmarks = landmarks.cast<PoseLandmark>();

    final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
    final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);
    final leftShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.leftShoulder);
    final rightShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.rightShoulder);
    final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
    final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);

    final bool allNecessaryLandmarksValid = _areLandmarksValid([
      leftHip, rightHip, leftWrist, rightWrist, leftShoulder, rightShoulder
    ]);

    if (!allNecessaryLandmarksValid) {
      _currentFeedback = "Adjust position - ensure upper body is visible.";
      if (_repCount == 0) _speak(_currentFeedback);
      return;
    }
    
    // Calculate reference points and normalization factor
    final hipMidX = (leftHip!.x + rightHip!.x) / 2;
    final hipMidY = (leftHip.y + rightHip.y) / 2;
    final hipMidZ = (leftHip.z + rightHip.z) / 2;
    final wristMidX = (leftWrist!.x + rightWrist!.x) / 2;
    final wristMidZ = (leftWrist.z + rightWrist.z) / 2;

    final shoulderMidY = (leftShoulder!.y + rightShoulder!.y) / 2;
    
    // Normalization factor: Torso height (screen-size independence). Use only Y-distance for robustness.
    final torsoHeight = (hipMidY - shoulderMidY).abs();
    
    // --- Determine View Angle (Front vs. Side) ---
    final double hipZDiff = (leftHip.z - rightHip.z).abs();
    final bool isSideView = hipZDiff > _sideViewThresholdZ;

    double normalizedTwist;

    if (isSideView) {
      // SIDE VIEW LOGIC: Twist is measured by depth (Z-axis) movement of the hands.
      final double twistDeltaZ = hipMidZ - wristMidZ;
      normalizedTwist = torsoHeight > 0 ? twistDeltaZ / torsoHeight : 0.0;
      _currentFeedback = "Twist detected (Side View)";
      
    } else {
      // FRONT VIEW LOGIC: Twist is measured by horizontal (X-axis) movement of the hands.
      final double twistDeltaX = wristMidX - hipMidX;
      normalizedTwist = torsoHeight > 0 ? twistDeltaX / torsoHeight : 0.0;
      _currentFeedback = "Twist detected (Front View)";
    }
    
    final double smoothedTwist = _smoothValue(_normalizedTwistBuffer, normalizedTwist);

    // --- Rep Counting Logic (Symmetrical State Machine) ---
    switch (_currentState) {
      case DumbbellRussianTwistState.initial:
        // Transition to the first peak
        if (smoothedTwist > _normalizedTwistThreshold) {
          _currentState = DumbbellRussianTwistState.twistedRight;
          _speak("Twist to the other side.");
        } else if (smoothedTwist < -_normalizedTwistThreshold) {
          _currentState = DumbbellRussianTwistState.twistedLeft;
          _speak("Twist to the other side.");
        }
        break;

      case DumbbellRussianTwistState.twistedLeft:
        // Must return significantly toward center (less than 40% of peak twist)
        if (smoothedTwist > -(_normalizedTwistThreshold * _centerReturnThreshold)) { 
          _currentState = DumbbellRussianTwistState.passedCenter;
        }
        break;

      case DumbbellRussianTwistState.twistedRight:
        // Must return significantly toward center (more than -40% of peak twist)
        if (smoothedTwist < (_normalizedTwistThreshold * _centerReturnThreshold)) { 
          _currentState = DumbbellRussianTwistState.passedCenter;
        }
        break;

      case DumbbellRussianTwistState.passedCenter:
        // Transition to the right peak and count a rep
        if (smoothedTwist > _normalizedTwistThreshold) {
          _repCount++;
          _currentState = DumbbellRussianTwistState.twistedRight;
          _speakRepFeedback();
        } 
        // Transition to the left peak and count a rep
        else if (smoothedTwist < -_normalizedTwistThreshold) {
          _repCount++;
          _currentState = DumbbellRussianTwistState.twistedLeft;
          _speakRepFeedback();
        }
        break;
    }
  }

  void _speakRepFeedback() {
    _speak("Rep $_repCount.");
  }

  @override
  void reset() {
    _repCount = 0;
    _currentState = DumbbellRussianTwistState.initial;
    _lastRepTime = DateTime.now();
    _normalizedTwistBuffer.clear();
    _currentFeedback = "Reset complete. Get into position.";
    _speak(_currentFeedback);
  }

  @override
  String get progressLabel => "Reps: $_repCount";

  @override
  int get reps => _repCount;
}