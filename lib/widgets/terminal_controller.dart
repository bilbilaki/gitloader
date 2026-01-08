import 'package:get/get.dart';
import 'package:gitloader/models/terminal_session.dart';

class TerminalTabController extends GetxController {
  // List of all active sessions
  var sessions = <TerminalSession>[].obs;

  // Index of the currently visible tab
  var currentIndex = 0.obs;

  TerminalSession? get activeSession =>
      sessions.isNotEmpty ? sessions[currentIndex.value] : null;

  @override
  void onInit() {
    super.onInit();
    addNewTab(); // Start with one tab
  }

  void addNewTab() async {
    final newSession = TerminalSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Tab ${sessions.length + 1}',
    );
    sessions.add(newSession);
    currentIndex.value = sessions.length - 1;
    await newSession.start();
  }

  void closeTab(int index) {
    if (sessions.length > 1) {
      sessions[index].terminate();
      sessions.removeAt(index);
      if (currentIndex.value >= sessions.length) {
        currentIndex.value = sessions.length - 1;
      }
    }
  }

  @override
  void onClose() {
    for (var s in sessions) {
      s.terminate();
    }
    super.onClose();
  }
}
