abstract class ExerciseLogic {
  void update(List<dynamic> landmarks, bool isFrontCamera);
  void reset();

  String get progressLabel;
}

// Rep-based exercises
abstract class RepExerciseLogic extends ExerciseLogic {
  int get reps;
}

// Time-based exercises
abstract class TimeExerciseLogic extends ExerciseLogic {
  int get seconds;
}
