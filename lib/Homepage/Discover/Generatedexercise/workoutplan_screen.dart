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
 final int seconds = newText.contains(':') ? int.tryParse(newText.split(':')[1]) ?? 0 : 0;
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

// New state variable to hold the user's weekly goal
int _userWeeklyGoal = 0; 

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
 }
 
 // 💡 MODIFICATION HERE: Fetch UserInfo and weekly goal
 final userInfo = await dbHelper.getLatestUserInfo();
 if (userInfo != null) {
 // Use the 'weeklyGoal' key which you added to the DatabaseHelper
 // Provide a safe default (e.g., 3) if null, or 0 if it must be set by user
 _userWeeklyGoal = userInfo['weeklyGoal'] ?? 0; 
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
  if (!_isEditMode) {
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

// MODIFIED METHOD: Removed Markdown and Emojis, fixed warning message construction
// MODIFIED METHOD: Use a Column in the dialog content to properly separate warnings.
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

 // Sorting logic remains correct
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

 // --- WARNING CHECKS ---
 // 💡 Using the new DatabaseHelper methods
 final bool workedOutToday = await dbHelper.didUserWorkoutToday();
 final int workoutsThisWeek = await dbHelper.getWorkoutsCompletedThisWeek();
 // 💡 Check if the goal is reached (only if goal is set, i.e., > 0)
 final bool goalReached = workoutsThisWeek >= _userWeeklyGoal && _userWeeklyGoal > 0;

 List<String> warnings = [];

 if (workedOutToday) {
  warnings.add('You have already completed a workout today.');
 }

 if (goalReached) {
  if (_userWeeklyGoal > 0) {
   final plural = _userWeeklyGoal > 1 ? 'times' : 'time'; // Corrected to 'times' for weekly count
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
    // --- FIX STARTS HERE: Use a Column for structured content ---
    content: SingleChildScrollView(
     child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
       // Display warnings in a distinct color/style
       if (warnings.isNotEmpty) ...[
        Text(
         // Join all warnings with newlines
         warnings.join('\n'),
         style: TextStyle(
          color: Theme.of(context).colorScheme.error, // Use error color for warnings
          fontWeight: FontWeight.bold,
         ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
       ],
       // Display the main question (always present)
       Text(mainQuestion),
      ],
     ),
    ),
    // --- FIX ENDS HERE ---
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
 // Replaced the old implementation with the new warning logic
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
 TextEditingController repsController =
  TextEditingController(
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
    decoration: const InputDecoration(labelText: 'Rest (MM:SS, max 10:00)'),
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
      : int.tryParse(repsController.text) ?? 0) <= 0
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
   subtitleText = 'Sets: ${exercisePlan.sets} | Time: $repsText | Rest: $restText';
  } else {
   subtitleText = 'Sets: ${exercisePlan.sets} | Reps: $repsText | Rest: $restText';
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