// lib/Homepage/Discover/Generatedexercise/start_workout_screen.dart

import 'package:fitnesss_tracker_app/Homepage/Discover/Generatedexercise/startworkout/enhanced_workout_screen.dart'
    show EnhancedWorkoutScreen;
import 'package:fitnesss_tracker_app/Homepage/Report/report_page.dart'
    show ReportPage;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:collection';

// Import necessary files
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutplan_model.dart';

// Import the actual DatabaseHelper to save data
import 'package:fitnesss_tracker_app/db/database_helper.dart';

// 🎯 CRITICAL FIX: Import the Supabase Service
import 'package:fitnesss_tracker_app/services/supabase_service.dart';

// Enum to define the overall workout state
enum WorkoutState { intro, exercise, rest, completed }

class StartWorkoutScreen extends StatefulWidget {
  final String workoutId;
  final String workoutName;
  final List<Map<String, dynamic>> exercises;

  const StartWorkoutScreen({
    super.key,
    required this.workoutId,
    required this.workoutName,
    required this.exercises,
  });

  @override
  State<StartWorkoutScreen> createState() => _StartWorkoutScreenState();
}

class _StartWorkoutScreenState extends State<StartWorkoutScreen> {
  // Main Workout Flow State
  WorkoutState _workoutState = WorkoutState.intro;
  int _currentExerciseIndex = 0;
  int _currentSet = 1;

  // Track the user's performance
  final List<Map<String, dynamic>> _userPerformance = [];

  // Timers and TTS
  int _timerRemaining = 0;
  Timer? _timer;
  late FlutterTts flutterTts;
  final Queue<String> _ttsQueue = Queue();
  bool _isProcessingTtsQueue = false;
  late DateTime _workoutStartTime;

  // Track subjective difficulty (for logging only)
  String? _subjectiveDifficulty;

  @override
  void initState() {
    super.initState();
    _initTts();
    _workoutStartTime = DateTime.now();
    _startIntro();
  }

  void _initTts() async {
    flutterTts = FlutterTts();
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);
    flutterTts.setCompletionHandler(() {
      _processTtsQueue();
    });
  }

  void _addToTtsQueue(String text) {
    _ttsQueue.add(text);
    if (!_isProcessingTtsQueue) {
      _processTtsQueue();
    }
  }

  Future<void> _processTtsQueue() async {
    if (_isProcessingTtsQueue || _ttsQueue.isEmpty) {
      return;
    }
    _isProcessingTtsQueue = true;
    final text = _ttsQueue.removeFirst();
    await flutterTts.speak(text);
    _isProcessingTtsQueue = false;
  }

  void _startIntro() {
    _timer?.cancel();
    _timerRemaining = 10;
    _addToTtsQueue('Workout starting. Get ready!');

    if (!mounted) return;
    setState(() {
      _workoutState = WorkoutState.intro;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_timerRemaining > 0) {
        setState(() {
          _timerRemaining--;
        });
        if (_timerRemaining <= 3 && _timerRemaining > 0) {
          _addToTtsQueue('$_timerRemaining');
        } else if (_timerRemaining == 0) {
          _addToTtsQueue('Go!');
        }
      } else {
        _timer?.cancel();
        _startExercise();
      }
    });
  }

  void _startExercise() {
    if (!mounted) return;

    if (_currentExerciseIndex >= widget.exercises.length) {
      _completeWorkout();
      return;
    }

    final currentExercise =
        widget.exercises[_currentExerciseIndex]['details'] as Exercise;
    final exercisePlan =
        widget.exercises[_currentExerciseIndex]['plan'] as ExercisePlan;
    _addToTtsQueue(
      'Start set $_currentSet of ${exercisePlan.sets}, ${currentExercise.name}',
    );

    setState(() {
      _workoutState = WorkoutState.exercise;
    });
  }

  void _startRest(int repsCompleted) {
    _timer?.cancel();

    final currentExercise =
        widget.exercises[_currentExerciseIndex]['details'] as Exercise;
    final exercisePlan =
        widget.exercises[_currentExerciseIndex]['plan'] as ExercisePlan;

    // Store the performance for the set
    _userPerformance.add({
      'exercisePlanId': exercisePlan.id,
      'exerciseName': currentExercise.name,
      'set': _currentSet,
      // CRITICAL: We also explicitly store 'plannedSets' for final aggregation,
      // as one ExercisePlan ID could have multiple sets logged.
      'plannedReps': exercisePlan.reps,
      'plannedSets': exercisePlan.sets,
      'actualReps': repsCompleted,
    });

    _addToTtsQueue('Take a break.');

    _timerRemaining = exercisePlan.rest;

    if (!mounted) return;
    setState(() {
      _workoutState = WorkoutState.rest;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_timerRemaining > 0) {
        setState(() {
          _timerRemaining--;
        });
        if (_timerRemaining <= 3 && _timerRemaining > 0) {
          _addToTtsQueue('$_timerRemaining');
        }
      } else {
        _timer?.cancel();
        _prepareAndStartNextPhase();
      }
    });
  }

  void _prepareAndStartNextPhase() {
    final exercisePlan =
        widget.exercises[_currentExerciseIndex]['plan'] as ExercisePlan;
    final bool isLastSetOfExercise = _currentSet >= exercisePlan.sets;

    if (isLastSetOfExercise) {
      _currentExerciseIndex++;
      _currentSet = 1;
    } else {
      _currentSet++;
    }

    if (_currentExerciseIndex >= widget.exercises.length) {
      _completeWorkout();
    } else {
      _startExercise();
    }
  }

  void _completeWorkout() {
    if (!mounted) return;
    setState(() {
      _workoutState = WorkoutState.completed;
    });
    _addToTtsQueue('Workout completed! Congratulations!');
  }

  /// Logs the session, performance, attempts data synchronization, and adapts the plan.
  void _onFinishAndLog(String difficulty) async {
    // 1. Log the subjective difficulty before clearing the state
    _subjectiveDifficulty = difficulty;

    // 2. Data Preparation and Logging (Local DB)
    final workoutDurationInMinutes = DateTime.now()
        .difference(_workoutStartTime)
        .inMinutes;
    final formattedDate = DateTime.now().toIso8601String();

    final int? workoutListId = int.tryParse(widget.workoutId);

    final sessionId = await DatabaseHelper.instance.insertWorkoutSession(
      date: formattedDate,
      durationInMinutes: workoutDurationInMinutes,
      workoutListId: workoutListId,
      difficultyFeedback: _subjectiveDifficulty, // Log the subjective feedback
    );

    final List<Map<String, dynamic>> performancesToSave = _userPerformance.map((
      performance,
    ) {
      // Safely retrieve and cast values
      final plannedReps = performance['plannedReps'] as int;
      final actualReps = performance['actualReps'] as int;
      final exercisePlanId = performance['exercisePlanId'] as int?;

      // Calculate accuracy, defaulting to 0.0 if plannedReps is 0 (e.g., timed exercises)
      final double accuracy = (plannedReps > 0)
          ? (actualReps / plannedReps * 100).clamp(0.0, 100.0)
          : 0.0;

      return {
        'sessionId': sessionId,
        'exercisePlanId': exercisePlanId,
        'exerciseName': performance['exerciseName'],
        'repsCompleted': actualReps,
        'accuracy': accuracy,
        'plannedReps': plannedReps,
        'plannedSets': performance['plannedSets'] as int,
      };
    }).toList();

    // Insert the performance records to local SQLite
    await DatabaseHelper.instance.insertExercisePerformance(performancesToSave);

    // 3. 🚀 CRITICAL FIX: SUPABASE SYNCHRONIZATION 🚀
    // Create a SupabaseService instance
    final supabaseService = SupabaseService(DatabaseHelper.instance); 
    
    // --- OFFLINE/NETWORK HANDLING FIX: START ---
    try {
      // Attempt to push the locally saved session data to Supabase
      await supabaseService.pushSessionPerformance(sessionId); 
    } catch (e) {
      // If the synchronization fails (e.g., due to no internet), catch the error.
      // The local data is already saved, so we log the failure and proceed 
      // without freezing the UI.
    }
    // --- OFFLINE/NETWORK HANDLING FIX: END ---
  
    // 4. ADAPT THE LOCAL PLAN LOGIC (This is a local DB operation, so it runs fine offline)
    if (workoutListId != null) {
      await DatabaseHelper.instance.adjustWorkoutPlanAfterSession(
        workoutListId: workoutListId,
        difficultyFeedback: _subjectiveDifficulty!,
      );
    }

    // 5. Navigate
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ReportPage()),
      );
    }
  }

  void _skipCurrentPhase({int reps = 0}) {
    _timer?.cancel();
    if (_workoutState == WorkoutState.intro) {
      _startExercise();
    } else if (_workoutState == WorkoutState.exercise) {
      _startRest(reps);
    } else if (_workoutState == WorkoutState.rest) {
      _prepareAndStartNextPhase();
    }
  }

  Future<bool> _onWillPop() async {
    return (await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Are you sure?'),
            content: const Text(
              'Do you want to leave the workout? Your progress will be lost.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        )) ??
        false;
  }

  void _handleSkipDialog({int reps = 0}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Skip'),
          content: Text(
            'Are you sure you want to skip this ${_workoutState == WorkoutState.intro
                ? 'intro'
                : _workoutState == WorkoutState.exercise
                ? 'exercise'
                : 'rest'}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _skipCurrentPhase(reps: reps);
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  void _adjustTime(int seconds) {
    if (!mounted) return;
    setState(() {
      _timerRemaining = (_timerRemaining + seconds).clamp(0, 300);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    flutterTts.stop();
    _ttsQueue.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentExerciseIndex >= widget.exercises.length &&
        _workoutState != WorkoutState.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeWorkout());
    }

    final currentExercise = _currentExerciseIndex < widget.exercises.length
        ? widget.exercises[_currentExerciseIndex]['details'] as Exercise
        : null;
    final exercisePlan = _currentExerciseIndex < widget.exercises.length
        ? widget.exercises[_currentExerciseIndex]['plan'] as ExercisePlan
        : null;

    Widget content;
    String screenTitle;

    switch (_workoutState) {
      case WorkoutState.intro:
        content = _buildIntroScreen();
        screenTitle = 'Get Ready!';
        break;

      case WorkoutState.exercise:
        // Updated to use EnhancedWorkoutScreen
        content = EnhancedWorkoutScreen(
          exercise: currentExercise!,
          exercisePlan: exercisePlan!,
          onExerciseCompleted: _startRest,
          onSkipExercise: _startRest,
        );
        screenTitle = currentExercise.name;
        return content; // Return directly since EnhancedWorkoutScreen has its own AppBar

      case WorkoutState.rest:
        content = _buildRestScreen(currentExercise, exercisePlan);
        screenTitle = 'Rest';
        break;

      case WorkoutState.completed:
        content = _buildCompletedScreen();
        screenTitle = 'Workout Completed!';
        break;
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(screenTitle),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: content,
      ),
    );
  }

  Widget _buildIntroScreen() {
    final firstExercise = widget.exercises[0]['details'] as Exercise;
    final firstExercisePlan = widget.exercises[0]['plan'] as ExercisePlan;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Next Up: ${firstExercise.name}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                if (firstExercise.imagePath != null)
                  Image.asset(
                    firstExercise.imagePath!,
                    height: 200,
                    fit: BoxFit.contain,
                  )
                else
                  const Icon(Icons.fitness_center, size: 100),
                const SizedBox(height: 10),
                Text(
                  'Set 1 of ${firstExercisePlan.sets} | Exercise 1 of ${widget.exercises.length}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_timerRemaining s',
                style: const TextStyle(
                  fontSize: 100,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => _adjustTime(-10),
                    child: const Text('-10 s'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: () => _adjustTime(10),
                    child: const Text('+10 s'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _handleSkipDialog(),
                icon: const Icon(Icons.skip_next),
                label: const Text('Skip'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRestScreen(
    Exercise? currentExercise,
    ExercisePlan? exercisePlan,
  ) {
    final nextExerciseIndex = _currentExerciseIndex + 1;
    final hasNextExercise = nextExerciseIndex < widget.exercises.length;
    final isNextSet = _currentSet < exercisePlan!.sets;

    final nextExerciseDetails = hasNextExercise
        ? widget.exercises[nextExerciseIndex]['details'] as Exercise
        : null;

    final nextExercisePlan = hasNextExercise
        ? widget.exercises[nextExerciseIndex]['plan'] as ExercisePlan
        : null;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Rest',
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (isNextSet) ...[
                  Text(
                    'Next Up: Set ${_currentSet + 1}/${exercisePlan.sets} of ${currentExercise!.name}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  if (currentExercise.imagePath != null)
                    Image.asset(
                      currentExercise.imagePath!,
                      height: 200,
                      fit: BoxFit.contain,
                    )
                  else
                    const Icon(Icons.fitness_center, size: 100),
                ] else if (hasNextExercise) ...[
                  Text(
                    'Next Exercise: Set 1/${nextExercisePlan!.sets} of ${nextExerciseDetails!.name}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  if (nextExerciseDetails.imagePath != null)
                    Image.asset(
                      nextExerciseDetails.imagePath!,
                      height: 200,
                      fit: BoxFit.contain,
                    )
                  else
                    const Icon(Icons.fitness_center, size: 100),
                ] else ...[
                  const Text(
                    'Workout Finished!',
                    style: TextStyle(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Icon(
                    Icons.check_circle_outline,
                    size: 100,
                    color: Colors.green,
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_timerRemaining s',
                style: const TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => _adjustTime(-10),
                    child: const Text('-10 s'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: () => _adjustTime(10),
                    child: const Text('+10 s'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _handleSkipDialog(),
                icon: const Icon(Icons.skip_next),
                label: const Text('Skip Rest'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Workout Completed!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text(
            'How did you feel about this workout?',
            style: TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => _onFinishAndLog('easy'),
                child: const Text('Too easy'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => _onFinishAndLog('right'),
                child: const Text('Just right'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => _onFinishAndLog('hard'),
                child: const Text('Too hard'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
