// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';
import 'package:fitnesss_tracker_app/main.dart'; // CRITICAL: Import main.dart to access globalSupabaseService
import 'package:supabase_flutter/supabase_flutter.dart'; // Import Supabase for user ID

class ProfileSettingsPage extends StatefulWidget {
    const ProfileSettingsPage({super.key});

    @override
    State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
    // Controllers for text input fields
    final TextEditingController nicknameController = TextEditingController();
    final TextEditingController heightController = TextEditingController();
    final TextEditingController weightController = TextEditingController();

    // State variables for user profile details
    String gender = 'Prefer Not to Say';
    DateTime birthday = DateTime(2000, 1, 1);
    int weeklyGoal = 3; // Default to 3 days
    bool isLoading = true;

    // CRITICAL FIX:
    // 1. currentUserId (String UUID): Used for Supabase Upsert and RLS.
    // 2. localProfileId (Integer): Used for SQLite UPDATE WHERE clause.
    String? currentUserId; 
    int? localProfileId; // <-- NEW: Holds the local integer primary key ID
    File? profileImage;

    @override
    void initState() {
        super.initState();
        // Get the current Supabase user ID right away
        currentUserId = Supabase.instance.client.auth.currentUser?.id;
        _loadUserInfo();
        _loadSavedImage();
    }

    // --- Data Loading and Initialization ---

    // Load user information from the database
    Future<void> _loadUserInfo() async {
        final userInfo = await DatabaseHelper.instance.getLatestUserInfo();
        
        // If local data exists, populate the fields
        if (userInfo != null && mounted) {
            setState(() {
                // CRITICAL FIX: Extract the local integer ID for future SQLite updates
                localProfileId = userInfo['id'] as int?; 
                
                nicknameController.text = userInfo['nickname'] ?? '';
                gender = userInfo['gender'] ?? 'Prefer Not to Say';
                try {
                    // Try parsing the birthday string from the database
                    birthday = DateFormat('yyyy-MM-dd').parse(userInfo['birthday'] ?? '2000-01-01');
                } catch (_) {
                     birthday = DateTime(2000, 1, 1); // Fallback
                }
                // Handle potential int/double storage from DB
                heightController.text = (userInfo['height'] is double) 
                    ? userInfo['height'].toString() 
                    : userInfo['height']?.toString() ?? '';
                weightController.text = (userInfo['weight'] is double) 
                    ? userInfo['weight'].toString() 
                    : userInfo['weight']?.toString() ?? '';
                weeklyGoal = userInfo['weeklyGoal'] ?? 3;
            });
        }
        if (mounted) {
              setState(() => isLoading = false);
        }
    }

    // Load a saved profile image from local storage
    Future<void> _loadSavedImage() async {
        final directory = await getApplicationDocumentsDirectory();
        final savedImage = File('${directory.path}/profile.jpg');
        if (await savedImage.exists() && mounted) {
            setState(() => profileImage = savedImage);
        }
    }

    // --- Image Handling ---

    // Open the image gallery for the user to pick a new profile photo
    Future<void> _pickImage() async {
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.gallery);
        if (picked == null) return;

        final directory = await getApplicationDocumentsDirectory();
        final newPath = '${directory.path}/profile.jpg';

        // Delete old image before copying new one
        final oldImage = File(newPath);
        if (await oldImage.exists()) await oldImage.delete();

        final newImage = await File(picked.path).copy(newPath);
        if (mounted) {
            setState(() {
                 profileImage = newImage;
            });
        }
    }

    // Delete the saved profile image
    Future<void> _deleteImage() async {
        final directory = await getApplicationDocumentsDirectory();
        final imagePath = '${directory.path}/profile.jpg';
        final imageFile = File(imagePath);

        if (await imageFile.exists()) {
            await imageFile.delete();
            if (mounted) {
                setState(() {
                     profileImage = null;
                });
            }
        }
    }

    // --- Profile Saving and Synchronization ---

    // Save the user's profile information to the database
  // --- Profile Saving and Synchronization ---

// Save the user's profile information to the database
Future<void> _saveProfile() async {
    // CRITICAL: Check if we have a user ID from Supabase AND a local ID to update
    if (currentUserId == null || localProfileId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(currentUserId == null 
                    ? '⚠️ Not logged in. Cannot save profile.' 
                    : '⚠️ Profile record not found locally. Cannot update.'),
                duration: const Duration(milliseconds: 2000),
            ),
        );
        return;
    }

    final nickname = nicknameController.text.trim();
    final height = double.tryParse(heightController.text);
    final weight = double.tryParse(weightController.text);

    if (nickname.isEmpty || height == null || weight == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Please complete all fields properly.'),
                duration: Duration(milliseconds: 1500),
            ),
        );
        return;
    }

    // 1. Update the local database. 
    await DatabaseHelper.instance.updateUserInfo({
        'local_id': localProfileId, // <-- CRITICAL: Local SQLite ID for WHERE clause
        'id': currentUserId,       // <-- Supabase UUID for data column/Cloud Sync
        'nickname': nickname,
        'gender': gender,
        'birthday': DateFormat('yyyy-MM-dd').format(birthday),
        'height': height,
        'weight': weight,
        'weeklyGoal': weeklyGoal,
        // 'last_modified_at' is handled by the LocalDatabaseService
    });
    
    // 2. Push the updated data from the local database to the Supabase cloud
    try {
        await globalSupabaseService.pushProfileToCloud();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('✅ Profile updated and synchronized successfully!'),
                duration: Duration(milliseconds: 1500),
            ),
        );
    } catch (e) {
        if (!mounted) return;

        // --- FIX HERE: Provide a user-friendly error message ---
        // If the error is a SocketException (e.g., no internet), it's a connection issue.
        final String errorMessage = (e is SocketException) 
            ? '⚠️ Profile saved locally. Cloud sync failed: Check your internet connection.'
            : '⚠️ Profile saved locally, but cloud sync failed. Try again later.';
        
        // Show user-friendly error if Supabase push fails
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(errorMessage),
                duration: const Duration(seconds: 3),
            ),
        );
    }
}

    @override
    void dispose() {
        nicknameController.dispose();
        heightController.dispose();
        weightController.dispose();
        super.dispose();
    }

    // --- UI Helpers ---

    String getGenderAsset() {
        switch (gender.toUpperCase()) {
            case 'MALE':
                return 'assets/MALE.png';
            case 'FEMALE':
                return 'assets/FEMALE.png';
            default:
                return 'assets/OIP.png';
        }
    }

    Future<void> _pickBirthday() async {
        final picked = await showDatePicker(
            context: context,
            initialDate: birthday,
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
        );
        if (picked != null) {
            if (mounted) {
                setState(() {
                     birthday = picked;
                });
            }
        }
    }

    Widget _buildTextField(
        String label,
        TextEditingController controller, {
        bool readOnly = false,
        bool isNumeric = false,
    }) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                    controller: controller,
                    readOnly: readOnly,
                    keyboardType: isNumeric
                            ? const TextInputType.numberWithOptions(decimal: true)
                            : TextInputType.text,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                ),
            ],
        );
    }

    Widget _buildDropdown<T>(
        String label,
        T value,
        List<T> items,
        Function(T) onChanged,
    ) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                DropdownButtonFormField<T>(
                    value: value,
                    items: items
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.toString())))
                            .toList(),
                    onChanged: (val) {
                        if (val != null) {
                            onChanged(val);
                        }
                    },
                    decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                ),
            ],
        );
    }

    Widget _buildBirthdayPicker() {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Text('Birthday', style: TextStyle(fontWeight: FontWeight.bold)),
                InkWell(
                    onTap: _pickBirthday,
                    child: InputDecorator(
                        decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                            ),
                        ),
                        child: Text(DateFormat.yMMMMd().format(birthday)),
                    ),
                ),
            ],
        );
    }

    Widget _buildWeeklyGoalSlider() {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Text(
                    'Weekly Goal (Days/Week)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                        '$weeklyGoal Day${weeklyGoal > 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                ),
                Slider(
                    value: weeklyGoal.toDouble(),
                    min: 1,
                    max: 7,
                    divisions: 6,
                    label: weeklyGoal.toString(),
                    onChanged: (double newValue) {
                        setState(() {
                            weeklyGoal = newValue.round();
                        });
                    },
                ),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(7, (index) {
                            final day = index + 1;
                            return Text(
                                '$day',
                                style: TextStyle(
                                    fontWeight:
                                            weeklyGoal == day ? FontWeight.bold : FontWeight.normal,
                                    color: weeklyGoal == day
                                            ? Theme.of(context).primaryColor
                                            : Colors.grey[600],
                                    fontSize: 14,
                                ),
                            );
                        }),
                    ),
                ),
                const SizedBox(height: 16),
            ],
        );
    }

    // --- Main Build Method ---

    @override
    Widget build(BuildContext context) {
        if (isLoading) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
            appBar: AppBar(
                title: const Text('Profile Settings'),
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                leading: BackButton(
                    onPressed: () => Navigator.of(context).pop(),
                ),
            ),
            body: Column(
                children: [
                    Expanded(
                        child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                                Center(
                                    child: Stack(
                                        children: [
                                            CircleAvatar(
                                                key: UniqueKey(),
                                                radius: 50,
                                                backgroundImage: profileImage != null
                                                        ? FileImage(profileImage!)
                                                        : AssetImage(getGenderAsset()) as ImageProvider,
                                            ),
                                            Positioned(
                                                bottom: 0,
                                                right: 0,
                                                child: Container(
                                                    decoration: const BoxDecoration(
                                                        color: Colors.blue,
                                                        shape: BoxShape.circle,
                                                    ),
                                                    child: PopupMenuButton<String>(
                                                        icon: const Icon(
                                                            Icons.edit,
                                                            color: Colors.white,
                                                            size: 20,
                                                        ),
                                                        onSelected: (value) {
                                                            if (value == 'gallery') _pickImage();
                                                            if (value == 'remove') _deleteImage();
                                                        },
                                                        itemBuilder: (context) => const [
                                                            PopupMenuItem(
                                                                value: 'gallery',
                                                                child: Text('Pick from Gallery'),
                                                            ),
                                                            PopupMenuItem(
                                                                value: 'remove',
                                                                child: Text('Remove Photo'),
                                                            ),
                                                        ],
                                                    ),
                                                ),
                                            ),
                                        ],
                                    ),
                                ),
                                const SizedBox(height: 20),
                                _buildTextField('Nickname', nicknameController),
                                const SizedBox(height: 16),
                                _buildDropdown<String>(
                                    'Gender',
                                    gender,
                                    [
                                        'MALE',
                                        'FEMALE',
                                        'Prefer Not to Say',
                                    ],
                                    (val) => setState(() => gender = val),
                                ),
                                const SizedBox(height: 16),
                                _buildBirthdayPicker(),
                                const SizedBox(height: 16),
                                _buildTextField(
                                    'Height (cm)',
                                    heightController,
                                    isNumeric: true,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                    'Weight (kg)',
                                    weightController,
                                    isNumeric: true,
                                ),
                                const SizedBox(height: 16),
                                _buildWeeklyGoalSlider(),
                            ],
                        ),
                    ),
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Save Changes'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                ),
                            ),
                            onPressed: _saveProfile,
                        ),
                    ),
                ],
            ),
        );
    }
}
