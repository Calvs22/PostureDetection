// nickname.dart (FIXED: Provider removed, Supabase sync added)

import 'package:flutter/material.dart';
import 'package:flutter_animated_button/flutter_animated_button.dart';
import 'package:gap/gap.dart';
// import 'package:provider/provider'; // <<< REMOVED: Causing errors
import '../db/database_helper.dart'; // Ensure this path is correct
import '../Homepage/homepage.dart'; // Ensure this path is correct
// import 'progress_state.dart'; // <<< REMOVED: Not necessary without provider
import '../main.dart'; // CRITICAL: Import to access globalSupabaseService

// --- NicknameScreen Class ---
class NicknameScreen extends StatefulWidget {
   final String gender;
   final String birthday;
   final double height;
   final double weight;
   final int weeklyGoal; 

   const NicknameScreen({
      super.key,
      required this.gender,
      required this.birthday,
      required this.height,
      required this.weight,
      required this.weeklyGoal,
   });

   @override
   State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
   final TextEditingController _nicknameController = TextEditingController();
   
  // Local state to track button enablement and progress completion
  bool _isButtonEnabled = false;

   @override
   void initState() {
      super.initState();
      // Add listener to enable/disable button
      _nicknameController.addListener(_updateButtonState);
   }

   @override
   void dispose() {
      _nicknameController.dispose();
      super.dispose();
   }

   // Updates the local state based on the text field content
   void _updateButtonState() {
      final isNotEmpty = _nicknameController.text.trim().isNotEmpty;
    // Only call setState if the state actually changes
    if (_isButtonEnabled != isNotEmpty) {
      setState(() {
        _isButtonEnabled = isNotEmpty;
      });
    }
   }

   Future<void> _onContinuePressed() async {
      final nickname = _nicknameController.text.trim();
      if (nickname.isEmpty) {
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Please enter your nickname to continue.')),
            );
         }
         return;
      }

      try {
         // 1. Save the full user profile data into the local SQLite database.
         await DatabaseHelper.instance.insertUserInfo(
            nickname: nickname,
            gender: widget.gender,
            birthday: widget.birthday,
            height: widget.height,
            weight: widget.weight,
            weeklyGoal: widget.weeklyGoal, // DATA SAVED LOCALLY
         );
      
      // 2. CRITICAL FIX: PUSH LOCAL DATA TO SUPABASE CLOUD
      // This solves the original issue of the 'profiles' table being empty.
      await globalSupabaseService.pushProfileToCloud();

         if (!mounted) return;

         // 3. Navigate to the next screen (HomePage) after local save and cloud sync.
         Navigator.pushReplacement(
            context,
            MaterialPageRoute(
               builder: (context) => const HomePage(),
            ),
         );
      } catch (e) {
         if (mounted) {
            // Log the error and show a user-friendly message
            ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('An error occurred. Could not save data: $e')),
            );
         }
      }
   }

   @override
   Widget build(BuildContext context) {
    // Removed context.watch call that was causing an error.
    // Replace with a static value or remove progress bar entirely if you don't have
    // an external way to calculate it without provider. Using static 1.0 for simplicity.
    const double currentProgress = 1.0; 

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
                                 // Using a static 1.0 progress bar here, as dynamic progress 
                      // required the removed 'provider' package.
                                 child: LinearProgressIndicator(
                                    value: currentProgress, 
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
                              'What is your Nickname?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                 fontSize: 20,
                                 fontWeight: FontWeight.bold,
                                 color: Colors.white,
                              ),
                           ),
                           const Gap(20),
                           Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: TextField(
                                 controller: _nicknameController,
                                 style: const TextStyle(color: Colors.black),
                                 decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                       borderRadius: BorderRadius.circular(10),
                                       borderSide: BorderSide.none,
                                    ),
                                    hintText: 'Enter your nickname',
                                    hintStyle: TextStyle(color: Colors.grey[600]),
                                 ),
                              ),
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
                        onPress: _isButtonEnabled ? _onContinuePressed : null, // Uses local state
                        height: 35,
                        width: 120,
                        text: 'Continue',
                        isReverse: true,
                        selectedTextColor: Colors.black,
                        transitionType: TransitionType.LEFT_TO_RIGHT,
                        backgroundColor: _isButtonEnabled ? Colors.blueAccent : Colors.grey, // Uses local state
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
