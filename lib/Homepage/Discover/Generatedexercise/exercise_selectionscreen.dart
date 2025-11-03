import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutplan_model.dart';

// (*** Keep all existing InputFormatter classes unchanged ***)

class _RepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final int? value = int.tryParse(newValue.text);
    if (value != null && value > 30) {
      return TextEditingValue(
        text: '30',
        selection: TextSelection.collapsed(offset: '30'.length),
      );
    }
    // New: If the value is 0, format it to 1.
    if (value != null && value == 0) {
      return TextEditingValue(
        text: '1',
        selection: TextSelection.collapsed(offset: '1'.length),
      );
    }
    return newValue;
  }
}

// New: Class to format the sets input to a maximum of 5.
class _SetsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final int? value = int.tryParse(newValue.text);
    if (value != null && value > 5) {
      return TextEditingValue(
        text: '5',
        selection: TextSelection.collapsed(offset: '5'.length),
      );
    }
    // New: If the value is 0, format it to 1.
    if (value != null && value == 0) {
      return TextEditingValue(
        text: '1',
        selection: TextSelection.collapsed(offset: '1'.length),
      );
    }
    return newValue;
  }
}

// New: Class to format the time input to MM:SS and limit to 5:00 (300 seconds).
class _TimeInputFormatter extends TextInputFormatter {
  final int _maxValueInSeconds = 300;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final newText = newValue.text;
    final int selectionIndexFromTheRight =
        newText.length - newValue.selection.end;

    // Handle backspace or empty input
    if (newText.isEmpty) {
      return const TextEditingValue();
    }

    // Clean the input, keeping only digits
    final cleanedText = newText.replaceAll(RegExp(r'\D'), '');
    if (cleanedText.isEmpty) {
      return TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }

    // Format the text to MM:SS
    int minutes = 0;
    int seconds = 0;

    if (cleanedText.length > 2) {
      minutes = int.tryParse(cleanedText.substring(0, cleanedText.length - 2)) ?? 0;
      seconds = int.tryParse(cleanedText.substring(cleanedText.length - 2)) ?? 0;
    } else {
      seconds = int.tryParse(cleanedText) ?? 0;
    }

    if (seconds > 59) {
      minutes += seconds ~/ 60;
      seconds %= 60;
    }

    final totalSeconds = minutes * 60 + seconds;
    if (totalSeconds > _maxValueInSeconds) {
      minutes = _maxValueInSeconds ~/ 60;
      seconds = _maxValueInSeconds % 60;
    }

    final formattedText =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(
          offset: formattedText.length - selectionIndexFromTheRight),
    );
  }
}

class ExerciseSelectionScreen extends StatefulWidget {
  final int workoutListId;
  final String? section;
  final bool isReplacing;
  final String userEquipment;

  const ExerciseSelectionScreen({
    super.key,
    required this.workoutListId,
    this.section,
    this.isReplacing = false,
    required this.userEquipment,
  });

  @override
  State<ExerciseSelectionScreen> createState() =>
      _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState extends State<ExerciseSelectionScreen> {
  final dbHelper = DatabaseHelper.instance;
  List<Exercise> _allExercises = [];
  List<Exercise> _filteredExercises = [];
  bool _isLoading = true;

  // RENAMED: from _selectedType to _selectedCategory for clarity in the workout section
  String? _selectedCategory;
  String? _selectedEquipment;
  final _searchController = TextEditingController();

  Exercise? _selectedExercise;
  final _setsController = TextEditingController(text: '3');
  final _repsController = TextEditingController(text: '12');
  final _restController = TextEditingController(text: '30');

  // 🚀 MODIFICATION 1: Updated to exclude 'Warm-up' from mapping to 'Cardio' for the 'Workout' section.
  // Only the original 'Cardio' category will map to the top-level 'Cardio' filter.
  static const Map<String, String> _categoryMapping = {
    // 'Warm-up': 'Cardio', // Removed to exclude Warm-up from the Workout section
    'Cardio': 'Cardio',
    'Core': 'Strength', // Assuming Core, Upper Body, Lower Body are Strength
    'Upper Body': 'Strength',
    'Lower Body': 'Strength',
    'Strength': 'Strength',
    'Stretch': 'Stretch/Cooldown',
    'Cool-down': 'Stretch/Cooldown',
    'Dumbbell Exercises': 'Strength',
  };

  @override
  void initState() {
    super.initState();
    // Initialize defaults based on section/user input
    // Only the main 'Workout' section uses the Cardio/Strength/Equipment filters
    if (widget.section == 'Workout') {
      _selectedCategory = 'All'; // Default to 'All' to show both Cardio and Strength
      // Default Equipment filter based on user's choice
      _selectedEquipment =
          widget.userEquipment == 'Bodyweight' ? 'Bodyweight' : 'All';
    } else {
      // For Warm-up/Cool-Down sections, the logic is simpler (handled below)
      _selectedCategory = 'All';
      _selectedEquipment = 'All';
    }

    _loadExercises();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _setsController.dispose();
    _repsController.dispose();
    _restController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final exercises = await dbHelper.getAllExercises();
    setState(() {
      _allExercises = exercises;
      _isLoading = false;
      _applyFilters();
    });
  }

// 🚀 MODIFICATION 2: Filtering Logic updated implicitly by the change to _categoryMapping.
// The check for `exercise.category == 'Warm-up'` in the 'Workout' filter is no longer needed
// if 'Warm-up' is correctly excluded from the _categoryMapping used for the 'Workout' section.
  void _applyFilters() {
    List<Exercise> tempExercises = _allExercises;
    final searchQuery = _searchController.text.toLowerCase();

    // 1. Filter by Section ('Warm-Up', 'Cool-Down', or 'Workout')
    if (widget.section == 'Warm-Up') {
      // Filter for 'Warm-up' category only
      tempExercises = tempExercises
          .where((exercise) => exercise.category == 'Warm-up')
          .toList();
    } else if (widget.section == 'Cool-Down') {
      // Filter for 'Stretch' category only
      tempExercises = tempExercises
          .where((exercise) => 
              exercise.category == 'Stretch' || exercise.category == 'Cool-down')
          .toList();
    } else if (widget.section == 'Workout') {
      // 2. Filter by Mapped Category (Cardio/Strength) for the Workout Section
      tempExercises = tempExercises.where((exercise) {
        final mappedCategory = _categoryMapping[exercise.category];

        // Ensure exercise maps to a valid Workout category (Cardio or Strength).
        // The exclusion of 'Warm-up' and 'Stretch/Cooldown' is now handled by 
        // the definition of _categoryMapping.
        if (mappedCategory == null || mappedCategory == 'Stretch/Cooldown') {
          return false;
        }

        // Apply the 'All', 'Cardio', or 'Strength' filter
        if (_selectedCategory == 'All') {
          return true; // Keep all exercises that mapped successfully to Cardio or Strength
        }

        return mappedCategory == _selectedCategory;
      }).toList();

      // 3. Apply the Equipment filter for the Workout Section
      if (_selectedEquipment != 'All') {
        tempExercises = tempExercises
            .where((exercise) => exercise.equipment == _selectedEquipment)
            .toList();
      }
    }

    // 4. Apply Search Query
    if (searchQuery.isNotEmpty) {
      tempExercises = tempExercises
          .where((exercise) => exercise.name.toLowerCase().contains(searchQuery))
          .toList();
    }

    setState(() {
      _filteredExercises = tempExercises;
      _selectedExercise = null; // Reset selection on filter change
    });
  }

// --------------------------------------------------------------------------

  // New: Method to parse MM:SS string to total seconds
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

  void _addOrReplaceExerciseToPlan() async {
    final sets = int.tryParse(_setsController.text) ?? 1;
    final int reps;
    final int rest;

    if (_selectedExercise!.type == 'Timer') {
      reps = _parseTimeStringToSeconds(_repsController.text);
    } else {
      reps = int.tryParse(_repsController.text) ?? 1;
    }

    rest = _parseTimeStringToSeconds(_restController.text);

    final newExercisePlan = ExercisePlan(
      id: null,
      workoutListId: widget.workoutListId,
      exerciseId: _selectedExercise!.id!,
      exerciseName: _selectedExercise!.name,
      sets: sets,
      reps: reps,
      rest: rest,
      title: widget.section ?? 'Workout',
      sequence: 0,
    );

    if (widget.isReplacing) {
      Navigator.of(context).pop(newExercisePlan);
    } else {
      await dbHelper.addExerciseToWorkoutList(
          widget.workoutListId, newExercisePlan);
      Navigator.of(context).pop();
    }
  }

  Future<void> _showDumbbellWarning(VoidCallback onProceed) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Warning'),
          content: const Text(
            'You chose a dumbbell exercise but indicated you have no equipment. Do you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close warning dialog
                onProceed();
              },
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );
  }

  // New: This method builds the dynamic input fields
  Widget _buildExerciseMetrics() {
    final isTimerExercise = _selectedExercise!.type == 'Timer';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _setsController,
            decoration: const InputDecoration(labelText: 'Sets (max 5)'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              _SetsInputFormatter(),
            ],
          ),
          TextField(
            controller: _repsController,
            decoration: InputDecoration(
                labelText: isTimerExercise
                    ? 'Time (MM:SS, max 5:00)'
                    : 'Reps (max 30)'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              if (isTimerExercise) _TimeInputFormatter() else _RepInputFormatter(),
            ],
          ),
          TextField(
            controller: _restController,
            decoration:
                const InputDecoration(labelText: 'Rest (MM:SS, max 5:00)'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              _TimeInputFormatter(),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (widget.userEquipment == 'Bodyweight' &&
                  _selectedExercise!.equipment == 'Dumbbells') {
                _showDumbbellWarning(_addOrReplaceExerciseToPlan);
              } else {
                _addOrReplaceExerciseToPlan();
              }
            },
            child: Text(widget.isReplacing ? 'Replace' : 'Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStretchingSection =
        widget.section == 'Warm-Up' || widget.section == 'Cool-Down';

    // UPDATED: Use the simplified Cardio/Strength categories for filtering the workout section
    final categoryOptions = ['All', 'Cardio', 'Strength'];

    // 💡 MODIFICATION START: Define equipmentOptions based on widget.userEquipment
    final List<String> equipmentOptions;
    if (widget.section == 'Warm-Up' || widget.section == 'Cool-Down') {
      // For Warm-up/Cool-Down, only Bodyweight exercises are relevant
      equipmentOptions = ['All', 'Bodyweight'];
    } 
    // 🛑 FIXED LOGIC HERE: If the user selected Bodyweight, still show Dumbbells
    // so they can choose it and trigger the warning.
    else if (widget.userEquipment == 'Bodyweight') { 
      equipmentOptions = ['All', 'Bodyweight', 'Dumbbells'];
    } 
    else if (widget.userEquipment == 'Dumbbells') {
      // If the user selected Dumbbells, allow both Bodyweight and Dumbbells
      equipmentOptions = ['All', 'Bodyweight', 'Dumbbells'];
    } else {
      // Default/Fallback
      equipmentOptions = ['All', 'Bodyweight', 'Dumbbells'];
    }
    // 💡 MODIFICATION END

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isReplacing
            ? 'Replace Exercise'
            : 'Add ${widget.section ?? 'Exercise'}'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Exercises',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (!isStretchingSection)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              border: OutlineInputBorder(),
                            ),
                            // Use the simplified list of categories
                            value: _selectedCategory,
                            items: categoryOptions.map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                _selectedCategory = newValue;
                              });
                              _applyFilters();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Equipment',
                              border: OutlineInputBorder(),
                            ),
                            // 💡 Uses the equipmentOptions list defined above
                            value: _selectedEquipment,
                            items: equipmentOptions.map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                _selectedEquipment = newValue;
                              });
                              _applyFilters();
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredExercises.length,
                    itemBuilder: (context, index) {
                      final exercise = _filteredExercises[index];
                      String subtitleText;
                      if (isStretchingSection) {
                        subtitleText =
                            'Category: ${exercise.category} | Primary: ${exercise.primaryMuscleGroups}';
                      } else {
                        // Display both Category and Equipment
                        subtitleText =
                            'Category: ${exercise.category} | Equipment: ${exercise.equipment}';
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: _selectedExercise == exercise
                            ? Theme.of(context).primaryColor.withOpacity(0.2)
                            : null,
                        child: ListTile(
                          leading: SizedBox(
                            width: 60,
                            height: 60,
                            child: exercise.imagePath != null
                                ? Image.asset(
                                      exercise.imagePath!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Icon(Icons.error_outline,
                                            size: 40);
                                      },
                                    )
                                : const Icon(Icons.image, size: 40),
                          ),
                          title: Text(exercise.name),
                          subtitle: Text(subtitleText),
                          onTap: () {
                            setState(() {
                              _selectedExercise = exercise;
                              if (_selectedExercise!.type == 'Timer') {
                                _repsController.text = '01:00';
                              } else {
                                _repsController.text = '12';
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                if (_selectedExercise != null) _buildExerciseMetrics(),
              ],
            ),
    );
  }
}