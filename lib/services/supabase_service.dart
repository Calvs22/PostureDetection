import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'local_database_service.dart';

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalDatabaseService _localDbService;
  final String _profileTableName = 'profiles';
  // NEW: Define the table for workout session/performance data
  static const String _sessionPerformanceTableName = 'session_performance';

  SupabaseService(this._localDbService);

  // ------------------------------------------------------------------
  // --- UTILITIES ---
  // ------------------------------------------------------------------
  
  /// 🛑 FIX: Public Getter to expose the private local database service
  /// This resolves the "getter 'localDbService' isn't defined" error.
  LocalDatabaseService get localDbService => _localDbService;

  // Helper to safely parse ISO 8601 strings into a DateTime object.
  DateTime? _parseTimestamp(Map<String, dynamic>? data, String key) {
    final timestamp = data?[key] as String?;
    if (timestamp == null) return null;
    try {
      return DateTime.parse(timestamp);
    } catch (e) {
      log('Error parsing timestamp $timestamp: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------
  // --- AUTHENTICATION ---
  // ------------------------------------------------------------------

  /// Handles user sign-up (creates the auth.users entry only).
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Signup failed: User object is null.');
      }
    } on AuthException catch (e) {
      log('Auth error: ${e.message}');
      rethrow;
    } catch (e) {
      log('General error during signup: $e');
      rethrow;
    }
  }

  /// Handles user login and triggers synchronization.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Trigger the NEW smart synchronization immediately after successful login
        await syncProfileWithConflictResolution();
        
        // NEW: Also sync performance data on login
        await pullSessionPerformance();
      }
    } on AuthException catch (e) {
      log('Auth error: ${e.message}');
      rethrow;
    } catch (e) {
      log('General error during login: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------------
  // --- PROFILE CHECK ---
  // ------------------------------------------------------------------

  /// Checks if the currently logged-in user has a profile in the 'profiles' table.
  Future<bool> getCurrentUserProfileExists() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final data = await _supabase
          .from(_profileTableName)
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      return data != null; // True if a record was found
    } catch (e) {
      log('Error checking profile existence: $e');
      return false;
    }
  }

  // ------------------------------------------------------------------
  // --- PROFILE SYNC HELPER METHODS (Modified for timestamp) ---
  // ------------------------------------------------------------------

  /// Pushes the local user profile data to Supabase (Local -> Cloud).
  /// This now includes the crucial 'last_modified_at' timestamp.
  Future<void> pushProfileToCloud() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Get local data including the local 'last_modified_at' timestamp
      final localData = await _localDbService.getLocalUserInfo(userId);

      if (localData != null) {
        // Use upsert. Supabase will check for conflicts if a unique key is provided.
        await _supabase.from(_profileTableName).upsert(localData);
        log('Profile data pushed to Supabase successfully.');
      }
    } catch (e) {
      log('Error pushing profile to cloud: $e');
      rethrow; // Re-throw so the caller knows the push failed.
    }
  }

  /// Fetches the cloud profile data (including the timestamp) for comparison/saving.
  Future<Map<String, dynamic>?> fetchCloudProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      // Fetch the user's single profile row, including 'last_modified_at'
      final data = await _supabase
          .from(_profileTableName)
          .select('*')
          .eq('id', userId)
          .maybeSingle();

      if (data == null) return null;
      return data;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') { // Specific code for no rows returned
        return null;
      }
      log('Postgrest error fetching cloud profile: ${e.message}');
      return null;
    } catch (e) {
      log('General error fetching cloud profile: $e');
      return null;
    }
  }

  /// Pulls the cloud profile data and saves it to the local database (Cloud -> Local).
  Future<void> pullProfileFromCloud(Map<String, dynamic> cloudData) async {
    try {
      // Use the local service to save the data in local DB format (camelCase)
      await _localDbService.saveLocalUserInfo(cloudData);
      log('Profile data pulled from Supabase successfully.');
    } catch (e) {
      log('Error pulling profile from cloud: $e');
      rethrow; // Re-throw so the caller knows the pull failed.
    }
  }

  // ------------------------------------------------------------------
  // --- MAIN SYNCHRONIZATION WITH CONFLICT RESOLUTION (NEW) ---
  // ------------------------------------------------------------------

  /// Main synchronization method using Last Write Wins via timestamp comparison.
  Future<void> syncProfileWithConflictResolution() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    log('Starting smart profile sync...');

    // 1. Fetch both records
    final localData = await _localDbService.getLatestUserInfo();
    final cloudData = await fetchCloudProfile();

    final isLocalPresent = localData != null;
    final isCloudPresent = cloudData != null;

    // 2. Extract Timestamps for comparison
    final localTime = _parseTimestamp(localData, 'last_modified_at');
    // Supabase will use 'last_modified_at' from the request body or the database column
    final cloudTime = _parseTimestamp(cloudData, 'last_modified_at'); 
    
    // --- DECISION LOGIC ---

    if (isLocalPresent && !isCloudPresent) {
      // Scenario A: Local exists, Cloud does not (e.g., initial signup/onboarding)
      log('Sync A: Cloud missing. Pushing local data to create cloud record.');
      await pushProfileToCloud();
    } 
    else if (!isLocalPresent && isCloudPresent) {
      // Scenario B: Cloud exists, Local does not (e.g., user logged into a new device)
      log('Sync B: Local missing. Pulling cloud data.');
      await pullProfileFromCloud(cloudData);
    } 
    else if (isLocalPresent && isCloudPresent) {
      // Scenario C: Both exist. CONFLICT RESOLUTION (Last Write Wins)
      
      // If either timestamp is missing/invalid, assume local wins to preserve data.
      if (localTime == null || cloudTime == null) {
        log('Sync C: Missing timestamp on local or cloud. Defaulting to PUSH (Local Wins).');
        await pushProfileToCloud();
        return;
      }

      // Local Wins if it's strictly *later*
      if (localTime.isAfter(cloudTime)) {
        log('Sync C: Local profile (${localTime.toIso8601String()}) is NEWER. PUSHING.');
        await pushProfileToCloud();
      } 
      // Cloud Wins if it's equal to or later than local
      else if (cloudTime.isAfter(localTime) || cloudTime.isAtSameMomentAs(localTime)) {
        log('Sync C: Cloud profile (${cloudTime.toIso8601String()}) is NEWER or SAME. PULLING.');
        await pullProfileFromCloud(cloudData);
      }
    } 
    else {
      // Scenario D: Neither exists (should only happen if the user is logged out or just cleared all data)
      log('Sync D: Neither local nor cloud profile exists. No action taken.');
    }
  }
  

// ------------------------------------------------------------------
// --- WORKOUT PERFORMANCE SYNCHRONIZATION ---
// ------------------------------------------------------------------

  /// Pushes the detailed workout session and exercise performance data to Supabase.
  Future<void> pushSessionPerformance(int sessionId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      log('Cannot push session performance: User is not logged in.');
      return;
    }

    try {
      // 1. Get local data from the DatabaseHelper
      final performanceData =
          await _localDbService.getSessionAndPerformanceData(sessionId);

      if (performanceData.isEmpty) {
        log('No performance data found for session $sessionId to push.');
        return;
      }

      // 2. Prepare data for Supabase upsert by adding the RLS-required 'user_id'
      final List<Map<String, dynamic>> dataToUpsert =
          performanceData.map((data) {
        // Create a mutable copy of the read-only map
        final mutableData = Map<String, dynamic>.from(data);

        // Add the user's UUID for Row Level Security (RLS) and linking
        mutableData['user_id'] = userId;
        return mutableData;
      }).toList();

      // 3. Upsert data to the Supabase performance table
      // CRITICAL: Ensure conflict resolution uses the Supabase UUID along with the local unique key.
      await _supabase.from(_sessionPerformanceTableName).upsert(
        dataToUpsert,
        onConflict: 'user_id, session_local_id, exercise_name', // <-- Robust composite key
      );

      log(
          'Session $sessionId performance data (${dataToUpsert.length} records) pushed to Supabase successfully.');
    } catch (e) {
      log('Error pushing session performance to cloud: $e');
      rethrow;
    }
  }

  /// Pulls all session performance data for the current user from Supabase and saves it locally.
  /// This ensures that a user logging into a new device has access to their full history.
  Future<void> pullSessionPerformance() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      log('Cannot pull session performance: User is not logged in.');
      return;
    }

    log('Starting pull for session performance data...');

    try {
      // 1. Fetch ALL performance data for the current user.
      final List<Map<String, dynamic>> cloudData = await _supabase
          .from(_sessionPerformanceTableName)
          .select('*')
          .eq('user_id', userId);

      if (cloudData.isEmpty) {
        log('No cloud performance data found for user $userId.');
        return;
      }

      // 2. Delegate the data merge/save operation to the local database service.
      await _localDbService.saveSessionPerformanceData(cloudData);
      
      log('${cloudData.length} performance records pulled and saved locally.');
    } catch (e) {
      log('Error pulling session performance from cloud: $e');
      rethrow;
    }
  }
}