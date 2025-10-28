class ExercisePerformance {
  final int? id;
  final int sessionId;
  final int? exercisePlanId; 
  final String exerciseName;
  final double? accuracy;
  final double? repsCompleted;
  
  // 🎯 NEW CRITICAL FIELDS FOR HISTORICAL ACCURACY
  final int? plannedReps; // Planned reps OR duration (e.g., 10 reps or 30 seconds)
  final int? plannedSets; // Planned number of sets (e.g., 3 sets)

  ExercisePerformance({
    this.id,
    required this.sessionId,
    this.exercisePlanId,
    required this.exerciseName,
    this.accuracy,
    this.repsCompleted,
    // 🎯 ADDED TO CONSTRUCTOR
    this.plannedReps, 
    this.plannedSets, 
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'exercisePlanId': exercisePlanId,
      'exerciseName': exerciseName,
      'accuracy': accuracy,
      'repsCompleted': repsCompleted,
      // 🎯 ADDED TO MAP
      'plannedReps': plannedReps,
      'plannedSets': plannedSets,
    };
  }

  factory ExercisePerformance.fromMap(Map<String, dynamic> map) {
    return ExercisePerformance(
      id: map['id'] as int?,
      sessionId: map['sessionId'] as int,
      exercisePlanId: map['exercisePlanId'] as int?,
      exerciseName: map['exerciseName'] as String,
      accuracy: map['accuracy'] as double?,
      repsCompleted: map['repsCompleted'] as double?,
      // 🎯 READ FROM MAP
      plannedReps: map['plannedReps'] as int?,
      plannedSets: map['plannedSets'] as int?,
    );
  }

  factory ExercisePerformance.fromJson(Map<String, dynamic> json) {
    // Helper function to safely cast json values
    int? safeInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    return ExercisePerformance(
      id: safeInt(json['id']),
      sessionId: safeInt(json['sessionId']) ?? 0,
      exercisePlanId: safeInt(json['exercisePlanId']),
      exerciseName: json['exerciseName'] as String,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      repsCompleted: (json['repsCompleted'] as num?)?.toDouble(),
      // 🎯 READ FROM JSON
      plannedReps: safeInt(json['plannedReps']),
      plannedSets: safeInt(json['plannedSets']),
    );
  }
}