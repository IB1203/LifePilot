/// Paths stored in records (receipts, documents) come back from backups,
/// which could be edited by someone else. Before reading, sharing or
/// deleting such a file, check that it is directly inside the app's own
/// folder for it and has the app's own naming pattern, so a crafted backup
/// cannot point LifePilot at another file (such as the records file).
bool isOwnFile(String path, String folder, RegExp name) {
  String norm(String value) {
    final slashes = value.replaceAll('\\', '/');
    return slashes.endsWith('/')
        ? slashes.substring(0, slashes.length - 1)
        : slashes;
  }

  final file = norm(path);
  final dir = norm(folder);
  if (!file.startsWith('$dir/')) return false;
  final rest = file.substring(dir.length + 1);
  return !rest.contains('/') && name.hasMatch(rest);
}

/// A file name safe to create in a folder: no directories, no leading
/// dot, only ordinary characters. Names come from backups too.
String safeFileName(String name, {String fallback = 'document'}) {
  final base = name.split(RegExp(r'[\\/]')).last;
  final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9._ ()-]'), '_').trim();
  if (clean.isEmpty || clean.startsWith('.')) return fallback;
  return clean.length > 80 ? clean.substring(clean.length - 80) : clean;
}

/// `receipt-<time>.<ext>`, optionally sealed (`.lps`).
final receiptFileName = RegExp(r'^receipt-\d+\.[A-Za-z0-9]{1,10}(\.lps)?$');

/// `doc-<time>.<ext>`, optionally sealed (`.lps`).
final vaultFileName = RegExp(r'^doc-\d+\.[A-Za-z0-9]{1,10}(\.lps)?$');
