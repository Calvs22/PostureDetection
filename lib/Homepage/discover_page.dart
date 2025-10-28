//lib/Homepage/discover_page.dart
import 'package:fitnesss_tracker_app/Homepage/Discover/Exercise%20List/exercises_list.dart'
    show ExercisesListPage;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
// 1. New Import: Add the import for the generated exercises page
import 'package:fitnesss_tracker_app/Homepage/Discover/generated_exercise_list.dart'
    show GeneratedExerciseListPage;

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> cardsData = [
      {
        'title': 'Generated Exercises',
        'subtitle': 'AI-powered suggestions',
        'icon': Icons.auto_awesome,
        'color': Colors.teal,
        // Add a route identifier for easy navigation handling
        'route': 'generated',
      },
      {
        'title': 'List of Exercises',
        'subtitle': 'Browse individual movements',
        'icon': Icons.list_alt,
        'color': Colors.brown,
        'route': 'list',
      },
    ];

    return Scaffold(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    'Discover',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  // Make the GridView fill the remaining space
                  child: GridView.count(
                    crossAxisCount: 1,
                    mainAxisSpacing: 16.0,
                    childAspectRatio: 2.5,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    children: cardsData.map((card) {
                      return GestureDetector(
                        onTap: () {
                          // 2. Updated Navigation Logic: Check the 'route' key
                          Widget? page;
                          if (card['route'] == 'list') {
                            page = const ExercisesListPage();
                          } else if (card['route'] == 'generated') {
                            // Navigate to the new GeneratedExerciseListPage
                            page = const GeneratedExerciseListPage();
                          }

                          if (page != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => page!),
                            );
                          }
                        },
                        child: Card(
                          elevation: 5,
                          color: card['color'],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  card['icon'],
                                  size: 50,
                                  color: Colors.white,
                                ),
                                const Gap(20),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        card['title'],
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const Gap(5),
                                      Text(
                                        card['subtitle'],
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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
