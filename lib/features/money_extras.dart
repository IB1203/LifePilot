import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart' hide SmsMessage;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/personal.dart';
import '../core/sms_import.dart';
import '../core/recurrence.dart';
import '../services/device_security.dart';
import '../ui/forms.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'sms_settings_page.dart';

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
            sum + accountBalance(account, store.entries, store.transfers));
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
    final balance = accountBalance(account, store.entries, store.transfers);
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
  final name = TextEditingController(text: account?.name ?? '');
  final opening = TextEditingController(
      text: account == null || account.openingBalancePaise == 0
          ? ''
          : paiseToInput(account.openingBalancePaise.abs()));
  var negative = (account?.openingBalancePaise ?? 0) < 0;
  var kind = account?.kind ?? AccountKind.bank;
  final formKey = GlobalKey<FormState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Form(
          key: formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(account == null ? 'Add account' : 'Edit account',
                  style: Theme.of(sheetContext).textTheme.headlineSmall),
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
                      onSelected: (_) => setSheetState(() {
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
                onChanged: (value) => setSheetState(() => negative = value),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final amount = (parseRupeesToPaise(opening.text) ?? 0) *
                      (negative ? -1 : 1);
                  if (account == null) {
                    await store.addAccount(name.text, kind,
                        openingBalancePaise: amount);
                  } else {
                    await store.updateAccount(account.copyWith(
                        name: name.text.trim(),
                        kind: kind,
                        openingBalancePaise: amount));
                  }
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Save account'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  name.dispose();
  opening.dispose();
}

Future<void> showTransferForm(
    BuildContext context, LifePilotStore store) async {
  final active = store.accounts.where((account) => !account.archived).toList();
  if (active.length < 2) return;
  var from = active[0].id;
  var to = active[1].id;
  final amount = TextEditingController();
  final note = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Form(
          key: formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Move money',
                  style: Theme.of(sheetContext).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text(
                  'A transfer between your own accounts. It is not counted as income or an expense.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: from,
                decoration: const InputDecoration(labelText: 'From'),
                items: [
                  for (final account in active)
                    DropdownMenuItem(
                        value: account.id, child: Text(account.name)),
                ],
                onChanged: (value) => setSheetState(() => from = value ?? from),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: to,
                decoration: const InputDecoration(labelText: 'To'),
                items: [
                  for (final account in active)
                    DropdownMenuItem(
                        value: account.id, child: Text(account.name)),
                ],
                onChanged: (value) => setSheetState(() => to = value ?? to),
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
                          color: Theme.of(sheetContext).colorScheme.error)),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (from == to) {
                    setSheetState(
                        () => error = 'Choose two different accounts.');
                    return;
                  }
                  await store.addTransfer(
                    fromAccountId: from,
                    toAccountId: to,
                    amountPaise: parseRupeesToPaise(amount.text)!,
                    note: note.text,
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Save transfer'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  amount.dispose();
  note.dispose();
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
    return ListView(
      padding: pagePadding,
      children: [
        PendingDraftsSection(store: store),
        SuspiciousSmsSection(store: store),
        SectionHeader(
            title: 'Recurring income and expenses',
            action: 'Add',
            onAction: () => showRecurringForm(context, store)),
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
                      Text(formatMoney(rule.amountPaise)),
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
        const SectionHeader(title: 'Bank SMS'),
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
                    Pill(
                      icon: switch (draft.source) {
                        'sms' => Icons.sms_outlined,
                        'upi' => Icons.qr_code_2,
                        _ => Icons.autorenew,
                      },
                      label: switch (draft.source) {
                        'sms' => 'From SMS',
                        'upi' when draft.bankConfirmed =>
                          'UPI payment · confirmed by bank SMS',
                        'upi' => 'UPI app report · not bank-verified',
                        _ => 'Recurring',
                      },
                      color: draft.bankConfirmed ? colors.income : null,
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
                        '${draft.entry.category} · ${formatDate(draft.entry.occurredAt)}'
                        '${store.accountById(draft.entry.accountId) == null ? '' : ' · ${store.accountById(draft.entry.accountId)!.name}'}',
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

const _recurringRepeats = [
  Recurrence(Repeat.weekly),
  Recurrence(Repeat.monthly),
  Recurrence(Repeat.quarterly),
  Recurrence(Repeat.yearly),
  Recurrence.none,
];

Future<void> showRecurringForm(BuildContext context, LifePilotStore store,
    {RecurringEntry? rule}) async {
  final title = TextEditingController(text: rule?.title ?? '');
  final amount = TextEditingController(
      text: rule == null ? '' : paiseToInput(rule.amountPaise));
  var kind = rule?.kind ?? EntryKind.expense;
  var category = rule?.category ??
      (store.categories.contains('Bills') ? 'Bills' : store.categories.first);
  var recurrence = rule == null
      ? const Recurrence(Repeat.monthly)
      : Recurrence(rule.recurrence.repeat);
  var date = rule?.nextDate ?? dateOnly(store.now());
  String? accountId = rule?.accountId;
  final formKey = GlobalKey<FormState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
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
                      active: true,
                    ));
                  }
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  title.dispose();
  amount.dispose();
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
