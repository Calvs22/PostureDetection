// lib/Homepage/Discover/Exercise List/exercise_logic_factory.dart


import 'package:fitnesss_tracker_app/body_posture/exercises_logic/arm_circles_clockwise_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/arm_circles_counterclockwise_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/cat_cow_pose_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/child_pose_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/cobra_stretch_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/inchworm_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/jumping_jacks_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/jumping_squat_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/knee_pushup_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/knee_to_chest_stretch_left_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/knee_to_chest_stretch_right_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/left_leg_donkey_kicks_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/lunges__logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/pike_pushup_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/plank_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/camera/exercises_logic.dart'
    show ExerciseLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/pushup_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/rhomboid_pulls.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/russian_twist_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/side_hop_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/standing_bicep_stretch_left_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/standing_bicep_stretch_right_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/tricep_dips_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/tricep_stretch_left_logic.dart';
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/tricep_stretch_right_logic.dart';
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart'
    show Exercise;

// ✅ Implemented logics
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/bwsquat_logic.dart'
    show BWSquatLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/abdominal_crunches_logic.dart'
    show AbdominalCrunchesLogicV2;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/arm_raises_logic.dart'
    show ArmRaisesLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/calf_stretch_left_logic.dart'
    show CalfStretchLeftLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/calf_stretch_right_logic.dart'
    show CalfStretchRightLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/decline_pushup_logic.dart'
    show DeclinePushUpLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/incline_pushup_logic.dart'
    show InclinePushupLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/left_leg_glute_kickback_logic.dart'
    show LeftLegGluteKickbackLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/leg_raises_logic.dart'
    show LegRaisesLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/right_leg_glute_kickback_logic.dart'
    show RightLegGluteKickbackLogic;
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/wall_sit_logic.dart'
    show WallSitLogic;

// ✅ Alternating Hooks Logic
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/alternating_hooks_logic.dart'
    show AlternatingHooksLogic;

// ✅ Diamond Push-Up Logic
import 'package:fitnesss_tracker_app/body_posture/exercises_logic/diamond_pushup_logic.dart'
    show DiamondPushUpLogic;

//DUMBELLS
// DUMBBELLS
// ✅ Bent Over Row Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/bentover_row_logic.dart'
    show BentOverRowLogic;
// ✅ Dumbbell Squat Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_squat_logic.dart'
    show DumbbellSquatLogic;
// ✅ Dumbbell Chest Fly Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_chestfly_logic.dart'
    show DumbbellChestFlyLogic;
// ✅ Dumbbell Crunch Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_crunch_logic.dart'
    show DumbbellCrunchLogic;
// ✅ Dumbbell Drag Curl Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_drag_curl_logic.dart'
    show DumbbellDragCurlLogic;
// ✅ Dumbbell Kickbacks Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_kickbacks_logic.dart'
    show DumbbellKickbacksLogic;
// ✅ Dumbbell Russian Twist Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_russian_twist.dart'
    show DumbbellRussianTwistLogic;
// ✅ Dumbbell Split Squat (Left) Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_split_squat_left_logic.dart';
// ✅ Dumbbell Split Squat (Right) Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/dumbbell_split_squat_right_logic.dart';
// ✅ Standing Dumbbell Curl Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/standing_dumbbell_curl_logic.dart'
    show StandingDumbbellCurlLogic;
// ✅ Valley Press Logic
import 'package:fitnesss_tracker_app/body_posture/dumbbell_logic/valley_press_logic.dart'
    show ValleyPressLogic;

// 🔹 Placeholder Logic - defined in this file
class PlaceholderLogic extends ExerciseLogic {
  final String exerciseName;

  PlaceholderLogic(this.exerciseName);

  @override
  String get progressLabel => "$exerciseName: Logic not implemented yet";

  @override
  void reset() {}

  @override
  void update(List landmarks, bool isFrontCamera) {}
}

class ExerciseLogicFactory {
  static ExerciseLogic create(Exercise exercise) {
    switch (exercise.name) {
      // BODYWEIGHT - WARM-UP/CARDIO
      case 'Jumping Jacks':
        return JumpingJacksLogic();
      case 'Arm Circles (Clockwise)':
        return ArmCirclesClockwiseLogic();
      case 'Arm Circles (Counter-Clockwise)':
        return ArmCirclesCounterClockwiseLogic();
      case 'Alternating Hooks':
        return AlternatingHooksLogic();
      case 'Side Hop':
        return SideHopLogic();
      case 'Inchworms':
        return InchwormLogic();

      // BODYWEIGHT - CORE
      case 'Abdominal Crunches':
        return AbdominalCrunchesLogicV2();
      case 'Leg Raises':
        return LegRaisesLogic();
      case 'Russian Twist':
        return RussianTwistLogic();
      case 'Plank':
        return PlankLogic();

      // BODYWEIGHT - UPPER BODY
      case 'Push-Ups':
        return PushUpLogic();
      case 'Diamond Push-Ups':
        return DiamondPushUpLogic();
      case 'Triceps Dips':
        return TricepDipsLogic();
      case 'Knee Push-Ups':
        return KneePushUpLogic();
      case 'Decline Push-Ups':
        return DeclinePushUpLogic();
      case 'Arm Raises':
        return ArmRaisesLogic();
      case 'Rhomboid Pulls':
        return RhomboidPullsLogic();
      case 'Incline Push-Ups':
        return InclinePushupLogic();
      case 'Pike Push-Ups':
        return PikePushupLogic();

      // BODYWEIGHT - LOWER BODY
      case 'Squats':
        return BWSquatLogic();
      case 'Lunges':
        return LungesLogic();
      case 'Jumping Squats':
        return JumpingSquatLogic();
      case 'Donkey Kicks (Right)':
        return LeftLegDonkeyKicksLogic();
      case 'Donkey Kicks (Left)':
        return LeftLegDonkeyKicksLogic();
      case 'Glute Kickbacks (Right)':
        return RightLegGluteKickbackLogic();
      case 'Glute Kickbacks (Left)':
        return LeftLegGluteKickbackLogic();
      case 'Wall Sit':
        return WallSitLogic();

      // BODYWEIGHT - STRETCH/COOLDOWN
      case 'Cobra Stretch':
        return CobraStretchLogic();
      case 'Triceps Stretch (Right)':
        return TricepStretchRightLogic();
      case 'Triceps Stretch (Left)':
        return TricepStretchLeftLogic();
      case 'Standing Biceps Stretch (Right)':
        return StandingBicepStretchRightLogic();
      case 'Standing Biceps Stretch (Left)':
        return StandingBicepStretchLeftLogic();
      case 'Knee to Chest Stretch (Right)':
        return KneeToChestStretchRightLogic();
      case 'Knee to Chest Stretch (Left)':
        return KneeToChestStretchLeftLogic();
      case 'Calf Stretch (Left)':
        return CalfStretchLeftLogic();
      case 'Calf Stretch (Right)':
        return CalfStretchRightLogic();
      case 'Cat Cow Pose':
        return CatCowLogic();
      case 'Child\'s Pose':
        return ChildPoseLogic();

      // DUMBBELL EXERCISES
      // DUMBBELL EXERCISES
      case 'Dumbbell Split Squat (Right)':
        return DumbbellSplitSquatRightLogic();
      case 'Dumbbell Split Squat (Left)':
        return DumbbellSplitSquatLeftLogic();
      case 'Dumbbell Squats':
        return DumbbellSquatLogic();
      case 'Valley Press':
        return ValleyPressLogic();
      case 'Dumbbell Chest Fly':
        return DumbbellChestFlyLogic();
      case 'Bent Over Row':
        return BentOverRowLogic();
      case 'Standing Dumbbell Curl':
        return StandingDumbbellCurlLogic();
      case 'Dumbbell Kickbacks':
        return DumbbellKickbacksLogic();
      case 'Dumbbell Drag Curl':
        return DumbbellDragCurlLogic();
      case 'Dumbbell Crunch':
        return DumbbellCrunchLogic();
      case 'Dumbbell Russian Twist':
        return DumbbellRussianTwistLogic();

      default:
        return PlaceholderLogic(exercise.name);
    }
  }
}
