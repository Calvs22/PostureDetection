// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:fitnesss_tracker_app/Homepage/Settings/profilesetting.dart';
import 'package:fitnesss_tracker_app/Homepage/Settings/backup_page.dart';
// IMPORTANT: Import your global service file to access the database helper
import 'package:fitnesss_tracker_app/main.dart'; 

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  
  // Helper function to show a generic confirmation dialog
  Future<bool> _showConfirmationDialog(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // User pressed "No"
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true), // User pressed "Yes"
              child: const Text('Yes'),
            ),
          ],
        );
      },
    ) ?? false; // Default to false if dialog is dismissed
  }

  // Logout handler with confirmation AND data wipe
  Future<void> _handleLogout() async {
    final confirmed = await _showConfirmationDialog(
      'Confirm Logout',
      'Are you sure you want to log out and clear all local data?',
    );

    if (confirmed) {
      try {
        // 1. Clear ALL local data for offline-first architecture
        // This requires clearAllLocalData to be implemented in DatabaseHelper
        await globalSupabaseService.localDbService.clearAllLocalData();
        
        // 2. Sign the user out of Supabase Auth (triggers navigation)
        await Supabase.instance.client.auth.signOut();
        
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logout failed. Please check your connection.')),
          );
        }
      }
    }
  }

  // Exit handler, modified to include confirmation
  void _exitAppWithConfirmation() async {
    final confirmed = await _showConfirmationDialog(
      'Confirm Exit',
      'Are you sure you want to exit the application?',
    );
    if (confirmed) {
      // Safely exits the application.
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/bg.jpeg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Text(
                'Background image not found',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                // Profile Settings Card (existing)
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    leading: const Icon(
                      Icons.person_outline,
                      color: Colors.blue,
                      size: 32,
                    ),
                    title: const Text(
                      'Profile Settings',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileSettingsPage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Backup Card (existing)
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    leading: const Icon(
                      Icons.backup_outlined,
                      color: Colors.green,
                      size: 32,
                    ),
                    title: const Text(
                      'Backup and Restore',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const BackupPage(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 40),

                // NEW: Row to hold Logout and Exit buttons side-by-side
                Row(
                  children: [
                    // LOGOUT BUTTON CARD
                    Expanded(
                      child: Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          leading: const Icon(
                            Icons.logout,
                            color: Colors.orange, 
                            size: 32,
                          ),
                          title: const Text(
                            'Logout',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.orange),
                          ),
                          onTap: _handleLogout, // Calls the handler with data wipe
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 16), // Space between cards

                    // EXIT BUTTON CARD
                    Expanded(
                      child: Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          leading: const Icon(
                            Icons.exit_to_app,
                            color: Colors.red,
                            size: 32,
                          ),
                          title: const Text(
                            'Exit',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.red),
                          ),
                          onTap: _exitAppWithConfirmation, // Calls the handler with confirmation
                        ),
                      ),
                    ),
                  ],
                ),
                // End of side-by-side buttons
              ],
            ),
          ),
        ),
      ],
    );
  }
}