import 'dart:math' as math; 
import 'package:flutter_tts/flutter_tts.dart'; 
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'; 
// NOTE: Assuming this path is correct for your project 
import '../camera/exercises_logic.dart';   

// Renamed state to reflect the Squeeze Press movement 
enum ValleyPressState { inPosition, extended }    
enum ViewOrientation { front, side, unknown } 

// Retaining the original class name as requested.   
class ValleyPressLogic implements RepExerciseLogic { 
     int _repCount = 0; 
     ValleyPressState _currentState = ValleyPressState.inPosition;    
     ViewOrientation _currentView = ViewOrientation.unknown; 
     final FlutterTts _flutterTts = FlutterTts(); 
     

     DateTime _lastRepTime = DateTime.now(); 
     final Duration _cooldownDuration = const Duration(milliseconds: 500); 
     DateTime? _lastFeedbackTime; 
     final Duration _feedbackCooldown = Duration(seconds: 4); 
     bool _hasStarted = false; 

     // --- Angle Thresholds (FURTHER RELAXED) --- 
     // FRONT VIEW (Hip-Shoulder-Wrist angle for Squeeze Press extension)
     final double _frontExtendedAngle = 95.0; // Relaxed from 90.0
     final double _frontInPositionAngle = 120.0; 
        
     // SIDE VIEW (Shoulder-Elbow-Wrist angle for Press extension)
     final double _sideExtendedAngle = 150.0; // Relaxed from 160.0 to be very forgiving (only mostly straight)
     final double _sideInPositionAngle = 90.0; 
     
     final double _angleHysteresis = 5.0; 
     final double _maxWristDistanceRatio = 0.35;    
     final double _sideViewHipShoulderRatio = 0.8; 

     final double _minLandmarkConfidence = 0.7; 

     // Error handling
     bool _isInGracePeriod = false; 

     ValleyPressLogic() { 
         _initializeTts(); 
     } 

     void _initializeTts() async { 
         await _flutterTts.setLanguage("en-US"); 
         await _flutterTts.setPitch(1.0); 
         await _flutterTts.setSpeechRate(0.5); 
     } 

     Future<void> _speak(String message) async { 
         final now = DateTime.now(); 
         if (_lastFeedbackTime != null && now.difference(_lastFeedbackTime!) < _feedbackCooldown) { 
              return; 
         } 
         await _flutterTts.stop(); 
         await _flutterTts.speak(message); 
         _lastFeedbackTime = now; 
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

     double _getDistance(PoseLandmark p1, PoseLandmark p2) { 
         final dx = p1.x - p2.x; 
         final dy = p1.y - p2.y; 
         return math.sqrt(dx * dx + dy * dy); 
     } 
        
     // Calculates the angle P1-P2-P3 
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
        
     ViewOrientation _detectOrientation( 
         PoseLandmark leftShoulder,    
         PoseLandmark rightShoulder,    
         PoseLandmark leftHip,    
         PoseLandmark rightHip 
     ) { 
         final shoulderDistance = _getDistance(leftShoulder, rightShoulder); 
         final hipDistance = _getDistance(leftHip, rightHip); 
            
         final bodyLength = (math.max(leftHip.y, rightHip.y) - math.min(leftShoulder.y, rightShoulder.y)).abs(); 

         if (bodyLength == 0) return ViewOrientation.unknown; 

         // If shoulder distance is much smaller than hip distance, or if shoulder distance    
         // is much smaller than body length, it's likely a SIDE view. 
         if (shoulderDistance / bodyLength < 0.25) { 
              return ViewOrientation.side; 
         } 
            
         // If shoulder distance is close to hip distance, it's a FRONT view. 
         if ((shoulderDistance / hipDistance).abs() > _sideViewHipShoulderRatio) { 
              return ViewOrientation.front; 
         } 

         return ViewOrientation.unknown; 
     } 


     @override 
     void update(List<dynamic> landmarks, bool isFrontCamera) { 
         final poseLandmarks = landmarks.cast<PoseLandmark>(); 

         // --- Mandatory Landmarks for View Detection (NOTE: Declared as 'var' to allow reassignment) --- 
         var leftShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.leftShoulder); 
         var rightShoulder = _getLandmark(poseLandmarks, PoseLandmarkType.rightShoulder); 
         final leftHip = _getLandmark(poseLandmarks, PoseLandmarkType.leftHip); 
         final rightHip = _getLandmark(poseLandmarks, PoseLandmarkType.rightHip); 

         // Initial Check 
         if (!_areLandmarksValid([leftShoulder, rightShoulder, leftHip, rightHip])) { 
              if (!_isInGracePeriod) { 
                  _isInGracePeriod = true; 
                  _speak("Ensure your full torso is visible."); 
              } 
              return; 
         } 
         _isInGracePeriod = false; 

         // 1. Determine the current view (front/side) 
         final newView = _detectOrientation(leftShoulder!, rightShoulder!, leftHip!, rightHip!); 
         if (newView == ViewOrientation.unknown) { 
              _speak("Please face the camera or turn side-on."); 
              return; 
         } 
         _currentView = newView; 
            
         // --- Landmark requirements based on view --- 
         PoseLandmark? wristA, elbowA; 
         double primaryAngle = 0.0; 
         final now = DateTime.now(); 

         if (_currentView == ViewOrientation.front) { 
              // FRONT: Need both arms for squeeze check, and hip/shoulder/wrist angle for extension 
              wristA = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist); 
              final wristB = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist); 
              if (!_areLandmarksValid([wristA, wristB])) return; // Exit if hands not visible 
                 
              // Use the average Hip-Shoulder-Wrist angle 
              final leftAngle = _getAngle(leftHip, leftShoulder, wristA!); 
              final rightAngle = _getAngle(rightHip, rightShoulder, wristB!); 
              primaryAngle = (leftAngle + rightAngle) / 2; 
                 
              // Form check for squeeze (only matters in front view) 
              final wristDistance = _getDistance(wristA, wristB); 
              final shoulderDistance = _getDistance(leftShoulder, rightShoulder); 
              if (wristDistance / shoulderDistance > _maxWristDistanceRatio) { 
                  _speak("Squeeze the weights together!"); 
              } 

         } else { // ViewOrientation.side 
              // SIDE: Need only one arm (shoulder/elbow/wrist) for press extension (Elbow angle) 
              wristA = _getLandmark(poseLandmarks, PoseLandmarkType.leftWrist); 
              elbowA = _getLandmark(poseLandmarks, PoseLandmarkType.leftElbow); 

              if (!_areLandmarksValid([wristA, elbowA])) { 
                  // Try the other side if the first side is invalid 
                  wristA = _getLandmark(poseLandmarks, PoseLandmarkType.rightWrist); 
                  elbowA = _getLandmark(poseLandmarks, PoseLandmarkType.rightElbow); 
                  // Reassign leftShoulder to be the rightShoulder landmark for angle calculation.
                  leftShoulder = rightShoulder; 
                  if (!_areLandmarksValid([wristA, elbowA])) return; // Exit if no arm visible 
              } 
                 
              // Use the Shoulder-Elbow-Wrist angle for extension 
              primaryAngle = _getAngle(leftShoulder, elbowA!, wristA!); 
         } 

         // Initial spoken instructions
         if (!_hasStarted) {
              _speak(_currentView == ViewOrientation.front 
                  ? "Start with weights pressed at your chest." 
                  : "Press forward until your arm is straight.");
              _hasStarted = true;
         } 

         // --- Dynamic Position Checks --- 
         final double extendedThreshold = _currentView == ViewOrientation.front ? _frontExtendedAngle : _sideExtendedAngle; 
         final double inPositionThreshold = _currentView == ViewOrientation.front ? _frontInPositionAngle : _sideInPositionAngle; 
            
         // Angle logic is inverted based on view: 
         // FRONT: Extended is SMALLER angle (95 degrees or less) - Hip-Shoulder-Wrist angle
         final bool isExtendedPosition = _currentView == ViewOrientation.front 
              ? primaryAngle <= extendedThreshold + _angleHysteresis 
              // SIDE: Extended is LARGER angle (150 degrees or more) - Shoulder-Elbow-Wrist angle
              : primaryAngle >= extendedThreshold - _angleHysteresis; 
            
         // FRONT: In Position is LARGER angle (120 degrees or more)
         final bool isInPosition = _currentView == ViewOrientation.front 
              ? primaryAngle >= inPositionThreshold - _angleHysteresis 
              // SIDE: In Position is SMALLER angle (90 degrees or less)
              : primaryAngle <= inPositionThreshold + _angleHysteresis; 


         // --- Rep counting logic (COUNTING ON EXTENSION/SQUEEZE) ---
         if (_currentState == ValleyPressState.inPosition) { 
              if (isExtendedPosition) { 
                  // REP COUNTED: Transition to EXTENDED state and increment count 
                  if (now.difference(_lastRepTime) >= _cooldownDuration) { 
                       _repCount++; // <-- REPETITION IS COUNTED HERE
                       _currentState = ValleyPressState.extended; 
                       _lastRepTime = now; 
                       _speak(_repCount % 5 == 0 ? "Rep $_repCount. Good work! Hold the squeeze." : "Rep $_repCount"); 
                  } else { 
                       _speak("Too fast! Control the press."); 
                  } 
              } else if (primaryAngle < extendedThreshold - 5) { 
                  _speak("Press to Lockout"); 
              } 
         } else if (_currentState == ValleyPressState.extended) { 
              // The user is in the extended state (rep counted), now waiting for return to inPosition 
              if (isInPosition) { 
                  // Transition back to IN_POSITION state (ready for the next rep) 
                  _currentState = ValleyPressState.inPosition; 
                  _speak("Good return. Press again."); 
              } else if (primaryAngle > inPositionThreshold + 10) { 
                  _speak("Pull back to Chest"); 
              } 
         } 
     } 

     @override 
     void reset() { 
         _repCount = 0; 
         _currentState = ValleyPressState.inPosition; 
         _currentView = ViewOrientation.unknown; 
         _lastRepTime = DateTime.now(); 
         _hasStarted = false; 
         _lastFeedbackTime = null; 
         _isInGracePeriod = false; 
         
         _speak("Exercise reset. Please position yourself."); 
     } 

     @override 
     // Minimalist progress label that satisfies the interface and shows ONLY the rep count.
     String get progressLabel => "Reps: $_repCount"; 

     @override 
     int get reps => _repCount; 
}