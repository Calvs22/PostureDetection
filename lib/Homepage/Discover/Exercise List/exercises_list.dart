// lib/Homepage/Discover/Exercise List/exercises_list.dart
import 'package:fitnesss_tracker_app/Homepage/Discover/Exercise%20List/exercise_logic_factory.dart'
    show ExerciseLogicFactory;
import 'package:flutter/material.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';

// ✅ Import the universal exercise screen & logic factory
import '../../../Homepage/Discover/Exercise List/exercise_screen.dart';

class ExercisesListPage extends StatefulWidget {
  const ExercisesListPage({super.key});

  @override
  State<ExercisesListPage> createState() => _ExercisesListPageState();
}

class _ExercisesListPageState extends State<ExercisesListPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Exercise> _allExercises = [];
  List<Exercise> _filteredExercises = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadExercisesFromDb();
    _searchController.addListener(_filterExercises);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterExercises);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExercisesFromDb() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final exercises = await DatabaseHelper.instance.getAllExercises();
      setState(() {
        _allExercises = exercises;
        _filteredExercises = exercises;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load exercises. Please try again.';
      });
      debugPrint('Error loading exercises: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterExercises() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredExercises = _allExercises;
      } else {
        _filteredExercises = _allExercises
            .where((exercise) => exercise.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _navigateToExercisePage(Exercise exercise) {
    try {
      final logic = ExerciseLogicFactory.create(exercise); // ✅ get logic

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ExerciseScreen(
            exercise: exercise,
            logic: logic, // ✅ FIX: add required argument
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No logic implemented yet for "${exercise.name}".'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Exercises List',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search exercises...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white70,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white12,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                _isLoading
                    ? const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.blueAccent,
                          ),
                        ),
                      )
                    : Expanded(
                        child:
                            _filteredExercises.isEmpty &&
                                _searchController.text.isNotEmpty
                            ? const Center(
                                child: Text(
                                  'No exercises found.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _filteredExercises.length,
                                itemBuilder: (context, index) {
                                  final exercise = _filteredExercises[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    elevation: 4,
                                    color: Colors.white10,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      leading:
                                          exercise.imagePath != null &&
                                              exercise.imagePath!.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.asset(
                                                exercise.imagePath!,
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return const Icon(
                                                        Icons.fitness_center,
                                                        color: Colors.white70,
                                                        size: 40,
                                                      );
                                                    },
                                              ),
                                            )
                                          : const Icon(
                                              Icons.fitness_center,
                                              color: Colors.white70,
                                              size: 40,
                                            ),
                                      title: Text(
                                        exercise.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${exercise.category} - ${exercise.equipment}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                        color: Colors.white70,
                                      ),
                                      onTap: () {
                                        _navigateToExercisePage(exercise);
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
