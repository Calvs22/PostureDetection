import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fitnesss_tracker_app/db/database_helper.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  String? _backupPath;

  /// Save backup directly into Downloads
  Future<void> _backupDatabase(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⏳ Preparing backup...')),
    );

    try {
      final String jsonContent =
          await DatabaseHelper.instance.exportDataToJsonString();
      final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonContent));

      // Try to resolve Downloads folder
      Directory? downloadsDir;
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          downloadsDir = Directory(
            "/storage/emulated/0/Download",
          ); // Fallback for most Androids
        }
      } catch (_) {
        downloadsDir = Directory("/storage/emulated/0/Download");
      }

      if (downloadsDir == null) {
        throw Exception("Downloads folder not found");
      }

      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // ✅ Add timestamp so each backup is unique
      final now = DateTime.now();
      final String fileName =
          'fitness_backup_${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}.json';

      final File file = File('${downloadsDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      setState(() => _backupPath = file.path);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Backup saved to Downloads: $fileName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Backup failed: $e')),
        );
      }
    }
  }

  /// Restore backup from a picked JSON file (with warning)
  Future<void> _restoreDatabase(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);

        // ⚠️ Ask for confirmation before restoring
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("⚠️ Warning"),
            content: const Text(
              "Restoring will delete your current data and replace it with the backup file.\n\n"
              "Are you sure you want to proceed?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text("Proceed"),
              ),
            ],
          ),
        );

        if (confirm == true) {
          final String jsonContent = await file.readAsString();

          // Use DatabaseHelper to restore from JSON string
          await DatabaseHelper.instance.importDataFromJsonString(jsonContent);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Restore successful!')),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('↩️ Restore cancelled.')),
            );
          }
        }
      } else {
        // ❌ No file selected
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ No JSON file selected.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Restore failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        backgroundColor: Colors.blue[700],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Backup (JSON)'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _backupDatabase(context),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('Restore from Backup'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _restoreDatabase(context),
              ),
              if (_backupPath != null) ...[
                const SizedBox(height: 20),
                const Text('Last backup saved at:'),
                SelectableText(
                  _backupPath!,
                  style: const TextStyle(fontSize: 12),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
