import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';

import 'dart:math';

class WorkoutGenerator {
  final dbHelper = DatabaseHelper.instance;
  final Random _random = Random();

  Future<List<Map<String, dynamic>>> generateWorkoutPlan() async {
    final workoutPreference = await dbHelper.getLatestWorkoutPreference();
    if (workoutPreference == null) return [];

    final fitnessLevel = workoutPreference.fitnessLevel;
    final goal = workoutPreference.goal;
    final useDumbbells = workoutPreference.equipment == 'Dumbbells';
    final targetDurationMinutes = workoutPreference.minutes;

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
      fullPlan.add(createPlanEntry('Warm-Up', ex, 1, 20, 15));
    }

    // 2. Generate Main Workout (Dynamic based on duration)
    final workoutExercises = await _filterMainExercises(
      allExercises: allExercises,
      goal: goal,
      level: fitnessLevel,
      dumbbells: useDumbbells,
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

      final workoutParams = _calculateWorkoutParams(goal, ex.type);
      final sets = workoutParams['sets']!;
      final reps = workoutParams['reps']!;
      final rest = workoutParams['rest']!;

      fullPlan.add(createPlanEntry('Workout', ex, sets, reps, rest));
      exercisesAdded++;

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
          final pairedParams = _calculateWorkoutParams(goal, pairedExercise.type);
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

      int coolDownReps = 30; // 30 seconds for stretch
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
          int pairedCoolDownReps = 30;
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

      if (matchesEquipment && matchesLevel && matchesGoal) {
        filtered.add(e);
      }
    }

    if (filtered.isEmpty) {
      // Fallback to a broader search if the initial filter is empty
      for (var e in workoutExercises) {
        if (levelsToFilter.contains(e.difficulty)) {
          filtered.add(e);
        }
      }
    }

    filtered.shuffle(_random);
    return filtered;
  }
  
  // New function to calculate sets, reps, and rest based on goal
  Map<String, int> _calculateWorkoutParams(String? goal, String? exerciseType) {
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
    
    // Override reps for 'Timer' type exercises
    if (exerciseType == 'Timer') {
      reps = 60; // 60 seconds
      sets = 1; // Always 1 set for timer-based exercises
    }

    return {'sets': sets, 'reps': reps, 'rest': rest};
  }
}