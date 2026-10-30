import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/upi.dart';
import '../services/upi_launcher.dart';
import '../ui/forms.dart';
import '../ui/widgets.dart';
import 'lock_screen.dart' show confirmIdentity;

/// Finance › UPI: scan a UPI QR code or enter a UPI ID, review the payment,
/// and hand it to a UPI app. LifePilot never sees the UPI PIN and never
/// treats the app's report as proof of payment.
class UpiTab extends StatefulWidget {
  const UpiTab({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<UpiTab> createState() => _UpiTabState();
}

class _UpiTabState extends State<UpiTab> {
  final _formKey = GlobalKey<FormState>();
  final _payee = TextEditingController();
  final _vpa = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _payee.dispose();
    _vpa.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final request = await Navigator.push<UpiRequest>(
      context,
      MaterialPageRoute(builder: (_) => const UpiScannerPage()),
    );
    if (request == null || !mounted) return;
    await _review(request);
  }

  Future<void> _reviewTyped() async {
    if (!_formKey.currentState!.validate()) return;
    await _review(
        UpiRequest(
          vpa: _vpa.text.trim(),
          name: _payee.text.trim(),
        ),
        typedAmount: parseRupeesToPaise(_amount.text));
  }

  Future<void> _review(UpiRequest request, {int? typedAmount}) async {
    final paid = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UpiReviewPage(
            store: widget.store, request: request, typedAmount: typedAmount),
      ),
    );
    if (paid == true && mounted) {
      _formKey.currentState?.reset();
      _payee.clear();
      _vpa.clear();
      _amount.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final payees = [...store.payees]..sort((a, b) {
        final byUse = b.timesPaid.compareTo(a.timesPaid);
        return byUse != 0
            ? byUse
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR to pay'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.gpp_maybe_outlined,
                    color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Scanning a QR code or entering your UPI PIN always sends money. You never need either to receive money. LifePilot never asks for your PIN or OTP.',
                    style: TextStyle(color: scheme.onTertiaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (payees.isNotEmpty) ...[
          const SectionHeader(title: 'Saved payees'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final payee in payees)
                InputChip(
                  avatar: CircleAvatar(
                    child: Text(payee.name.isEmpty
                        ? '?'
                        : payee.name.characters.first.toUpperCase()),
                  ),
                  label: Text(payee.name),
                  tooltip: payee.vpa,
                  onPressed: () =>
                      _review(UpiRequest(vpa: payee.vpa, name: payee.name)),
                  onDeleted: () async {
                    if (await confirmAction(context,
                        title: 'Remove ${payee.name}?',
                        message:
                            '${payee.vpa} will no longer be treated as a known payee.',
                        confirmLabel: 'Remove')) {
                      await store.deletePayee(payee.id);
                    }
                  },
                ),
            ],
          ),
        ],
        const SectionHeader(title: 'Pay a UPI ID'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _vpa,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'UPI ID', hintText: 'name@bank'),
                    validator: (value) => validateVpa(value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _payee,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Payee name (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText: 'Amount (optional)',
                        prefixText: '${MoneyFormat.symbol} '),
                    validator: (value) => (value ?? '').trim().isEmpty ||
                            parseRupeesToPaise(value!) != null
                        ? null
                        : 'Enter a valid amount.',
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _reviewTyped,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Review payment'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (store.handoffs.isNotEmpty) ...[
          const SectionHeader(title: 'Recent payments'),
          CardList(
            children: [
              for (final handoff in store.handoffs.take(10))
                _HandoffTile(store: store, handoff: handoff),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              'These are what the UPI app reported, not bank confirmations. Check your bank SMS or statement before approving a draft. Long-press one to remove it.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _HandoffTile extends StatelessWidget {
  const _HandoffTile({required this.store, required this.handoff});

  final LifePilotStore store;
  final PaymentHandoff handoff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (handoff.status) {
      'success' => (
          'App reported paid · not bank-verified',
          Icons.check_circle_outline,
          scheme.primary
        ),
      'submitted' => ('App reported pending', Icons.schedule, scheme.tertiary),
      'failure' => ('App reported failed', Icons.error_outline, scheme.error),
      'cancelled' => (
          'Closed without paying',
          Icons.cancel_outlined,
          scheme.onSurfaceVariant
        ),
      'unknown' => (
          'App gave no result',
          Icons.help_outline,
          scheme.onSurfaceVariant
        ),
      _ => ('Opened in UPI app', Icons.open_in_new, scheme.onSurfaceVariant),
    };
    final canRecord = handoff.status == 'opened' || handoff.status == 'unknown';
    return ListTile(
      leading: Icon(icon, color: color),
      onLongPress: () async {
        if (await confirmAction(context,
            title: 'Remove from recent payments?',
            message:
                'Only this record of the handoff is removed. Recorded expenses and drafts stay as they are.',
            confirmLabel: 'Remove')) {
          await store.removeHandoff(handoff.id);
        }
      },
      title: Text('${handoff.payee} · ${formatMoney(handoff.amountPaise)}'),
      subtitle: Text([
        label,
        formatDate(handoff.createdAt),
        if (handoff.appName.isNotEmpty) handoff.appName,
        if (handoff.bankReference.isNotEmpty) 'Ref ${handoff.bankReference}',
      ].join(' · ')),
      trailing: canRecord
          ? TextButton(
              onPressed: () => showEntryForm(
                context,
                store,
                template: LedgerEntry(
                  id: '',
                  kind: EntryKind.expense,
                  amountPaise: handoff.amountPaise,
                  category: 'Other',
                  title: handoff.payee,
                  occurredAt: handoff.createdAt,
                  paymentMethod: 'UPI',
                  merchant: handoff.vpa.isEmpty ? handoff.payee : handoff.vpa,
                ),
              ),
              child: const Text('Record'),
            )
          : null,
    );
  }
}

/// Camera view that returns the first valid UPI payment QR code.
class UpiScannerPage extends StatefulWidget {
  const UpiScannerPage({super.key});

  @override
  State<UpiScannerPage> createState() => _UpiScannerPageState();
}

class _UpiScannerPageState extends State<UpiScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _handle(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      try {
        final request = UpiRequest.parse(value);
        _done = true;
        Navigator.pop(context, request);
        return;
      } on FormatException catch (error) {
        setState(() => _error = error.message);
      }
    }
  }

  Future<void> _fromGallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final capture = await _controller
        .analyzeImage(picked.path, formats: const [BarcodeFormat.qrCode]);
    if (!mounted) return;
    if (capture == null || capture.barcodes.isEmpty) {
      setState(() => _error = 'No QR code found in that image.');
      return;
    }
    _handle(capture);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan UPI QR'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Scan from a photo',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _fromGallery,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handle,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera permission is off. Allow it in Android settings, or scan a QR code from a photo.'
                      : 'The camera could not start. You can scan a QR code from a photo instead.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Card(
              color: _error == null ? Colors.black54 : Colors.red.shade900,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error ??
                      'Point the camera at a UPI QR code. You will see the payee and amount before anything is paid.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows who will be paid, how much, and any warnings, then hands the
/// payment to the chosen UPI app. Pops `true` once a payment was handed off.
class UpiReviewPage extends StatefulWidget {
  const UpiReviewPage({
    required this.store,
    required this.request,
    this.typedAmount,
    super.key,
  });

  final LifePilotStore store;
  final UpiRequest request;
  final int? typedAmount;

  @override
  State<UpiReviewPage> createState() => _UpiReviewPageState();
}

class _UpiReviewPageState extends State<UpiReviewPage> {
  late final _amount = TextEditingController(
      text:
          widget.typedAmount == null ? '' : paiseToInput(widget.typedAmount!));
  late final _note = TextEditingController(text: widget.request.note);
  late bool _savePayee = widget.store.payeeFor(widget.request.vpa) == null &&
      !widget.request.isMerchant;
  List<UpiApp>? _apps;
  UpiApp? _app;

  /// The phone (Xiaomi, POCO, Redmi) hides other apps until allowed.
  bool _appsHidden = false;
  bool _paying = false;

  UpiRequest get _request => widget.request;

  int? get _amountPaise =>
      _request.amountPaise ?? parseRupeesToPaise(_amount.text);

  @override
  void initState() {
    super.initState();
    unawaited(_loadApps());
  }

  Future<void> _loadApps() async {
    final apps = await installedUpiApps();
    final access = await upiAppListAccess();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _appsHidden = access == 'denied';
      // Default to the app used last, if it is still installed; otherwise
      // let Android show every UPI app.
      final last = widget.store.handoffs
          .map((handoff) => handoff.appName)
          .firstWhere((name) => name.isNotEmpty, orElse: () => '');
      _app = apps.where((app) => app.name == last).firstOrNull;
    });
  }

  Future<void> _allowAppList() async {
    final granted = await requestUpiAppListAccess();
    if (!mounted) return;
    if (granted) {
      await _loadApps();
    } else {
      showMessage(context,
          'Not allowed. You can still tap "Other UPI app" to pick from all your apps, or allow "Get installed apps" for LifePilot in Settings › Apps › Permissions.');
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final amount = _amountPaise;
    if (amount == null || amount > upiMaxPaise) {
      showMessage(context, 'Enter a valid amount.', error: true);
      return;
    }
    final store = widget.store;
    final warnings = upiWarnings(_request,
        amountPaise: amount,
        payees: store.payees,
        largePaymentPaise: store.settings.largePaymentPaise);
    if (warnings.any((warning) => warning.risk == UpiRisk.danger) &&
        !await confirmAction(context,
            title: 'This payee needs a closer look',
            message:
                '${warnings.where((w) => w.risk == UpiRisk.danger).map((w) => w.message).join('\n\n')}\n\nOnly continue if you are sure this is who you mean to pay.',
            confirmLabel: 'Pay anyway',
            destructive: true)) {
      return;
    }
    if (!mounted) return;
    if (amount >= store.settings.largePaymentPaise &&
        !await confirmAction(context,
            title: 'Pay ${formatMoney(amount)}?',
            message:
                'This is a large payment to ${_request.vpa}. Check the amount and the name your UPI app shows before entering your PIN.',
            confirmLabel: 'Continue')) {
      return;
    }
    if (!mounted) return;
    if (!await confirmIdentity(context, store,
            'Confirm to pay ${formatMoney(amount)} to ${_request.vpa}') ||
        !mounted) {
      return;
    }
    setState(() => _paying = true);
    PaymentHandoff? handoff;
    try {
      handoff = await store.recordHandoff(
        payee: _request.displayName,
        amountPaise: amount,
        vpa: _request.vpa,
        appName: _app?.name ?? '',
        reference: _request.params['tr'] ?? '',
        fromQr: _request.fromQr,
      );
      final link = _request.toLink(
          amountPaise: amount, note: _request.isSigned ? null : _note.text);
      final response =
          await payWithUpiApp(link, packageName: _app?.packageName);
      // The app opened, so the payee was real enough to remember.
      if (_savePayee) {
        await store.savePayee(_request.displayName, _request.vpa);
      }
      final draft = await store.reportHandoffResult(handoff.id, response);
      if (response.status == UpiReported.success) {
        await store.notePayeePaid(_request.vpa);
      }
      if (!mounted) return;
      await _showResult(response, draft != null);
      if (mounted) Navigator.pop(context, true);
    } on NoUpiAppException {
      if (handoff != null) await store.removeHandoff(handoff.id);
      if (mounted) {
        showMessage(context, 'No UPI app on this phone can open this payment.',
            error: true);
      }
    } on Object catch (error) {
      if (handoff != null) await store.removeHandoff(handoff.id);
      if (mounted) {
        showMessage(context, 'The UPI app could not be opened: $error',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _showResult(UpiResponse response, bool drafted) {
    final (title, message) = switch (response.status) {
      UpiReported.success => (
          'UPI app reported success',
          'LifePilot cannot confirm this with your bank. A draft expense is waiting in Finance; approve it once your bank SMS or statement shows the debit.'
        ),
      UpiReported.submitted => (
          'Payment pending',
          'The UPI app says the payment is still processing. A draft expense is waiting in Finance; approve it only once the money has left your account.'
        ),
      UpiReported.failure => (
          'UPI app reported a failure',
          'Nothing was recorded. If money left your account anyway, banks usually reverse failed UPI payments within a few days.'
        ),
      UpiReported.cancelled => (
          'Payment not completed',
          'The UPI app closed without paying. Nothing was recorded.'
        ),
      UpiReported.unknown => (
          'No result from the UPI app',
          'Check the UPI app for the payment status. If it went through, use Record under Recent payments.'
        ),
    };
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text([
          message,
          if (response.reference.isNotEmpty) 'Reference: ${response.reference}',
          if (!drafted && response.status == UpiReported.success)
            'A draft for this payment already exists.',
        ].join('\n\n')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final amount = _amountPaise;
    final warnings = upiWarnings(_request,
        amountPaise: amount,
        payees: store.payees,
        largePaymentPaise: store.settings.largePaymentPaise);
    final saved = store.payeeFor(_request.vpa);
    return Scaffold(
      appBar: AppBar(title: const Text('Review payment')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paying', style: text.labelMedium),
                  const SizedBox(height: 4),
                  Text(_request.displayName, style: text.titleLarge),
                  const SizedBox(height: 2),
                  SelectableText(_request.vpa,
                      style: text.bodyLarge?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (saved != null)
                        Pill(
                            icon: Icons.verified_outlined,
                            label: 'Saved payee',
                            color: scheme.primary),
                      if (_request.fromQr)
                        const Pill(icon: Icons.qr_code_2, label: 'From QR'),
                      if (_request.isMerchant)
                        const Pill(
                            icon: Icons.storefront_outlined, label: 'Merchant'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_request.amountFixed)
            Card(
              child: ListTile(
                title: const Text('Amount set by the QR code'),
                trailing: Text(formatMoney(_request.amountPaise!),
                    style: text.titleLarge),
              ),
            )
          else
            TextField(
              controller: _amount,
              autofocus: widget.typedAmount == null,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: text.headlineSmall,
              decoration: InputDecoration(
                  labelText: 'Amount', prefixText: '${MoneyFormat.symbol} '),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            enabled: !_request.isSigned,
            maxLength: 50,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              helperText: _request.isSigned
                  ? 'Set by the merchant\'s signed QR code'
                  : null,
            ),
          ),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _WarningCard(warning: warning),
            ),
          if (saved == null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _savePayee,
              onChanged: (value) => setState(() => _savePayee = value ?? false),
              title: const Text('Save as a payee'),
              subtitle: const Text(
                  'Saved payees help LifePilot spot look-alike UPI IDs later'),
            ),
          const SectionHeader(title: 'Pay with'),
          if (_apps == null)
            const LinearProgressIndicator()
          else ...[
            if (_appsHidden)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.apps_outlined),
                  title: const Text('Show all your UPI apps'),
                  subtitle: const Text(
                      'Your phone hides other apps from LifePilot until you allow "Get installed apps".'),
                  trailing: TextButton(
                    onPressed: _allowAppList,
                    child: const Text('Allow'),
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.apps, size: 18),
                  label: const Text('Other UPI app'),
                  tooltip: 'Android shows all your UPI apps to choose from',
                  selected: _app == null,
                  onSelected: (_) => setState(() => _app = null),
                ),
                for (final app in _apps!)
                  ChoiceChip(
                    avatar: app.icon == null
                        ? null
                        : Image.memory(app.icon!, width: 20, height: 20),
                    label: Text(app.name),
                    selected: _app?.packageName == app.packageName,
                    onSelected: (selected) =>
                        setState(() => _app = selected ? app : null),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _paying || amount == null ? null : _pay,
              icon: const Icon(Icons.open_in_new),
              label: Text(_paying
                  ? 'Waiting for the UPI app…'
                  : amount == null
                      ? 'Enter an amount'
                      : 'Pay ${formatMoney(amount)}${_app == null ? '' : ' with ${_app!.name}'}'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your UPI app shows the payee\'s bank-registered name and asks for your PIN. Check that name before paying.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warning});

  final UpiWarning warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (warning.risk) {
      UpiRisk.danger => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.warning_amber_rounded
        ),
      UpiRisk.caution => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.info_outline
        ),
      UpiRisk.info => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.lock_outline
        ),
    };
    return Card(
      margin: EdgeInsets.zero,
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child:
                    Text(warning.message, style: TextStyle(color: foreground))),
          ],
        ),
      ),
    );
  }
}
