class NotificationTextSanitizer {
  static final RegExp _doubleBraces = RegExp(r'\{\{\s*([^}]+?)\s*\}\}');
  static final RegExp _singleBraces = RegExp(r'\{\s*([^}]+?)\s*\}');
  static final RegExp _brackets = RegExp(r'\[([^\]]+)\]');

  static String clean(String text) {
    return text
        .replaceAllMapped(_doubleBraces, (m) => (m.group(1) ?? '').trim())
        .replaceAllMapped(_singleBraces, (m) => (m.group(1) ?? '').trim())
        .replaceAllMapped(_brackets, (m) => m.group(1) ?? '')
        .replaceAll('**', '')
        .replaceAll('*', '')
        .trim();
  }
}
