import 'dart:math' as math;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/foundation.dart';
import '../camera/exercises_logic.dart'; // Assuming this defines RepExerciseLogic

// Added a SQUEEZE state for clarity at the peak of the movement
enum StandingDumbbellCurlState { down, squeeze, lowering }

class StandingDumbbellCurlLogic implements RepExerciseLogic {
   int _repCount = 0;
   StandingDumbbellCurlState _currentState = StandingDumbbellCurlState.down;
   final FlutterTts _flutterTts = FlutterTts();
   
   // Removed the _feedback string variable completely.
   

   // Rep timing and cooldown (Still necessary for rapid movement spamming)
   DateTime _lastRepTime = DateTime.now();
   final Duration _repCooldown = const Duration(milliseconds: 500); 

   // TTS Feedback control
   DateTime? _lastFeedbackTime;
   final Duration _feedbackCooldown = Duration(seconds: 4);

   bool _hasStarted = false; // Flag to ensure initial instructions are given

   // Thresholds (Adjusted for typical curl)
   final double _elbowDownAngle = 165.0; // Arms extended (bottom of movement)
   final double _elbowUpAngle = 55.0; // Arms fully curled (top of movement/contraction)
   final double _torsoAngleThreshold = 160.0; // Torso angle check for swinging
   final double _movementThreshold = 3.0; // Degrees per second (Slightly reduced for slower movement)
   final double _minLandmarkConfidence = 0.7;
   final double _hysteresisMargin = 5.0; // Margin to avoid flickering at thresholds

   // Smoothing
   final List<double> _elbowAngleBuffer = [];
   final List<double> _torsoAngleBuffer = [];
   final int _bufferSize = 5; // Smooth over 5 frames

   // Velocity tracking
   double _lastElbowAngle = 0.0;
   DateTime _lastUpdateTime = DateTime.now();

   // Error handling
   DateTime? _lastInvalidLandmarksTime;
   final Duration _gracePeriod = Duration(seconds: 1);
   bool _isInGracePeriod = false;

   StandingDumbbellCurlLogic() {
      if (!kIsWeb) {
         _initializeTts();
      }
   }

   void _initializeTts() async {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
   }

   // Speak function now only handles TTS.
   Future<void> _speak(String message) async {
      if (kIsWeb) return;
      final now = DateTime.now();
      
      // Cooldown logic only for non-rep count messages
      if (!_isRepCountMessage(message) && _lastFeedbackTime != null &&
            now.difference(_lastFeedbackTime!) < _feedbackCooldown) {
         return;
      }
      await _flutterTts.stop();
      await _flutterTts.speak(message);
      _lastFeedbackTime = now;
   }

   bool _isRepCountMessage(String message) {
      return message.startsWith("Rep") || message.startsWith("Great tempo");
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
      return buffer.isEmpty ? newAngle : buffer.reduce((a, b) => a + b) / buffer.length;
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

   @override
   void update(List<dynamic> landmarks, bool isFrontCamera) {
      if (!_hasStarted) {
         // Initial instruction (TTS only)
         _speak("Stand upright with arms extended, holding dumbbells, facing the camera.");
         _hasStarted = true;
      }

      final poseLandmarks = landmarks.cast<PoseLandmark>();

      // Retrieve landmarks
      final leftShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.leftShoulder);
      final rightShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.rightShoulder);
      final leftElbow = _getLandmark(poseLandmarks, PoseLandmarkType.leftElbow);
      final rightElbow = _getLandmark(poseLandmarks, PoseLandmarkType.rightElbow);
      final leftWrist = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist);
      final rightWrist = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist);
      final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip);
      final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip);

      // Validate landmarks
      final bool allNecessaryLandmarksValid = _areLandmarksValid([
         leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip,
      ]);

      if (!allNecessaryLandmarksValid) {
         // Handle invalid landmarks (TTS only)
         if (!_isInGracePeriod) {
            _lastInvalidLandmarksTime = DateTime.now();
            _isInGracePeriod = true;
            _speak("Ensure your full body is visible and you are facing the camera.");
         } else if (_lastInvalidLandmarksTime != null &&
               DateTime.now().difference(_lastInvalidLandmarksTime!) > _gracePeriod) {
            _currentState = StandingDumbbellCurlState.down;
            _isInGracePeriod = false;
            _speak("Position lost - please restart.");
         }
         return;
      }

      _isInGracePeriod = false;
      _lastInvalidLandmarksTime = null;

      // Calculate angles
      final double leftElbowAngle = _getAngle(leftShoulder!, leftElbow!, leftWrist!);
      final double rightElbowAngle = _getAngle(rightShoulder!, rightElbow!, rightWrist!);
      final double avgElbowAngle = _smoothAngle(_elbowAngleBuffer, (leftElbowAngle + rightElbowAngle) / 2);
      
      // Torso angle (Hip-Shoulder-Elbow) - used for form checking torso lean/swinging
      final double leftTorsoAngle = _getAngle(leftHip!, leftShoulder, leftElbow);
      final double rightTorsoAngle = _getAngle(rightHip!, rightShoulder, rightElbow);
      final double avgTorsoAngle = _smoothAngle(_torsoAngleBuffer, (leftTorsoAngle + rightTorsoAngle) / 2);


      // Calculate velocity
      final now = DateTime.now();
      final timeDelta = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
      // A negative velocity means the angle is decreasing (curling up)
      final velocity = timeDelta > 0.0 ? (avgElbowAngle - _lastElbowAngle) / timeDelta : 0.0;
      _lastElbowAngle = avgElbowAngle;
      _lastUpdateTime = now;

      // Track movement direction
      final bool isMovingUp = velocity < -_movementThreshold; 
      final bool isMovingDown = velocity > _movementThreshold;

      // Form checks (TTS only)
      _checkForm(leftShoulder, rightShoulder, leftElbow, rightElbow, leftHip, rightHip, avgTorsoAngle);

      // Position checks with hysteresis
      final bool isUpPosition = avgElbowAngle <= _elbowUpAngle + _hysteresisMargin;
      final bool isDownPosition = avgElbowAngle >= _elbowDownAngle - _hysteresisMargin;


      // --------------------------------
      // | REPETITION COUNTING LOGIC |
      // --------------------------------

      if (_currentState == StandingDumbbellCurlState.down) {
         if (isUpPosition && isMovingUp) {
            // Transition to SQUEEZE/PEAK state and COUNT THE REP
            if (DateTime.now().difference(_lastRepTime) >= _repCooldown) {
               _repCount++;
               _currentState = StandingDumbbellCurlState.squeeze;
               _lastRepTime = now;
               // Rep counted (TTS only)
               _speak(_repCount % 5 == 0 ? "Great tempo! Reps: $_repCount. Now lower slowly." : "Rep $_repCount. Lower the weight.");
            } else {
               _currentState = StandingDumbbellCurlState.squeeze; // Still transition the state
               // Too fast instruction (TTS only)
               _speak("Too fast! Control the movement.");
            }
         } else if (avgElbowAngle < _elbowDownAngle - 10) {
            // Lift up instruction (TTS only)
            _speak("Lift up.");
         }
      } else if (_currentState == StandingDumbbellCurlState.squeeze) {
         // User has reached the peak and is now either holding or starting the descent.
         if (isMovingDown) {
            _currentState = StandingDumbbellCurlState.lowering;
            // Descent instruction (TTS only)
            _speak("Control the descent.");
         } else if (!isUpPosition) {
            _currentState = StandingDumbbellCurlState.lowering;
         } 
      } else if (_currentState == StandingDumbbellCurlState.lowering) {
         if (isDownPosition && isMovingDown) {
            // User reached full extension, ready for the next rep.
            _currentState = StandingDumbbellCurlState.down;
            // Next rep instruction (TTS only)
            _speak("Full extension. Curl up for the next rep.");
         } else if (!isDownPosition && avgElbowAngle > _elbowDownAngle - 10) {
            // Full extension instruction (TTS only)
            _speak("Fully extend your arms.");
         }
      }
   }

   void _checkForm(
      PoseLandmark leftShoulder,
      PoseLandmark rightShoulder,
      PoseLandmark leftElbow,
      PoseLandmark rightElbow,
      PoseLandmark leftHip,
      PoseLandmark rightHip,
      double avgTorsoAngle,
   ) {
      // Torso angle check (Back straightness / swinging) (TTS only)
      if (avgTorsoAngle < _torsoAngleThreshold) {
         _speak("Keep your back straight. Avoid swinging.");
      }
      
      // Additional form check for elbow drift (moving forward) (TTS only)
      final double leftUpperArmAngle = _getAngle(leftElbow, leftShoulder, leftHip);
      final double rightUpperArmAngle = _getAngle(rightElbow, rightShoulder, rightHip);
      
      final double avgUpperArmAngle = (leftUpperArmAngle + rightUpperArmAngle) / 2;
      // Give feedback on form during the lifting phase (TTS only)
      if (avgUpperArmAngle < 165.0 && _currentState != StandingDumbbellCurlState.down) {
         _speak("Keep your elbows pinned to your sides.");
      }
   }

   @override
   void reset() {
      _repCount = 0;
      _currentState = StandingDumbbellCurlState.down;
      _lastRepTime = DateTime.now();
      _hasStarted = false;
      _lastFeedbackTime = null;
      _lastInvalidLandmarksTime = null;
      _isInGracePeriod = false;
      _lastElbowAngle = 0.0;
      _lastUpdateTime = DateTime.now();
      _elbowAngleBuffer.clear();
      _torsoAngleBuffer.clear();
      // Reset voice instruction (TTS only)
      _speak("Exercise reset. Stand upright with arms extended, facing the camera.");
   }

   @override
   // progressLabel now only shows the rep count, as requested.
   String get progressLabel => "Reps: $_repCount";

   @override
   int get reps => _repCount;
}