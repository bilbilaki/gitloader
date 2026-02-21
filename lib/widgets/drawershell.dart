import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'fileexplorerpanel.dart';
class EditorWithExplorerShell extends StatefulWidget {
  final Directory projectRoot;
  final Widget Function(File file) editorBuilder;
  final Widget aisidebar;

  const EditorWithExplorerShell({
    super.key,
    required this.projectRoot,
    required this.editorBuilder, required this.aisidebar,
  });

  @override
  State<EditorWithExplorerShell> createState() => _EditorWithExplorerShellState();
}

class _EditorWithExplorerShellState extends State<EditorWithExplorerShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  File? _activeFile;

  // sidebar width state
  double _sidebarWidth = 280;
  double _aiSidebarWidth = 360;
  bool _showAiSidebar = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isSmall = c.maxWidth < 900;

        final editor = _activeFile == null
            ? const Center(child: Text("Select a file"))
            : widget.editorBuilder(_activeFile!);

        final explorer = FileExplorerPanel(
          root: widget.projectRoot,
          sidebarWidth: isSmall ? 280 : _sidebarWidth,
          onOpenFile: (file) {
            setState(() => _activeFile = file);
            if (isSmall) Navigator.of(context).maybePop(); // close drawer
          },
        );

        if (isSmall) {
          return Scaffold(
            key: _scaffoldKey,
            appBar: AppBar(
              title: Text(_activeFile == null ? 'Editor' : p.basename(_activeFile!.path)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ],
            ),
            drawer: Drawer(
              child: SafeArea(child: explorer),
            ),
            endDrawer: Drawer(child: SafeArea(child: widget.aisidebar)),
            body: editor,
          );
        }

        // Desktop/tablet: persistent resizable sidebar
        final minW = 220.0;
        final maxW = (c.maxWidth * 0.55).clamp(260.0, 520.0);
        final aiMinW = 280.0;
        final aiMaxW = (c.maxWidth * 0.45).clamp(320.0, 640.0);

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0xFF151A1E),
                  child: Row(
                    children: [
                      Text(
                        _activeFile == null
                            ? 'Editor'
                            : p.basename(_activeFile!.path),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _showAiSidebar
                              ? Icons.close
                              : Icons.open_in_new,
                        ),
                        onPressed: () {
                          setState(() {
                            _showAiSidebar = !_showAiSidebar;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: _sidebarWidth.clamp(minW, maxW),
                        child: explorer,
                      ),
                      _ResizeHandle(
                        onDrag: (dx) {
                          setState(() {
                            _sidebarWidth = (_sidebarWidth + dx).clamp(minW, maxW);
                          });
                        },
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: editor),
                      if (_showAiSidebar) ...[
                        const VerticalDivider(width: 1, thickness: 1),
                        _ResizeHandle(
                          onDrag: (dx) {
                            setState(() {
                              _aiSidebarWidth =
                                  (_aiSidebarWidth - dx).clamp(aiMinW, aiMaxW);
                            });
                          },
                        ),
                        SizedBox(
                          width: _aiSidebarWidth.clamp(aiMinW, aiMaxW),
                          child: widget.aisidebar,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: SizedBox(
          width: 10,
          child: Center(
            child: Container(
              width: 2,
              height: 28,
              color: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}
