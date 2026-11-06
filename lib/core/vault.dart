import 'formatters.dart';
import 'reminder_plan.dart';

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// Documents kept on the phone, encrypted with the device key: warranties,
/// insurance, tax papers, IDs and bills. A warranty or policy can have an
/// expiry date and is reminded before it runs out.

enum VaultKind { warranty, insurance, tax, identity, bill, other }

extension VaultKindLabel on VaultKind {
  String get label => switch (this) {
        VaultKind.warranty => 'Warranty',
        VaultKind.insurance => 'Insurance',
        VaultKind.tax => 'Tax document',
        VaultKind.identity => 'ID document',
        VaultKind.bill => 'Bill or invoice',
        VaultKind.other => 'Other',
      };
}

class VaultItem {
  const VaultItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    this.filePath,
    this.fileName,
    this.purchaseDate,
    this.expiryDate,
    this.amountPaise,
    this.notes = '',
  });

  final String id;
  final String title;
  final VaultKind kind;
  final DateTime createdAt;

  /// Stored (encrypted) copy of the document, if one was added.
  final String? filePath;

  /// Original file name, for type and sharing.
  final String? fileName;
  final DateTime? purchaseDate;

  /// When the warranty, policy or document runs out.
  final DateTime? expiryDate;
  final int? amountPaise;
  final String notes;

  bool get isImage {
    final name = (fileName ?? '').toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.heic');
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'createdAt': createdAt.toIso8601String(),
        if (filePath != null) 'filePath': filePath,
        if (fileName != null) 'fileName': fileName,
        if (purchaseDate != null)
          'purchaseDate': purchaseDate!.toIso8601String(),
        if (expiryDate != null) 'expiryDate': expiryDate!.toIso8601String(),
        if (amountPaise != null) 'amountPaise': amountPaise,
        if (notes.isNotEmpty) 'notes': notes,
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String;
    if (title.trim().isEmpty) {
      throw const FormatException('Invalid document in backup.');
    }
    DateTime? date(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return VaultItem(
      id: json['id'] as String,
      title: title,
      kind: _enum(VaultKind.values, json['kind'], VaultKind.other),
      createdAt: DateTime.parse(json['createdAt'] as String),
      filePath: json['filePath'] as String?,
      fileName: json['fileName'] as String?,
      purchaseDate: date('purchaseDate'),
      expiryDate: date('expiryDate'),
      amountPaise: json['amountPaise'] as int?,
      notes: json['notes'] as String? ?? '',
    );
  }
}

/// End of a warranty of [months] from [purchase] (the day before the same
/// date [months] later).
DateTime warrantyEnd(DateTime purchase, int months) =>
    DateTime(purchase.year, purchase.month + months, purchase.day - 1);

/// Days from today to [expiry]; negative once expired.
int daysUntil(DateTime expiry, DateTime now) =>
    DateTime.utc(expiry.year, expiry.month, expiry.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;

/// Items expiring within [days] (including already expired in the last
/// 30 days), soonest first.
List<VaultItem> expiringSoon(Iterable<VaultItem> items, DateTime now,
        {int days = 60}) =>
    items.where((item) {
      final expiry = item.expiryDate;
      if (expiry == null) return false;
      final left = daysUntil(expiry, now);
      return left <= days && left >= -30;
    }).toList()
      ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));

/// Reminders 30 days and 7 days before, and on, each expiry date.
List<PlannedNotification> expiryReminders(
    Iterable<VaultItem> items, DateTime now,
    {Duration horizon = const Duration(days: 31)}) {
  final until = now.add(horizon);
  final reminders = <PlannedNotification>[];
  for (final item in items) {
    final expiry = item.expiryDate;
    if (expiry == null) continue;
    final due =
        DateTime(expiry.year, expiry.month, expiry.day, defaultReminderHour);
    for (final (label, at, body) in [
      (
        '30',
        due.subtract(const Duration(days: 30)),
        '${item.kind.label} ends ${formatDate(due)} · in 30 days'
      ),
      (
        '7',
        due.subtract(const Duration(days: 7)),
        '${item.kind.label} ends ${formatDate(due)} · in a week'
      ),
      ('due', due, '${item.kind.label} ends today'),
    ]) {
      if (!at.isAfter(now) || at.isAfter(until)) continue;
      reminders.add(PlannedNotification(
        key: 'vault:${item.id}:${due.toIso8601String()}:$label',
        at: at,
        title: item.title,
        body: body,
        channel: ReminderChannel.bills,
        payload: 'vault:${item.id}',
      ));
    }
  }
  return reminders;
}
