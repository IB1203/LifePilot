import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/transaction_intelligence.dart';
import '../features/money_extras.dart' show showAccountForm;
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Bank Accounts page: shows detailed bank account information including
/// bank name, masked account number, IFSC code, current balance, available
/// balance, and last synced time.
class BankAccountsPage extends StatelessWidget {
  const BankAccountsPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final active =
        store.accounts.where((account) => !account.archived).toList();
    final archived =
        store.accounts.where((account) => account.archived).toList();
    final colors = AppColors.of(context);

    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
          title: 'Bank Accounts',
          action: 'Add Account',
          onAction: () => showAccountForm(context, store),
        ),
        if (active.isEmpty)
          EmptyState(
            icon: Icons.account_balance_outlined,
            title: 'No bank accounts yet',
            message:
                'Add a bank account to track balances from SMS notifications and statement imports.',
            actionLabel: 'Add Account',
            onAction: () => showAccountForm(context, store),
          )
        else ...[
          const SizedBox(height: 8),
          // Total balance summary
          _TotalBalanceTile(store: store, active: active),
          const SizedBox(height: 12),
          // Account list
          const SectionHeader(title: 'Your Accounts'),
          for (final account in active)
            _BankAccountTile(store: store, account: account, colors: colors),
          const SizedBox(height: 12),
          // Reconciliation summary
          _ReconciliationSummary(store: store),
          const SizedBox(height: 12),
          if (archived.isNotEmpty) ...[
            const SectionHeader(title: 'Archived Accounts'),
            for (final account in archived)
              _BankAccountTile(store: store, account: account, colors: colors,
                  archived: true),
          ],
        ],
      ],
    );
  }
}

/// Total balance across all bank accounts.
class _TotalBalanceTile extends StatelessWidget {
  const _TotalBalanceTile({required this.store, required this.active});

  final LifePilotStore store;
  final List<Account> active;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    int total = 0;
    int availableTotal = 0;
    for (final account in active) {
      total += store.accountRunningBalance(account.id);
      if (account.availableBalancePaise != null) {
        availableTotal += account.availableBalancePaise!;
      } else {
        availableTotal += store.accountRunningBalance(account.id);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Balance',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recorded',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(formatMoney(total),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.income,
                              )),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Available (Bank)',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(formatMoney(availableTotal),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              )),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual bank account tile with detailed bank information.
class _BankAccountTile extends StatelessWidget {
  const _BankAccountTile({
    required this.store,
    required this.account,
    required this.colors,
    this.archived = false,
  });

  final LifePilotStore store;
  final Account account;
  final AppColors colors;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final balance = store.accountRunningBalance(account.id);
    final entryCount = store.entries
        .where((entry) => entry.accountId == account.id)
        .length;
    final synced = account.lastSyncedAt;
    final bankName = account.bankName ?? account.name;
    final masked = account.accountNumberMasked ?? account.last4;
    final ifsc = account.ifscCode;
    final acctType = account.accountType ?? account.kind.label;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(bankName,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (archived)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Archived',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 10,
                                      )),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('$acctType${masked.isNotEmpty ? ' • $masked' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium),
                      if (ifsc != null && ifsc.isNotEmpty)
                        Text('IFSC: $ifsc',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                )),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(balance),
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: balance < 0
                                  ? colors.expense
                                  : colors.income,
                            )),
                    if (account.availableBalancePaise != null &&
                        account.availableBalancePaise != balance)
                      Text('Available: ${formatMoney(account.availableBalancePaise!)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.schedule, size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    synced != null
                        ? 'Last synced: ${formatDate(synced)}'
                        : 'Never synced',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (account.verificationStatus.isNotEmpty &&
                    account.verificationStatus != 'unidentified')
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: account.verificationStatus == 'verified'
                          ? colors.income.withValues(alpha: 0.15)
                          : colors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      account.verificationStatus == 'verified'
                          ? 'Verified'
                          : account.verificationStatus == 'matched'
                              ? 'Matched'
                              : 'Unidentified',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(
                            color: account.verificationStatus == 'verified'
                                ? colors.income
                                : colors.warning,
                            fontSize: 10,
                          ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit Account',
                  onPressed: () => showAccountForm(context, store,
                      account: account),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.receipt_long, size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('$entryCount transactions',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 16),
                Icon(Icons.balance, size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Opening: ${formatMoney(account.openingBalancePaise)}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (account.lastStatementBalancePaise != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.receipt, size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Statement: ${formatMoney(account.lastStatementBalancePaise!)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Reconciliation summary showing which accounts match bank-reported balances.
class _ReconciliationSummary extends StatelessWidget {
  const _ReconciliationSummary({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final results = synchronizeAllBalances(store);
    final colors = AppColors.of(context);
    final reconciled =
        results.where((r) => r.isReconciled).length;
    final total = results.length;
    final mismatched = total - reconciled;

    if (total == 0) return const SizedBox.shrink();

    return Card(
      color: mismatched == 0
          ? colors.income.withValues(alpha: 0.08)
          : colors.warning.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              mismatched == 0 ? Icons.check_circle : Icons.warning,
              color: mismatched == 0
                  ? colors.income
                  : colors.warning,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Balance Reconciliation',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    reconciled == total
                        ? 'All $total accounts reconciled with bank balances.'
                        : '$reconciled of $total accounts reconciled. $mismatched need review.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (mismatched > 0)
              FilledButton.tonal(
                onPressed: () {},
                child: const Text('Review'),
              ),
          ],
        ),
      ),
    );
  }
}
