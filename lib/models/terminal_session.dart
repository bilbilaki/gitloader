import 'dart:convert';
import 'dart:io';
import 'package:xterm/xterm.dart';

class TerminalSession {
  final String id;
  final String title;
  late final Terminal terminal;
  Process? _process;

  TerminalSession({required this.id, required this.title}) {
    terminal = Terminal(maxLines: 10000);
  }

  Future<void> start() async {
    try {
      // 1. Determine Shell based on Platform
      String shell = '';
      List<String> args = [];

      if (Platform.isWindows) {
        // You can switch this to 'cmd.exe' if preferred
        shell = 'powershell.exe';
        args = ['-NoLogo'];
      } else if (Platform.isLinux || Platform.isMacOS) {
        shell = Platform.environment['SHELL'] ?? '/bin/sh';
      }

      // 2. Start the Process
      _process = await Process.start(shell, args);

      // 3. STREAM OUTPUT: Process -> Terminal UI
      _process!.stdout
          .transform(utf8.decoder)
          .listen((data) => terminal.write(data));

      _process!.stderr
          .transform(utf8.decoder)
          .listen((data) => terminal.write(data));

      // 4. WRITE INPUT: Terminal UI -> Process
      terminal.onOutput = (data) {
        _process!.stdin.write(data);
      };

      // Handle process exit
      _process!.exitCode.then((code) {
        terminal.write('\r\n[Process exited with code $code]\r\n');
      });
    } catch (e) {
      terminal.write('Failed to start shell: $e');
    }
  }

  void terminate() {
    _process?.kill();
  }
}
