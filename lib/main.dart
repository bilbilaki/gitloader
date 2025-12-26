import 'package:flutter/material.dart';
import 'package:gitloader/ai/chat_service.dart';
import 'package:gitloader/code_forge.dart'; // Assuming this contains AdvancedCodeEditor
import 'package:gitloader/widgets/ai_sidebar.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

// Import the logic for downloading/extracting
import 'ai/config.dart';
import 'repo_loader.dart';

void main() {
  runApp(const GitLoaderApp());
}

// Global selection state to keep track of files across navigation
final Set<String> selectedPaths = {};

class AppColors {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const border = Color(0xFF30363D);
  static const accent = Color(0xFF58A6FF);
  static const textPrimary = Color(0xFFC9D1D9);
  static const textSecondary = Color(0xFF8B949E);
  static const folder = Color(0xFFE3B341);
  static const file = Color(0xFF7D8590);
}

class GitLoaderApp extends StatelessWidget {
  const GitLoaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(primary: AppColors.accent),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 0,

        ),
      ),
      home: const RemoteLoaderPage(),
    );
  }
}

class RemoteLoaderPage extends StatefulWidget {
  const RemoteLoaderPage({super.key});

  @override
  State<RemoteLoaderPage> createState() => _RemoteLoaderPageState();
}

class _RemoteLoaderPageState extends State<RemoteLoaderPage> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;

  void _loadRepo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Downloading repository snapshot...";
    });

    try {
      String localPath = await RepoUtils.downloadAndExtract(url);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RepoBrowserScaffold(path: localPath, title: "Root"),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome_motion, size: 80, color: AppColors.accent),
              const SizedBox(height: 24),
              const Text(
                "GitLoader",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                "Enter a GitHub URL to explore and edit code",
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _urlController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: "Repository URL",
                  hintText: "https://github.com/username/repo",
                  filled: true,
                  fillColor: AppColors.surface,
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.accent, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _loadRepo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: Platform.isAndroid 
                        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("EXPLORE REPO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 20),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _statusMessage!.startsWith("Error") ? Colors.redAccent : AppColors.accent,
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class RepoBrowserScaffold extends StatefulWidget {
  final String path; // The Root Path downloaded
  final String title;

  const RepoBrowserScaffold({super.key, required this.path, required this.title});

  @override
  State<RepoBrowserScaffold> createState() => _RepoBrowserScaffoldState();
}

class _RepoBrowserScaffoldState extends State<RepoBrowserScaffold> {
  ChatService? _chatService;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _initAI();
  }

  void _initAI() async {
    // Load config (make sure Config.load() works in your existing config.dart)
    final cfg = await Config.load();
    setState(() {
      // Initialize service with the repo ROOT path
      _chatService = ChatService(cfg, widget.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // Button to toggle AI Sidebar
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      body: RepoBrowser(path: widget.path),
      // The Sidebar
      endDrawer: _chatService == null 
          ? const Drawer(child: Center(child: CircularProgressIndicator()))
          : AiSidebar(chatService: _chatService!),
    );
  }
}

class RepoBrowser extends StatefulWidget {
  final String path;
  const RepoBrowser({super.key, required this.path});

  @override
  State<RepoBrowser> createState() => _RepoBrowserState();
}

class _RepoBrowserState extends State<RepoBrowser> {
  List<FileSystemEntity> _files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  void _loadFiles() {
    final dir = Directory(widget.path);
    try {
      final List<FileSystemEntity> entities = dir.listSync();
      entities.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      setState(() {
        _files = entities.where((e) => !p.basename(e.path).startsWith('.')).toList();
      });
    } catch (e) {
      debugPrint("Error loading files: $e");
    }
  }

  void _navigateTo(FileSystemEntity entity) {
    if (entity is Directory) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RepoBrowserScaffold(
            path: entity.path,
            title: p.basename(entity.path),
          ),
        ),
      ).then((_) => setState(() {})); // Re-build on return to refresh checkboxes
    } else if (entity is File) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AdvancedCodeEditor(file: entity)),
      );
    }
  }

  void _toggleSelection(String path) {
    setState(() {
      if (selectedPaths.contains(path)) {
        selectedPaths.remove(path);
      } else {
        selectedPaths.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const Center(child: Text("Empty directory", style: TextStyle(color: AppColors.textSecondary)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final entity = _files[index];
        final isDir = entity is Directory;
        final name = p.basename(entity.path);
        final isSelected = selectedPaths.contains(entity.path);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            onTap: () => _navigateTo(entity),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.accent.withOpacity(0.5) : AppColors.border,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 8, right: 16),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: isSelected,
                      activeColor: AppColors.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (_) => _toggleSelection(entity.path),
                    ),
                    Icon(
                      isDir ? Icons.folder_rounded : Icons.description_outlined,
                      color: isDir ? AppColors.folder : AppColors.file,
                      size: 28,
                    ),
                  ],
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    color: isSelected ? AppColors.accent : AppColors.textPrimary,
                    fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 15,
                  ),
                ),
                trailing: isDir 
                  ? const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20)
                  : Text(
                      "${(File(entity.path).lengthSync() / 1024).toStringAsFixed(1)} KB",
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}