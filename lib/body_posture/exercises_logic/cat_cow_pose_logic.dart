// lib/body_posture/exercises/exercises_logic/cat_cow_logic.dart

//NEED TESTING

import 'dart:math';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../camera/exercises_logic.dart';

class CatCowLogic implements RepExerciseLogic {
  int _catCowCount = 0;
  bool _isCatPoseActive = false;
  bool _isCowPoseActive = false;
  bool _isRepCompleteSignalSent = false;

  // TTS feedback related fields
  DateTime? _lastFeedbackTime;
  static const Duration _feedbackCooldown = Duration(seconds: 3);
  bool _isInTransition = false;

  // Error handling related fields
  bool _isSensorStable = true; // Used for sensor state tracking
  int _consecutivePoorFrames = 0;
  static const int _maxPoorFramesBeforeReset = 10;
  bool _isRecoveringFromSensorIssue = false;

  // Angle thresholds for spine curvature with tolerance ranges
  final double _catAngleMinThreshold = 85.0; // Lower bound for cat pose
  final double _catAngleMaxThreshold = 95.0; // Upper bound for cat pose
  final double _cowAngleMinThreshold = 105.0; // Lower bound for cow pose
  final double _cowAngleMaxThreshold = 115.0; // Upper bound for cow pose

  // Hysteresis margins to prevent rapid state changes
  final double _hysteresisMargin = 5.0;

  // Thresholds for the "on all fours" starting position with tolerance
  final double _kneeAngleMin = 70.0;
  final double _kneeAngleMax = 110.0;
  final double _armStraightMinAngle = 160.0;
  final double _minLandmarkConfidence = 0.7;

  @override
  String get progressLabel => "Cat-Cows: $_catCowCount";

  /// ✅ Only rep-based exercises expose this
  @override
  int get reps => _catCowCount;

  @override
  void update(List landmarks, bool isFrontCamera) {
    // Check sensor stability before processing
    _isSensorStable = _checkSensorStability(landmarks);
    if (!_isSensorStable) {
      _consecutivePoorFrames++;

      if (_consecutivePoorFrames >= _maxPoorFramesBeforeReset) {
        _handleSensorFailure();
      }
      return;
    }

    // Reset poor frame counter on good frame
    if (_consecutivePoorFrames > 0) {
      _consecutivePoorFrames = 0;

      // If recovering from sensor issue, provide feedback
      if (_isRecoveringFromSensorIssue) {
        _isRecoveringFromSensorIssue = false;
        _provideTTSFeedback("Tracking resumed. Continue your exercise.");
      }
    }

    final landmarksMap = _extractLandmarks(landmarks, isFrontCamera);

    if (!_areLandmarksValid(landmarksMap)) {
      _resetTracking();
      return;
    }

    final angles = _calculateAngles(landmarksMap);
    final isOnAllFours = _checkIfOnAllFours(angles);

    if (!isOnAllFours) {
      _resetTracking();
      _provideTTSFeedback(
        "Please return to all fours position with hands under shoulders and knees under hips.",
      );
      return;
    }

    _detectPoses(angles['averageTrunkAngle']!);
  }

  @override
  void reset() {
    _catCowCount = 0;
    _isCatPoseActive = false;
    _isCowPoseActive = false;
    _isRepCompleteSignalSent = false;
    _lastFeedbackTime = null;
    _isInTransition = false;
    _isSensorStable = true;
    _consecutivePoorFrames = 0;
    _isRecoveringFromSensorIssue = false;
  }

  // 🔽 (helper methods remain unchanged)

  Map<String, Map<PoseLandmarkType, PoseLandmark>> _extractLandmarks(
    List landmarks,
    bool isFrontCamera,
  ) {
    final leftShoulder = _getLandmark(
      landmarks,
      isFrontCamera
          ? PoseLandmarkType.rightShoulder
          : PoseLandmarkType.leftShoulder,
    );
    final leftHip = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip,
    );
    final leftKnee = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightKnee : PoseLandmarkType.leftKnee,
    );
    final leftElbow = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightElbow : PoseLandmarkType.leftElbow,
    );
    final leftWrist = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightWrist : PoseLandmarkType.leftWrist,
    );
    final leftAnkle = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.rightAnkle : PoseLandmarkType.leftAnkle,
    );

    final rightShoulder = _getLandmark(
      landmarks,
      isFrontCamera
          ? PoseLandmarkType.leftShoulder
          : PoseLandmarkType.rightShoulder,
    );
    final rightHip = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip,
    );
    final rightKnee = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee,
    );
    final rightElbow = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow,
    );
    final rightWrist = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist,
    );
    final rightAnkle = _getLandmark(
      landmarks,
      isFrontCamera ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle,
    );

    return {
      'left': {
        PoseLandmarkType.leftShoulder: leftShoulder!,
        PoseLandmarkType.leftHip: leftHip!,
        PoseLandmarkType.leftKnee: leftKnee!,
        PoseLandmarkType.leftElbow: leftElbow!,
        PoseLandmarkType.leftWrist: leftWrist!,
        PoseLandmarkType.leftAnkle: leftAnkle!,
      },
      'right': {
        PoseLandmarkType.rightShoulder: rightShoulder!,
        PoseLandmarkType.rightHip: rightHip!,
        PoseLandmarkType.rightKnee: rightKnee!,
        PoseLandmarkType.rightElbow: rightElbow!,
        PoseLandmarkType.rightWrist: rightWrist!,
        PoseLandmarkType.rightAnkle: rightAnkle!,
      },
    };
  }

  PoseLandmark? _getLandmark(List landmarks, PoseLandmarkType type) {
    try {
      return landmarks.firstWhere((l) => l.type == type);
    } catch (_) {
      return null;
    }
  }

  bool _areLandmarksValid(
    Map<String, Map<PoseLandmarkType, PoseLandmark>> landmarksMap,
  ) {
    final leftLandmarks = landmarksMap['left']!;
    final rightLandmarks = landmarksMap['right']!;

    return leftLandmarks.values.every(
          (landmark) => landmark.likelihood >= _minLandmarkConfidence,
        ) &&
        rightLandmarks.values.every(
          (landmark) => landmark.likelihood >= _minLandmarkConfidence,
        );
  }

  Map<String, double> _calculateAngles(
    Map<String, Map<PoseLandmarkType, PoseLandmark>> landmarksMap,
  ) {
    final leftLandmarks = landmarksMap['left']!;
    final rightLandmarks = landmarksMap['right']!;

    final leftTrunkAngle = _getAngle(
      leftLandmarks[PoseLandmarkType.leftShoulder]!,
      leftLandmarks[PoseLandmarkType.leftHip]!,
      leftLandmarks[PoseLandmarkType.leftKnee]!,
    );

    final rightTrunkAngle = _getAngle(
      rightLandmarks[PoseLandmarkType.rightShoulder]!,
      rightLandmarks[PoseLandmarkType.rightHip]!,
      rightLandmarks[PoseLandmarkType.rightKnee]!,
    );

    final leftKneeBendAngle = _getAngle(
      leftLandmarks[PoseLandmarkType.leftHip]!,
      leftLandmarks[PoseLandmarkType.leftKnee]!,
      leftLandmarks[PoseLandmarkType.leftAnkle]!,
    );

    final rightKneeBendAngle = _getAngle(
      rightLandmarks[PoseLandmarkType.rightHip]!,
      rightLandmarks[PoseLandmarkType.rightKnee]!,
      rightLandmarks[PoseLandmarkType.rightAnkle]!,
    );

    final leftElbowAngle = _getAngle(
      leftLandmarks[PoseLandmarkType.leftShoulder]!,
      leftLandmarks[PoseLandmarkType.leftElbow]!,
      leftLandmarks[PoseLandmarkType.leftWrist]!,
    );

    final rightElbowAngle = _getAngle(
      rightLandmarks[PoseLandmarkType.rightShoulder]!,
      rightLandmarks[PoseLandmarkType.rightElbow]!,
      rightLandmarks[PoseLandmarkType.rightWrist]!,
    );

    return {
      'averageTrunkAngle': (leftTrunkAngle + rightTrunkAngle) / 2,
      'leftKneeBendAngle': leftKneeBendAngle,
      'rightKneeBendAngle': rightKneeBendAngle,
      'leftElbowAngle': leftElbowAngle,
      'rightElbowAngle': rightElbowAngle,
    };
  }

  bool _checkIfOnAllFours(Map<String, double> angles) {
    final isLeftKneeBentCorrectly =
        angles['leftKneeBendAngle']! > _kneeAngleMin &&
        angles['leftKneeBendAngle']! < _kneeAngleMax;

    final isRightKneeBentCorrectly =
        angles['rightKneeBendAngle']! > _kneeAngleMin &&
        angles['rightKneeBendAngle']! < _kneeAngleMax;

    final areArmsStraight =
        angles['leftElbowAngle']! > _armStraightMinAngle &&
        angles['rightElbowAngle']! > _armStraightMinAngle;

    return isLeftKneeBentCorrectly &&
        isRightKneeBentCorrectly &&
        areArmsStraight;
  }

  void _detectPoses(double averageTrunkAngle) {
    // Detect if we're in a transition phase
    _isInTransition =
        averageTrunkAngle > _catAngleMaxThreshold &&
        averageTrunkAngle < _cowAngleMinThreshold;

    // Cat pose detection with hysteresis
    if (averageTrunkAngle >= _catAngleMinThreshold &&
        averageTrunkAngle <= _catAngleMaxThreshold &&
        !_isCatPoseActive &&
        !_isInTransition) {
      _isCatPoseActive = true;
      _isCowPoseActive = false;
      _isRepCompleteSignalSent = false;
      _provideTTSFeedback("Good cat pose. Now move to cow pose.");
    }
    // Cow pose detection with hysteresis
    else if (averageTrunkAngle >= _cowAngleMinThreshold &&
        averageTrunkAngle <= _cowAngleMaxThreshold &&
        !_isCowPoseActive &&
        !_isInTransition) {
      _isCowPoseActive = true;
      _isCatPoseActive = false;
      _isRepCompleteSignalSent = false;
      _provideTTSFeedback("Good cow pose. Now move to cat pose.");
    }

    // Counting completed repetitions with hysteresis
    if (_isCatPoseActive &&
        averageTrunkAngle > _cowAngleMinThreshold + _hysteresisMargin &&
        !_isRepCompleteSignalSent) {
      _catCowCount++;
      _isRepCompleteSignalSent = true;
      _isCatPoseActive = false;
      _isCowPoseActive = true;
      _provideTTSFeedback(
        "Good! $_catCowCount ${_catCowCount == 1 ? 'rep' : 'reps'} completed.",
      );
    } else if (_isCowPoseActive &&
        averageTrunkAngle < _catAngleMaxThreshold - _hysteresisMargin &&
        !_isRepCompleteSignalSent) {
      _catCowCount++;
      _isRepCompleteSignalSent = true;
      _isCowPoseActive = false;
      _isCatPoseActive = true;
      _provideTTSFeedback(
        "Good! $_catCowCount ${_catCowCount == 1 ? 'rep' : 'reps'} completed.",
      );
    } else if (_isInTransition) {
      _isRepCompleteSignalSent = false;
    }
  }

  void _resetTracking() {
    _isCatPoseActive = false;
    _isCowPoseActive = false;
    _isRepCompleteSignalSent = false;
    _isInTransition = false;
  }

  double _getAngle(PoseLandmark p1, PoseLandmark p2, PoseLandmark p3) {
    final double v1x = p1.x - p2.x;
    final double v1y = p1.y - p2.y;
    final double v2x = p3.x - p2.x;
    final double v2y = p3.y - p2.y;

    final double dotProduct = v1x * v2x + v1y * v2y;
    final double magnitude1 = sqrt(v1x * v1x + v1y * v1y);
    final double magnitude2 = sqrt(v2x * v2x + v2y * v2y);

    if (magnitude1 == 0 || magnitude2 == 0) return 180.0;

    double cosineAngle = dotProduct / (magnitude1 * magnitude2);
    cosineAngle = max(-1.0, min(1.0, cosineAngle));

    double angleRad = acos(cosineAngle);
    return angleRad * 180 / pi;
  }

  // New method for TTS feedback with cooldown
  void _provideTTSFeedback(String message) {
    final now = DateTime.now();

    // Skip feedback if we're in cooldown period
    if (_lastFeedbackTime != null &&
        now.difference(_lastFeedbackTime!) < _feedbackCooldown) {
      return;
    }

    // Skip feedback during transitions to avoid confusion
    if (_isInTransition) {
      return;
    }

    // Update last feedback time
    _lastFeedbackTime = now;

    // In a real implementation, this would call a TTS service
    // For now, we'll just print the message
    print("TTS: $message");
  }

  // New method for checking sensor stability
  bool _checkSensorStability(List landmarks) {
    // Check if we have enough landmarks
    if (landmarks.length < 10) {
      return false;
    }

    // Check if landmarks have reasonable confidence
    double avgConfidence =
        landmarks.fold(0.0, (sum, landmark) => sum + landmark.likelihood) /
        landmarks.length;

    // Consider sensor unstable if average confidence is too low
    if (avgConfidence < _minLandmarkConfidence * 0.8) {
      // 80% of the min confidence threshold
      return false;
    }

    return true;
  }

  // New method for handling sensor failure
  void _handleSensorFailure() {
    if (!_isRecoveringFromSensorIssue) {
      _isRecoveringFromSensorIssue = true;
      _provideTTSFeedback(
        "Camera tracking issue detected. Please ensure you're visible in the frame.",
      );
    }

    // Reset tracking but preserve count
    _resetTracking();

    // Reset poor frame counter to allow recovery
    _consecutivePoorFrames = 0;
  }
}
