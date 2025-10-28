import 'package:flutter/material.dart';

enum ProgressStep {
  gender,
  birthday,
  height,
  weight,
  weeklyGoal, // <<<<<<<< NEW STEP ADDED
  nickname,
}

class AppProgressState with ChangeNotifier {
  final Set<ProgressStep> _completedSteps = {};
  
  // 💡 MODIFIED: There are now 6 total steps (gender, birthday, height, 
  // weight, weeklyGoal, nickname), so each is ~16.67%
  final int _totalSteps = 6; // <<<<<<<< UPDATED TOTAL STEPS

  double get currentProgress {
    if (_totalSteps == 0) return 0.0;
    return _completedSteps.length / _totalSteps;
  }

  void completeStep(ProgressStep step) {
    if (!_completedSteps.contains(step)) {
      _completedSteps.add(step);
      notifyListeners();
    }
  }

  bool isStepCompleted(ProgressStep step) {
    return _completedSteps.contains(step);
  }

  void resetProgress() {
    _completedSteps.clear();
    notifyListeners();
  }
}