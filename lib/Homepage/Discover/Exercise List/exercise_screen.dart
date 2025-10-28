// lib/Homepage/Discover/Exercise List/exercise_screen.dart

import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show ExerciseLogic;
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart'
    show Exercise;
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '/db/Models/exercise_model.dart';
import '/body_posture/camera/pose_detection_camera_screen.dart';

class ExerciseScreen extends StatefulWidget {
  final Exercise exercise;
  final ExerciseLogic logic;

  const ExerciseScreen({
    super.key,
    required this.exercise,
    required this.logic,
  });

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  late String? _gifPath;

  @override
  void initState() {
    super.initState();
    _gifPath = widget.exercise.imagePath;
  }

  /// ✅ Safe update method (no setState during build)
  void _update(List<PoseLandmark> landmarks, bool isFrontCamera) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        widget.logic.update(landmarks, isFrontCamera);
      });
    });
  }

  /// ✅ Safe reset method (same protection as _update)
  void _reset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        widget.logic.reset();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PoseDetectionCameraScreen(
      builder: (context, landmarks, cameraViewSize, isFrontCamera) {
        _update(landmarks, isFrontCamera);

        return Column(
          children: [
            // Exercise GIF/Image Preview
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _gifPath != null && _gifPath!.isNotEmpty
                    ? Image.asset(
                        _gifPath!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Text(
                              'Exercise preview not found (check imagePath)',
                              style: TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      )
                    : const Center(
                        child: Text(
                          'No preview available for this exercise.',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
            ),

            // Exercise Progress
            Expanded(
              flex: 1,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.logic.progressLabel,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Reset button
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: ElevatedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
