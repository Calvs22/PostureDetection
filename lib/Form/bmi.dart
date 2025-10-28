// bmi.dart

// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_animated_button/flutter_animated_button.dart';
import 'package:gap/gap.dart';
import 'weekly_goal.dart'; // NEW TARGET: weekly_goal.dart
import 'package:provider/provider.dart';
import 'progress_state.dart';

class HeightWeightScreen extends StatefulWidget {
  final String gender;
  final String birthday;

  const HeightWeightScreen({
    required this.gender,
    required this.birthday,
    super.key,
  });

  @override
  State<HeightWeightScreen> createState() => _HeightWeightScreenState();
}

class _HeightWeightScreenState extends State<HeightWeightScreen> {
  int _selectedHeight = 170; // default cm
  int _selectedWeight = 65; // default kg

  final List<int> _heightList = List.generate(
    121,
    (i) => 120 + i,
  ); // 120-240 cm
  final List<int> _weightList = List.generate(131, (i) => 30 + i); // 30-160 kg

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
                    'PERSONAL INFO',
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
                    'Select Your Height (cm)',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  SizedBox(
                    height: 120,
                    child: CupertinoPicker(
                      backgroundColor: Colors.transparent,
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(
                        initialItem: _selectedHeight - 120,
                      ),
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedHeight = _heightList[index];
                        });
                        context.read<AppProgressState>().completeStep(
                              ProgressStep.height,
                            );
                      },
                      children: _heightList
                          .map(
                            (h) => Center(
                              child: Text(
                                '$h cm',
                                style: const TextStyle(
                                  fontSize: 22,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Gap(20),
                  const Text(
                    'Select Your Weight (kg)',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  SizedBox(
                    height: 120,
                    child: CupertinoPicker(
                      backgroundColor: Colors.transparent,
                      itemExtent: 40,
                      scrollController: FixedExtentScrollController(
                        initialItem: _selectedWeight - 30,
                      ),
                      onSelectedItemChanged: (index) {
                        setState(() {
                          _selectedWeight = _weightList[index];
                        });
                        context.read<AppProgressState>().completeStep(
                              ProgressStep.weight,
                            );
                      },
                      children: _weightList
                          .map(
                            (w) => Center(
                              child: Text(
                                '$w kg',
                                style: const TextStyle(
                                  fontSize: 22,
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
                    onPress: () {
                      // Mark both steps as complete before continuing
                      context.read<AppProgressState>().completeStep(
                            ProgressStep.height,
                          );
                      context.read<AppProgressState>().completeStep(
                            ProgressStep.weight,
                          );
                      
                      // Navigate to WeeklyGoalScreen, passing data
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => WeeklyGoalScreen(
                            gender: widget.gender,
                            birthday: widget.birthday,
                            height: _selectedHeight.toDouble(),
                            weight: _selectedWeight.toDouble(),
                            // No nickname needed here
                          ),
                        ),
                      );
                    },
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