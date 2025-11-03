// ignore_for_file: avoid_function_literals_in_foreach_calls, avoid_print, file_names


import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:fitnesss_tracker_app/services/local_database_service.dart';
import 'package:fitnesss_tracker_app/db/Models/exercise_model.dart';
import 'package:fitnesss_tracker_app/db/initial_exercise_data.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutlist_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutplan_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workout_preference_model.dart';
import 'package:fitnesss_tracker_app/db/Models/workout_feedback_model.dart';
import 'package:fitnesss_tracker_app/db/Models/exercise_performance_model.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:developer'; // Import for log function

class DatabaseHelper extends LocalDatabaseService {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  // Table names
  static const _workoutListsTable = 'generated_workouts';
  static const _workoutExercisesTable = 'workout_exercises';
  static const _workoutPreferencesTable = 'workout_preferences';
  static const _workoutSessionsTable = 'workout_sessions';
  static const _exercisePerformanceTable = 'exercise_performance';
  static const _workoutFeedbackTable = 'workout_feedback';
  static const _userInfoTable = 'user_info';

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'user_data.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onDowngrade: onDatabaseDowngradeDelete,
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // User Info Table - **SCHEMA MODIFICATION HERE**
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_userInfoTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supabase_user_id TEXT UNIQUE,
        nickname TEXT,
        gender TEXT,
        birthday TEXT,
        height REAL,
        weight REAL,
        weeklyGoal INTEGER DEFAULT 0,
        updated_at TEXT,
        last_modified_at TEXT,
        -- NEW COLUMN ADDED HERE
        haveDisease INTEGER DEFAULT 0 
      )
    ''');

    // Workout Preferences Table - ⭐️ CRITICAL CHANGE HERE
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workoutPreferencesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fitnessLevel TEXT NOT NULL,
        goal TEXT NOT NULL,
        equipment TEXT NOT NULL,
        minutes INTEGER NOT NULL,
        soreMuscleGroup TEXT NOT NULL -- ⭐️ NEW COLUMN ADDED
      )
    ''');

    // Master Exercises List Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        category TEXT NOT NULL,
        primaryMuscleGroups TEXT NOT NULL,
        equipment TEXT NOT NULL,
        type TEXT NOT NULL,
        difficulty TEXT NOT NULL,
        imagePath TEXT,
        detectorPath TEXT
      )
    ''');

    // Workout Plans Table (lists of exercises)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workoutListsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        listName TEXT NOT NULL UNIQUE,
        isPinned INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Workout Exercises Table (the exercises within a plan)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workoutExercisesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workoutListId INTEGER NOT NULL,
        exerciseId INTEGER NOT NULL,
        exerciseName TEXT NOT NULL,
        title TEXT NOT NULL,
        sets INTEGER NOT NULL,
        reps INTEGER NOT NULL,
        rest INTEGER NOT NULL,
        sequence INTEGER NOT NULL,
        FOREIGN KEY (workoutListId) REFERENCES $_workoutListsTable (id) ON DELETE CASCADE,
        FOREIGN KEY (exerciseId) REFERENCES exercises (id)
      )
    ''');

    // Overall Workout Sessions Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workoutSessionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        durationInMinutes INTEGER,
        workoutListId INTEGER,
        difficultyFeedback TEXT,
        FOREIGN KEY (workoutListId) REFERENCES $_workoutListsTable (id) ON DELETE SET NULL
      )
    ''');

    // Individual Exercise Performance within a session
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_exercisePerformanceTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER NOT NULL,
        exercisePlanId INTEGER,
        exerciseName TEXT NOT NULL,
        accuracy REAL,
        repsCompleted REAL,
        plannedReps INTEGER,
        plannedSets INTEGER,
        FOREIGN KEY (sessionId) REFERENCES $_workoutSessionsTable (id) ON DELETE CASCADE
      )
    ''');

    // Workout Feedback Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_workoutFeedbackTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER NOT NULL,
        feedback TEXT NOT NULL,
        FOREIGN KEY (sessionId) REFERENCES $_workoutSessionsTable (id) ON DELETE CASCADE
      )
    ''');

    await _populateExercises(db);
  }

  Future<void> _populateExercises(Database db) async {
    // Accessing initialExercises list from saved information
    // NOTE: This relies on the 'initialExercises' variable from 'initial_exercise_data.dart'
    for (var exercise in initialExercises) {
      await db.insert(
        'exercises',
        exercise.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // ------------------------------------------------------------------
  // --- USER INFO CRUD (for initial onboarding and AuthCheckWrapper) ---
  // ------------------------------------------------------------------

  // Helper for boolean to integer conversion
  int _boolToInt(bool value) => value ? 1 : 0; 
  
  /// Retrieves the single local profile entry. Used by AuthCheckWrapper and SignUpScreen.
  @override
  Future<Map<String, dynamic>?> getLatestUserInfo() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        _userInfoTable,
        orderBy: 'id DESC',
        limit: 1,
      );
      return maps.isNotEmpty ? maps.first : null;
    } catch (e) {
      print('Error getting latest user info: $e');
      return null;
    }
  }

  /// Inserts the full user profile data into the local $_userInfoTable during onboarding.
  Future<int> insertUserInfo({
    required String nickname,
    required String gender,
    required String birthday,
    required double height,
    required double weight,
    required int weeklyGoal, required bool haveDisease,
  }) async {
    final db = await database;
    final nowUtc = DateTime.now().toUtc().toIso8601String(); // <<< GENERATE TIMESTAMP

    final Map<String, dynamic> data = {
      // 'supabase_user_id' remains NULL until sign-up.
      'nickname': nickname,
      'gender': gender,
      'birthday': birthday,
      'height': height,
      'weight': weight,
      'weeklyGoal': weeklyGoal,
      // ⭐️ CRITICAL FIX: Add the converted haveDisease value
      'haveDisease': _boolToInt(haveDisease), 
      'last_modified_at': nowUtc, // <<< INCLUDE TIMESTAMP
    };
    // Clear old data to ensure only one profile row exists
    await db.delete(_userInfoTable);
    return await db.insert(_userInfoTable, data,
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Updates the user's profile information and stamps it with a new modified time.
  Future<void> updateUserInfo(Map<String, dynamic> updatedData) async {
      final db = await database;
      
      // 1. Get the local INTEGER ID from the data map, passed as 'local_id'
      final dynamic idValue = updatedData['local_id']; 
      
      // Safely convert the ID to an integer for SQLite WHERE clause
      int? localId = idValue != null ? int.tryParse(idValue.toString()) : null; 
      
      if (localId == null) {
        // FIX: Explicitly use the 'name' parameter for log to avoid type errors
        log('Error: Cannot update local profile. Local ID is missing or invalid.', name: 'DB_ERROR');
        return; 
      }

      // 2. Prepare data for update: create a copy and remove conflicting keys
      final Map<String, dynamic> dataToUpdate = Map.from(updatedData);
      dataToUpdate.remove('local_id'); // Remove the temporary key
          
          // FIX: The core fix for the SqfliteDatabaseException (datatype mismatch).
          // The 'id' column is INTEGER. If the sync process passed the Supabase UUID 
          // under the 'id' key, we must remove it to prevent the update from trying
          // to set an INTEGER column to a STRING UUID.
          dataToUpdate.remove('id');
          
      // CRITICAL: Update the last modified timestamp before saving
      dataToUpdate['last_modified_at'] = DateTime.now().toIso8601String(); 

      // 3. Execute the update using the local integer ID
      // 'id' here is the INTEGER PRIMARY KEY AUTOINCREMENT column, which matches 'localId'.
      await db.update(
        'user_info', // Table name
        dataToUpdate,
        where: 'id = ?', 
        whereArgs: [localId],
      );
      // FIX: Explicitly use the 'name' parameter for log
      log('Local profile updated successfully (Local ID: $localId).', name: 'DB_SUCCESS');
    }

  // ------------------------------------------------------------------
  // --- SUPABASE SYNC METHODS (IMPLEMENTING LocalDatabaseService) ---
  // ------------------------------------------------------------------

  /// Fetches the local user profile data to be pushed to Supabase (PUSH logic).
  /// Includes the critical `last_modified_at` timestamp.
  @override
  Future<Map<String, dynamic>?> getLocalUserInfo(String userId) async {
    final db = await database;
    // Fetch the single local row
    final List<Map<String, dynamic>> maps = await db.query(_userInfoTable, limit: 1);

    if (maps.isEmpty) return null;

    final localData = maps.first;

    // Transform local camelCase to Supabase snake_case
    // The key 'id' MUST be the Supabase UUID (userId) for the UPSERT to work.
    return {
      'id': userId, // Supabase UUID
      'nickname': localData['nickname'],
      'gender': localData['gender'],
      'birthday': localData['birthday'],
      'height': localData['height'],
      'weight': localData['weight'],
      // Correct mapping for the Supabase column name
      'weekly_goal': localData['weeklyGoal'],
      'have_disease': localData['haveDisease'] == 1, // Sends true/false
      // <<< CRITICAL: Send the local timestamp to the cloud
      'last_modified_at': localData['last_modified_at'], 
    };
  }

  /// Saves the user profile data received from Supabase into the local database (PULL logic).
  /// Includes the critical `last_modified_at` timestamp.
  @override
  Future<void> saveLocalUserInfo(Map<String, dynamic> userInfo) async {
    final db = await database;
    final supabaseId = userInfo['id'] as String; // The Supabase UUID

    // Transform Supabase snake_case to local camelCase
    final localData = {
      // Save the Supabase UUID in the dedicated local column
      'supabase_user_id': supabaseId,
      'nickname': userInfo['nickname'],
      'gender': userInfo['gender'],
      'birthday': userInfo['birthday'],
      'height': userInfo['height'],
      'weight': userInfo['weight'],
      // Correct mapping from Supabase column name
      'weeklyGoal': userInfo['weekly_goal'],
      'haveDisease': (userInfo['have_disease'] as bool?) == true ? 1 : 0,
      'updated_at': userInfo['updated_at'],
      // <<< CRITICAL: Save the cloud's timestamp locally
      'last_modified_at': userInfo['last_modified_at'], 
    };

    // Clear old data and insert the new synchronized row
    await db.delete(_userInfoTable);
    await db.insert(_userInfoTable, localData,
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Fetches the denormalized workout session and performance data for Supabase PUSH.
  /// This method joins session data with performance data and converts keys to snake_case.
  @override
  Future<List<Map<String, dynamic>>> getSessionAndPerformanceData(
      int sessionId) async {
    final db = await database;

    // 1. Get workout session details to grab the date
    final sessionMaps = await db.query(
      _workoutSessionsTable,
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (sessionMaps.isEmpty) return [];

    // 2. Get all exercise performance records for this session
    final performanceMaps = await db.query(
      _exercisePerformanceTable,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );

    final List<Map<String, dynamic>> results = [];

    // 3. Combine and Transform to Supabase snake_case format, removing unneeded session columns
    for (final performance in performanceMaps) {
      // Combine session and performance data for denormalized push
      results.add({
        // ------------------------------------------------------------------
        // SESSION DATA MAPPED TO SUPABASE COLUMNS (snake_case)
        // ------------------------------------------------------------------
        'session_local_id': sessionId, // Local session ID
        'date': sessionMaps.first['date'], // Workout completion date
        // 🛑 OMITTED: 'duration_in_minutes' (As requested)
        // 🛑 OMITTED: 'difficulty_feedback' (Fixed previously)

        // ------------------------------------------------------------------
        // EXERCISE PERFORMANCE DATA MAPPED TO SUPABASE COLUMNS (snake_case)
        // ------------------------------------------------------------------
        'exercise_name': performance['exerciseName'],
        'reps_completed': performance['repsCompleted'],
        'planned_reps': performance['plannedReps'],
        'planned_sets': performance['plannedSets'],
      });
    }

    return results;
  }

  // ------------------------------------------------------------------
  // --- OTHER CRUD METHODS ---
  // ------------------------------------------------------------------

  Future<void> clearUserData() async {
    final db = await database;
    await db.delete(_userInfoTable);
  }

  Future<int> insertWorkoutPreference(WorkoutPreference preference) async {
    final db = await database;
    return await db.insert(_workoutPreferencesTable, preference.toMap());
  }

  Future<WorkoutPreference?> getLatestWorkoutPreference() async {
    final db = await database;
    final result = await db.query(
      _workoutPreferencesTable,
      orderBy: 'id DESC',
      limit: 1,
    );
    return result.isNotEmpty ? WorkoutPreference.fromMap(result.first) : null;
  }

  Future<void> updateWorkoutPreference(WorkoutPreference preference) async {
    final db = await database;
    if (preference.id == null) {
      throw ArgumentError('WorkoutPreference must have an ID to be updated.');
    }
    await db.update(
      _workoutPreferencesTable,
      preference.toMap(),
      where: 'id = ?',
      whereArgs: [preference.id],
    );
  }

  Future<int> insertExercise(Exercise exercise) async {
    final db = await database;
    return await db.insert(
      'exercises',
      exercise.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Exercise>> getAllExercises() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('exercises');
    return List.generate(maps.length, (i) {
      return Exercise.fromMap(maps[i]);
    });
  }

  // ------------------------------------------------------------------
  // --- EXERCISE METADATA METHODS ---
  // ------------------------------------------------------------------

  Future<Map<String, String>> getAllExerciseNameAndType() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exercises',
      columns: ['name', 'type'],
    );

    final Map<String, String> lookup = {};
    for (var map in maps) {
      lookup[map['name'] as String] = map['type'] as String;
    }
    return lookup;
  }

  // ------------------------------------------------------------------
  // --- WORKOUT LIST METHODS ---
  // ------------------------------------------------------------------

  Future<int> insertWorkoutList(WorkoutList workoutList) async {
    final db = await database;
    return await db.insert(
      _workoutListsTable,
      workoutList.toMap(),
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
  }

  Future<WorkoutList?> getWorkoutListById(int id) async {
    final db = await database;
    final maps = await db.query(
      _workoutListsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty ? WorkoutList.fromMap(maps.first) : null;
  }

  Future<WorkoutList?> getPinnedWorkoutList() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _workoutListsTable,
      where: 'isPinned = ?',
      whereArgs: [1],
      limit: 1,
    );
    return maps.isNotEmpty ? WorkoutList.fromMap(maps.first) : null;
  }

  Future<List<WorkoutList>> getAllGeneratedWorkoutLists() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _workoutListsTable,
      orderBy: 'isPinned DESC, listName ASC',
    );
    return List.generate(maps.length, (i) {
      return WorkoutList.fromMap(maps[i]);
    });
  }

  Future<int> getNextManualPlanNumber() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
      "SELECT COUNT(*) FROM $_workoutListsTable WHERE listName LIKE 'Manual Workout Plan %'",
      ),
    );
    return (count ?? 0) + 1;
  }

  Future<int> getNextGeneratedPlanNumber() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
      "SELECT COUNT(*) FROM $_workoutListsTable WHERE listName LIKE 'Generated Plan %'",
      ),
    );
    return (count ?? 0) + 1;
  }

  Future<int> updateWorkoutList(WorkoutList workoutList) async {
    final db = await database;
    if (workoutList.id == null) {
      throw ArgumentError('WorkoutList must have an ID to be updated.');
    }
    return await db.update(
      _workoutListsTable,
      workoutList.toMap(),
      where: 'id = ?',
      whereArgs: [workoutList.id],
    );
  }

  Future<int> deleteWorkoutList(int id) async {
    final db = await database;
    return await db.delete(
      _workoutListsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertWorkoutExercise(Map<String, dynamic> exerciseData) async {
    final db = await database;
    return await db.insert(_workoutExercisesTable, exerciseData);
  }

  Future<void> insertWorkoutExercises(List<ExercisePlan> exercises) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final exercise in exercises) {
        await txn.insert(_workoutExercisesTable, exercise.toMap());
      }
    });
  }

  Future<List<ExercisePlan>> getExercisesForWorkoutList(int listId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _workoutExercisesTable,
      where: 'workoutListId = ?',
      whereArgs: [listId],
      orderBy: 'sequence ASC',
    );
    return List.generate(maps.length, (i) {
      return ExercisePlan.fromMap(maps[i]);
    });
  }

  Future<void> addExerciseToWorkoutList(
    int workoutListId,
    ExercisePlan newExercise,
  ) async {
    final db = await database;
    final maxSequenceResult = await db.rawQuery(
      'SELECT MAX(sequence) FROM $_workoutExercisesTable WHERE workoutListId = ?',
      [workoutListId],
    );
    final currentMaxSequence =
      maxSequenceResult.first.values.first as int? ?? 0;
    final newSequence = currentMaxSequence + 1;

    await db.insert(
      _workoutExercisesTable,
      newExercise.copyWith(sequence: newSequence).toMap(),
    );
  }

  Future<void> replaceWorkoutExercise(
    int workoutListId,
    int oldSequence,
    int newExerciseId,
    String newExerciseName,
  ) async {
    final db = await database;
    await db.update(
      _workoutExercisesTable,
      {'exerciseId': newExerciseId, 'exerciseName': newExerciseName},
      where: 'workoutListId = ? AND sequence = ?',
      whereArgs: [workoutListId, oldSequence],
    );
  }

  Future<void> removeWorkoutExercise(int workoutListId, int sequence) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Delete the specific exercise
      await txn.delete(
        _workoutExercisesTable,
        where: 'workoutListId = ? AND sequence = ?',
        whereArgs: [workoutListId, sequence],
      );

      // 2. Re-sequence the remaining exercises
      final remainingExercises = await txn.query(
        _workoutExercisesTable,
        where: 'workoutListId = ? AND sequence > ?',
        whereArgs: [workoutListId, sequence],
        orderBy: 'sequence ASC',
      );

      for (var i = 0; i < remainingExercises.length; i++) {
        final newSequence = sequence + i;
        final int oldSequence = remainingExercises[i]['sequence'] as int;

        await txn.update(
          _workoutExercisesTable,
          {'sequence': newSequence},
          where: 'workoutListId = ? AND sequence = ?',
          whereArgs: [workoutListId, oldSequence],
        );
      }
    });
  }

  Future<void> updateWorkoutExercise(
    int id,
    int sets,
    int reps,
    int rest,
  ) async {
    final db = await database;
    await db.update(
      _workoutExercisesTable,
      {'sets': sets, 'reps': reps, 'rest': rest},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- NEW WORKOUT SESSION METHODS ---
  Future<int> insertWorkoutSession({
    required String date,
    int? durationInMinutes,
    int? workoutListId,
    String? difficultyFeedback,
  }) async {
    final db = await database;
    return await db.insert(_workoutSessionsTable, {
      'date': date,
      'durationInMinutes': durationInMinutes,
      'workoutListId': workoutListId,
      'difficultyFeedback': difficultyFeedback,
    });
  }

  Future<void> insertExercisePerformance(
    List<Map<String, dynamic>> performances,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final performance in performances) {
        await txn.insert(_exercisePerformanceTable, performance);
      }
    });
  }

  Future<int> insertWorkoutFeedback(
    int sessionId,
    WorkoutFeedback feedback,
  ) async {
    final db = await database;
    return await db.insert(_workoutFeedbackTable, {
      'sessionId': sessionId,
      'feedback': feedback.toString(),
    });
  }

  // ------------------------------------------------------------------
  // --- ADAPTIVE PLAN LOGIC ---

  Future<void> adjustWorkoutPlanAfterSession({
    required int workoutListId,
    required String difficultyFeedback,
  }) async {
    if (difficultyFeedback == 'right') {
      return;
    }

    final db = await database;
    final List<ExercisePlan> exercises =
      await getExercisesForWorkoutList(workoutListId);

    await db.transaction((txn) async {
      for (final exercisePlan in exercises) {
        int currentReps = exercisePlan.reps;
        int currentSets = exercisePlan.sets;

        if (difficultyFeedback == 'hard') {
          int newReps = currentReps - 3;
          if (newReps < 5) {
            if (currentSets > 1) {
              currentSets -= 1;
              currentReps = 5;
            } else {
              currentReps = 5;
            }
          } else {
            currentReps = newReps;
          }
        } else if (difficultyFeedback == 'easy') {
          currentReps += 3;
          if (currentReps > 20) {
            currentSets += 1;
            currentReps = 10;
          }
        }

        currentReps = currentReps.clamp(1, 100);
        currentSets = currentSets.clamp(1, 10);

        await txn.update(
          _workoutExercisesTable,
          {'sets': currentSets, 'reps': currentReps},
          where: 'id = ?',
          whereArgs: [exercisePlan.id],
        );
      }
    });
  }

  // ------------------------------------------------------------------
  // --- WORKOUT TRACKING METHODS ---

  Future<bool> didUserWorkoutToday() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final result = await db.query(
      _workoutSessionsTable,
      where: "date(date) = ?",
      whereArgs: [today],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<Set<int>> getDaysWithCompletedWorkouts(int month, int year) async {
    final db = await database;
    final startOfMonth =
      DateTime(year, month, 1).toIso8601String().substring(0, 10);
    final endOfMonth =
      DateTime(year, month + 1, 0).toIso8601String().substring(0, 10);

    final result = await db.rawQuery('''
      SELECT DISTINCT SUBSTR(date, 9, 2) as day_of_month 
      FROM $_workoutSessionsTable 
      WHERE date(date) BETWEEN ? AND ?
    ''', [startOfMonth, endOfMonth]);

    return result
      .map((row) {
        final dayString = row['day_of_month'] as String;
        return int.parse(dayString);
      })
      .toSet();
  }

  Future<int> getWorkoutsCompletedThisWeek() async {
    final db = await database;
    final now = DateTime.now();
    final dayOfWeek = now.weekday;
    final startOfWeek = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: dayOfWeek - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    final startOfWeekString = startOfWeek.toIso8601String().substring(0, 10);
    final endOfWeekString = endOfWeek.toIso8601String().substring(0, 10);

    final result = await db.rawQuery('''
      SELECT COUNT(DISTINCT date(date)) FROM $_workoutSessionsTable 
      WHERE date(date) BETWEEN ? AND ?
    ''', [startOfWeekString, endOfWeekString]);

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> fetchWorkoutSessions() async {
    final db = await database;

    final sessions = await db.query(
      _workoutSessionsTable,
      orderBy: 'date DESC',
    );
    if (sessions.isEmpty) return [];

    final sessionIds = sessions.map((s) => s['id'] as int).toList();

    final performanceMaps = await db.query(
      _exercisePerformanceTable,
      where: 'sessionId IN (${List.filled(sessionIds.length, '?').join(',')})',
      whereArgs: sessionIds,
    );

    final performanceBySessionId = <int, List<Map<String, dynamic>>>{};
    for (var perfMap in performanceMaps) {
      final sessionId = perfMap['sessionId'] as int;
      if (!performanceBySessionId.containsKey(sessionId)) {
        performanceBySessionId[sessionId] = [];
      }
      performanceBySessionId[sessionId]!.add(Map<String, dynamic>.from(perfMap));
    }

    final List<Map<String, dynamic>> mutableSessions = [];
    for (var session in sessions) {
      final Map<String, dynamic> mutableSession = Map<String, dynamic>.from(
        session,
      );
      final sessionId = session['id'] as int;
      final List<Map<String, dynamic>> exercises =
        performanceBySessionId[sessionId] ?? [];
      mutableSession['exercises'] = exercises;
      mutableSessions.add(mutableSession);
    }

    return mutableSessions;
  }

  Future<List<ExercisePerformance>> fetchExercisesForSession(
    int sessionId,
  ) async {
    final db = await database;
    final maps = await db.query(
      _exercisePerformanceTable,
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
    return maps.map((map) => ExercisePerformance.fromMap(map)).toList();
  }

  Future<void> updateWorkoutPlan(
    int workoutListId,
    List<ExercisePlan> exercises,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        _workoutExercisesTable,
        where: 'workoutListId = ?',
        whereArgs: [workoutListId],
      );
      for (final exercise in exercises) {
        await txn.insert(_workoutExercisesTable, exercise.toMap());
      }
    });
  }

  Future<void> updateExercisePlan(int exerciseId, int sets, int reps) async {
    final db = await database;
    await db.update(
      _workoutExercisesTable,
      {'sets': sets, 'reps': reps},
      where: 'id = ?',
      whereArgs: [exerciseId],
    );
  }

  Future<void> close() async {
    final db = await instance.database;
    if (db.isOpen) {
      await db.close();
      _database = null;
    }
  }

  // ------------------------------------------------------------------
  // --- BACKUP & RESTORE METHODS (JSON) ---
  // ------------------------------------------------------------------

  /// EXPORT METHOD: Returns all user data as a JSON string.
  Future<String> exportDataToJsonString() async {
    final db = await database;

    final userInfo = await db.query(_userInfoTable);
    final preferences = await db.query(_workoutPreferencesTable);
    final workoutLists = await db.query(_workoutListsTable);
    final workoutSessions = await db.query(_workoutSessionsTable);
    final workoutExercises = await db.query(_workoutExercisesTable);
    final performance = await db.query(_exercisePerformanceTable);
    final feedback = await db.query(_workoutFeedbackTable);

    final data = {
      "user_info": userInfo,
      "workout_preferences": preferences,
      "workout_lists": workoutLists,
      "workout_sessions": workoutSessions,
      "workout_exercises": workoutExercises,
      "exercise_performance": performance,
      "workout_feedback": feedback,
    };

    return jsonEncode(data);
  }

  /// IMPORT METHOD (File): Reads JSON directly from a file.
  Future<void> importFromJson(File file) async {
    final content = await file.readAsString();
    await importDataFromJsonString(content);
  }

  /// IMPORT METHOD (String): Restores DB from a JSON string.
  Future<void> importDataFromJsonString(String jsonContent) async {
    final db = await database;
    final data = jsonDecode(jsonContent);

    await db.transaction((txn) async {
      // 1. TEMPORARILY DISABLE FOREIGN KEY CHECKS
      await txn.execute('PRAGMA foreign_keys = OFF');

      // 2. CLEAR ALL EXISTING USER-GENERATED DATA
      await txn.delete(_userInfoTable);
      await txn.delete(_workoutPreferencesTable);
      await txn.delete(_workoutListsTable);
      await txn.delete(_workoutSessionsTable);
      await txn.delete(_workoutExercisesTable);
      await txn.delete(_exercisePerformanceTable);
      await txn.delete(_workoutFeedbackTable);

      Future<void> insertRows(String tableName, List<dynamic>? rows) async {
        if (rows == null) return;
        for (var row in rows) {
          await txn.insert(tableName, Map<String, dynamic>.from(row));
        }
      }

      // 3. RESTORE DATA IN RELATIONAL ORDER
      await insertRows(_userInfoTable, data['user_info']);
      await insertRows(_workoutPreferencesTable, data['workout_preferences']);
      await insertRows(_workoutListsTable, data['workout_lists']);
      await insertRows(_workoutSessionsTable, data['workout_sessions']);
      await insertRows(_workoutExercisesTable, data['workout_exercises']);
      await insertRows(_exercisePerformanceTable, data['exercise_performance']);
      await insertRows(_workoutFeedbackTable, data['workout_feedback']);

      // 4. RE-ENABLE FOREIGN KEY CHECKS
      await txn.execute('PRAGMA foreign_keys = ON');

      // 5. RESET AUTO-INCREMENT SEQUENCES
      final tablesToReset = [
        _userInfoTable,
        _workoutPreferencesTable,
        _workoutListsTable,
        _workoutSessionsTable,
        _workoutExercisesTable,
        _exercisePerformanceTable,
        _workoutFeedbackTable,
      ];

      for (var tableName in tablesToReset) {
        final maxIdResult = await txn.rawQuery(
          'SELECT MAX(id) AS max_id FROM $tableName',
        );
        final maxId = maxIdResult.first['max_id'] as int? ?? 0;
        await txn.rawInsert(
          'UPDATE sqlite_sequence SET seq = ? WHERE name = ?',
          [maxId, tableName],
        );
      }
    });
  }
  
  @override
  Future<void> saveSessionPerformanceData(List<Map<String, dynamic>> cloudData) {
    // This implementation remains an unimplemented error, which is fine if not yet used.
    throw UnimplementedError();
  }
  @override
  Future<void> clearAllLocalData() async {
  final db = await database;
  
  // Use a transaction to ensure all deletes happen atomically
  await db.transaction((txn) async {
    log('Clearing all local user data for logout...');
    
    // This is the exact block of code from your import method's cleanup step
    await txn.delete(_userInfoTable);
    await txn.delete(_workoutPreferencesTable);
    await txn.delete(_workoutListsTable);
    await txn.delete(_workoutSessionsTable);
    await txn.delete(_workoutExercisesTable);
    await txn.delete(_exercisePerformanceTable);
    await txn.delete(_workoutFeedbackTable);
    
    log('All local user data successfully cleared.', name: 'DB_CLEANUP');
  });
}
}