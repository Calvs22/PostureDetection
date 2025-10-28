// lib/Homepage/Discover/Generatedexercise/startworkout/enhanced_workout_screen.dart

import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutplan_model.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    as el;
import 'package:fitnesss_tracker_app/Homepage/Discover/Exercise List/exercise_logic_factory.dart';
import '../../../../body_posture/camera/pose_detection_camera_screen_v2.dart';

// Helper function to format seconds into mm:ss
String _formatDuration(int totalSeconds) {
  final minutes = (totalSeconds / 60).floor().toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Wrapper to unify both time-based and rep-based exercise logic
class _WorkoutExerciseLogic {
  final el.ExerciseLogic _logic;
  final int _targetValue; // reps or seconds
  final bool _isTimedExercise;

  int _lastKnownReps = 0;
  int _lastKnownSeconds = 0;

  _WorkoutExerciseLogic(this._logic, this._targetValue, this._isTimedExercise);

  void update(List<dynamic> landmarks, bool isFrontCamera) {
    _logic.update(landmarks, isFrontCamera);
  }

  void reset() {
    _logic.reset();
    _lastKnownReps = 0;
    _lastKnownSeconds = 0;
  }

  String get displayProgressLabel {
    if (_isTimedExercise) {
      // Use _formatDuration for the mm:ss display
      final current = _formatDuration(seconds);
      final target = _formatDuration(_targetValue);
      return 'Time: $current / $target';
    } else {
      return 'Reps: $reps / $_targetValue';
    }
  }

  int get reps {
    if (_logic is el.RepExerciseLogic) {
      // ignore: unnecessary_cast
      _lastKnownReps = (_logic as el.RepExerciseLogic).reps;
    }
    return _lastKnownReps;
  }

  int get seconds {
    if (_logic is el.TimeExerciseLogic) {
      // ignore: unnecessary_cast
      _lastKnownSeconds = (_logic as el.TimeExerciseLogic).seconds;
    }
    return _lastKnownSeconds;
  }

  // Use to check for completion
  bool get isComplete {
    if (_isTimedExercise) {
      return seconds >= _targetValue;
    } else {
      return reps >= _targetValue;
    }
  }

  // 🚀 FIX 1 (Part 1): Ensure only *form* feedback is returned, and filter out all progress labels.
  String get feedback {
    final label = _logic.progressLabel;
    
    // Check if the label is the same as the main progress label format.
    // This correctly filters out things like "Reps: 0", "Time: 5s", and "Time: 0s" 
    // that the UI displays, but should not be spoken as "feedback".
    if (label.contains('Reps:') || label.contains('Time:')) {
      return '';
    }

    // Otherwise, it's form feedback (e.g., "Go deeper!", "Hold steady") or "Get Ready!".
    return label;
  }
}

class EnhancedWorkoutScreen extends StatefulWidget {
  final Exercise exercise;
  final ExercisePlan exercisePlan;
  final Function(int progress) onExerciseCompleted;
  final Function(int progress) onSkipExercise;

  const EnhancedWorkoutScreen({
    super.key,
    required this.exercise,
    required this.exercisePlan,
    required this.onExerciseCompleted,
    required this.onSkipExercise,
  });

  @override
  State<EnhancedWorkoutScreen> createState() => _EnhancedWorkoutScreenState();
}

class _EnhancedWorkoutScreenState extends State<EnhancedWorkoutScreen> {
  final GlobalKey<PoseDetectionCameraScreenV2State> _cameraScreenKey =
      GlobalKey();
  late final _WorkoutExerciseLogic _exerciseLogic;

  Timer? _uiUpdateTimer;
  String _currentFeedback = '';
  bool _hasCompletedSet = false;
  late FlutterTts flutterTts;
  final Queue<String> _ttsQueue = Queue<String>();
  bool _isSpeaking = false;
  
  // Keep track of the last announced progress for reps and time
  int _lastAnnouncedRep = 0;
  int _lastAnnouncedSecond = 0;

  @override
  void initState() {
    super.initState();
    _initTts();

    // Determine if the exercise is time-based
    final isTimed = widget.exercise.type.toLowerCase().contains('timer');

    // Use reps field for seconds in timed exercises
    final targetValue = widget.exercisePlan.reps;

    _exerciseLogic = _WorkoutExerciseLogic(
      ExerciseLogicFactory.create(widget.exercise),
      targetValue,
      isTimed,
    );

    // Only start the timer for timed exercises; rep exercises update on every frame
    if (isTimed) _startUiTimer();
  }

  void _startUiTimer() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_hasCompletedSet && mounted) {
        // Call announcer for timed exercises on timer tick
        if (_exerciseLogic._isTimedExercise) {
          _announceProgress();
        }
        
        // _checkWorkoutCompletion is safe to call here because it's outside the build phase.
        _checkWorkoutCompletion();
        setState(() {}); // Refresh display
      } else if (_hasCompletedSet) {
        _stopUiTimer();
      }
    });
  }

  void _stopUiTimer() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
  }

  void _initTts() async {
    flutterTts = FlutterTts();
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
    flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _processQueue();
    });
  }

  void _addToQueue(String text) {
    if (text.isEmpty) return;
    _ttsQueue.add(text);
    _processQueue();
  }
  
  // Function to clear the TTS queue, effectively muting feedback
  void _clearTtsQueue() {
      // Stops anything currently speaking and clears pending items.
      flutterTts.stop();
      _ttsQueue.clear();
      _isSpeaking = false;
  }

  void _processQueue() async {
    if (_isSpeaking || _ttsQueue.isEmpty) return;
    _isSpeaking = true;
    final text = _ttsQueue.removeFirst();
    await flutterTts.speak(text);
    _isSpeaking = false; // Reset after speaking
  }

  // Logic for announcing reps or time
  void _announceProgress() {
    if (_hasCompletedSet) return;

    if (_exerciseLogic._isTimedExercise) {
      final currentSeconds = _exerciseLogic.seconds;
      
      bool shouldAnnounce = false;
      String announcement = '';

      if (currentSeconds > _lastAnnouncedSecond) {
         if (currentSeconds > 0 && currentSeconds <= 5) {
            // Announce first 5 seconds: "1 second", "2 seconds", etc.
            shouldAnnounce = true;
            announcement = '$currentSeconds seconds';
         } else if (currentSeconds >= 10 && currentSeconds % 5 == 0) {
            // Announce every 5 seconds starting at 10: "10 seconds", "15 seconds", etc.
            shouldAnnounce = true;
            
            // Format for announcement (handle minutes):
            final minutes = (currentSeconds / 60).floor();
            final remainingSeconds = currentSeconds % 60;
            
            if (minutes > 0 && remainingSeconds == 0) {
                // Announce "1 minute", "2 minutes", etc.
                announcement = '$minutes minute${minutes > 1 ? 's' : ''}';
            } else if (minutes > 0) {
                // Announce "1 minute and 5 seconds", etc.
                announcement = '$minutes minute${minutes > 1 ? 's' : ''} and $remainingSeconds seconds';
            } else {
                // Announce "10 seconds", "15 seconds", etc.
                announcement = '$remainingSeconds seconds';
            }
         }
      }

      if (shouldAnnounce) {
          _lastAnnouncedSecond = currentSeconds;
          _clearTtsQueue(); // Prioritize count announcement
          _addToQueue(announcement); 
      }
      
    } else { // Rep-based exercise
      final currentReps = _exerciseLogic.reps;

      // 🚀 FIX 2: Check for new rep and announce it.
      if (currentReps > _lastAnnouncedRep) {
        _lastAnnouncedRep = currentReps;
        _clearTtsQueue(); // Explicitly stop/clear everything to ensure rep count is heard
        _addToQueue('Rep $currentReps'); // Announce "Rep 1", "Rep 2", etc.
      }
    }
  }

  void _handleCompletion() {
    if (_hasCompletedSet) return;

    // Mark as complete to prevent further updates
    _hasCompletedSet = true; 
    _stopUiTimer();
    _clearTtsQueue(); // Clear any queued announcements/feedback

    // This correctly extracts reps or seconds based on exercise type.
    final progress = _exerciseLogic._isTimedExercise
        ? _exerciseLogic.seconds
        : _exerciseLogic.reps;
        
    // Announce "Exercise Complete"
    _addToQueue("Exercise complete. Take a break.");

    // Defer the non-UI/Navigation logic to the next microtask.
    Future.microtask(() {
      if (!mounted) return;

      // Call the parent callback (which starts the rest screen in StartWorkoutScreen)
      widget.onExerciseCompleted(progress);

      // The parent (StartWorkoutScreen) is now responsible for handling the navigation.
    });
  }

  void _checkWorkoutCompletion() {
    if (_hasCompletedSet) return;

    if (_exerciseLogic.isComplete) {
      _handleCompletion();
    }
  }

  void _resetProgress() {
    _exerciseLogic.reset();
    _currentFeedback = '';
    _hasCompletedSet = false;
    _lastAnnouncedRep = 0; // RESET ANNOUNCERS
    _lastAnnouncedSecond = 0; // RESET ANNOUNCERS
    _clearTtsQueue(); // Clear queue on reset
    if (_exerciseLogic._isTimedExercise) _startUiTimer();
    setState(() {});
  }

  void _switchCamera() => _cameraScreenKey.currentState?.switchCamera();

  Future<bool> _showBackConfirmationDialog() async {
    if (_hasCompletedSet) return true;
    _clearTtsQueue(); // Clear queue when exiting
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Exercise?'),
        content: const Text(
          'Going back will cancel the current exercise. Are you sure you want to quit?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // Report 0 progress when quitting via back button
              widget.onSkipExercise(0);
              Navigator.pop(context, true);
            },
            child: const Text('Quit', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  void _showSkipConfirmationDialog() {
    _clearTtsQueue(); // Clear queue when skipping
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip Exercise'),
        content: const Text('Skip this exercise? Progress will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Send current progress before skipping
              final progress = _exerciseLogic._isTimedExercise
                  ? _exerciseLogic.seconds
                  : _exerciseLogic.reps;
              widget.onSkipExercise(progress);
            },
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopUiTimer();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _showBackConfirmationDialog,
      child: PoseDetectionCameraScreenV2(
        key: _cameraScreenKey,
        initialIsFrontCamera: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            widget.exercise.name,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.white, blurRadius: 3)],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.cameraswitch, color: Colors.black),
              onPressed: _switchCamera,
            ),
          ],
        ),
        builder: (context, landmarks, size, isFrontCamera) {
          // 1. Update the exercise logic first
          if (!_hasCompletedSet) {
            _exerciseLogic.update(landmarks, isFrontCamera);
            
            // 🚀 FIX 2: Move _announceProgress for Reps into the main frame update,
            // where it will check for new reps and aggressively clear the queue.
            if (!_exerciseLogic._isTimedExercise) {
              _announceProgress();
            }
          }

          // 2. Check for completion for REP-BASED exercises and defer the state change/navigation.
          if (!_exerciseLogic._isTimedExercise &&
              _exerciseLogic.isComplete &&
              !_hasCompletedSet) {
            // Use post-frame callback to call _handleCompletion immediately without
            // waiting for a timer, which will trigger navigation.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _handleCompletion();
            });
          }

          final progressLabel = _exerciseLogic.displayProgressLabel;
          final feedback =
              _exerciseLogic.feedback; // This now only gets form feedback

          // 🚀 FIX 1 (Part 2): Handle TTS: Only queue form feedback if it's new and valid.
          if (feedback.isNotEmpty && feedback != _currentFeedback) {
            // Do NOT check !_isSpeaking here. We rely on _clearTtsQueue in _announceProgress
            // to stop/override the form feedback if a count is ready to be spoken.
            _currentFeedback = feedback;
            _addToQueue(feedback);
          }

          return Stack(
            children: [
              // Progress Display (Only Reps/Time is visible)
              Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress Display (Primary Green Text) - ONLY THIS REMAINS VISIBLE
                      Text(
                        progressLabel,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              
              // Control Buttons
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Reset Button
                    ElevatedButton.icon(
                      onPressed: _hasCompletedSet ? null : _resetProgress, 
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reset'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    ),

                    // Skip Button
                    FloatingActionButton(
                      onPressed: _hasCompletedSet
                          ? null
                          : _showSkipConfirmationDialog,
                      backgroundColor: Colors.redAccent,
                      child: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}