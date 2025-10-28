// lib/models/workout_list_model.dart

class WorkoutList {
  final int? id; // listId from your request
  final String listName;
  final bool isPinned;

  WorkoutList({
    this.id,
    required this.listName,
    this.isPinned = false,
  });

  // Convert an object into a Map for SQLite insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'listName': listName,
      'isPinned': isPinned ? 1 : 0, // SQLite stores booleans as 0 or 1
    };
  }

  // Create an object from a Map (read from SQLite)
  factory WorkoutList.fromMap(Map<String, dynamic> map) {
    return WorkoutList(
      id: map['id'],
      listName: map['listName'],
      isPinned: map['isPinned'] == 1,
    );
  }

  // Allows creating a copy of the object with some fields changed
  WorkoutList copyWith({bool? isPinned, String? listName}) {
    return WorkoutList(
      id: id,
      listName: listName ?? this.listName, // Use the new value or the existing one
      isPinned: isPinned ?? this.isPinned, // Use the new value or the existing one
    );
  }
}
