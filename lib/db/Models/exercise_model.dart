// lib/db/models/exercise_model.dart

class Exercise {
  final int? id; // Null for new exercises before insertion
  final String name;
  final String category;
  final List<String> primaryMuscleGroups;
  final String equipment;
  final String type;
  final String difficulty;
  final String? imagePath; // Path to local asset
  final String? detectorPath; // Path for ML detection logic

  Exercise({
    this.id,
    required this.name,
    required this.category,
    required this.primaryMuscleGroups,
    required this.equipment,
    required this.type,
    required this.difficulty,
    this.imagePath, // Optional
    this.detectorPath, // ADDED TO CONSTRUCTOR
  });

  // --------------------------------------------------------------------------
  // --- DATABASE MAPPING ---
  // --------------------------------------------------------------------------

  // Convert an Exercise object into a Map for SQLite insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'primaryMuscleGroups': primaryMuscleGroups.join(
        ',',
      ), // Store list as comma-separated string
      'equipment': equipment,
      'type': type,
      'difficulty': difficulty,
      'imagePath': imagePath,
      'detectorPath': detectorPath, // ADDED TO toMap()
    };
  }

  // Create an Exercise object from a Map (read from SQLite)
  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      id: map['id'],
      name: map['name'],
      category: map['category'],
      primaryMuscleGroups: (map['primaryMuscleGroups'] as String).split(
        ',',
      ), // Convert string back to list
      equipment: map['equipment'],
      type: map['type'],
      difficulty: map['difficulty'],
      imagePath: map['imagePath'],
      detectorPath: map['detectorPath'], // ADDED TO fromMap()
    );
  }

  // --------------------------------------------------------------------------
  // --- UTILITY FACTORIES & METHODS ---
  // --------------------------------------------------------------------------

  // Factory constructor for an empty placeholder exercise
  factory Exercise.empty() {
    return Exercise(
      id: 0,
      name: 'Add Exercise',
      category: 'N/A',
      primaryMuscleGroups: [],
      equipment: 'N/A',
      type: 'N/A',
      difficulty: 'N/A',
      imagePath: null,
      detectorPath: null,
    );
  }



  /// Creates a new [Exercise] object with optional new values.
  Exercise copyWith({
    int? id,
    String? name,
    String? category,
    List<String>? primaryMuscleGroups,
    String? equipment,
    String? type,
    String? difficulty,
    String? imagePath,
    String? detectorPath,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      primaryMuscleGroups: primaryMuscleGroups ?? this.primaryMuscleGroups,
      equipment: equipment ?? this.equipment,
      type: type ?? this.type,
      difficulty: difficulty ?? this.difficulty,
      imagePath: imagePath ?? this.imagePath,
      detectorPath: detectorPath ?? this.detectorPath,
    );
  }
}
