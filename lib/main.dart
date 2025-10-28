import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';

// --- YOUR APP IMPORTS ---
import 'Form/genderform.dart';
import 'Form/progress_state.dart';
import 'Homepage/homepage.dart';
import 'db/database_helper.dart';
import 'services/supabase_service.dart';
import 'auth/login_screen.dart';
// Note: confirmation_screen.dart is no longer imported/used

// ------------------------------------------------------------------
// 🔑 SUPABASE INITIALIZATION & SERVICE INJECTION
// ------------------------------------------------------------------

late final SupabaseService globalSupabaseService;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    // REPLACE THESE PLACEHOLDERS WITH YOUR ACTUAL KEYS
    url:
        'https://brgabqwalqhsedehkhlr.supabase.co', // <-- CORRECTED from 'supabaseUrl' to 'url'
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJyZ2FicXdhbHFoc2VkZWhraGxyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA4NjA3MzIsImV4cCI6MjA3NjQzNjczMn0.nsChIsC8v8gAvj6eME-p3U2u8Aq4k8qBggm3qZbUQoc',

    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  final localDbService = DatabaseHelper.instance;
  globalSupabaseService = SupabaseService(localDbService);

  runApp(
    ChangeNotifierProvider(
      create: (context) => AppProgressState(),
      child: const MyApp(),
    ),
  );
}

// ------------------------------------------------------------------
// 3. AUTH CHECK WRAPPER (Local Data Check -> Cloud Profile Check)
// ------------------------------------------------------------------

class AuthCheckWrapper extends StatelessWidget {
  const AuthCheckWrapper({super.key});

  // Helper method to check the local database for any user info
  Future<bool> _isLocalUserInfoAvailable() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    // Use a very light local database query to see if the user profile table has data.
    final localData = await DatabaseHelper.instance.getLatestUserInfo();
    return localData != null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final Session? session = snapshot.data?.session;

          if (session == null) {
            // Case 1: No active session (Logged Out)
            return const LoginScreen();
          } else {
            // Case 2: Active Session -> Check Local Data FIRST
            return FutureBuilder<bool>(
              future: _isLocalUserInfoAvailable(),
              builder: (context, localDataSnapshot) {
                if (localDataSnapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final bool isLocalDataAvailable =
                    localDataSnapshot.data ?? false;

                if (isLocalDataAvailable) {
                  // Flow 1: Profile exists locally (2nd open of app, already logged in)
                  log(
                    'Flow: Local profile found. Syncing and navigating to HomePage.',
                  );

                  // Use smart sync here to compare local and cloud timestamps
                  return FutureBuilder<void>(
                    future: globalSupabaseService
                        .syncProfileWithConflictResolution(),
                    builder: (context, syncSnapshot) {
                      if (syncSnapshot.connectionState ==
                          ConnectionState.done) {
                        return const HomePage();
                      }
                      return const Scaffold(
                        body: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 10),
                              Text('Synchronizing profile data...'),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                } else {
                  // Flow 2: No local data found. Must check cloud to see if they completed onboarding elsewhere.
                  log(
                    'Flow: No local data found. Checking Supabase profile existence.',
                  );

                  return FutureBuilder<bool>(
                    future: globalSupabaseService.getCurrentUserProfileExists(),
                    builder: (context, profileSnapshot) {
                      if (profileSnapshot.connectionState !=
                          ConnectionState.done) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final bool profileExistsInCloud =
                          profileSnapshot.data ?? false;

                      if (profileExistsInCloud) {
                        // FIX: Wrap the async sync call in a FutureBuilder
                        log(
                          'Cloud profile found. Triggering sync (pull) and navigating to HomePage.',
                        );

                        return FutureBuilder<void>(
                          // This future call replaces the problematic 'await'
                          future: globalSupabaseService
                              .syncProfileWithConflictResolution(),
                          builder: (context, syncSnapshot) {
                            if (syncSnapshot.connectionState ==
                                ConnectionState.done) {
                              // Sync complete (should have pulled cloud data to local)
                              return const HomePage();
                            }
                            // Show loading while the initial sync/pull is happening
                            return const Scaffold(
                              body: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 10),
                                    Text('Retrieving cloud profile...'),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      } else {
                        // Profile does NOT exist anywhere (New Login, First Time Onboarding)
                        log('No profile found. Directing to GenderForm.');
                        return const GenderScreen();
                      }
                    },
                  );
                }
              },
            );
          }
        }

        // Default loading screen while stream is connecting
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

// ------------------------------------------------------------------
// 4. MyApp Class
// ------------------------------------------------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Form Fit',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      navigatorKey: navigatorKey,
      home: const AuthCheckWrapper(),
    );
  }
}
