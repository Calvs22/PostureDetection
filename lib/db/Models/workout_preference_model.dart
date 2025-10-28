class WorkoutPreference {
 final int? id;
 final String fitnessLevel;
 final String goal;
 final String equipment; // 'Dumbbells' or 'Bodyweight'
 final int minutes;

 WorkoutPreference({
  this.id,
  required this.fitnessLevel,
  required this.goal,
  required this.equipment,
  required this.minutes,
 });

 Map<String, dynamic> toMap() {
  return {
   'id': id,
   'fitnessLevel': fitnessLevel,
   'goal': goal,
   'equipment': equipment,
   'minutes': minutes,
  };
 }

 static WorkoutPreference fromMap(Map<String, dynamic> map) {
  return WorkoutPreference(
   id: map['id'] as int?,
   fitnessLevel: map['fitnessLevel'] as String,
   goal: map['goal'] as String,
   equipment: map['equipment'] as String,
   minutes: map['minutes'] as int,
  );
 }
}