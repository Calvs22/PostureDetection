// lib/services/local_database_service.dart
import 'dart:async';

/// An abstract class defining the contract for any local storage
/// service (e.g., SQLite/DatabaseHelper) that needs to synchronize
/// user profile data and workout data with Supabase.
abstract class LocalDatabaseService {
  
  // ----------------------------------------------------------------------
  // --- REQUIRED ADDITION FOR SMART SYNC CONFLICT RESOLUTION ---
  // ----------------------------------------------------------------------
  
  /// Fetches the single, most recent profile record from the local database.
  /// Used by SupabaseService to compare the local timestamp against the cloud's.
  /// The returned Map MUST contain the 'last_modified_at' timestamp string.
  Future<Map<String, dynamic>?> getLatestUserInfo();

  // ----------------------------------------------------------------------
  // --- NEW WORKOUT PERFORMANCE SYNC METHOD ---
  // ----------------------------------------------------------------------

  /// Saves/updates a batch of workout performance records from the cloud 
  /// into the local database. This method is responsible for merging the 
  /// cloud data into the local 'session_performance' table(s).
  Future<void> saveSessionPerformanceData(List<Map<String, dynamic>> cloudData);

  // ----------------------------------------------------------------------
  // --- EXISTING SYNC METHODS ---
  // ----------------------------------------------------------------------

  /// Fetches the local user profile data to be pushed to Supabase.
  /// The returned Map MUST use the 'id' key for the Supabase UUID 
  /// (which must be provided to the method).
  Future<Map<String, dynamic>?> getLocalUserInfo(String userId);

  /// Saves the user profile data received from Supabase into the local database.
  /// The incoming Map is in Supabase column format (using 'id' as the UUID) 
  /// and must be mapped to local storage columns (e.g., camelCase).
  Future<void> saveLocalUserInfo(Map<String, dynamic> userInfo);

  /// Required by SupabaseService to fetch combined session and
  /// performance data for pushing to the cloud.
  /// The returned data list MUST include the 'session_local_id' and 'exercise_name'
  /// keys for conflict resolution on the Supabase side.
  Future<List<Map<String, dynamic>>> getSessionAndPerformanceData(int sessionId);

  // ----------------------------------------------------------------------
  // --- LOGOUT DATA CLEANUP (FIXED POSITION) ---
  // ----------------------------------------------------------------------
  
  /// Wipes ALL user-generated data from the local database upon logout.
  Future<void> clearAllLocalData(); 
}