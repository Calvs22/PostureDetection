import 'package:flutter/material.dart';

enum ProgressStep {
  gender,
  birthday,
  height,
  weight,
  weeklyGoal, 
  haveDisease, // ⭐️ NEW STEP: Added for the health check screen
  nickname,
}

class AppProgressState with ChangeNotifier {
  final Set<ProgressStep> _completedSteps = {};
  
  // 💡 UPDATED: There are now 7 total steps (gender, birthday, height, 
  // weight, weeklyGoal, haveDisease, nickname).
  final int _totalSteps = 7; // ⭐️ UPDATED TOTAL STEPS

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