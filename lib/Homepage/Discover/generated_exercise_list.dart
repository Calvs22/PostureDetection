import 'package:fitnesss_tracker_app/Homepage/Discover/Generatedexercise/workoutconfiguration.dart' show WorkoutConfigurationScreen;
import 'package:fitnesss_tracker_app/Homepage/Discover/Generatedexercise/workoutplan_screen.dart' show WorkoutPlanScreen;
import 'package:flutter/material.dart';
import 'package:fitnesss_tracker_app/db/Models/workoutlist_model.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';

class GeneratedExerciseListPage extends StatefulWidget {
  const GeneratedExerciseListPage({super.key});

  @override
  State<GeneratedExerciseListPage> createState() =>
      _GeneratedExerciseListPageState();
}

class _GeneratedExerciseListPageState extends State<GeneratedExerciseListPage> {
  List<WorkoutList> generatedLists = [];
  bool isLoading = true;
  final dbHelper = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _fetchGeneratedLists().then((_) {
      // Check if there is a pinned list after fetching
      final hasPinnedList = generatedLists.any((list) => list.isPinned);
      if (!hasPinnedList) {
        // Show the snack bar only if no pinned list is found
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No pinned plan found. Please generate and pin a workout plan to view it on the training page!'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
        });
      }
    });
  }

  Future<void> _fetchGeneratedLists() async {
    setState(() {
      isLoading = true;
    });
    try {
      final lists = await dbHelper.getAllGeneratedWorkoutLists();
      setState(() {
        // Sort the lists: pinned ones first, then by descending ID (newest first)
        lists.sort((a, b) {
          if (a.isPinned == b.isPinned) {
            return b.id!.compareTo(a.id!); 
          }
          // The sort function wants 1 to place 'b' (the pinned item) before 'a'
          // when b.isPinned is true and a.isPinned is false.
          return b.isPinned ? 1 : -1; 
        });
        generatedLists = lists;
        isLoading = false;
      });
    } catch (e) {
      // Consider adding a print(e) here for debugging errors
      setState(() {
        isLoading = false;
      });
    }
  }

  void _createManualList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const WorkoutPlanScreen(
          workoutListId: null,
          isManualCreation: true,
        ), 
      ),
    );
    _fetchGeneratedLists(); // Trigger refresh after returning
  }

  void _showAddPlanOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(bottom: 12.0),
                child: Text(
                  'Create New Plan',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate Plan (AI Assisted)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  // FIX 1: Use .then() to refresh the list upon return
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const WorkoutConfigurationScreen(),
                    ),
                  ).then((_) => _fetchGeneratedLists()); 
                },
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Manual Create Plan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _createManualList(); // This method already includes the refresh logic
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(WorkoutList listToDelete) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to permanently delete "${listToDelete.listName}"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop();
                if (listToDelete.id != null) {
                    await dbHelper.deleteWorkoutList(listToDelete.id!);
                }
                _fetchGeneratedLists();
              },
            ),
          ],
        );
      },
    );
  }

  void _renameList(WorkoutList listToRename) {
    TextEditingController controller =
        TextEditingController(text: listToRename.listName);
    
    String? errorMessage; // Variable to hold the error message

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder( // Use StatefulBuilder to update the dialog content
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('Rename Exercise List'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    onChanged: (_) {
                      // Clear error message when the user types
                      if (errorMessage != null) {
                        setStateSB(() {
                          errorMessage = null;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      hintText: "Enter new name",
                      errorText: errorMessage, // Display error message here
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Rename'),
                  onPressed: () async {
                    final newName = controller.text.trim();
                    
                    if (newName.isEmpty) {
                        setStateSB(() {
                          errorMessage = 'Name cannot be empty.';
                        });
                        return;
                    }

                    // 1. Check if the name has actually changed
                    if (newName == listToRename.listName.trim()) {
                      Navigator.of(context).pop(); // Name is the same, just close
                      return;
                    }
                    
                    // 2. Check for duplicates (case-insensitive and trimming whitespace)
                    final isDuplicate = generatedLists.any((list) => 
                        list.id != listToRename.id && // Don't compare against itself
                        list.listName.trim().toLowerCase() == newName.toLowerCase()
                    );
                    
                    if (isDuplicate) {
                      setStateSB(() {
                        errorMessage = 'This name is already used. Please use a different name.';
                      });
                      return; // Stop the process
                    }
                    
                    // 3. Update the list name in the database
                    final updatedList = listToRename.copyWith(listName: newName);
                    await dbHelper.updateWorkoutList(updatedList);
                    
                    // 4. Close dialog and refresh list
                    Navigator.of(context).pop();
                    _fetchGeneratedLists();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _togglePin(WorkoutList workoutList) async {
    if (workoutList.isPinned) {
      final updatedList = workoutList.copyWith(isPinned: false);
      await dbHelper.updateWorkoutList(updatedList);
      _fetchGeneratedLists();
      return;
    }

    final currentPinnedList = generatedLists.firstWhere(
      (list) => list.isPinned,
      orElse: () => WorkoutList(listName: '', isPinned: false),
    );
    
    if (currentPinnedList.id != null) {
      final unpinnedList = currentPinnedList.copyWith(isPinned: false);
      await dbHelper.updateWorkoutList(unpinnedList);
    }
    
    final newPinnedList = workoutList.copyWith(isPinned: true);
    await dbHelper.updateWorkoutList(newPinnedList);

    _fetchGeneratedLists();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Generated Exercises', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/bg.jpeg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[800],
                  child: const Center(
                    child: Text(
                      'Background image not found',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          if (isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.white70)),
          
          if (!isLoading)
            ListView.builder(
              padding: EdgeInsets.only(
                top: AppBar().preferredSize.height + MediaQuery.of(context).padding.top + 8.0,
                bottom: 80.0,
              ),
              itemCount: generatedLists.length,
              itemBuilder: (context, index) {
                final list = generatedLists[index];
                
                final borderColor = list.isPinned ? Colors.red : Colors.transparent;
                final backgroundColor = list.isPinned ? Colors.white70 : Colors.white.withOpacity(0.9);
                final pinIcon = list.isPinned ? Icons.push_pin : Icons.push_pin_outlined;
                final pinTooltip = list.isPinned ? 'Unpin' : 'Pin This List';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Card(
                    color: backgroundColor,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: borderColor, width: 2.0), 
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 16.0, right: 8.0),
                      title: Text(
                        list.listName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(pinIcon, color: Colors.blueGrey),
                            onPressed: () => _togglePin(list),
                            tooltip: pinTooltip,
                          ),
                          IconButton(
                            icon: const Icon(Icons.drive_file_rename_outline, color: Colors.blue),
                            onPressed: () => _renameList(list),
                            tooltip: 'Rename',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _confirmDelete(list),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                      onTap: () async {
                        if (list.id != null) {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => WorkoutPlanScreen(
                                workoutListId: list.id,
                                isManualCreation: false,
                              ),
                            ),
                          );
                          _fetchGeneratedLists();
                        }
                      },
                    ),
                  ));
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPlanOptions,
        backgroundColor: Colors.blue,
        tooltip: 'Add New List',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}