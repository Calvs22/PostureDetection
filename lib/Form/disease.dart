// havedisease.dart

import 'package:flutter/material.dart';
import 'package:flutter_animated_button/flutter_animated_button.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';
import 'progress_state.dart'; // Ensure this path is correct
import 'nickname.dart'; // Ensure this path is correct

class DiseaseScreen extends StatefulWidget {
  final String gender;
  final String birthday;
  final double height;
  final double weight;
  final int weeklyGoal; // New data passed from WeeklyGoalScreen

  const DiseaseScreen({
    required this.gender,
    required this.birthday,
    required this.height,
    required this.weight,
    required this.weeklyGoal,
    super.key,
  });

  @override
  State<DiseaseScreen> createState() => _DiseaseScreenState();
}

class _DiseaseScreenState extends State<DiseaseScreen> {
  // Use a nullable bool for the state (null = not selected)
  bool? _haveDisease; 

  // Helper text to display based on selection
  String _getSelectionText(bool value) {
    return value ? 'Yes, I have one or more of these.' : 'No, I am healthy.';
  }

  void _navigateToNicknameScreen() {
    if (_haveDisease == null) {
      // Show an error/snackbar if nothing is selected
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Yes or No to continue.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 1. Mark this step as complete
    context.read<AppProgressState>().completeStep(ProgressStep.haveDisease); 
    
    // 2. Navigate to the final step (NicknameScreen)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NicknameScreen(
          gender: widget.gender,
          birthday: widget.birthday,
          height: widget.height,
          weight: widget.weight,
          weeklyGoal: widget.weeklyGoal,
          // ⭐️ PASS THE NEWLY COLLECTED DATA
          haveDisease: _haveDisease!, 
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'HEALTH CHECK',
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
                  const Gap(40),
                  const Text(
                    'Do you have a cardiopulmonary disease?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white
                    ),
                  ),
                  const Gap(10),
                  const Text(
                    '(e.g., hypertension, heart disease, asthma, etc.)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  const Gap(40),

                  // YES Button
                  _buildOptionButton(
                    text: 'Yes',
                    isSelected: _haveDisease == true,
                    onTap: () {
                      setState(() {
                        _haveDisease = true;
                      });
                    },
                  ),
                  const Gap(20),

                  // NO Button
                  _buildOptionButton(
                    text: 'No',
                    isSelected: _haveDisease == false,
                    onTap: () {
                      setState(() {
                        _haveDisease = false;
                      });
                    },
                  ),

                  const Gap(30),
                  if (_haveDisease != null)
                    Text(
                      _getSelectionText(_haveDisease!),
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  
                  const Gap(50),
                  
                  AnimatedButton(
                    onPress: _navigateToNicknameScreen,
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
  
  // Helper method for consistent button styling
  Widget _buildOptionButton({
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        width: 250,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white12,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white38,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.blueAccent : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}