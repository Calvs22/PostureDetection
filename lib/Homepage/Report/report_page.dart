import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import 'package:fitnesss_tracker_app/db/Models/exercise_performance_model.dart';

// Helper function to format seconds into mm:ss
String _formatDuration(int totalSeconds) {
  final clampedSeconds = totalSeconds.clamp(0, totalSeconds.abs());
  final minutes = (clampedSeconds / 60).floor().toString().padLeft(2, '0');
  final seconds = (clampedSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  // 1. DYNAMIC LOOKUP MAP: Removed the static map and made it a state variable
  Map<String, String> _exerciseTypeLookup = const {};

  double? _userHeight; // in cm
  double? _userWeight; // in kg
  
  // Future that depends on the lookup map being loaded
  late Future<List<Map<String, dynamic>>> _processedSessionDataFuture;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  String _selectedFilter = 'Last 7 Days'; // Default filter

  @override
  void initState() {
    super.initState();
    // 2. INITIALIZATION: Load user info and exercise types first
    _loadUserInfo();
    _loadExerciseTypes().then((_) {
      // 3. START DATA PROCESSING: Start loading the session data only after types are available
      setState(() {
        _processedSessionDataFuture = _loadAndProcessSessionData();
      });
    });
  }

  /// Loads the definitive exercise type map from the DatabaseHelper.
  Future<void> _loadExerciseTypes() async {
    try {
      final lookup = await _dbHelper.getAllExerciseNameAndType();
      setState(() {
        _exerciseTypeLookup = lookup;
      });
    } catch (e) {
      // Handle potential DB error, but continue with empty map
      debugPrint('Error loading exercise types from DB: $e');
    }
  }

  /// Looks up the exercise type using the dynamically loaded map. 
  String _getExerciseType(String exerciseName) {
    // Check for 'Rep' or 'Reps' (handling the inconsistency found in the initial data)
    final type = _exerciseTypeLookup[exerciseName];
    if (type == 'Timer') {
      return 'Timer';
    }
    // Default to Rep for anything else (Rep, Reps, or not found)
    return 'Rep';
  }

  // --- EXISTING METHODS (UNCHANGED logic for _loadUserInfo, _loadAndProcessSessionData, etc.) ---

  Future<void> _loadUserInfo() async {
    final userInfo = await DatabaseHelper.instance.getLatestUserInfo();
    if (userInfo != null) {
      setState(() {
        _userHeight = userInfo['height'] as double?;
        _userWeight = userInfo['weight'] as double?;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadAndProcessSessionData() async {
    // Note: This method now relies on _exerciseTypeLookup being populated
    final List<Map<String, dynamic>> sessions =
        await _dbHelper.fetchWorkoutSessions();

    final List<Map<String, dynamic>> mutableSessions = [];

    for (final session in sessions) {
      final List<dynamic> rawPerformances = session['exercises'] as List? ?? [];
      final List<ExercisePerformance> performances = rawPerformances
          .map((e) => ExercisePerformance.fromMap(e as Map<String, dynamic>))
          .toList();

      final List<Map<String, dynamic>> individualPerformances = [];
      for (var performance in performances) {
        final double completedValue = performance.repsCompleted ?? 0.0;
        double percentage = 0.0;
        final int plannedValuePerSet = performance.plannedReps ?? 0;
        final int plannedSets = performance.plannedSets ?? 1;

        final int totalPlannedValue = plannedValuePerSet * plannedSets;

        if (totalPlannedValue > 0) {
          percentage = (completedValue / totalPlannedValue) * 100;
        } else if (completedValue > 0) {
          percentage = 100.0; 
        }

        individualPerformances.add({
          'exerciseName': performance.exerciseName,
          'repsCompleted': completedValue, 
          'plannedRepsPerSet': plannedValuePerSet, 
          'plannedSets': plannedSets,
          'percentage': percentage.clamp(0, 100),
        });
      }

      final Map<String, dynamic> mutableSession =
          Map<String, dynamic>.from(session);
      mutableSession['exercises'] = individualPerformances;
      mutableSessions.add(mutableSession);
    }
    return mutableSessions;
  }

  List<Map<String, dynamic>> _filterSessions(
      List<Map<String, dynamic>> allData, String filter) {
    final now = DateTime.now();
    int daysToSubtract;
    switch (filter) {
      case 'Last 1 Day':
        daysToSubtract = 1;
        break;
      case 'Last 3 Days':
        daysToSubtract = 3;
        break;
      case 'Last 7 Days':
        daysToSubtract = 7;
        break;
      case 'Last 15 Days':
        daysToSubtract = 15;
        break;
      case 'Last 30 Days':
        daysToSubtract = 30;
        break;
      default:
        daysToSubtract = 2000;
    }

    final filteredSessions = allData.where((session) {
      try {
        final sessionDate = DateTime.parse(session['date'] as String);
        final startOfToday = DateTime(now.year, now.month, now.day); 
        final startOfSessionDate = DateTime(sessionDate.year, sessionDate.month, sessionDate.day);
        return startOfToday.difference(startOfSessionDate).inDays < daysToSubtract;
      } catch (e) {
        debugPrint('Error parsing date for session: $e');
        return false;
      }
    }).toList();

    filteredSessions.sort((a, b) => DateTime.parse(a['date'] as String)
        .compareTo(DateTime.parse(b['date'] as String)));

    return filteredSessions;
  }
  
  void _onFilterChanged(String? newFilter) {
    if (newFilter != null && newFilter != _selectedFilter) {
      setState(() {
        _selectedFilter = newFilter;
      });
    }
  }

  String _getBMICategory(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25.0) return 'Normal';
    if (bmi < 30.0) return 'Overweight';
    return 'Obese';
  }

  double _calculateTargetWeight(
      double height, double currentBmi, String category) {
    const double normalMinBmi = 18.5;
    const double normalMaxBmi = 24.9;
    final heightInMeters = height / 100;

    if (category == 'Underweight') {
      return normalMinBmi * heightInMeters * heightInMeters;
    } else {
      return normalMaxBmi * heightInMeters * heightInMeters; 
    }
  }

  String _getBMIText(double height, double weight) {
    final bmi = weight / ((height / 100) * (height / 100));
    final category = _getBMICategory(bmi);
    final formattedBmi = bmi.toStringAsFixed(1);

    if (category == 'Normal') {
      return '$formattedBmi ($category) — Keep up the good work! 💪';
    } else {
      final targetWeight = _calculateTargetWeight(height, bmi, category);
      final weightDifference = (targetWeight - weight).abs().toStringAsFixed(1);
      String action = (category == 'Underweight') ? 'gain' : 'lose';
      String emoji = (category == 'Underweight') ? '🍔' : '🏃';
      return '$formattedBmi ($category) — Goal: $action $weightDifference kg to reach a Normal BMI. $emoji';
    }
  }

  // --- WIDGET BUILDERS (UNCHANGED) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Your Progress Report',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.grey[850],
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        // Ensure _exerciseTypeLookup is populated before building
        future: _exerciseTypeLookup.isEmpty 
          ? Future.error("Exercise types are not loaded.") 
          : _processedSessionDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _exerciseTypeLookup.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: Colors.blue));
          } else if (snapshot.hasError && snapshot.error.toString() != "Exercise types are not loaded.") {
            return Center(
                child: Text('Error loading data: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white70)));
          }
          final List<Map<String, dynamic>> allSessionData =
              snapshot.data ?? [];

          final List<Map<String, dynamic>> filteredSessionsForGraph =
              _filterSessions(allSessionData, _selectedFilter);

          final allExercises = allSessionData.expand((session) {
            final exercises = session['exercises'];
            return exercises is List<Map<String, dynamic>>
                ? exercises
                : <Map<String, dynamic>>[];
          }).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSummarySection(allExercises, allSessionData.length),
                const SizedBox(height: 20),
                _buildBMICard(),
                const SizedBox(height: 20),
                _buildRepsGraph(filteredSessionsForGraph),
                const SizedBox(height: 20),
                _buildSessionHistorySection(allSessionData),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBMICard() {
    final height = _userHeight;
    final weight = _userWeight;
    
    String title = 'Body Mass Index (BMI)';
    String content;
    Color contentColor = Colors.white;

    if (height != null && weight != null && height > 0) {
      content = _getBMIText(height, weight);
      
      final bmi = weight / ((height / 100) * (height / 100));
      final category = _getBMICategory(bmi);
      
      if (category == 'Normal') {
        contentColor = Colors.green[300]!;
      } else if (category == 'Overweight' || category == 'Obese') {
        contentColor = Colors.red[300]!;
      } else if (category == 'Underweight') {
        contentColor = Colors.orange[300]!;
      }
      
    } else {
      content = 'Please enter your Height (cm) and Weight (kg) in Profile Settings to calculate your BMI and get recommendations.';
      contentColor = Colors.white70;
    }

    return Card(
      color: Colors.grey[800],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              content,
              style: TextStyle(fontSize: 16, color: contentColor, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(
      List<Map<String, dynamic>> allExercises, int totalSessions) {
    if (allExercises.isEmpty) {
      return Card(
        color: Colors.grey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No workout data available yet. Start a session!',
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    double grandTotalCompletedValue = 0.0;
    int grandTotalPlannedValue = 0;

    for (var setPerformance in allExercises) {
      final double completedValue = setPerformance['repsCompleted'] as double;
      final int plannedSets = setPerformance['plannedSets'] as int;
      final int plannedValuePerSet = setPerformance['plannedRepsPerSet'] as int;

      grandTotalCompletedValue += completedValue;
      grandTotalPlannedValue += plannedValuePerSet * plannedSets;
    }

    double overallAveragePercentage = 0.0;
    if (grandTotalPlannedValue > 0) {
      overallAveragePercentage =
          (grandTotalCompletedValue / grandTotalPlannedValue) * 100;
    } else if (grandTotalCompletedValue > 0) {
      overallAveragePercentage = 100.0;
    }

    final validPercentages = allExercises
        .map<double>((e) => e['percentage'] as double)
        .where((p) => p > 0.0)
        .toList();
    final double highestPercentage = validPercentages.isNotEmpty
        ? validPercentages.reduce((a, b) => a > b ? a : b)
        : 0.0;

    return Card(
      color: Colors.grey[800],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Summary (Lifetime)',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 10),
            _buildSummaryRow('Overall Average Performance %',
                '${overallAveragePercentage.clamp(0, 100).toStringAsFixed(1)}%'),
            _buildSummaryRow('Total Sessions Completed', totalSessions.toString()),
            _buildSummaryRow('Personal Best Set %',
                '${highestPercentage.toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildRepsGraph(List<Map<String, dynamic>> data) {
    if (data.length < 2) {
      return Card(
        color: Colors.grey[800],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Text(
                'Log at least two sessions for the $_selectedFilter period to view your progress graph.',
                style: const TextStyle(color: Colors.white70)),
          ),
        ),
      );
    }

    final spots = data.asMap().entries.map((entry) {
      final session = entry.value;
      double sessionTotalCompletedValue = 0.0;
      int sessionTotalPlannedGoal = 0;
      double averagePercentageForSession = 0.0;

      final exercises = session['exercises'] as List<Map<String, dynamic>>;

      if (exercises.isNotEmpty) {
        for (var setPerformance in exercises) {
          sessionTotalCompletedValue += setPerformance['repsCompleted'] as double;
          sessionTotalPlannedGoal += (setPerformance['plannedRepsPerSet'] as int) *
              (setPerformance['plannedSets'] as int);
        }

        if (sessionTotalPlannedGoal > 0) {
          averagePercentageForSession =
              (sessionTotalCompletedValue / sessionTotalPlannedGoal) * 100;
        } else if (sessionTotalCompletedValue > 0) {
          averagePercentageForSession = 100.0;
        }
      }

      return FlSpot(
          entry.key.toDouble(), averagePercentageForSession.clamp(0, 100));
    }).toList();

    return Card(
      color: Colors.grey[800],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Over Time ($_selectedFilter)',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: 1.7,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: spots.length.toDouble() - 1,
                  minY: 0,
                  maxY: 100,
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < data.length) {
                            final dateString = data[value.toInt()]['date'] as String;
                            final date = DateTime.parse(dateString);
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(DateFormat('M/d').format(date), 
                                style: const TextStyle(color: Colors.white70, fontSize: 10)),
                            );
                          }
                          return Container();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}%', 
                            style: const TextStyle(color: Colors.white70, fontSize: 10));
                        },
                        reservedSize: 30,
                        interval: 25,
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  gridData: const FlGridData(show: true, horizontalInterval: 25, drawVerticalLine: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue[300],
                      barWidth: 3,
                      dotData: FlDotData(show: true, checkToShowDot: (spot, barData) => spot.y > 0),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue[300]!.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionHistorySection(List<Map<String, dynamic>> allData) {
    final List<Map<String, dynamic>> filteredSessions =
        _filterSessions(allData, _selectedFilter);

    final List<Map<String, dynamic>> historyData =
        List<Map<String, dynamic>>.from(filteredSessions.reversed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Session History',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              _buildFilterDropdown(),
            ],
          ),
        ),
        _buildHistoryList(historyData),
      ],
    );
  }

  Widget _buildFilterDropdown() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedFilter,
        icon: const Icon(Icons.filter_list, color: Colors.white),
        style: const TextStyle(color: Colors.white),
        dropdownColor: Colors.grey[800],
        items: <String>[
          'Last 1 Day',
          'Last 3 Days',
          'Last 7 Days',
          'Last 15 Days',
          'Last 30 Days'
        ].map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value),
          );
        }).toList(),
        onChanged: _onFilterChanged,
      ),
    );
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
          child: Text(
            'No workout sessions found for $_selectedFilter.',
            style: const TextStyle(fontSize: 16, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      primary: false,
      itemCount: data.length,
      itemBuilder: (context, index) {
        return _buildSessionCard(data[index]);
      },
    );
  }

  /// Helper function to perform data aggregation and display
  Widget _buildSessionCard(Map<String, dynamic> session) {
    final dateString = session['date'] as String?;
    final date = dateString != null
        ? DateFormat('MMMM d, yyyy').format(DateTime.parse(dateString))
        : 'Unknown Date';
    final time = dateString != null
        ? DateFormat('h:mm a').format(DateTime.parse(dateString))
        : 'Unknown Time';

    final List<Map<String, dynamic>> setPerformances =
        (session['exercises'] as List).cast<Map<String, dynamic>>();

    // 1. Group individual set performances by exerciseName
    final Map<String, List<Map<String, dynamic>>> groupedPerformances = {};
    for (var set in setPerformances) {
      final name = set['exerciseName'] as String;
      if (!groupedPerformances.containsKey(name)) {
        groupedPerformances[name] = [];
      }
      groupedPerformances[name]!.add(set);
    }

    // 2. Calculate the total performance and overall session average
    final List<Map<String, dynamic>> aggregatedExercises = [];
    double totalSessionPercentageSum = 0.0;
    int exerciseCount = 0;

    groupedPerformances.forEach((exerciseName, sets) {
      double totalCompletedValue = 0.0; // Total reps/seconds completed
      
      final int plannedValuePerSet = sets.first['plannedRepsPerSet'] as int;
      final int plannedSets = sets.first['plannedSets'] as int;
      final int totalPlannedGoal = plannedValuePerSet * plannedSets;

      final String exerciseType = _getExerciseType(exerciseName); // <-- Using the DYNAMIC lookup

      for (var set in sets) {
        totalCompletedValue += set['repsCompleted'] as double;
      }

      double overallExercisePercentage = 0.0;
      if (totalPlannedGoal > 0) {
        overallExercisePercentage = (totalCompletedValue / totalPlannedGoal) * 100;
      } else if (totalCompletedValue > 0) {
        overallExercisePercentage = 100.0;
      }

      String repLabel;
      if (totalPlannedGoal == 0) {
        // No goal was set, just show completed value if > 0
        repLabel = totalCompletedValue > 0 ? '${totalCompletedValue.toStringAsFixed(0)} Done' : 'No Goal';
      } else if (exerciseType == 'Timer') { // <-- Using the explicit type
        // Time-based: Format to MM:SS (e.g., 00:00/00:30)
        final String currentFormatted = _formatDuration(totalCompletedValue.toInt());
        final String targetFormatted = _formatDuration(totalPlannedGoal.toInt());
        repLabel = '$currentFormatted/$targetFormatted';
      } else {
        // Rep-based: Show raw number and 'Reps' label (e.g., 10/30 Reps)
        repLabel =
            '${totalCompletedValue.toStringAsFixed(0)}/${totalPlannedGoal.toStringAsFixed(0)} Reps';
      }

      aggregatedExercises.add({
        'exerciseName': exerciseName,
        'repLabel': repLabel,
        'percentage': overallExercisePercentage.clamp(0, 100),
      });

      totalSessionPercentageSum += overallExercisePercentage.clamp(0, 100);
      exerciseCount++;
    });

    final double sessionTotalPercentage = exerciseCount > 0
        ? totalSessionPercentageSum / exerciseCount
        : 0.0;

    return Card(
      color: Colors.grey[800],
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${sessionTotalPercentage.toStringAsFixed(1)}% Avg',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),
            ...aggregatedExercises.map((exercise) {
              final String exerciseName = exercise['exerciseName'];
              final double percentage = exercise['percentage'];
              final String repLabel = exercise['repLabel'];
              final Color percentageColor =
                  percentage >= 70 ? Colors.green[300]! : Colors.red[300]!;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$exerciseName ($repLabel)',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: percentageColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}