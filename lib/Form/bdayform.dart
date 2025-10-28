// ignore_for_file: unused_import

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:bottom_picker/bottom_picker.dart';
import 'package:bottom_picker/resources/arrays.dart'; // Needed for DatePickerDateOrder
import 'package:flutter_animated_button/flutter_animated_button.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'progress_state.dart';
import 'bmi.dart';

// --- SecondScreen Class (Second Registration Step) ---
class BdayScreen extends StatefulWidget {
  final String gender;
  const BdayScreen({required this.gender, super.key});

  @override
  State<BdayScreen> createState() => _BdayScreenState();
}

class _BdayScreenState extends State<BdayScreen> {
  DateTime? _selectedBirthday;

  String _getMonthAbbreviation(int month) {
    final DateTime dummyDate = DateTime(2000, month, 1);
    return DateFormat('MMM').format(dummyDate);
  }

  void _openDatePickerWithButtonStyle(BuildContext context) {
    BottomPicker.date(
      pickerTitle: const Text(
        'Set your Birthday',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: Colors.white,
        ),
      ),
      pickerTextStyle: const TextStyle(fontSize: 20, color: Colors.white),
      dateOrder: DatePickerDateOrder.dmy,
      initialDateTime: _selectedBirthday ?? DateTime(2000, 1, 1),
      maxDateTime: DateTime.now(),
      minDateTime: DateTime(1970, 1, 1),
      backgroundColor: Colors.black,
      closeIconColor: Colors.white,
      bottomPickerTheme: BottomPickerTheme.plumPlate,
      onSubmit: (dateTime) {
        setState(() {
          _selectedBirthday = dateTime;
          context.read<AppProgressState>().completeStep(ProgressStep.birthday);
        });
      },
      buttonStyle: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue[200]!),
      ),
      buttonWidth: 200,
      buttonContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedBirthday == null
                  ? 'Select your birthday'
                  : '${_selectedBirthday!.day.toString().padLeft(2, '0')} : '
                      '${_getMonthAbbreviation(_selectedBirthday!.month)} : '
                      '${_selectedBirthday!.year}',
              style: const TextStyle(color: Colors.white),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 15),
          ],
        ),
      ),
    ).show(context);
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
                  const Gap(150),
                  const Text(
                    'When is your Birthday?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Gap(20),
                  AnimatedButton(
                    onPress: () => _openDatePickerWithButtonStyle(context),
                    height: 50,
                    width: 300,
                    text: _selectedBirthday == null
                        ? 'Select your birthday'
                        : '${_selectedBirthday!.day.toString().padLeft(2, '0')} : '
                            '${_getMonthAbbreviation(_selectedBirthday!.month)} : '
                            '${_selectedBirthday!.year}',
                    isReverse: true,
                    selectedTextColor: Colors.black,
                    transitionType: TransitionType.LEFT_TO_RIGHT,
                    backgroundColor: Colors.black,
                    borderColor: Colors.white,
                    borderRadius: 0,
                    borderWidth: 2,
                  ),
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
                  if (_selectedBirthday != null &&
                      appProgressState.isStepCompleted(ProgressStep.birthday)) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HeightWeightScreen(
                          gender: widget.gender,
                          birthday: _selectedBirthday!.toIso8601String(),
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select your birthday.'),
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