// lib/db/Models/workoutplan_model.dart

class ExercisePlan {
  int? id;
  final int workoutListId;
  final int exerciseId;
  final String exerciseName;
  final String title; // 'Warm-Up', 'Workout', 'Cool-Down'
  int sets;
  int reps;
  int rest;
  int sequence;

  ExercisePlan({
    this.id,
    required this.workoutListId,
    required this.exerciseId,
    required this.exerciseName,
    required this.title,
    required this.sets,
    required this.reps,
    required this.rest,
    required this.sequence,
  });

  // Method to convert an ExercisePlan object into a Map for database insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workoutListId': workoutListId,
      'exerciseId': exerciseId,
      'exerciseName': exerciseName,
      'title': title,
      'sets': sets,
      'reps': reps,
      'rest': rest,
      'sequence': sequence,
    };
  }

  // Method to create an ExercisePlan object from a Map from the database
  factory ExercisePlan.fromMap(Map<String, dynamic> map) {
    return ExercisePlan(
      id: map['id'] as int,
      workoutListId: map['workoutListId'] as int,
      exerciseId: map['exerciseId'] as int,
      exerciseName: map['exerciseName'] as String,
      title: map['title'] as String,
      sets: map['sets'] as int,
      reps: map['reps'] as int,
      rest: map['rest'] as int,
      sequence: map['sequence'] as int,
    );
  }

  // FIX: Added copyWith method to allow for creating a new object with updated values.
  ExercisePlan copyWith({
    int? id,
    int? workoutListId,
    int? exerciseId,
    String? exerciseName,
    String? title,
    int? sets,
    int? reps,
    int? rest,
    int? sequence,
  }) {
    return ExercisePlan(
      id: id ?? this.id,
      workoutListId: workoutListId ?? this.workoutListId,
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      title: title ?? this.title,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      rest: rest ?? this.rest,
      sequence: sequence ?? this.sequence,
    );
  }
}