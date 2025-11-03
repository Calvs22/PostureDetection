import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';

import 'dart:math';

class WorkoutGenerator {
  final dbHelper = DatabaseHelper.instance;
  final Random _random = Random();

  Future<List<Map<String, dynamic>>> generateWorkoutPlan() async {
    final workoutPreference = await dbHelper.getLatestWorkoutPreference();
    if (workoutPreference == null) return [];

    // ⭐️ Retrieve User Info for cardiopulmonary safety constraint
    final userInfo = await dbHelper.getLatestUserInfo();
    final bool hasCardiopulmonaryIssue = userInfo?['haveDisease'] == 1;

    final fitnessLevel = workoutPreference.fitnessLevel;
    final goal = workoutPreference.goal;
    final useDumbbells = workoutPreference.equipment == 'Dumbbells';
    final targetDurationMinutes = workoutPreference.minutes;
    // ⭐️ Retrieve the sore muscle group
    final soreMuscleGroup = workoutPreference.soreMuscleGroup;

    final allExercises = await dbHelper.getAllExercises();
    final List<Map<String, dynamic>> fullPlan = [];

    // Helper function to format the output map
    Map<String, dynamic> createPlanEntry(
        String title, Exercise exercise, int sets, int reps, int rest) {
      return {
        'title': title,
        'exerciseId': exercise.id,
        'exerciseName': exercise.name,
        'sets': sets,
        'reps': reps,
        'rest': rest,
        'type': exercise.type,
      };
    }

    // 1. Generate Warm-Up (Always 3 exercises)
    final warmUpExercises =
        allExercises.where((e) => e.category == 'Warm-up').toList()
          ..shuffle(_random);
    for (var ex in warmUpExercises.take(3)) {
      
      // Apply safety check to Warm-up reps/sets
      final warmUpSets = hasCardiopulmonaryIssue ? 1 : 1;
      final warmUpReps = hasCardiopulmonaryIssue ? 15 : 20; // Cap to 15-20
      
      fullPlan.add(createPlanEntry('Warm-Up', ex, warmUpSets, warmUpReps, 15));
    }

    // 2. Generate Main Workout (Dynamic based on duration)
    final workoutExercises = await _filterMainExercises(
      allExercises: allExercises,
      goal: goal,
      level: fitnessLevel,
      dumbbells: useDumbbells,
      soreMuscleGroup: soreMuscleGroup, // Pass sore muscle group
    );

    int mainWorkoutCount;
    if (targetDurationMinutes <= 25) {
      mainWorkoutCount = 4;
    } else if (targetDurationMinutes <= 45) {
      mainWorkoutCount = 6;
    } else {
      mainWorkoutCount = 8;
    }

    final exercisesToChoose = List.of(workoutExercises);
    int exercisesAdded = 0;

    while (exercisesAdded < mainWorkoutCount && exercisesToChoose.isNotEmpty) {
      final selectedIndex = _random.nextInt(exercisesToChoose.length);
      final ex = exercisesToChoose[selectedIndex];

      // Pass cardiopulmonary flag to calculate parameters
      final workoutParams = _calculateWorkoutParams(
          goal, ex.type, hasCardiopulmonaryIssue);
      final sets = workoutParams['sets']!;
      final reps = workoutParams['reps']!;
      final rest = workoutParams['rest']!;

      fullPlan.add(createPlanEntry('Workout', ex, sets, reps, rest));
      exercisesAdded++;

      // Handle paired exercises (left/right)
      if (ex.name.contains('(Left)') || ex.name.contains('(Right)')) {
        final pairedName = ex.name.contains('(Left)')
            ? ex.name.replaceAll('(Left)', '(Right)')
            : ex.name.replaceAll('(Right)', '(Left)');

        Exercise? pairedExercise;
        for (var e in exercisesToChoose) {
          if (e.name == pairedName) {
            pairedExercise = e;
            break;
          }
        }

        if (pairedExercise != null) {
          // Pass cardiopulmonary flag to calculate parameters for paired exercise
          final pairedParams = _calculateWorkoutParams(
              goal, pairedExercise.type, hasCardiopulmonaryIssue);
          final pairedSets = pairedParams['sets']!;
          final pairedReps = pairedParams['reps']!;
          final pairedRest = pairedParams['rest']!;
          
          fullPlan.add(createPlanEntry(
              'Workout', pairedExercise, pairedSets, pairedReps, pairedRest));
          exercisesAdded++;
          exercisesToChoose.remove(pairedExercise);
        }
      }
      exercisesToChoose.removeAt(selectedIndex);
    }

    // 3. Generate Cool-Down (Always 2 exercises, modified to handle pairs)
    final coolDownExercises =
        allExercises.where((e) => e.category == 'Stretch').toList()
          ..shuffle(_random);
    final exercisesToChooseCoolDown = List.of(coolDownExercises);
    int coolDownExercisesAdded = 0;

    while (coolDownExercisesAdded < 2 && exercisesToChooseCoolDown.isNotEmpty) {
      final selectedIndex = _random.nextInt(exercisesToChooseCoolDown.length);
      final ex = exercisesToChooseCoolDown[selectedIndex];

      // Set Cool-Down parameters
      int coolDownReps = hasCardiopulmonaryIssue ? 20 : 30; // 20-30 seconds for stretch
      int coolDownSets = 1;

      fullPlan.add(createPlanEntry(
          'Cool-Down', ex, coolDownSets, coolDownReps, 10));
      coolDownExercisesAdded++;

      if (ex.name.contains('(Left)') || ex.name.contains('(Right)')) {
        final pairedName = ex.name.contains('(Left)')
            ? ex.name.replaceAll('(Left)', '(Right)')
            : ex.name.replaceAll('(Right)', '(Left)');

        Exercise? pairedExercise;
        for (var e in exercisesToChooseCoolDown) {
          if (e.name == pairedName) {
            pairedExercise = e;
            break;
          }
        }

        if (pairedExercise != null) {
          int pairedCoolDownReps = hasCardiopulmonaryIssue ? 20 : 30;
          int pairedCoolDownSets = 1;
          fullPlan.add(createPlanEntry('Cool-Down', pairedExercise,
              pairedCoolDownSets, pairedCoolDownReps, 10));
          coolDownExercisesAdded++;
          exercisesToChooseCoolDown.remove(pairedExercise);
        }
      }
      exercisesToChooseCoolDown.removeAt(selectedIndex);
    }

    return fullPlan;
  }

  Future<List<Exercise>> _filterMainExercises({
    required List<Exercise> allExercises,
    required String? goal,
    required String? level,
    required bool dumbbells,
    required String soreMuscleGroup,
  }) async {
    final List<Exercise> filtered = [];
    final workoutExercises = allExercises
        .where((e) => e.category != 'Warm-up' && e.category != 'Stretch')
        .toList();

    // Define a list of difficulties to filter, starting with the user's level.
    final List<String> levelsToFilter = [level!];
    if (level == 'Advanced') {
      levelsToFilter.add('Intermediate');
    } else if (level == 'Intermediate') {
      levelsToFilter.add('Beginner');
    }

    // Define muscles to exclude based on user input, matching your data's capitalization
    final List<String> excludedMuscles;
    if (soreMuscleGroup == 'lower body') {
      // Muscles from your list: Quads, Glutes, Hamstrings, Calves
      excludedMuscles = ['quads', 'glutes', 'hamstrings', 'calves'];
    } else if (soreMuscleGroup == 'upper body') {
      // Muscles from your list: Shoulders, Arms, Chest, Triceps, Biceps, Back, Upper Chest, Upper Back, Abs, Obliques
      excludedMuscles = ['shoulders', 'arms', 'chest', 'triceps', 'biceps', 'back', 'upper chest', 'upper back', 'abs', 'obliques', 'core'];
    } else {
      excludedMuscles = []; // 'none at all'
    }

    for (var e in workoutExercises) {
      bool matchesEquipment;
      if (dumbbells) {
        matchesEquipment = e.equipment == 'Dumbbells' || e.equipment == 'Bodyweight';
      } else {
        matchesEquipment = e.equipment == 'Bodyweight';
      }

      bool matchesLevel = levelsToFilter.contains(e.difficulty);

      bool matchesGoal = (goal == 'Lose Weight' && (e.category == 'Cardio' || e.category == 'Strength')) ||
          (goal == 'Build Muscle' && e.category == 'Strength') ||
          (goal == 'Keep Fit' && (e.category == 'Cardio' || e.category == 'Strength'));

      // ⭐️ CORRECTED FIX: Check for sore muscle exclusion
      bool isMuscleSore = false;
      if (excludedMuscles.isNotEmpty) {
        // Convert the List<String> to a new List<String> of lowercase names
        final exerciseMuscles = e.primaryMuscleGroups
            .map((m) => m.toLowerCase()) // 👈 Map and convert each string to lowercase
            .toList();
        
        // Check if any of the exercise's primary muscles are in the excluded list
        isMuscleSore = exerciseMuscles.any((muscle) => excludedMuscles.contains(muscle));
      }
      
      // Only add the exercise if it meets all criteria AND the muscle is NOT sore
      if (matchesEquipment && matchesLevel && matchesGoal && !isMuscleSore) {
        filtered.add(e);
      }
    }

    if (filtered.isEmpty) {
      // Fallback to a broader search if the initial filter is empty, but still respect sore muscle logic
      for (var e in workoutExercises) {
        // Re-check sore muscle condition for fallback
        bool isMuscleSore = false;
        if (excludedMuscles.isNotEmpty) {
          final exerciseMuscles = e.primaryMuscleGroups
              .map((m) => m.toLowerCase()) // 👈 Map and convert each string to lowercase
              .toList();
          isMuscleSore = exerciseMuscles.any((muscle) => excludedMuscles.contains(muscle));
        }

        if (levelsToFilter.contains(e.difficulty) && !isMuscleSore) {
          filtered.add(e);
        }
      }
    }

    filtered.shuffle(_random);
    return filtered;
  }
  
  // New function to calculate sets, reps, and rest based on goal
  Map<String, int> _calculateWorkoutParams(
      String? goal,
      String? exerciseType,
      bool hasCardiopulmonaryIssue, // Health safety flag
      ) {
    int sets = 3;
    int reps = 12;
    int rest = 30;

    if (goal == 'Build Muscle') {
      sets = 4;
      reps = 10;
      rest = 60;
    } else if (goal == 'Lose Weight') {
      sets = 3;
      reps = 15;
      rest = 30;
    } else if (goal == 'Keep Fit') {
      sets = 3;
      reps = 12;
      rest = 45;
    }
    
    // Override reps/sets for 'Timer' type exercises
    if (exerciseType == 'Timer') {
      reps = 60; // 60 seconds is standard
      sets = 1; // Always 1 set for timer-based exercises
    }
    
    // ⭐️ CRITICAL SAFETY LOGIC: Override for cardiopulmonary issue
    if (hasCardiopulmonaryIssue) {
      sets = 1; // Must be 1 set to pass the safety check (<=2 sets)
      rest = 60; // Increase rest time for safety
      
      if (exerciseType == 'Timer') {
        // Must be <= 15 seconds to pass the safety check
        reps = 15; 
      } else {
        // Must be <= 15 reps to pass the safety check (10 reps is safe)
        reps = 10; 
      }
    }

    return {'sets': sets, 'reps': reps, 'rest': rest};
  }
}