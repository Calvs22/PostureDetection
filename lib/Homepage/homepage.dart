import 'dart:io';
import 'package:fitnesss_tracker_app/Homepage/discover_page.dart';
import 'package:fitnesss_tracker_app/Homepage/Report/report_page.dart'
    show ReportPage;
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:fitnesss_tracker_app/Homepage/settings_page.dart';
import 'package:fitnesss_tracker_app/Homepage/training_page.dart';
import 'package:fitnesss_tracker_app/Homepage/Settings/profilesetting.dart';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  File? profileImage;
  String gender = 'Prefer Not to Say';
  String _nickname = 'User';

  static final List<Widget> _mainPagesContent = <Widget>[
    const TrainingPage(),
    const DiscoverPage(),
    const ReportPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Initial load of profile data when the widget is created
    _loadProfileData();
  }

  /// 🔄 Load and update all profile data (nickname, gender, and image).
  /// This function is called on initialization, when returning from ProfileSettings,
  /// and crucially, whenever a new main tab is selected.
  Future<void> _loadProfileData() async {
    // Load data from local database
    final userInfo = await DatabaseHelper.instance.getLatestUserInfo();

    // Determine the path and existence of the profile image
    final directory = await getApplicationDocumentsDirectory();
    final imageFile = File('${directory.path}/profile.jpg');
    final bool imageExists = await imageFile.exists();

    // CRITICAL: Evict the image from the cache *before* setting the new state.
    // This ensures the CircleAvatar shows the updated image file immediately.
    if (imageExists) {
      FileImage(imageFile).evict();
    }

    // Ensure the widget is still mounted before calling setState
    if (mounted) {
      setState(() {
        _nickname = userInfo?['nickname'] ?? 'User';
        gender = userInfo?['gender'] ?? 'Prefer Not to Say';
        profileImage = imageExists ? imageFile : null;
      });
    }
  }

  String _getGenderAsset() {
    switch (gender.toUpperCase()) {
      case 'MALE':
        return 'assets/MALE.png';
      case 'FEMALE':
        return 'assets/FEMALE.png';
      default:
        return 'assets/OIP.png';
    }
  }

  /// Handles tab switching and triggers a profile data reload.
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    // ✨ NEW: Reload profile data every time a tab is tapped.
    // This ensures the AppBar header (nickname and image) is refreshed,
    // covering the case where profile data might have been updated from
    // a nested page within the main tabs (e.g., inside SettingsPage).
    _loadProfileData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        // Use the updated nickname state variable in the title
        title: Text(
          'Hello, $_nickname',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () async {
                // 1. Navigate to the profile settings page and WAIT for it to close
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileSettingsPage(),
                  ),
                );

                // 2. Upon return, reload all profile data
                // This is the automatic refresh when navigating back from settings.
                _loadProfileData();
              },
              child: CircleAvatar(
                // Add a key to force the CircleAvatar to rebuild when data changes
                key: ValueKey(profileImage?.path ?? 'default_$gender'),
                radius: 20,
                backgroundColor: Colors.grey[800],
                // The image is correctly sourced from the state variables
                backgroundImage: profileImage != null
                    ? FileImage(profileImage!)
                    : AssetImage(_getGenderAsset()) as ImageProvider,
              ),
            ),
          ),
        ],
      ),
      body: _selectedIndex < _mainPagesContent.length
          ? _mainPagesContent[_selectedIndex]
          : const Center(child: Text('Invalid Tab Content')),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.fitness_center),
            label: 'Training',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Report'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.white70,
        backgroundColor: Colors.black,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
      ),
    );
  }
}
