// ignore_for_file: avoid_function_literals_in_foreach_calls, avoid_print, file_names, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutlist_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutplan_model.dart'; // Contains ExercisePlan
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workout_preference_model.dart';
import '/Homepage/Discover/Generatedexercise/exercise_selectionscreen.dart';
import 'package:fitnesss_tracker_app/Homepage/Discover/Generatedexercise/startworkout/start_workout_screen.dart';

// --- NEW VALIDATION FORMATTERS AND PARSERS ---

// Formats a number to a max value.
class _NumberInputFormatter extends TextInputFormatter {
  final int maxValue;

  _NumberInputFormatter({required this.maxValue});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final int? value = int.tryParse(newValue.text);
    if (value != null && value > maxValue) {
      final cappedText = maxValue.toString();
      return TextEditingValue(
        text: cappedText,
        selection: TextSelection.collapsed(offset: cappedText.length),
      );
    }
    return newValue;
  }
}

// Formats a time string (MM:SS) and validates against a max value in seconds.
class _TimeInputFormatter extends TextInputFormatter {
  final int maxValueInSeconds;

  _TimeInputFormatter({required this.maxValueInSeconds});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String newText = newValue.text;
    if (newText.isEmpty) {
      return newValue;
    }

    // Remove any non-digit characters
    newText = newText.replaceAll(RegExp(r'[^0-9]'), '');

    // Add colon
    if (newText.length > 2) {
      newText = '${newText.substring(0, 2)}:${newText.substring(2)}';
    }

    // Truncate to MM:SS format
    if (newText.length > 5) {
      newText = newText.substring(0, 5);
    }

    // Parse to seconds for validation
    final int minutes = int.tryParse(newText.split(':')[0]) ?? 0;
    final int seconds =
        newText.contains(':') ? int.tryParse(newText.split(':')[1]) ?? 0 : 0;
    final int totalSeconds = minutes * 60 + seconds;

    // Check against max value and adjust
    if (totalSeconds > maxValueInSeconds) {
      final cappedMinutes = (maxValueInSeconds ~/ 60).toString().padLeft(2, '0');
      final cappedSeconds = (maxValueInSeconds % 60).toString().padLeft(2, '0');
      newText = '$cappedMinutes:$cappedSeconds';
    } else if (seconds > 59) {
      // Handle seconds overflow
      final cappedSeconds = '59';
      newText = '${newText.substring(0, 3)}$cappedSeconds';
    }

    // Return the new value with the correct selection
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

// Formats seconds to a MM:SS string
String _formatSecondsToTime(int totalSeconds) {
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

// Parses a MM:SS string to total seconds
int _parseTimeStringToSeconds(String timeString) {
  if (timeString.isEmpty) return 0;
  final parts = timeString.split(':');
  if (parts.length == 2) {
    final minutes = int.tryParse(parts[0]) ?? 0;
    final seconds = int.tryParse(parts[1]) ?? 0;
    return (minutes * 60) + seconds;
  }
  return int.tryParse(timeString) ?? 0;
}

class WorkoutPlanScreen extends StatefulWidget {
  final int? workoutListId;
  final bool isManualCreation;

  const WorkoutPlanScreen({
    super.key,
    this.workoutListId,
    required this.isManualCreation,
  });

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen> {
  final dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _exercisesWithDetails = [];
  bool _isLoading = true;
  String? _userEquipment;
  int? _currentWorkoutListId;
  String _currentPlanName = 'Workout Plan';

  // New state variables for safety checks
  int _userWeeklyGoal = 0;
  bool _userHasDisease = false; // To check cardiopulmonary safety

  bool _isEditMode = false;

  late TextEditingController _planNameController;

  @override
  void initState() {
    super.initState();
    _currentWorkoutListId = widget.workoutListId;

    _isEditMode = widget.isManualCreation && widget.workoutListId == null;

    if (widget.isManualCreation && widget.workoutListId == null) {
      _setInitialPlanName();
      _planNameController = TextEditingController(text: 'Loading...');
    } else {
      _planNameController = TextEditingController();
      _loadWorkoutData();
    }
  }

  @override
  void dispose() {
    _planNameController.dispose();
    super.dispose();
  }

  Future<void> _setInitialPlanName() async {
    final nextNumber = await dbHelper.getNextManualPlanNumber();
    final newName = 'Manual Workout Plan $nextNumber';

    if (mounted) {
      setState(() {
        _currentPlanName = newName;
      });
      _planNameController.text = newName;
    }

    await _savePlanName();

    _loadWorkoutData();
  }

  Future<void> _loadWorkoutData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final WorkoutPreference? userPreference =
        await dbHelper.getLatestWorkoutPreference();
    if (userPreference != null) {
      _userEquipment = userPreference.equipment;
      // Removed the assignment to _soreMuscleGroup here, as it's unused.
    }

    // Fetch UserInfo and weekly goal & disease flag
    final userInfo = await dbHelper.getLatestUserInfo();
    if (userInfo != null) {
      _userWeeklyGoal = userInfo['weeklyGoal'] ?? 0;
      // Convert stored INTEGER (0 or 1) back to boolean
      _userHasDisease = (userInfo['haveDisease'] as int?) == 1; 
    }

    if (_currentWorkoutListId != null) {
      final list = await dbHelper.getWorkoutListById(_currentWorkoutListId!);

      if (list != null) {
        _currentPlanName = list.listName;
        _planNameController.text = list.listName;
      }

      final loadedExercises =
          await dbHelper.getExercisesForWorkoutList(_currentWorkoutListId!);
      loadedExercises.sort((a, b) => a.sequence.compareTo(b.sequence));

      final allExercises = await dbHelper.getAllExercises();
      final Map<int?, Exercise> exerciseMap = {
        for (var ex in allExercises) ex.id: ex
      };

      final List<Map<String, dynamic>> exercisesWithDetails = [];
      for (var plan in loadedExercises) {
        final exerciseDetails = exerciseMap[plan.exerciseId];
        if (exerciseDetails != null) {
          exercisesWithDetails.add({
            'plan': plan,
            'details': exerciseDetails,
          });
        }
      }

      if (mounted) {
        setState(() {
          _exercisesWithDetails = exercisesWithDetails;
          _isLoading = false;
        });
        // Show Cardiopulmonary safety warning after data loads
        if (!_isEditMode) {
          _showCardioSafetyWarning();
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ------------------------------------------------------------------
  // --- PART 1: CARDIOPULMONARY SAFETY CHECK (ON LOAD) ---
  // ------------------------------------------------------------------

  // Check if the current plan is above the safety threshold (2 sets, 15 reps/sec)
// Check if the current plan is above the new safety threshold.
bool _isPlanAboveSafetyThreshold() {
  for (var item in _exercisesWithDetails) {
    final plan = item['plan'] as ExercisePlan;
    // final details = item['details'] as Exercise; // Not strictly needed here

    final int sets = plan.sets;
    final int reps = plan.reps; // This is Reps or Seconds (Time)

    // Rule 1: 3 Sets or more (e.g., 3 sets, 1 rep -> DANGER)
    if (sets >= 3) {
      return true;
    }

    // Rule 2: 2 Sets AND Reps/Time is 16 or higher (e.g., 2 sets, 16 reps -> DANGER)
    if (sets == 2 && reps >= 16) {
      return true;
    }

    // Rule 3: 1 Set AND Reps/Time is 31 or higher (e.g., 1 set, 31 reps -> DANGER)
    if (sets == 1 && reps >= 31) {
      return true;
    }
  }
  return false;
}
  // Apply the safe settings (1 set, 10 reps, 15 sec for timer)
// Apply the safe settings (1 set, 10 reps, 15 sec for timer)
Future<void> _adjustPlanToSafetySettings() async {
  if (_currentWorkoutListId == null) return;
  
  // Conservative safety setting to apply when a threshold is exceeded
  const int safeSets = 1;
  const int safeRepsCount = 10; // For Reps exercises (below 31 threshold)
  const int safeTimeSeconds = 15; // For Timer exercises (below 31 threshold)
  
  final List<ExercisePlan> updatedExercises = [];
  final List<ExercisePlan> exercisesToUpdate = await dbHelper.getExercisesForWorkoutList(_currentWorkoutListId!);
  final allExercises = await dbHelper.getAllExercises();
  final Map<int?, Exercise> exerciseMap = { for (var ex in allExercises) ex.id: ex };

  for (var plan in exercisesToUpdate) {
    final details = exerciseMap[plan.exerciseId];
    if (details == null) continue;
    
    int newSets = plan.sets;
    int newReps = plan.reps;

    final int currentSets = plan.sets;
    final int currentReps = plan.reps;

    // Check against the DANGER threshold (same logic as _isPlanAboveSafetyThreshold)
    final bool isAboveSafety = (currentSets >= 3) || 
                               (currentSets == 2 && currentReps >= 16) || 
                               (currentSets == 1 && currentReps >= 16);
    
    if (isAboveSafety) {
      newSets = safeSets;
      if (details.type == 'Timer') {
        newReps = safeTimeSeconds;
      } else {
        newReps = safeRepsCount;
      }
    }
    
    // Add the (potentially unchanged) plan to the list
    updatedExercises.add(plan.copyWith(sets: newSets, reps: newReps));
  }
  
  // Perform the bulk update in the database
  await dbHelper.updateWorkoutPlan(_currentWorkoutListId!, updatedExercises);
  
  // Reload data to reflect changes
  _loadWorkoutData();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Workout plan adjusted to safer intensity (1 set, max 10 reps/15 sec).')),
  );
}

void _showCardioSafetyWarning() {
  if (!_userHasDisease || !_isPlanAboveSafetyThreshold()) {
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Safety Warning:\n High Intensity'),
          ],
        ),
        // Updated dialog content for the new combination-based check
        content: const Text(
          'Your profile indicates a heart/lung condition. The current workout is above safety thresholds (e.g., 3+ Sets, or 2 Sets & 16+ Reps).\n\nDo you want to adjust all high-intensity exercises to a safer level (1 Set, max 10 Reps/15 sec)?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Proceed Anyway'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _adjustPlanToSafetySettings();
            },
            child: const Text('Adjust to Safety'),
          ),
        ],
      );
    },
  );
}

  // ------------------------------------------------------------------
  // --- PART 2: START WORKOUT SAFETY CHECK (SORE MUSCLE) ---
  // ------------------------------------------------------------------

  // Checks which exercises target the chosen muscle group (Upper/Lower Body)
  List<Map<String, dynamic>> _getAffectedExercises(String soreArea) {
    if (soreArea == 'None' || soreArea.isEmpty) return [];

    final affected = <Map<String, dynamic>>[];
    final soreAreaLower = soreArea.toLowerCase();

    // Define keywords for simple upper/lower body detection
    final upperBodyKeywords = ['chest', 'back', 'shoulder', 'arm', 'triceps', 'biceps', 'abs', 'core'];
    final lowerBodyKeywords = ['leg', 'glute', 'quad', 'hamstring', 'calf'];

    // Determine the set of keywords to check based on user input
    final checkKeywords = soreAreaLower.contains('upper') 
        ? upperBodyKeywords 
        : soreAreaLower.contains('lower')
            ? lowerBodyKeywords
            : [];
            
    if (checkKeywords.isEmpty) return [];

    for (var item in _exercisesWithDetails) {
      final details = item['details'] as Exercise;
      
      // Assuming primaryMuscleGroups is stored as a comma-separated string in the Exercise model
      final dynamic muscleData = details.primaryMuscleGroups;
      
      final List<String> primaryMuscleGroups;

      if (muscleData is String) {
        primaryMuscleGroups = muscleData.split(',').map((e) => e.trim().toLowerCase()).toList();
      } else if (muscleData is List) {
        // If it's a List<String> (as the error suggests it might be)
        primaryMuscleGroups = muscleData.map((e) => e.toString().trim().toLowerCase()).toList();
      } else {
        primaryMuscleGroups = [];
      }

      // Check if any muscle group in the exercise is in the checkKeywords list
      final isAffected = primaryMuscleGroups.any((muscle) => checkKeywords.any((keyword) => muscle.contains(keyword)));

      if (isAffected) {
        affected.add(item);
      }
    }
    return affected;
  }

  // Adjusts the plan by replacing affected exercises with non-conflicting ones
  Future<void> _replaceAffectedExercises(List<Map<String, dynamic>> affected) async {
    if (_currentWorkoutListId == null || affected.isEmpty) return;
    
    // --- 1. Determine the sore area keyword based on the affected exercises ---
    final dynamic firstAffectedMuscles = (affected.first['details'] as Exercise).primaryMuscleGroups;
    
    final muscleList = (firstAffectedMuscles is String) 
        ? firstAffectedMuscles.split(',').map((e) => e.trim().toLowerCase()).toList() 
        : (firstAffectedMuscles is List) 
            ? firstAffectedMuscles.map((e) => e.toString().trim().toLowerCase()).toList()
            : <String>[];
    
    String soreAreaKeyword = '';
    if (muscleList.any((m) => m.contains('leg') || m.contains('glute') || m.contains('quad') || m.contains('calf'))) {
        soreAreaKeyword = 'lower';
    } else if (muscleList.any((m) => m.contains('chest') || m.contains('back') || m.contains('arm') || m.contains('shoulder') || m.contains('core') || m.contains('abs'))) {
        soreAreaKeyword = 'upper';
    }
    
    if (soreAreaKeyword.isEmpty) return; // Cannot determine replacement area

    // --- 2. Find replacement exercises (opposite body part) ---
   // In _WorkoutPlanScreenState (inside _replaceAffectedExercises)

// --- 2. Find replacement exercises (opposite body part) ---
final allExercises = await dbHelper.getAllExercises();
final nonConflictingExercises = allExercises.where((ex) {
  
  // 💡 CORRECTED LOGIC START: Safely handle primaryMuscleGroups type
  final dynamic muscleData = ex.primaryMuscleGroups;
  
  final List<String> exMuscleGroups;
  
  if (muscleData is String) {
    // Treat as a comma-separated string, which is common for database storage
    exMuscleGroups = muscleData.split(',').map((e) => e.trim().toLowerCase()).toList();
  } else if (muscleData is List) {
    // Treat as an already processed list of strings (the cause of your error)
    exMuscleGroups = muscleData.map((e) => e.toString().trim().toLowerCase()).toList();
  } else {
    exMuscleGroups = [];
  }
  // 💡 CORRECTED LOGIC END

  if (soreAreaKeyword == 'upper') {
    // Find exercises that are NOT upper body (i.e., they are lower body or neutral)
    return exMuscleGroups.any((m) => m.contains('leg') || m.contains('glute') || m.contains('quad') || m.contains('calf'));
  } else if (soreAreaKeyword == 'lower') {
    // Find exercises that are NOT lower body (i.e., they are upper body or neutral)
    return exMuscleGroups.any((m) => m.contains('chest') || m.contains('back') || m.contains('arm') || m.contains('shoulder') || m.contains('core') || m.contains('abs'));
  }
  return false; 
}).toList();

    if (nonConflictingExercises.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find enough non-conflicting exercises to replace.')),
        );
        return;
    }

    // --- 3. Replace each affected exercise ---
    for (var item in affected) {
      final exercisePlan = item['plan'] as ExercisePlan;
      
      // Select a random non-conflicting exercise
      final newExercise = nonConflictingExercises[
          (DateTime.now().microsecondsSinceEpoch % nonConflictingExercises.length)];
      
      // Perform replacement in the database
      await dbHelper.replaceWorkoutExercise(
        _currentWorkoutListId!,
        exercisePlan.sequence,
        newExercise.id!,
        newExercise.name,
      );
    }
    
    // Reload data and inform user
    await _loadWorkoutData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Successfully replaced ${affected.length} exercises with non-conflicting ones.')),
    );
  }
  
  // Replaces the original _showStartWorkoutWarning
  void _showStartWorkoutWarning() async {
    if (_exercisesWithDetails.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add exercises before starting the workout!')),
      );
      return;
    }
    if (_currentWorkoutListId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Workout plan ID is missing.')),
      );
      return;
    }

    // Sort exercises before showing any dialogs
    final sectionOrder = {'Warm-Up': 1, 'Workout': 2, 'Cool-Down': 3};
    _exercisesWithDetails.sort((a, b) {
      final titleA = a['plan'].title;
      final titleB = b['plan'].title;
      final sequenceA = a['plan'].sequence;
      final sequenceB = b['plan'].sequence;

      final int sectionOrderA = sectionOrder[titleA] ?? 99;
      final int sectionOrderB = sectionOrder[titleB] ?? 99;

      if (sectionOrderA != sectionOrderB) {
        return sectionOrderA.compareTo(sectionOrderB);
      }
      return sequenceA.compareTo(sequenceB);
    });

    // --- SORE MUSCLE / AFFECTED EXERCISE CHECK ---
    
    // 1. Ask about current pain/soreness (Upper/Lower/None)
    final String? chosenSoreMuscle = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Check for Soreness'),
          content: const Text('Do you have soreness in your body today?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop('None'),
              child: const Text('None'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('Upper Body'),
              child: const Text('Upper Body'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('Lower Body'),
              child: const Text('Lower Body'),
            ),
          ],
        );
      },
    );

    final String soreAreaChoice = chosenSoreMuscle ?? 'None';
    
    // 2. Check for conflicts based on the choice
    if (soreAreaChoice != 'None') {
      final affectedExercises = _getAffectedExercises(soreAreaChoice);

      if (affectedExercises.isNotEmpty) {
        final exerciseNames = affectedExercises
            .map((e) => (e['plan'] as ExercisePlan).exerciseName)
            .take(3)
            .join(', '); // Show max 3 names
        
        // 3. Show Conflict Dialog
        final String? soreMuscleAction = await showDialog<String?>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Soreness Conflict: $soreAreaChoice'),
              content: Text(
                'You indicated soreness in your $soreAreaChoice, but your plan contains affected exercises (e.g., $exerciseNames).\n\nWhat would you like to do?',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop('Cancel'),
                  child: const Text('Cancel Workout'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop('Proceed'),
                  child: const Text('Proceed Anyway'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop('Adjust'),
                  child: const Text('Adjust (Replace Exercises)'),
                ),
              ],
            );
          },
        );
        
        if (soreMuscleAction == 'Cancel') return; // Stop the workout process
        
        if (soreMuscleAction == 'Adjust') {
          await _replaceAffectedExercises(affectedExercises);
          // If no exercises are left after replacement, stop.
          if (_exercisesWithDetails.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No exercises left after adjustment!')),
            );
            return;
          }
        }
      }
    }

    // --- 4. MAIN START WARNING DIALOG (Daily Goal/Today's Workout Check) ---
    final bool workedOutToday = await dbHelper.didUserWorkoutToday();
    final int workoutsThisWeek = await dbHelper.getWorkoutsCompletedThisWeek();
    final bool goalReached = workoutsThisWeek >= _userWeeklyGoal && _userWeeklyGoal > 0;
    
    List<String> warnings = [];

    if (workedOutToday) {
      warnings.add('You have already completed a workout today.');
    }

    if (goalReached) {
      if (_userWeeklyGoal > 0) {
        final plural = _userWeeklyGoal > 1 ? 'times' : 'time';
        warnings.add(
            'You have already reached your weekly goal of $_userWeeklyGoal $plural this week.');
      }
    }
    
    String dialogTitle = warnings.isNotEmpty ? 'Warning: Proceed?' : 'Start Workout?';
    String confirmText = warnings.isNotEmpty ? 'Proceed' : 'Start';
    String mainQuestion = 'Are you sure you want to start the "$_currentPlanName" workout?';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (warnings.isNotEmpty) ...[
                  Text(
                    warnings.join('\n'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                ],
                Text(mainQuestion),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => StartWorkoutScreen(
                      workoutId: _currentWorkoutListId!.toString(),
                      workoutName: _currentPlanName,
                      exercises: _exercisesWithDetails,
                    ),
                  ),
                );
              },
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
  }

  void _startWorkout() {
    // Triggers the safety checks and main dialog flow
    _showStartWorkoutWarning();
  }

  /// Toggles edit mode, saving changes directly when "Done" is pressed.
  void _toggleEditMode() async {
    if (_isEditMode) {
      await _saveChanges();
      if (mounted) {
        setState(() {
          _isEditMode = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isEditMode = true;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_currentWorkoutListId == null) {
      await _savePlanName();
    }
    if (mounted) {
      setState(() {
      });
    }
  }

  Future<void> _addExercise(String section) async {
    final String equipmentForSelection = _userEquipment ?? 'All';

    if (_currentWorkoutListId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait, saving initial plan first.')),
      );
      return;
    }

    int listId = _currentWorkoutListId!;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ExerciseSelectionScreen(
          workoutListId: listId,
          section: section,
          isReplacing: false,
          userEquipment: equipmentForSelection,
        ),
      ),
    );
    _loadWorkoutData();
  }

  Future<void> _savePlanName() async {
    if (_currentWorkoutListId == null) {
      final newlistId = await dbHelper.insertWorkoutList(
        WorkoutList(listName: _planNameController.text),
      );

      if (mounted) {
        setState(() {
          _currentWorkoutListId = newlistId;
          _currentPlanName = _planNameController.text;
        });
      }
    }
  }

  Future<void> _editExercise(ExercisePlan exercise, Exercise exerciseDetails) async {
    TextEditingController setsController =
        TextEditingController(text: exercise.sets.toString());
    TextEditingController repsController = TextEditingController(
        text: exerciseDetails.type == 'Timer'
            ? _formatSecondsToTime(exercise.reps)
            : exercise.reps.toString());
    TextEditingController restController =
        TextEditingController(text: _formatSecondsToTime(exercise.rest));

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit ${exercise.exerciseName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: setsController,
                  decoration: const InputDecoration(labelText: 'Sets (max 10)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [_NumberInputFormatter(maxValue: 10)],
                ),
                TextField(
                  controller: repsController,
                  decoration: InputDecoration(
                      labelText: exerciseDetails.type == 'Timer'
                          ? 'Time (MM:SS, max 10:00)'
                          : 'Reps (max 40)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    if (exerciseDetails.type == 'Timer')
                      // New: 10 mins = 600 seconds
                      _TimeInputFormatter(maxValueInSeconds: 600)
                    else
                      _NumberInputFormatter(maxValue: 40),
                  ],
                ),
                TextField(
                  controller: restController,
                  decoration:
                      const InputDecoration(labelText: 'Rest (MM:SS, max 10:00)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    _TimeInputFormatter(maxValueInSeconds: 600),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final int newSets =
                    (int.tryParse(setsController.text) ?? 0) <= 0
                        ? 1
                        : int.tryParse(setsController.text)!;
                final int newReps =
                    (exerciseDetails.type == 'Timer'
                            ? _parseTimeStringToSeconds(repsController.text)
                            : int.tryParse(repsController.text) ?? 0) <=
                        0
                        ? 1
                        : exerciseDetails.type == 'Timer'
                            ? _parseTimeStringToSeconds(repsController.text)
                            : int.tryParse(repsController.text)!;
                final newRest = _parseTimeStringToSeconds(restController.text);
                await dbHelper.updateWorkoutExercise(
                  exercise.id!,
                  newSets,
                  newReps,
                  newRest,
                );
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    _loadWorkoutData();
  }

  Future<void> _replaceExercise(
      ExercisePlan exerciseToReplace, String section) async {
    if (_currentWorkoutListId == null) {
      return;
    }

    final String equipmentForSelection = _userEquipment ?? 'All';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ExerciseSelectionScreen(
          workoutListId: _currentWorkoutListId!,
          section: section,
          isReplacing: true,
          userEquipment: equipmentForSelection,
        ),
      ),
    ).then((newExercise) async {
      if (newExercise != null) {
        final newPlan = newExercise as ExercisePlan;
        await dbHelper.replaceWorkoutExercise(
          _currentWorkoutListId!,
          exerciseToReplace.sequence,
          newPlan.exerciseId,
          newPlan.exerciseName,
        );
      }
      _loadWorkoutData();
    });
  }

  Future<void> _removeExercise(int sequence) async {
    if (_currentWorkoutListId == null) {
      return;
    }
    await dbHelper.removeWorkoutExercise(_currentWorkoutListId!, sequence);
    _loadWorkoutData();
  }

  Map<String, List<Map<String, dynamic>>> _groupExercises() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var exercise in _exercisesWithDetails) {
      final title = exercise['plan'].title;
      if (!grouped.containsKey(title)) {
        grouped[title] = [];
      }
      grouped[title]!.add(exercise);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final groupedExercises = _groupExercises();
    List<String> sections = ['Warm-Up', 'Workout', 'Cool-Down'];

    if (!_isEditMode && !widget.isManualCreation) {
      sections = sections.where(groupedExercises.containsKey).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentPlanName),
        actions: [
          TextButton(
            onPressed: _toggleEditMode,
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            child: Text(
              _isEditMode ? 'Done' : 'Edit',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...sections.map((title) {
                    final exercisesInSection = groupedExercises[title] ?? [];
                    return _buildSection(title, exercisesInSection);
                  }),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),

          if (!_isEditMode)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: ElevatedButton.icon(
                onPressed: _startWorkout,
                icon: const Icon(Icons.play_arrow),
                label: const Text(
                  'Start Workout',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> exercises) {
    final bool isEditable = _isEditMode;

    if (exercises.isEmpty && isEditable == false) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: title == 'Warm-Up'
                          ? Colors.blue
                          : title == 'Cool-Down'
                              ? Colors.purple
                              : Colors.green,
                    ),
              ),
              if (isEditable)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _addExercise(title),
                ),
            ],
          ),
        ),

        if (exercises.isEmpty && isEditable)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Text(
              'No exercises added yet. Tap the + icon above to add a $title exercise.',
              style:
                  TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[600]),
            ),
          ),

        ...exercises.map((item) {
          final exercisePlan = item['plan'] as ExercisePlan;
          final exerciseDetails = item['details'] as Exercise;

          final String repsText = exerciseDetails.type == 'Timer'
              ? _formatSecondsToTime(exercisePlan.reps)
              : exercisePlan.reps.toString();
          final String restText = _formatSecondsToTime(exercisePlan.rest);
          final String subtitleText;

          if (exerciseDetails.type == 'Timer') {
            subtitleText =
                'Sets: ${exercisePlan.sets} | Time: $repsText | Rest: $restText';
          } else {
            subtitleText =
                'Sets: ${exercisePlan.sets} | Reps: $repsText | Rest: $restText';
          }

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: SizedBox(
                width: 60,
                height: 60,
                child: exerciseDetails.imagePath != null
                    ? Image.asset(
                        exerciseDetails.imagePath!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.image, size: 40);
                        },
                      )
                    : const Icon(Icons.image, size: 40),
              ),
              title: Text(exercisePlan.exerciseName),
              subtitle: Text(subtitleText),
              trailing: isEditable
                  ? PopupMenuButton<String>(
                      onSelected: (String value) {
                        if (value == 'edit') {
                          _editExercise(exercisePlan, exerciseDetails);
                        } else if (value == 'replace') {
                          _replaceExercise(exercisePlan, title);
                        } else if (value == 'remove') {
                          _removeExercise(exercisePlan.sequence);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit Sets/Reps/Rest'),
                        ),
                        const PopupMenuItem(
                          value: 'replace',
                          child: Text('Replace Exercise'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove'),
                        ),
                      ],
                    )
                  : null,
            ),
          );
        }),
      ],
    );
  }
}