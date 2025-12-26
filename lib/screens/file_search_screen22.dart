import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:path/path.dart' as path_pkg;
//import '../services/ai_file_ops.dart'; // Import the new AI Ops service

class FileSearchAndDiffScreen extends StatefulWidget {
  const FileSearchAndDiffScreen({super.key});

  @override
  State<FileSearchAndDiffScreen> createState() => _FileSearchAndDiffScreenState();
}

class _FileSearchAndDiffScreenState extends State<FileSearchAndDiffScreen> {
  final TextEditingController _fileTypeController = TextEditingController();
  final TextEditingController _excludePatternController = TextEditingController();
  final TextEditingController _diffInputController = TextEditingController();
  final TextEditingController _includePathPatternController = TextEditingController();
  final TextEditingController _excludePathPatternController = TextEditingController();
  final TextEditingController _includeFileNamePatternController = TextEditingController();
  final TextEditingController _excludeFileNamePatternController = TextEditingController();
  final TextEditingController _postSearchContentFilterController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final Debouncer<String> _contentFilterDebouncer = Debouncer(const Duration(milliseconds: 500), initialValue: '');

  String? _selectedDirectory;
  List<FileItem> _files = [];
  List<FileItem> _filteredFiles = []; // For post-search content filtering
  bool _isSearching = false;
  bool _isCancelled = false;
  Cancelable<List<FileItem>>? _searchTask;
  
  // AI Tools Instance
  //final AiFileOps _aiOps = AiFileOps();

  @override
  void initState() {
    super.initState();
    _initWorker();
    _postSearchContentFilterController.addListener(_onContentFilterTextChanged);
  }

  void _onContentFilterTextChanged() {
    _contentFilterDebouncer.value = _postSearchContentFilterController.text;
  }

  Future<void> _initWorker() async {
    await workerManager.init();
    
    _contentFilterDebouncer.values.listen((filterText) {
      _applyPostSearchContentFilter(filterText);
    });
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        _selectedDirectory = selectedDirectory;
        _files.clear();
        _filteredFiles.clear();
      });
    }
  }

void _searchFiles() async {
    if (_selectedDirectory == null) return;

    setState(() {
      _isSearching = true;
      _isCancelled = false;
      _files.clear();
      _filteredFiles.clear();
    });

    final dir = Directory(_selectedDirectory!);
    final extensions = _fileTypeController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    // ... (Your other pattern lists here) ...
    // Note: Assuming you have the logic to fill excludePatterns, etc. from your controllers

    final params = DirectorySearchParams(
      dirPath: dir.path,
      extensions: extensions,
      excludePatterns: _excludePatternController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      includePathPatterns: _includePathPatternController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      excludePathPatterns: _excludePathPatternController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      includeFileNamePatterns: _includeFileNamePatternController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      excludeFileNamePatterns: _excludeFileNamePatternController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    );

    // 1. EXECUTE: Pass a closure that returns the List<FileItem>
    _searchTask = workerManager.execute(
      () => _searchFilesIsolate(params),
    );

    // 2. HANDLE RESULTS: 'results' is now correctly typed as List<FileItem>
    _searchTask!.then((results) {
      if (!_isCancelled) {
        setState(() {
          _files = results;
          _filteredFiles = results;
          _isSearching = false;
        });
      }
    }).catchError((error) {
      debugPrint('Search error: $error');
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    });
  }

  static List<FileItem> _searchFilesIsolate(DirectorySearchParams params) {
    final dir = Directory(params.dirPath);
    final List<FileItem> foundFiles = [];

    if (!dir.existsSync()) return [];

    try {
      final lister = dir.listSync(recursive: true, followLinks: false);
      for (final entity in lister) {
         if (entity is File) {
            String path = entity.path;
            String filename = path_pkg.basename(path);
            String relativePath = path.substring(params.dirPath.length);
            if (relativePath.startsWith(path_pkg.separator)) {
              relativePath = relativePath.substring(1);
            }

            // --- FILTERING LOGIC ---
            // 1. Exclude Patterns (General)
            bool isExcluded = false;
            for (final pattern in params.excludePatterns) {
              if (path.contains(pattern)) {
                isExcluded = true;
                break;
              }
            }
            if (isExcluded) continue;

             // 2. Exclude Path Patterns
            bool isPathExcluded = false;
             if (params.excludePathPatterns.isNotEmpty) {
                for (final pattern in params.excludePathPatterns) {
                   if (relativePath.contains(pattern)) { // Check against relative path usually
                       isPathExcluded = true;
                       break;
                   }
                }
            }
            if (isPathExcluded) continue;

             // 3. Exclude File Name Patterns
             bool isFileNameExcluded = false;
             if (params.excludeFileNamePatterns.isNotEmpty) {
                 for(final pattern in params.excludeFileNamePatterns) {
                      // Simple wildcard * support
                      if (pattern.contains('*')) {
                          RegExp regex = RegExp(pattern.replaceAll('*', '.*'));
                          if(regex.hasMatch(filename)) {
                              isFileNameExcluded = true;
                              break;
                          }
                      } else if (filename.contains(pattern)) {
                           isFileNameExcluded = true;
                           break;
                      }
                 }
             }
             if (isFileNameExcluded) continue;


            // 4. Extensions
            if (params.extensions.isNotEmpty) {
              String ext = path_pkg.extension(path).replaceAll('.', '');
              if (!params.extensions.contains(ext)) continue;
            }

            // 5. Include Path Patterns (Must match at least one if provided)
            if (params.includePathPatterns.isNotEmpty) {
                bool isPathIncluded = false;
                for(final pattern in params.includePathPatterns) {
                    if(relativePath.contains(pattern)) {
                        isPathIncluded = true;
                        break;
                    }
                }
                if(!isPathIncluded) continue;
            }

             // 6. Include File Name Patterns (Must match at least one if provided)
            if (params.includeFileNamePatterns.isNotEmpty) {
                bool isFileNameIncluded = false;
                for(final pattern in params.includeFileNamePatterns) {
                     // Simple wildcard * support
                      if (pattern.contains('*')) {
                          RegExp regex = RegExp(pattern.replaceAll('*', '.*'));
                          if(regex.hasMatch(filename)) {
                              isFileNameIncluded = true;
                              break;
                          }
                      } else if (filename.contains(pattern)) {
                           isFileNameIncluded = true;
                           break;
                      }
                }
                if(!isFileNameIncluded) continue;
            }

            try {
              // Read content for search/diff
              // Note: Reading all files might be slow for huge repos. 
              // Optimization: Read only on demand or check size.
              // Here we keep original behavior.
              if (entity.lengthSync() < 1000000) { // Limit to 1MB files for safety
                  final content = entity.readAsStringSync();
                  foundFiles.add(FileItem(filePath: path, content: content));
              }
            } catch (e) {
              // Ignore read errors (binary files etc)
            }
         }
      }
    } catch (e) {
      debugPrint("Error listing directory: $e");
    }
    return foundFiles;
  }

  void _cancelSearch() {
    if (_searchTask != null) {
      _searchTask!.cancel();
      setState(() {
        _isCancelled = true;
        _isSearching = false;
      });
    }
  }

  void _applyPostSearchContentFilter(String filterText) {
      if (filterText.isEmpty) {
        setState(() {
          _filteredFiles = List.from(_files);
        });
        return;
      }

      setState(() {
        _filteredFiles = _files.where((file) {
          return file.content.toLowerCase().contains(filterText.toLowerCase()) ||
                 file.filePath.toLowerCase().contains(filterText.toLowerCase());
        }).toList();
      });
  }


  void _showFileContent(FileItem file) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(path_pkg.basename(file.filePath), style: const TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(file.content),
                ),
              ),
               // --- AI OPS Integration: Patch Button Example ---
              ButtonBar(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text("Patch (Save)"),
                    onPressed: () async {
                      // Example: Save logic or show edit dialog
                      // For now, we just demonstrate using the service
                      // try {
                      //   await _aiOps.patchFileContent(file.filePath, file.content); 
                      //   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("File Saved/Patched!")));
                      // } catch (e) {
                      //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                      // }
                    },
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showDiff() {
    // Basic Diff Logic from original code
    // Assuming user wants to diff against the text in the "Diff Input" box
    // OR diff two selected files.
    // The original code had a _diffInputController.
    
    // For brevity, using a simple dialog to show diff of selected file vs Input box
    final selected = _files.where((f) => f.isSelected).toList();
    if (selected.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a file to diff")));
       return;
    }
    
    FileItem file = selected.first;
    // Simple line-by-line diff visualization
    List<String> originalLines = file.content.split('\n');
    List<String> diffLines = _diffInputController.text.split('\n'); // Compare with text box

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
             width: MediaQuery.of(context).size.width * 0.9,
             height: MediaQuery.of(context).size.height * 0.9,
             padding: const EdgeInsets.all(20),
             child: Column(
               children: [
                 Text("Diff: ${path_pkg.basename(file.filePath)} vs Input"),
                 const Divider(),
                 Expanded(
                   child: ListView( // Very naive diff view
                     children: [
                        for(int i=0; i< originalLines.length || i< diffLines.length; i++)
                          if (i < originalLines.length && i < diffLines.length && originalLines[i] == diffLines[i])
                            Text("  ${originalLines[i]}")
                          else ...[
                             if(i < originalLines.length) Container(color: Colors.red[100], child: Text("- ${originalLines[i]}", style: TextStyle(color: Colors.red[900]))),
                             if(i < diffLines.length) Container(color: Colors.green[100], child: Text("+ ${diffLines[i]}", style: TextStyle(color: Colors.green[900]))),
                          ]
                     ],
                   )
                 )
               ],
             ),
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GitLoader: File Search & AI Tools"),
        actions: [
          IconButton(
            icon: const Icon(Icons.difference),
            onPressed: _showDiff,
            tooltip: "Diff Selected vs Input",
          )
        ],
      ),
      body: Column(
        children: [
          // --- CONTROLS SECTION ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(children: [
                   ElevatedButton(onPressed: _pickDirectory, child: const Text("Pick Dir")),
                   const SizedBox(width: 10),
                   Expanded(child: Text(_selectedDirectory ?? "No directory selected", overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 5),
                TextField(controller: _fileTypeController, decoration: const InputDecoration(labelText: "Extensions (dart, yaml)", isDense: true)),
                // ... Add other pattern fields as needed based on original file ...
                TextField(controller: _postSearchContentFilterController, decoration: const InputDecoration(labelText: "Filter Content (Post-search)", prefixIcon: Icon(Icons.search))),
                 const SizedBox(height: 5),
                 Row(children: [
                    ElevatedButton(onPressed: _isSearching ? null : _searchFiles, child: const Text("Scan Files")),
                    if (_isSearching) ...[
                      const SizedBox(width: 10),
                      const CircularProgressIndicator(),
                      IconButton(icon: const Icon(Icons.cancel), onPressed: _cancelSearch)
                    ]
                 ])
              ],
            ),
          ),
          const Divider(),
          // --- RESULTS SECTION ---
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _filteredFiles.length,
              itemBuilder: (context, index) {
                final file = _filteredFiles[index];
                return ListTile(
                  title: Text(path_pkg.basename(file.filePath)),
                  subtitle: Text(file.filePath, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  trailing: Text("${file.content.length} chars"),
                  selected: file.isSelected,
                  onTap: () => _showFileContent(file),
                  onLongPress: () {
                     setState(() {
                       file.isSelected = !file.isSelected;
                     });
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _fileTypeController.dispose();
    _excludePatternController.dispose();
    _diffInputController.dispose();
    _includePathPatternController.dispose();
    _excludePathPatternController.dispose();
    _includeFileNamePatternController.dispose();
    _excludeFileNamePatternController.dispose();
    _postSearchContentFilterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// Data Classes
class FileItem {
  final String filePath;
  final String content;
  bool isSelected;

  FileItem({required this.filePath, required this.content, this.isSelected = false});
}

class DirectorySearchParams {
  final String dirPath;
  final List<String> extensions;
  final List<String> excludePatterns;
  final List<String> includePathPatterns;
  final List<String> excludePathPatterns;
  final List<String> includeFileNamePatterns;
  final List<String> excludeFileNamePatterns;

  DirectorySearchParams({
    required this.dirPath,
    required this.extensions,
    required this.excludePatterns,
    required this.includePathPatterns,
    required this.excludePathPatterns,
    required this.includeFileNamePatterns,
    required this.excludeFileNamePatterns,
  });
}