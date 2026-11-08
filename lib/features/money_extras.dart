import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart' hide SmsMessage;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/cash_plan.dart' show occurrences;
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/sms_import.dart';
import '../core/recurrence.dart';
import '../core/recurring_detect.dart';
import '../services/device_security.dart';
import '../ui/forms.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'sms_settings_page.dart';
import 'statement_import_flow.dart';
import '../ui/platform.dart';

// ---------------------------------------------------------------------------
// Accounts

class AccountsTab extends StatelessWidget {
  const AccountsTab({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final active =
        store.accounts.where((account) => !account.archived).toList();
    final archived =
        store.accounts.where((account) => account.archived).toList();
    final colors = AppColors.of(context);
    final total = active.fold<int>(
        0,
        (sum, account) =>
            sum + store.accountRunningBalance(account.id));
    final unlinked =
        store.entries.where((entry) => entry.accountId == null).length;
    final recentTransfers = [...store.transfers]
      ..sort((a, b) => b.at.compareTo(a.at));
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
            title: 'Accounts and wallets',
            action: 'Add',
            onAction: () => showAccountForm(context, store)),
        if (active.isEmpty)
          EmptyState(
            icon: Icons.account_balance_outlined,
            title: 'No accounts yet',
            message:
                'Add Cash, a bank account, a card or a wallet, then choose it when you record money in or out.',
            actionLabel: 'Add account',
            onAction: () => showAccountForm(context, store),
          )
        else ...[
          StatTile(
            label: 'Total recorded balance',
            value: formatMoney(total),
            icon: Icons.account_balance_wallet_outlined,
            caption:
                'From opening balances and entries you recorded. Not read from your bank.',
          ),
          const SizedBox(height: 10),
          CardList(
            indent: 72,
            children: [
              for (final account in active)
                _AccountTile(store: store, account: account),
            ],
          ),
          const SizedBox(height: 10),
          if (active.length >= 2)
            OutlinedButton.icon(
              onPressed: () => showTransferForm(context, store),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Move money between accounts'),
            ),
          if (unlinked > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  '$unlinked entries are not linked to an account and are not counted in these balances.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
        if (recentTransfers.isNotEmpty) ...[
          const SectionHeader(title: 'Transfers'),
          CardList(
            children: [
              for (final transfer in recentTransfers.take(10))
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: colors.chart[2]),
                  title: Text(
                      '${store.accountById(transfer.fromAccountId)?.name ?? 'Deleted'} → ${store.accountById(transfer.toAccountId)?.name ?? 'Deleted'}'),
                  subtitle: Text([
                    formatDate(transfer.at),
                    if (transfer.note.isNotEmpty) transfer.note,
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(formatMoney(transfer.amountPaise)),
                      IconButton(
                        tooltip: 'Delete transfer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmAction(context,
                              title: 'Delete transfer?',
                              message:
                                  'Both account balances will change back.',
                              confirmLabel: 'Delete',
                              destructive: true)) {
                            await store.deleteTransfer(transfer.id);
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (archived.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Archived (${archived.length})'),
            children: [
              for (final account in archived)
                _AccountTile(store: store, account: account),
            ],
          ),
      ],
    );
  }
}

IconData accountIcon(AccountKind kind) => switch (kind) {
      AccountKind.cash => Icons.payments_outlined,
      AccountKind.bank => Icons.account_balance_outlined,
      AccountKind.upi => Icons.qr_code_2,
      AccountKind.card => Icons.credit_card,
      AccountKind.wallet => Icons.account_balance_wallet_outlined,
      AccountKind.other => Icons.savings_outlined,
    };

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.store, required this.account});

  final LifePilotStore store;
  final Account account;

  @override
  Widget build(BuildContext context) {
    final balance = store.accountRunningBalance(account.id);
    final count =
        store.entries.where((entry) => entry.accountId == account.id).length;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(accountIcon(account.kind),
            color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(account.name),
      subtitle: Text('${account.kind.label} · $count entries'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatMoney(balance),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: balance < 0 ? AppColors.of(context).expense : null,
                  fontWeight: FontWeight.w700)),
          PopupMenuButton<String>(
            tooltip: 'Account options',
            onSelected: (value) async {
              switch (value) {
                case 'edit':
                  await showAccountForm(context, store, account: account);
                case 'archive':
                  await store.updateAccount(
                      account.copyWith(archived: !account.archived));
                case 'delete':
                  if (await confirmAction(context,
                      title: 'Delete ${account.name}?',
                      message:
                          'Its transfers are removed. Entries keep their amounts but are no longer linked to an account.',
                      confirmLabel: 'Delete',
                      destructive: true)) {
                    await store.deleteAccount(account.id);
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                  value: 'archive',
                  child: Text(account.archived ? 'Restore' : 'Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showAccountForm(BuildContext context, LifePilotStore store,
    {Account? account}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _AccountFormSheet(
      store: store,
      account: account,
    ),
  );
}

/// Sheet content for adding or editing an account. Owns its text controllers
/// and disposes them when the sheet widget is disposed (after the exit
/// animation), avoiding "used after being disposed" crashes.
class _AccountFormSheet extends StatefulWidget {
  const _AccountFormSheet({required this.store, required this.account});

  final LifePilotStore store;
  final Account? account;

  @override
  State<_AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<_AccountFormSheet> {
  late final TextEditingController name;
  late final TextEditingController opening;
  var negative = false;
  var kind = AccountKind.bank;
  final formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    name = TextEditingController(text: account?.name ?? '');
    opening = TextEditingController(
      text: account == null || account.openingBalancePaise == 0
          ? ''
          : paiseToInput(account.openingBalancePaise.abs()));
    negative = (account?.openingBalancePaise ?? 0) < 0;
    kind = account?.kind ?? AccountKind.bank;
  }

  @override
  void dispose() {
    name.dispose();
    opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(account == null ? 'Add account' : 'Edit account',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in AccountKind.values)
                  ChoiceChip(
                    avatar: Icon(accountIcon(option), size: 18),
                    label: Text(option.label),
                    selected: kind == option,
                    onSelected: (_) => setState(() {
                      if (name.text.isEmpty || name.text == kind.label) {
                        name.text = option.label;
                      }
                      kind = option;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'e.g. HDFC savings'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name the account.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: opening,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
              ],
              decoration: InputDecoration(
                labelText: 'Opening balance (optional)',
                prefixText: '${negative ? '−' : ''}${MoneyFormat.symbol} ',
                helperText:
                    'What the account held when you started tracking it here.',
              ),
              validator: (value) => value == null ||
                      value.trim().isEmpty ||
                      parseRupeesToPaise(value) != null
                  ? null
                  : 'Enter a valid amount.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Starts in debt (e.g. card dues)'),
              value: negative,
              onChanged: (value) => setState(() => negative = value),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amount =
                    (parseRupeesToPaise(opening.text) ?? 0) *
                        (negative ? -1 : 1);
                if (account == null) {
                  await widget.store.addAccount(name.text, kind,
                      openingBalancePaise: amount);
                } else {
                  await widget.store.updateAccount(account.copyWith(
                      name: name.text.trim(),
                      kind: kind,
                      openingBalancePaise: amount));
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save account'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showTransferForm(
    BuildContext context, LifePilotStore store) async {
  final active = store.accounts.where((account) => !account.archived).toList();
  if (active.length < 2) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _TransferFormSheet(
      store: store,
      active: active,
    ),
  );
}

/// Sheet content for moving money between accounts. Owns its text controllers
/// and disposes them when the sheet widget is disposed (after the exit
/// animation), avoiding "used after being disposed" crashes.
class _TransferFormSheet extends StatefulWidget {
  const _TransferFormSheet({required this.store, required this.active});

  final LifePilotStore store;
  final List<Account> active;

  @override
  State<_TransferFormSheet> createState() => _TransferFormSheetState();
}

class _TransferFormSheetState extends State<_TransferFormSheet> {
  late final TextEditingController amount;
  late final TextEditingController note;
  var from = '';
  var to = '';
  String? error;
  final formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    from = widget.active[0].id;
    to = widget.active[1].id;
    amount = TextEditingController();
    note = TextEditingController();
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Move money',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text(
                'A transfer between your own accounts. It is not counted as income or an expense.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: from,
              decoration: const InputDecoration(labelText: 'From'),
              items: [
                for (final account in widget.active)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.name} · ${account.kind.label} '
                      '(${formatMoney(widget.store.accountRunningBalance(account.id))})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => from = value ?? from),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: to,
              decoration: const InputDecoration(labelText: 'To'),
              items: [
                for (final account in widget.active)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.name} · ${account.kind.label} '
                      '(${formatMoney(widget.store.accountRunningBalance(account.id))})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => to = value ?? to),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Amount', prefixText: '${MoneyFormat.symbol} '),
              validator: (value) => parseRupeesToPaise(value ?? '') == null
                  ? 'Enter an amount greater than zero.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                if (from == to) {
                  setState(
                      () => error = 'Choose two different accounts.');
                  return;
                }
                final amountPaise = parseRupeesToPaise(amount.text)!;
                final fromAccount =
                    widget.active.firstWhere((item) => item.id == from);
                final fromBalance =
                    widget.store.accountRunningBalance(fromAccount.id);
                if (fromBalance < amountPaise) {
                  setState(() => error =
                      'Insufficient balance in ${fromAccount.name} (${formatMoney(fromBalance)} available).');
                  return;
                }
                await widget.store.addTransfer(
                  fromAccountId: from,
                  toAccountId: to,
                  amountPaise: amountPaise,
                  note: note.text,
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save transfer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recurring entries and drafts

class RecurringTab extends StatelessWidget {
  const RecurringTab({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rules = [...store.recurring]
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    var monthlyIn = 0;
    var monthlyOut = 0;
    for (final rule in rules.where((rule) => rule.active)) {
      final monthly =
          monthlyEquivalent(rule.amountPaise, rule.recurrence.repeat);
      if (rule.kind == EntryKind.income) {
        monthlyIn += monthly;
      } else {
        monthlyOut += monthly;
      }
    }
    return ListView(
      padding: pagePadding,
      children: [
        BankBalancesSection(store: store),
        PendingDraftsSection(store: store),
        SuspiciousSmsSection(store: store),
        MoneyFlowSection(store: store),
        RecurringSuggestionsSection(store: store),
        SectionHeader(
            title: 'Recurring income and expenses',
            action: 'Add',
            onAction: () => showRecurringForm(context, store)),
        if (monthlyIn > 0 || monthlyOut > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Each month: ${[
                if (monthlyIn > 0) 'about ${formatMoney(monthlyIn)} in',
                if (monthlyOut > 0) 'about ${formatMoney(monthlyOut)} out',
              ].join(', ')}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (rules.isEmpty)
          EmptyState(
            icon: Icons.autorenew,
            title: 'Nothing recurring yet',
            message:
                'Add salary, rent, SIPs or other regular entries. Each time one is due, a draft waits here for you to approve — nothing is recorded automatically.',
            actionLabel: 'Add recurring entry',
            onAction: () => showRecurringForm(context, store),
          )
        else
          CardList(
            children: [
              for (final rule in rules)
                ListTile(
                  leading: Icon(
                    rule.kind == EntryKind.income
                        ? Icons.south_west
                        : Icons.north_east,
                    color: rule.kind == EntryKind.income
                        ? colors.income
                        : colors.expense,
                  ),
                  title: Text(rule.title),
                  subtitle: Text(rule.active
                      ? '${rule.recurrence.label} · next ${formatDate(rule.nextDate)}'
                      : 'Paused'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${rule.kind == EntryKind.income ? '+' : '−'}${formatMoney(rule.amountPaise)}',
                        style: TextStyle(
                            color: rule.kind == EntryKind.income
                                ? colors.income
                                : null),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Recurring options',
                        onSelected: (value) async {
                          switch (value) {
                            case 'edit':
                              await showRecurringForm(context, store,
                                  rule: rule);
                            case 'pause':
                              await store.updateRecurring(
                                  rule.copyWith(active: !rule.active));
                            case 'delete':
                              if (await confirmAction(context,
                                  title: 'Delete “${rule.title}”?',
                                  message:
                                      'Entries already recorded stay. Drafts waiting for approval are removed.',
                                  confirmLabel: 'Delete',
                                  destructive: true)) {
                                await store.deleteRecurring(rule.id);
                              }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                              value: 'pause',
                              child: Text(rule.active ? 'Pause' : 'Resume')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SectionHeader(title: 'Bank SMS and statements'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Turn bank and UPI transaction messages into drafts you review. Messages are read on this phone only. OTPs, reminders, requests and failed transactions are ignored, and messages that look like scams are held back.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!isDesktop)
                      FilledButton.tonalIcon(
                        onPressed: () => importFromSmsInbox(context, store),
                        icon: const Icon(Icons.sms_outlined),
                        label: const Text('Scan last 30 days'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => importPastedSms(context, store),
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Paste messages'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => importStatement(context, store),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Import statement'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => SmsSettingsPage(store: store)),
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('Settings and rules'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Drafts waiting for approval, with approve, edit and discard actions.
/// Messages held back because they looked like scams, with what to do.
class SuspiciousSmsSection extends StatelessWidget {
  const SuspiciousSmsSection({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    if (store.suspiciousSms.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
            title: 'Possible scam messages (${store.suspiciousSms.length})'),
        for (final item in store.suspiciousSms.take(10))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From ${item.sender} · ${formatDate(item.receivedAt)}',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(color: scheme.onErrorContainer)),
                    const SizedBox(height: 4),
                    Text(item.reason,
                        style: TextStyle(color: scheme.onErrorContainer)),
                    const SizedBox(height: 4),
                    Text('“${item.snippet}”',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: scheme.onErrorContainer)),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => store.dismissSuspicious(item.key),
                          child: const Text('Dismiss'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => showScamHelp(context),
                          child: const Text('What to do'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Where to report fraud in India. Opens the phone dialer or browser only
/// when the user taps.
Future<void> showScamHelp(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text(
                'Do not open links, call numbers or share OTPs from this message. Your bank never asks for your PIN, OTP or KYC update by SMS.'),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Lost money? Call 1930'),
              subtitle:
                  const Text('National cyber-fraud helpline. Call quickly.'),
              onTap: () => launchUrl(Uri.parse('tel:1930')),
            ),
            ListTile(
              leading: const Icon(Icons.local_police_outlined),
              title: const Text('Report at cybercrime.gov.in'),
              onTap: () => launchUrl(Uri.parse('https://cybercrime.gov.in'),
                  mode: LaunchMode.externalApplication),
            ),
            ListTile(
              leading: const Icon(Icons.report_outlined),
              title:
                  const Text('Report the message on Sanchar Saathi (Chakshu)'),
              subtitle: const Text('For suspected fraud calls and SMS'),
              onTap: () => launchUrl(Uri.parse('https://sancharsaathi.gov.in'),
                  mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      ),
    );

class PendingDraftsSection extends StatelessWidget {
  const PendingDraftsSection({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    if (store.pending.isEmpty) return const SizedBox.shrink();
    final drafts = [...store.pending]
      ..sort((a, b) => a.entry.occurredAt.compareTo(b.entry.occurredAt));
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Waiting for review (${drafts.length})',
          action: drafts.length > 1 ? 'Approve all' : null,
          onAction: () async {
            if (!await confirmAction(context,
                title: 'Approve ${drafts.length} drafts?',
                message:
                    'Each becomes a recorded entry with the values shown. Check SMS drafts first if you are unsure.',
                confirmLabel: 'Approve all')) {
              return;
            }
            for (final draft in drafts) {
              await store.approvePending(draft.id);
            }
          },
        ),
        for (final draft in drafts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(
                          icon: switch (draft.source) {
                            'sms' => Icons.sms_outlined,
                            'statement' => Icons.description_outlined,
                            'upi' => Icons.qr_code_2,
                            _ => Icons.autorenew,
                          },
                          label: switch (draft.source) {
                            'sms' when draft.recurringId != null =>
                              'From SMS · matches a recurring entry',
                            'sms' => 'From SMS',
                            'statement' => 'From bank statement',
                            'upi' when draft.bankConfirmed =>
                              'UPI payment · confirmed by bank SMS',
                            'upi' => 'UPI app report · not bank-verified',
                            _ when draft.bankConfirmed =>
                              'Recurring · confirmed by bank SMS',
                            _ => 'Recurring',
                          },
                          color: draft.bankConfirmed ? colors.income : null,
                        ),
                        if (draft.autoPay)
                          const Pill(
                              icon: Icons.event_repeat, label: 'Autopay'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            draft.entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          '${draft.entry.isIncome ? '+' : '−'}${formatMoney(draft.entry.amountPaise)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: draft.entry.isIncome
                                      ? colors.income
                                      : null,
                                  fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        '${draft.entry.isIncome ? 'Credited' : 'Debited'} · ${draft.entry.category} · ${formatDate(draft.entry.occurredAt)}'
                        '${store.accountById(draft.entry.accountId) == null ? '' : ' · ${store.accountById(draft.entry.accountId)!.name}'}',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (draft.balancePaise != null)
                      Text(
                          'Available balance after: ${formatMoney(draft.balancePaise!)}',
                          style: Theme.of(context).textTheme.bodySmall),
                    if (draft.warning.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(draft.warning,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                            ),
                          ],
                        ),
                      ),
                    if (draft.sourceText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('“${draft.sourceText}”',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => store.dismissPending(draft.id),
                          child: const Text('Discard'),
                        ),
                        TextButton(
                          onPressed: () => showEntryForm(context, store,
                              template: draft.entry, pendingId: draft.id),
                          child: const Text('Edit'),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final saved = await store.approvePending(draft.id);
                            if (context.mounted) {
                              showMessage(context,
                                  'Recorded ${formatMoney(saved.amountPaise)} · ${saved.title}');
                            }
                          },
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The latest available balance (or card limit) each bank SMS reported,
/// next to the balance LifePilot has recorded for the matching account.
class BankBalancesSection extends StatelessWidget {
  const BankBalancesSection({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    if (store.bankBalances.isEmpty) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    final now = store.now();
    final balances = [...store.bankBalances]
      ..sort((a, b) => b.at.compareTo(a.at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Available balance',
          action: 'Forget',
          onAction: () async {
            if (await confirmAction(context,
                title: 'Forget bank balances?',
                message:
                    'Removes the balances read from bank SMS. They come back the next time a bank message mentions one.',
                confirmLabel: 'Forget')) {
              await store.forgetBankBalances();
            }
          },
        ),
        CardList(
          indent: 56,
          children: [
            for (final balance in balances)
              Builder(builder: (context) {
                final hint = balance.accountHint;
                final account = hint == null
                    ? null
                    : store.accounts
                        .where((item) =>
                            !item.archived && item.name.contains(hint))
                        .firstOrNull;
                final recorded = account == null
                    ? null
                    : store.accountRunningBalance(account.id);
                final stale = now.difference(balance.at).inDays >= 7;
                return ListTile(
                  leading: Icon(balance.isLimit
                      ? Icons.credit_card
                      : Icons.account_balance_outlined),
                  title: Text(balance.label),
                  subtitle: Text([
                    '${balance.isLimit ? 'Available credit limit' : 'Available balance'} · from SMS on ${formatDate(balance.at)}',
                    if (stale) 'May be out of date',
                    if (recorded != null && !balance.isLimit)
                      recorded == balance.paise
                          ? 'Matches ${account!.name} in LifePilot'
                          : '${account!.name} in LifePilot: ${formatMoney(recorded)} (${formatMoney((balance.paise - recorded).abs())} ${balance.paise > recorded ? 'more' : 'less'} at the bank)',
                  ].join('\n')),
                  isThreeLine: stale || recorded != null,
                  trailing: Text(
                    formatMoney(balance.paise),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: balance.paise < 0 ? colors.expense : null),
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }
}

/// Money credited and debited this month (default) or over the last 30
/// days, with what is still waiting for review. This month also shows the
/// recurring income and payments still due before the month ends.
class MoneyFlowSection extends StatefulWidget {
  const MoneyFlowSection({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<MoneyFlowSection> createState() => _MoneyFlowSectionState();
}

enum _FlowPeriod { thisMonth, last30Days }

class _MoneyFlowSectionState extends State<MoneyFlowSection> {
  var _period = _FlowPeriod.thisMonth;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = store.now();
    final today = dateOnly(now);
    final month = _period == _FlowPeriod.thisMonth;
    final since = month
        ? DateTime(now.year, now.month)
        : today.subtract(const Duration(days: 29));
    final until = DateTime(today.year, today.month, today.day + 1);
    bool inPeriod(LedgerEntry entry) =>
        !entry.occurredAt.isBefore(since) && entry.occurredAt.isBefore(until);
    final recorded = store.entries.where(inPeriod).toList();
    final waiting = store.pending.map((draft) => draft.entry).where(inPeriod);
    // Recurring income and payments still to come this month, from today.
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    var dueIn = 0;
    var dueOut = 0;
    if (month) {
      for (final rule in store.recurring.where((rule) => rule.active)) {
        final count =
            occurrences(rule.nextDate, rule.recurrence, today, monthEnd).length;
        if (rule.kind == EntryKind.income) {
          dueIn += count * rule.amountPaise;
        } else {
          dueOut += count * rule.amountPaise;
        }
      }
    }
    if (recorded.isEmpty && waiting.isEmpty && dueIn == 0 && dueOut == 0) {
      return const SizedBox.shrink();
    }
    int total(Iterable<LedgerEntry> items, bool income) => items
        .where((entry) => entry.isIncome == income)
        .fold(0, (sum, entry) => sum + entry.amountPaise);
    final credited = total(recorded, true);
    final debited = total(recorded, false);
    final waitingIn = total(waiting, true);
    final waitingOut = total(waiting, false);
    final colors = AppColors.of(context);
    final net = credited - debited;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          // Wraps the switch under the heading on narrow screens.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(month ? monthLabel(now) : 'Last 30 days',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              SegmentedButton<_FlowPeriod>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: _FlowPeriod.thisMonth, label: Text('This month')),
                  ButtonSegment(
                      value: _FlowPeriod.last30Days, label: Text('30 days')),
                ],
                selected: {_period},
                onSelectionChanged: (value) =>
                    setState(() => _period = value.first),
              ),
            ],
          ),
        ),
        TileGrid(
          children: [
            StatTile(
              label: 'Credited',
              value: formatMoney(credited),
              icon: Icons.south_west,
              color: colors.income,
              caption: waitingIn > 0
                  ? '+${formatMoney(waitingIn)} awaiting review'
                  : '${recorded.where((entry) => entry.isIncome).length} recorded',
            ),
            StatTile(
              label: 'Debited',
              value: formatMoney(debited),
              icon: Icons.north_east,
              color: colors.expense,
              caption: waitingOut > 0
                  ? '+${formatMoney(waitingOut)} awaiting review'
                  : '${recorded.where((entry) => !entry.isIncome).length} recorded',
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            net >= 0
                ? 'You kept ${formatMoney(net)} of what came in.'
                : 'You spent ${formatMoney(-net)} more than came in.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (dueIn > 0 || dueOut > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Recurring still due this month: ${[
                if (dueIn > 0) '${formatMoney(dueIn)} in',
                if (dueOut > 0) '${formatMoney(dueOut)} out',
              ].join(', ')}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Payments from the user's history that repeat at a steady rhythm, offered
/// as recurring entries.
class RecurringSuggestionsSection extends StatelessWidget {
  const RecurringSuggestionsSection({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final suggestions = store.recurringSuggestions();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Looks recurring'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              'Found in your history. Add one to get a draft each time it is due, matched to your bank SMS.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          suggestion.kind == EntryKind.income
                              ? Icons.south_west
                              : Icons.north_east,
                          size: 18,
                          color: suggestion.kind == EntryKind.income
                              ? colors.income
                              : colors.expense,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(suggestion.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        Text(
                          '${suggestion.amountVaries ? '≈ ' : ''}${formatMoney(suggestion.amountPaise)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Recurrence(suggestion.repeat).label} · seen ${suggestion.occurrences} times, last ${formatDate(suggestion.lastDate)} · next ${formatDate(suggestion.nextDate)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              store.dismissSuggestion(suggestion.key),
                          child: const Text('Not recurring'),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final rule =
                                await store.acceptSuggestion(suggestion);
                            if (context.mounted) {
                              showMessage(context,
                                  'Added “${rule.title}” · next ${formatDate(rule.nextDate)}');
                            }
                          },
                          child: const Text('Add as recurring'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

const _recurringRepeats = [
  Recurrence(Repeat.weekly),
  Recurrence(Repeat.monthly),
  Recurrence(Repeat.quarterly),
  Recurrence(Repeat.yearly),
  Recurrence.none,
];

Future<void> showRecurringForm(BuildContext context, LifePilotStore store,
        {RecurringEntry? rule}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecurringForm(store: store, rule: rule),
    );

/// Owns its text controllers so they are disposed only after the sheet has
/// finished closing, not while its exit animation still uses them.
class _RecurringForm extends StatefulWidget {
  const _RecurringForm({required this.store, this.rule});

  final LifePilotStore store;
  final RecurringEntry? rule;

  @override
  State<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<_RecurringForm> {
  late final title = TextEditingController(text: widget.rule?.title ?? '');
  late final amount = TextEditingController(
      text: widget.rule == null ? '' : paiseToInput(widget.rule!.amountPaise));
  late var kind = widget.rule?.kind ?? EntryKind.expense;
  late var category = widget.rule?.category ??
      (store.categories.contains('Bills') ? 'Bills' : store.categories.first);
  late var recurrence = widget.rule == null
      ? const Recurrence(Repeat.monthly)
      : Recurrence(widget.rule!.recurrence.repeat);
  late var date = widget.rule?.nextDate ?? dateOnly(store.now());
  late String? accountId = widget.rule?.accountId;
  final formKey = GlobalKey<FormState>();

  LifePilotStore get store => widget.store;
  RecurringEntry? get rule => widget.rule;

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    super.dispose();
  }

  void setSheetState(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Form(
          key: formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(rule == null ? 'Recurring entry' : 'Edit recurring entry',
                  style: Theme.of(sheetContext).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text(
                  'When it is due, a draft is prepared for you to approve. Nothing is recorded automatically.'),
              const SizedBox(height: 16),
              SegmentedButton<EntryKind>(
                segments: const [
                  ButtonSegment(
                      value: EntryKind.expense, label: Text('Expense')),
                  ButtonSegment(value: EntryKind.income, label: Text('Income')),
                ],
                selected: {kind},
                onSelectionChanged: (value) => setSheetState(() {
                  kind = value.first;
                  if (kind == EntryKind.income &&
                      store.categories.contains('Salary')) {
                    category = 'Salary';
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Description', hintText: 'Rent, salary, SIP…'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Add a description.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Amount', prefixText: '${MoneyFormat.symbol} '),
                validator: (value) => parseRupeesToPaise(value ?? '') == null
                    ? 'Enter an amount greater than zero.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final item in store.categories)
                    DropdownMenuItem(value: item, child: Text(item)),
                ],
                onChanged: (value) =>
                    setSheetState(() => category = value ?? category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Recurrence>(
                initialValue: _recurringRepeats.contains(recurrence)
                    ? recurrence
                    : const Recurrence(Repeat.monthly),
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: [
                  for (final option in _recurringRepeats)
                    DropdownMenuItem(
                        value: option,
                        child: Text(option.isNone ? 'Once' : option.label)),
                ],
                onChanged: (value) =>
                    setSheetState(() => recurrence = value ?? recurrence),
              ),
              if (store.accounts.any((account) => !account.archived)) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: store.accountById(accountId)?.id,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Not set')),
                    for (final account
                        in store.accounts.where((item) => !item.archived))
                      DropdownMenuItem(
                          value: account.id, child: Text(account.name)),
                  ],
                  onChanged: (value) => setSheetState(() => accountId = value),
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(
                    '${rule == null ? 'First' : 'Next'} date: ${formatDate(date)}'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setSheetState(() => date = picked);
                },
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final paise = parseRupeesToPaise(amount.text)!;
                  final rule = this.rule;
                  if (rule == null) {
                    await store.addRecurring(
                      kind: kind,
                      amountPaise: paise,
                      category: category,
                      title: title.text,
                      recurrence: recurrence,
                      firstDate: date,
                      accountId: accountId,
                    );
                  } else {
                    await store.updateRecurring(RecurringEntry(
                      id: rule.id,
                      kind: kind,
                      amountPaise: paise,
                      category: category,
                      title: title.text.trim(),
                      recurrence: recurrence,
                      nextDate: dateOnly(date),
                      accountId: accountId,
                      paymentMethod: rule.paymentMethod,
                      // Editing a paused entry keeps it paused.
                      active: rule.active,
                    ));
                  }
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// SMS import

/// Drafts that [messages] would create; nothing is saved here.
List<PendingEntry> draftsFromSms(
  LifePilotStore store,
  Iterable<SmsMessage> messages,
) =>
    buildSmsImport(store, messages).drafts;

Future<void> importFromSmsInbox(
    BuildContext context, LifePilotStore store) async {
  final agreed = await confirmAction(
    context,
    title: 'Read bank SMS?',
    message:
        'LifePilot will read messages from the last 30 days on this phone, find completed bank or UPI transactions, and create drafts for you to review. Messages are not stored or sent anywhere; only the drafts you approve are recorded.',
    confirmLabel: 'Continue',
  );
  if (!agreed || !context.mounted) return;
  final status = await Permission.sms.request();
  if (!context.mounted) return;
  if (!status.isGranted) {
    showMessage(
        context,
        status.isPermanentlyDenied
            ? 'SMS permission is blocked. Allow it in system settings, or use “Paste messages”.'
            : 'SMS permission was not granted. You can use “Paste messages” instead.',
        error: true);
    return;
  }
  try {
    final since = store.now().subtract(const Duration(days: 30));
    final messages = await SmsQuery().querySms(
      kinds: [SmsQueryKind.inbox],
      count: 500,
      sort: true,
    );
    final recent = [
      for (final message in messages)
        if (message.date != null &&
            message.date!.isAfter(since) &&
            (message.body ?? '').isNotEmpty)
          (
            address: message.address ?? '',
            body: message.body!,
            date: message.date!
          ),
    ];
    final import = buildSmsImport(store, recent);
    await store.applySmsImport(import);
    if (!context.mounted) return;
    showMessage(
        context, 'Checked ${recent.length} messages: ${import.summary()}');
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not read messages: $error', error: true);
    }
  }
}

Future<void> importPastedSms(BuildContext context, LifePilotStore store) async {
  final pasted = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return;
  final controller = TextEditingController(text: pasted?.text ?? '');
  final text = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Paste bank messages'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: controller,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(
              hintText: 'Paste one or more messages, separated by blank lines'),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Create drafts')),
      ],
    ),
  );
  controller.dispose();
  if (text == null || !context.mounted) return;
  final now = store.now();
  final blocks = text
      .split(RegExp(r'\n\s*\n'))
      .map((block) => block.trim())
      .where((block) => block.isNotEmpty);
  final import = buildSmsImport(store, [
    for (final block in blocks) (address: 'pasted', body: block, date: now),
  ]);
  await store.applySmsImport(import);
  // Bank messages should not linger where other apps can read them.
  await clearClipboardIf(text);
  if (!context.mounted) return;
  showMessage(
      context,
      import.drafts.isEmpty
          ? import.summary()
          : '${import.summary()} Check the date of each before approving.');
}
