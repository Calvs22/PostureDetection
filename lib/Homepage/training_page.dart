import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import '/Homepage/Discover/Generatedexercise/workoutplan_screen.dart';
import '/Homepage/Discover/generated_exercise_list.dart';

class TrainingPage extends StatefulWidget {
const TrainingPage({super.key});

@override
State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
DateTime selectedDate = DateTime.now();
late List<DateTime> monthDates;
late ScrollController _scrollController;
final dbHelper = DatabaseHelper.instance;

// State variables for user data and workout tracking
int _weeklyGoal = 4;
int _workoutsCompleted = 0;

// Stores the days of the current visible month that have completed workouts.
Set<int> _daysWithWorkouts = {}; 

@override
void initState() {
super.initState();
_scrollController = ScrollController();
updateMonthDates();
// Load all necessary data
_loadTrainingData(); 

// Scroll to today's date after the widget is built
WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
}

// Reload data when the month changes (optional, but good practice)
Future<void> _loadTrainingData() async {
final currentMonth = selectedDate.month;
final currentYear = selectedDate.year;

// Fetch user info, weekly goal, and weekly completed count
final userInfo = await dbHelper.getLatestUserInfo();
// Fix: Renamed method to match DatabaseHelper
final completedInWeek = await dbHelper.getWorkoutsCompletedThisWeek();
// Fetch the days with completed workouts for the currently viewed month
final daysInMonth = await dbHelper.getDaysWithCompletedWorkouts(currentMonth, currentYear);

if (mounted) {
setState(() {
 _weeklyGoal = userInfo?['weeklyGoal'] ?? 4;
 _workoutsCompleted = completedInWeek;
 _daysWithWorkouts = daysInMonth;
});
}
}

void updateMonthDates() {
final nextMonth = (selectedDate.month == 12)
 ? DateTime(selectedDate.year + 1, 1, 0)
 : DateTime(selectedDate.year, selectedDate.month + 1, 0);

monthDates = List.generate(
nextMonth.day,
(index) => DateTime(selectedDate.year, selectedDate.month, index + 1),
);
// Reload workout data whenever the month changes
_loadTrainingData(); 
}



void scrollToToday() {
if (!_scrollController.hasClients) return;

final today = DateTime.now();
// Only scroll if today is in the current displayed month
if (today.month != selectedDate.month || today.year != selectedDate.year) return;

final index = today.day - 1; // Gets the list index of today's date
const itemWidth = 48.0; // Width of a date item (40 width + 8 margin)

_scrollController.animateTo(
index * itemWidth,
duration: const Duration(milliseconds: 500),
curve: Curves.easeOut,
);
}

Future<void> _onViewWorkoutPlanPressed() async {
final pinnedList = await dbHelper.getPinnedWorkoutList();

if (mounted) {
if (pinnedList != null) {
 Navigator.of(context).push(
 MaterialPageRoute(
 builder: (context) => WorkoutPlanScreen(
 workoutListId: pinnedList.id,
 isManualCreation: false,
 ),
 ),
 );
} else {
 await Navigator.of(context).push(
 MaterialPageRoute(
 builder: (context) => const GeneratedExerciseListPage(),
 ),
 );
}
// Re-load data when returning to this page, in case a workout was completed
_loadTrainingData(); 
}
}

@override
void dispose() {
_scrollController.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
return Stack(
children: [
 Positioned.fill(
 child: Image.asset(
 'assets/bg.jpeg',
 fit: BoxFit.cover,
 errorBuilder: (context, error, stackTrace) {
 return Center(
  child: Text(
  'Background image not found',
  style: TextStyle(color: Colors.red.shade700, fontSize: 16),
  ),
 );
 },
 ),
 ),
 SafeArea(
 child: ListView(
 padding: const EdgeInsets.all(16.0),
 children: [
 // REMOVED: Welcome Text ('Ready to train, $_nickname?')
 const SizedBox(height: 24),

 // Weekly Goal (Now using live data, made bigger)
 Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
  const Text(
  'Weekly goal',
  style: TextStyle(
  fontSize: 22, // Increased size
  fontWeight: FontWeight.bold,
  color: Colors.white,
  ),
  ),
  Text(
  // Using actual state variables
  '$_workoutsCompleted/$_weeklyGoal',
  style: const TextStyle(
  fontSize: 20, // Increased size
  color: Colors.blue,
  fontWeight: FontWeight.bold,
  ),
  ),
  ],
 ),
 const SizedBox(height: 16), // Increased spacing

 // Date Headers
 Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
  Text(
  // Format set to 'MMMM yyyy' for full month name (e.g., September 2025)
  DateFormat('MMMM yyyy').format(selectedDate),
  style: const TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.bold,
  color: Colors.white,
  ),
  ),
  // REMOVED: Calendar icon/button
  ],
 ),
 const SizedBox(height: 8),

 Text(
  DateFormat('EEEE, d').format(selectedDate),
  style: const TextStyle(fontSize: 14, color: Colors.white70),
 ),
 const SizedBox(height: 16),

 // Date Calendar Row
 SizedBox(
  height: 60,
  child: ListView.builder(
  controller: _scrollController,
  scrollDirection: Axis.horizontal,
  itemCount: monthDates.length,
  itemBuilder: (context, index) {
  final day = monthDates[index];
  final isSelected = DateUtils.isSameDay(day, selectedDate);
  final isToday = DateUtils.isSameDay(day, DateTime.now());
  final hasWorkout = _daysWithWorkouts.contains(day.day); 

  // Determine the circle color based on state
  Color circleColor;
  Color textColor;
  
  if (hasWorkout) {
   // REQUESTED: Green if workout is done
   circleColor = Colors.lightGreen;
   textColor = Colors.white;
  } else if (isToday) {
   // Blue for today if no workout
   circleColor = Colors.blue[700]!;
   textColor = Colors.white;
  } else {
   // Default gray/white
   circleColor = const Color.fromARGB(179, 255, 255, 255);
   textColor = Colors.black;
  }

  // If the day is currently selected, use a blue border regardless of the fill color
  final borderColor = isSelected ? Colors.blue : null;


  return GestureDetector(
  onTap: () {
   setState(() {
   selectedDate = day;
   });
  },
  child: Container(
   width: 40,
   margin: const EdgeInsets.symmetric(horizontal: 4),
   child: Column(
   mainAxisAlignment: MainAxisAlignment.center,
   children: [
   Container(
   width: 40,
   height: 40,
   decoration: BoxDecoration(
    color: circleColor,
    shape: BoxShape.circle,
    border: borderColor != null ? Border.all(color: borderColor, width: 2) : null,
   ),
   alignment: Alignment.center,
   child: Text(
    '${day.day}',
    style: TextStyle(
    color: textColor,
    fontWeight: FontWeight.bold,
    fontSize: 16,
    ),
   ),
   ),
   // Dot indicator for workout completion (now redundant but kept for structure)
   if (hasWorkout) ...[
   const SizedBox(height: 4),
   Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(
    color: Colors.lightGreenAccent, // Green dot
    shape: BoxShape.circle,
    ),
   ),
   ],
   ],
   ),
  ),
  );
  },
  ),
 ),
 const SizedBox(height: 32),
 
 // View Workout Plan Button (Increased size and padding)
 ElevatedButton.icon(
  onPressed: _onViewWorkoutPlanPressed,
  icon: const Icon(Icons.fitness_center, size: 28), // Increased icon size
  label: const Text(
  'View Workout Plan',
  style: TextStyle(fontSize: 20), // Increased font size
  ),
  style: ElevatedButton.styleFrom(
  backgroundColor: Colors.blue[700],
  foregroundColor: Colors.white,
  minimumSize: const Size(double.infinity, 60), // Increased card height
  padding: const EdgeInsets.symmetric(vertical: 18), // Increased padding
  shape: RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(15), // Slightly increased border radius
  ),
  ),
 ),
 const SizedBox(height: 16),

 const SizedBox(height: 80),
 ],
 ),
 ),
],
);
}
}