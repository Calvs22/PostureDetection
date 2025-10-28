// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter_animated_button/flutter_animated_button.dart';
import 'bdayform.dart';
import 'progress_state.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

// --- Gender Class (First Registration Step) ---
class GenderScreen extends StatefulWidget {
  const GenderScreen({super.key});

  @override
  State<GenderScreen> createState() => _GenderScreenState();
}

class _GenderScreenState extends State<GenderScreen> {
  String? _selectedGender;

  void _onGenderSelected(String gender) {
    setState(() {
      _selectedGender = gender;
      context.read<AppProgressState>().completeStep(ProgressStep.gender);
    });
  }

  Widget _buildGenderButton(String genderText) {
    final isSelected = _selectedGender == genderText;

    return GestureDetector(
      onTap: () => _onGenderSelected(genderText),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: 50,
        width: 300,
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.black,
          border: Border.all(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          genderText,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
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
        automaticallyImplyLeading: false, // 🚀 Removes back button
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
                children: <Widget>[
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
                  const Gap(100),
                  const Text(
                    'Whats Your Gender?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Gap(20),
                  _buildGenderButton('MALE'),
                  const Gap(10),
                  _buildGenderButton('FEMALE'),
                  const Gap(10),
                  _buildGenderButton('Prefer Not to Say'),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20, bottom: 20),
              child: AnimatedButton(
                onPress: () {
                  if (_selectedGender != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BdayScreen(gender: _selectedGender!), // Pass gender
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select your gender.'),
                      ),
                    );
                  }
                },
                height: 35,
                width: 120,
                text: 'Continue',
                isReverse: true,
                selectedTextColor: Colors.black,
                transitionType: TransitionType.LEFT_TO_RIGHT,
                backgroundColor: Colors.blueAccent,
                borderColor: Colors.white,
                borderRadius: 10,
                borderWidth: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
