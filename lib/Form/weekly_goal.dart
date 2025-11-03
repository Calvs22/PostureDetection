// weekly_goal.dart

// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_animated_button/flutter_animated_button.dart';
import 'package:gap/gap.dart';
import 'disease.dart'; // ⬅️ NEW TARGET SCREEN
import 'package:provider/provider.dart';
import 'progress_state.dart';
// import 'package:fitnesss_tracker_app/db/database_helper.dart'; // Database saving is moved to the last step (NicknameScreen)

class WeeklyGoalScreen extends StatefulWidget {
  final String gender;
  final String birthday;
  final double height;
  final double weight;

  const WeeklyGoalScreen({
    required this.gender,
    required this.birthday,
    required this.height,
    required this.weight,
    super.key,
  });

  @override
  State<WeeklyGoalScreen> createState() => _WeeklyGoalScreenState();
}

class _WeeklyGoalScreenState extends State<WeeklyGoalScreen> {
  int _selectedWeeklyGoal = 3; // Default goal is 3 days a week
  final List<int> _daysList = List.generate(7, (i) => 1 + i);

  @override
  void initState() {
    super.initState();
    // ❌ REMOVED: Calling completeStep in initState is incorrect
    // context.read<AppProgressState>().completeStep(ProgressStep.weeklyGoal);
  }

  // 🔄 UPDATED METHOD NAME AND NAVIGATION TARGET
  void _navigateToDiseaseScreen() {
    // 🌟 Call completeStep right before navigating, marking this step as finished.
    context.read<AppProgressState>().completeStep(ProgressStep.weeklyGoal);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiseaseScreen( // ⬅️ Navigate to the new DiseaseScreen
          gender: widget.gender,
          birthday: widget.birthday,
          height: widget.height,
          weight: widget.weight,
          weeklyGoal: _selectedWeeklyGoal, // Pass the selected goal
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appProgressState = context.watch<AppProgressState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/bg.jpeg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    'Background image not found',
                    style: TextStyle(color: Colors.white),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Gap(40),
                  const Text(
                    'WORKOUT SCHEDULE',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Gap(15),
                  SizedBox(
                    width: 200,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: appProgressState.currentProgress,
                        minHeight: 7,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const Gap(30),
                  const Text(
                    'How many days per week do you want to train?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  const Gap(20),
                  SizedBox(
                    height: 120,
                    width: 120,
                    child: CupertinoPicker(
                      backgroundColor: Colors.transparent,
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(
                        initialItem: _selectedWeeklyGoal - 1,
                      ),
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedWeeklyGoal = _daysList[index];
                        });
                        // ❌ REMOVED: Calling completeStep inside onSelectedItemChanged
                        // context.read<AppProgressState>().completeStep(ProgressStep.weeklyGoal);
                      },
                      children: _daysList
                          .map(
                            (d) => Center(
                              child: Text(
                                d == 1 ? '$d day' : '$d days',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Gap(40),
                  AnimatedButton(
                    onPress: _navigateToDiseaseScreen, // ⬅️ CALLING THE NEW METHOD
                    height: 50,
                    width: 200,
                    text: 'Continue',
                    isReverse: true,
                    selectedTextColor: Colors.black,
                    transitionType: TransitionType.LEFT_TO_RIGHT,
                    backgroundColor: Colors.blueAccent,
                    borderColor: Colors.white,
                    borderRadius: 10,
                    borderWidth: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}