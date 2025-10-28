import 'package:flutter/material.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutlist_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workout_preference_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutplan_model.dart'; // REQUIRED for bulk insertion
import '/Homepage/Discover/Generatedexercise/workoutgenerator.dart';
import 'package:fitnesss_tracker_app/Homepage/Discover/Generatedexercise/workoutplan_screen.dart';


class WorkoutConfigurationScreen extends StatefulWidget {
const WorkoutConfigurationScreen({super.key});

@override
State<WorkoutConfigurationScreen> createState() =>
 _WorkoutConfigurationScreenState();
}

class _WorkoutConfigurationScreenState extends State<WorkoutConfigurationScreen> {
final dbHelper = DatabaseHelper.instance;
final generator = WorkoutGenerator();

// State variables for the 4 questions
String _fitnessLevel = 'Beginner';
String _goal = 'Build Muscle';
bool _useDumbbells = false;
double _targetMinutes = 45.0;

bool _isGenerating = false;

final List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];
final List<String> _goals = ['Build Muscle', 'Lose Weight', 'Keep Fit'];

Future<void> _generatePlan() async {
 setState(() {
 _isGenerating = true;
 });

 int? listId; // Declare here to delete the list on failure

 try {
 // 1. Create a WorkoutPreference object from the user's selections
 final newPreference = WorkoutPreference(
  fitnessLevel: _fitnessLevel,
  goal: _goal,
  equipment: _useDumbbells ? 'Dumbbells' : 'Bodyweight',
  // 'days' parameter removed here
  minutes: _targetMinutes.round(),
 );

 // 2. Insert the new preferences into the database.
 await dbHelper.insertWorkoutPreference(newPreference);

 // 3. Generate the actual workout plan.
 final generatedExercises = await generator.generateWorkoutPlan();

 // 4. Check for empty exercises immediately and exit
 if (generatedExercises.isEmpty) {
  if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
   const SnackBar(content: Text('No exercises were found for your criteria.')),
  );
  }
  return;
 }

 // 5. Create a new WorkoutList entry (only if exercises are found)
 final nextListNumber = await dbHelper.getNextGeneratedPlanNumber(); 
 final newWorkoutList = WorkoutList(listName: 'Generated Plan $nextListNumber');
 listId = await dbHelper.insertWorkoutList(newWorkoutList);
 
 List<ExercisePlan> exercisesToInsert = [];
 int sequence = 1;

 // 6. Build ExercisePlan objects for efficient bulk insertion
 if (listId > 0) {
  for (var data in generatedExercises) {
  final exerciseId = data['exerciseId'];
  final exerciseName = data['exerciseName'];
  final sets = data['sets'];
  final reps = data['reps'];
  final rest = data['rest'];
  final title = data['title'];

  if (exerciseId != null && exerciseName != null) {
   exercisesToInsert.add(
   ExercisePlan(
    workoutListId: listId,
    exerciseId: exerciseId,
    exerciseName: exerciseName,
    sets: sets,
    reps: reps,
    rest: rest,
    sequence: sequence++, 
    title: title,
   ),
   );
  }
  }
  
  await dbHelper.insertWorkoutExercises(exercisesToInsert);

  // 7. Navigate to the generated plan screen
  if (mounted && exercisesToInsert.isNotEmpty) {
  Navigator.of(context).pushReplacement(
   MaterialPageRoute(
   builder: (context) => WorkoutPlanScreen(
    workoutListId: listId,
    isManualCreation: false,
   ),
   ),
  );
  } else {
  // If the list was created but no valid exercises were found, delete it
  await dbHelper.deleteWorkoutList(listId);
  if (mounted) {
   ScaffoldMessenger.of(context).showSnackBar(
   const SnackBar(content: Text('No valid exercises were generated. Try different settings.')),
   );
  }
  }
 }
 } catch (e) {
 // If insertion fails, attempt to delete the list to avoid orphans
 if (listId != null) await dbHelper.deleteWorkoutList(listId); 
 
 if (mounted) {
  // Handle error
  ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('Error generating plan: $e')),
  );
 }
 } finally {
 if (mounted) {
  setState(() {
  _isGenerating = false;
  });
 }
 }
}

@override
Widget build(BuildContext context) {
 return Scaffold(
 extendBodyBehindAppBar: true,
 appBar: AppBar(
  title: const Text('Generate New Plan', style: TextStyle(color: Colors.white)),
  backgroundColor: Colors.black.withOpacity(0.5),
  elevation: 0,
  iconTheme: const IconThemeData(color: Colors.white),
 ),
 body: Stack(
  children: [
  // Background Image
  Positioned.fill(
   child: Image.asset('assets/bg.jpeg', fit: BoxFit.cover),
  ),
  // Content
  SafeArea(
   child: SingleChildScrollView(
   padding: const EdgeInsets.all(16.0),
   child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    const SizedBox(height: 20),
    // 1. Fitness Level
    _buildSectionTitle('1. Fitness Level'),
    _buildRadioGroup(_levels, _fitnessLevel, (val) {
     setState(() => _fitnessLevel = val!);
    }),
    const SizedBox(height: 15),

    // 2. Goal
    _buildSectionTitle('2. Primary Goal'),
    _buildRadioGroup(_goals, _goal, (val) {
     setState(() => _goal = val!);
    }),
    const SizedBox(height: 15),

    // 3. Dumbbells
    _buildSectionTitle('3. Access to Dumbbells?'),
    SwitchListTile(
     title: Text(
     _useDumbbells ? 'Yes, use dumbbells' : 'No, bodyweight only',
     style: const TextStyle(color: Colors.white),
     ),
     value: _useDumbbells,
     onChanged: (bool value) {
     setState(() => _useDumbbells = value);
     },
     tileColor: Colors.black54,
     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    const SizedBox(height: 15),

    // 4. Minutes
    _buildSectionTitle('4. Target Duration: ${_targetMinutes.round()} mins'),
    Slider(
     value: _targetMinutes,
     min: 15,
     max: 120,
     divisions: (120 - 15) ~/ 5, // steps of 5 minutes
     label: '${_targetMinutes.round()} minutes',
     onChanged: (double value) {
     setState(() => _targetMinutes = value);
     },
     activeColor: Colors.blueAccent,
     inactiveColor: Colors.white54,
    ),
    const SizedBox(height: 30),

    // Generate Button
    SizedBox(
     width: double.infinity,
     child: ElevatedButton(
     onPressed: _isGenerating ? null : _generatePlan,
     style: ElevatedButton.styleFrom(
      backgroundColor: Colors.lightGreen,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 18),
      shape: RoundedRectangleBorder(
       borderRadius: BorderRadius.circular(12)),
     ),
     child: _isGenerating
      ? const Row(
       mainAxisAlignment: MainAxisAlignment.center,
       children: [
        CircularProgressIndicator(color: Colors.white),
        SizedBox(width: 10),
        Text('Generating Plan...'),
       ],
       )
      : const Text('Generate My Workout Plan',
       style: TextStyle(fontSize: 18)),
     ),
    ),
    ],
   ),
   ),
  ),
  ],
 ),
 );
}

Widget _buildSectionTitle(String title) {
 return Padding(
 padding: const EdgeInsets.symmetric(vertical: 8.0),
 child: Text(
  title,
  style: const TextStyle(
   fontSize: 16,
   fontWeight: FontWeight.bold,
   color: Colors.white70),
 ),
 );
}

Widget _buildRadioGroup(
 List<String> options, String currentValue, ValueChanged<String?> onChanged) {
 return Container(
 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
 decoration: BoxDecoration(
  color: Colors.black54,
  borderRadius: BorderRadius.circular(10),
 ),
 child: Column(
  children: options.map((option) {
  return RadioListTile<String>(
   title: Text(option, style: const TextStyle(color: Colors.white)),
   value: option,
   groupValue: currentValue,
   onChanged: onChanged,
   activeColor: Colors.blueAccent,
   contentPadding: EdgeInsets.zero,
  );
  }).toList(),
 ),
 );
}
}