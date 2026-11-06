import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/vault.dart';
import '../services/vault_files.dart';
import '../ui/platform.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// More › Documents and warranties: papers kept encrypted on the phone,
/// with reminders before warranties and policies run out.
class VaultPage extends StatelessWidget {
  const VaultPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final now = store.now();
          final soon = expiringSoon(store.vault, now);
          final items = [...store.vault]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return Scaffold(
            appBar: AppBar(title: const Text('Documents and warranties')),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => showVaultForm(context, store),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
            body: ListView(
              padding: pagePadding,
              children: [
                if (items.isEmpty)
                  EmptyState(
                    icon: Icons.folder_special_outlined,
                    title: 'Nothing saved yet',
                    message:
                        'Keep warranty cards, insurance policies, tax papers and IDs here, encrypted on this phone. Add an end date and you will be reminded 30 and 7 days before.',
                    actionLabel: 'Add a document',
                    onAction: () => showVaultForm(context, store),
                  )
                else ...[
                  if (soon.isNotEmpty) ...[
                    const SectionHeader(title: 'Ending soon'),
                    CardList(
                      children: [
                        for (final item in soon)
                          _VaultTile(store: store, item: item, now: now),
                      ],
                    ),
                  ],
                  const SectionHeader(title: 'All documents'),
                  CardList(
                    children: [
                      for (final item in items)
                        _VaultTile(store: store, item: item, now: now),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Files are encrypted with this phone\'s key and are not included in backups. Keep the originals somewhere safe too.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          );
        },
      );
}

class _VaultTile extends StatelessWidget {
  const _VaultTile(
      {required this.store, required this.item, required this.now});

  final LifePilotStore store;
  final VaultItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiry = item.expiryDate;
    final left = expiry == null ? null : daysUntil(expiry, now);
    final urgent = left != null && left <= 30;
    return ListTile(
      leading: Icon(switch (item.kind) {
        VaultKind.warranty => Icons.verified_outlined,
        VaultKind.insurance => Icons.health_and_safety_outlined,
        VaultKind.tax => Icons.request_quote_outlined,
        VaultKind.identity => Icons.badge_outlined,
        VaultKind.bill => Icons.receipt_outlined,
        VaultKind.other => Icons.description_outlined,
      }),
      title: Text(item.title),
      subtitle: Text([
        item.kind.label,
        if (left != null)
          left < 0
              ? 'ended ${formatDate(expiry!)}'
              : left == 0
                  ? 'ends today'
                  : 'ends ${formatDate(expiry!)} ($left day${left == 1 ? '' : 's'})',
        if (item.filePath == null) 'no file',
      ].join(' · ')),
      trailing: urgent
          ? Icon(Icons.schedule,
              color: left < 0
                  ? theme.colorScheme.error
                  : AppColors.of(context).warning)
          : null,
      onTap: () => _details(context),
    );
  }

  Future<void> _details(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(item.title,
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text([
                item.kind.label,
                if (item.purchaseDate != null)
                  'bought ${formatDate(item.purchaseDate!)}',
                if (item.amountPaise != null) formatMoney(item.amountPaise!),
              ].join(' · ')),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.notes),
              ],
              const SizedBox(height: 12),
              if (item.filePath != null)
                FilledButton.tonalIcon(
                  onPressed: () => _open(sheetContext),
                  icon: Icon(
                      item.isImage ? Icons.image_outlined : Icons.open_in_new),
                  label: Text(item.isImage ? 'View' : 'Open or share'),
                ),
              TextButton.icon(
                onPressed: () async {
                  if (!await confirmAction(sheetContext,
                      title: 'Delete “${item.title}”?',
                      message: 'The stored copy is deleted from this phone.',
                      confirmLabel: 'Delete',
                      destructive: true)) {
                    return;
                  }
                  await deleteVaultFile(await store.deleteVaultItem(item.id));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      );

  Future<void> _open(BuildContext context) async {
    final Uint8List bytes;
    try {
      bytes = await readVaultFile(item.filePath!, store.dataCipher);
    } on Object {
      if (context.mounted) {
        showMessage(context, 'The stored file could not be opened.',
            error: true);
      }
      return;
    }
    if (!context.mounted) return;
    if (item.isImage) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(item.title)),
            backgroundColor: Colors.black,
            body: Center(
              child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes)),
            ),
          ),
        ),
      );
      return;
    }
    final file = await sharedCopy(bytes, item.fileName ?? 'document');
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }
}

Future<void> showVaultForm(BuildContext context, LifePilotStore store) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VaultForm(store: store),
    );

class _VaultForm extends StatefulWidget {
  const _VaultForm({required this.store});

  final LifePilotStore store;

  @override
  State<_VaultForm> createState() => _VaultFormState();
}

class _VaultFormState extends State<_VaultForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _months = TextEditingController();
  final _notes = TextEditingController();
  var _kind = VaultKind.warranty;
  DateTime? _purchase;
  DateTime? _expiry;
  Uint8List? _bytes;
  String? _fileName;
  var _saving = false;

  @override
  void dispose() {
    for (final controller in [_title, _amount, _months, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _bytes = bytes;
      _fileName =
          picked.name.contains('.') ? picked.name : '${picked.name}.jpg';
    });
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose a document');
    if (picked == null) return;
    final bytes = await picked.xFile.readAsBytes();
    setState(() {
      _bytes = bytes;
      _fileName = picked.name;
    });
  }

  Future<DateTime?> _date(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? widget.store.now(),
        firstDate: DateTime(1990),
        lastDate: DateTime(2100),
      );

  /// The end date: typed directly, or worked out from months of warranty.
  DateTime? get _end {
    final months = int.tryParse(_months.text.trim());
    if (months != null && months > 0 && _purchase != null) {
      return warrantyEnd(_purchase!, months);
    }
    return _expiry;
  }

  @override
  Widget build(BuildContext context) {
    final end = _end;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Add a document',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            DropdownButtonFormField<VaultKind>(
              isExpanded: true,
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final kind in VaultKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.label)),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: _kind == VaultKind.warranty
                      ? 'Samsung TV, Bosch washing machine…'
                      : 'Health policy, Form 16, PAN…'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Add a title.' : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.shopping_bag_outlined),
              title: Text(_purchase == null
                  ? 'Purchase or start date (optional)'
                  : 'Bought ${formatDate(_purchase!)}'),
              onTap: () async {
                final picked = await _date(_purchase);
                if (picked != null) setState(() => _purchase = picked);
              },
            ),
            if (_kind == VaultKind.warranty)
              TextFormField(
                controller: _months,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Warranty in months (optional)',
                    hintText: '12, 24…'),
                onChanged: (_) => setState(() {}),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(end == null
                  ? 'End or renewal date (optional)'
                  : 'Ends ${formatDate(end)}'),
              subtitle: end != null && _months.text.trim().isNotEmpty
                  ? const Text('Worked out from the purchase date')
                  : null,
              onTap: () async {
                final picked = await _date(_expiry ?? end);
                if (picked != null) {
                  setState(() {
                    _expiry = picked;
                    _months.clear();
                  });
                }
              },
            ),
            TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Amount (optional)',
                  prefixText: '${MoneyFormat.symbol} '),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Policy number, service centre phone…'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!isDesktop)
                  ActionChip(
                    avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Photo'),
                    onPressed: () => _pickPhoto(ImageSource.camera),
                  ),
                if (!isDesktop)
                  ActionChip(
                    avatar: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Gallery'),
                    onPressed: () => _pickPhoto(ImageSource.gallery),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.attach_file, size: 18),
                  label: const Text('File (PDF…)'),
                  onPressed: _pickFile,
                ),
              ],
            ),
            if (_fileName != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(_fileName!),
                trailing: IconButton(
                  tooltip: 'Remove file',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _bytes = null;
                    _fileName = null;
                  }),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final bytes = _bytes;
      final path = bytes == null
          ? null
          : await storeVaultFile(bytes, _fileName!, widget.store.dataCipher);
      await widget.store.addVaultItem(
        title: _title.text,
        kind: _kind,
        filePath: path,
        fileName: bytes == null ? null : _fileName,
        purchaseDate: _purchase,
        expiryDate: _end,
        amountPaise: parseRupeesToPaise(_amount.text),
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, 'Could not save: $error', error: true);
    }
  }
}
