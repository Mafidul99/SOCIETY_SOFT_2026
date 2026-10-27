import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.apiService,
    required this.session,
    required this.onNavigate,
  });

  final ApiService apiService;
  final AuthSession session;
  final ValueChanged<int> onNavigate;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = _fetchData();
  }

  bool get _isMember => widget.session.role.toLowerCase() == 'member';
  bool get _canReadLoans =>
      widget.session.hasPermission('loan_view') ||
      (_isMember && widget.session.hasPermission('loan_add')) ||
      widget.session.hasPermission('loan_edit') ||
      widget.session.hasPermission('loan_delete') ||
      widget.session.hasPermission('loan_update');

  Future<_DashboardData> _fetchData() async {
    final canReadLedger = !_isMember &&
        (widget.session.hasPermission('shared_data_read') ||
            widget.session.hasPermission('ledger_view'));
    final canReadUsers = !_isMember &&
        (widget.session.hasPermission('shared_data_read') ||
            widget.session.hasPermission('user_view'));
    final canReadDepositAccounts = widget.session.hasPermission('deposit_view');
    const depositReports = <(String, String, int)>[
      ('FD', 'monthly', 4),
      ('RD', 'weekly', 5),
      ('RD', 'monthly', 6),
      ('DRD', 'daily', 7),
      ('DRD', 'weekly', 8),
      ('DRD', 'monthly', 9),
    ];
    final availableDepositReports = canReadDepositAccounts
        ? depositReports
            .where((report) => widget.session.canViewReport(report.$2))
            .toList()
        : const <(String, String, int)>[];

    final results = await Future.wait([
      canReadLedger
          ? _loadRecords('getAmount', 'Ledger')
          : Future.value(const _DashboardRecords(label: 'Ledger')),
      canReadUsers
          ? _loadRecords('getUsers', 'Users')
          : Future.value(const _DashboardRecords(label: 'Users')),
      _canReadLoans
          ? _loadLoans()
          : Future.value(const _DashboardRecords(label: 'Loans')),
    ]);
    final depositResults = await Future.wait(
      availableDepositReports.map(
        (report) => _loadDepositRecords(report.$1, report.$2),
      ),
    );
    return _DashboardData(
      ledger: results[0],
      users: results[1],
      loans: results[2],
      canReadLoans: _canReadLoans,
      deposits: [
        for (var index = 0; index < availableDepositReports.length; index++)
          _DashboardDepositReport(
            product: availableDepositReports[index].$1,
            cadence: availableDepositReports[index].$2,
            pageIndex: availableDepositReports[index].$3,
            result: depositResults[index],
          ),
      ],
    );
  }

  Future<_DashboardRecords> _loadLoans() async {
    try {
      final loans = await widget.apiService.fetchLoans(
        session: widget.session,
      );
      return _DashboardRecords(label: 'Loans', records: loans);
    } catch (error) {
      return _DashboardRecords(label: 'Loans', error: error.toString());
    }
  }

  Future<_DashboardRecords> _loadDepositRecords(
    String product,
    String cadence,
  ) async {
    final label = '$product ${cadence[0].toUpperCase()}${cadence.substring(1)}';
    try {
      final records = await widget.apiService.fetchDepositAccounts(
        product: product,
        cadence: cadence,
        session: widget.session,
      );
      return _DashboardRecords(label: label, records: records);
    } catch (error) {
      return _DashboardRecords(label: label, error: error.toString());
    }
  }

  Future<_DashboardRecords> _loadRecords(String action, String label) async {
    try {
      final value =
          await widget.apiService.fetchSheetData(action, widget.session);
      if (value is! List) {
        throw FormatException('The server returned invalid data for $action.');
      }
      return _DashboardRecords(
        label: label,
        records: value.whereType<Map>().map<Map<String, dynamic>>((record) {
          return Map<String, dynamic>.from(record);
        }).toList(),
      );
    } catch (error) {
      return _DashboardRecords(label: label, error: error.toString());
    }
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return PortalGradientBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const PortalLoadingState(label: 'Loading dashboard');
              }
              if (!snapshot.hasData) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Unable to load dashboard data.',
                          key: Key('dashboard-error'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('dashboard-retry'),
                          onPressed: () => setState(_load),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final data = snapshot.data!;
              if (_isMember) return _buildMemberDashboard(data);

              final totalDeposits = data.ledger.error == null
                  ? _currency(_sum(data.ledger.records, 'deposit'))
                  : 'Unavailable';
              final totalWithdrawals = data.ledger.error == null
                  ? _currency(_sum(data.ledger.records, 'withdrawal'))
                  : 'Unavailable';
              final netBalance = data.ledger.records.isEmpty
                  ? 0
                  : _number(data.ledger.records.last['balance']);
              final failures = data.sources
                  .where((source) => source.error != null)
                  .toList(growable: false);
              final availableDeposits = data.deposits;

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  children: [
                    _DashboardHero(
                      name: widget.session.name,
                      title: 'Dashboard',
                      subtitle:
                          'Your finances and account activity at a glance.',
                    ),
                    if (failures.isNotEmpty) ...[
                      Card(
                        key: const Key('dashboard-partial-error'),
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Some dashboard data could not be loaded.',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              for (final source in failures)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child:
                                      Text('${source.label}: ${source.error}'),
                                ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  key: const Key('dashboard-retry'),
                                  onPressed: () => setState(_load),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry all'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _metricGrid(context, [
                      PortalMetricCard(
                        label: 'Ledger balance',
                        value: data.ledger.error == null
                            ? _currency(netBalance)
                            : 'Unavailable',
                        icon: Icons.account_balance_wallet_rounded,
                        accent: const Color(0xFF3458D4),
                      ),
                      PortalMetricCard(
                        label: 'Deposits',
                        value: totalDeposits,
                        icon: Icons.south_west_rounded,
                        accent: const Color(0xFF078A6A),
                      ),
                      PortalMetricCard(
                        label: 'Withdrawals',
                        value: totalWithdrawals,
                        icon: Icons.north_east_rounded,
                        accent: const Color(0xFFD25858),
                      ),
                      PortalMetricCard(
                        label: 'User accounts',
                        value: data.users.error == null
                            ? '${data.users.records.length}'
                            : 'Unavailable',
                        icon: Icons.people_alt_rounded,
                        accent: const Color(0xFF039BE5),
                      ),
                    ]),
                    if (availableDeposits.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DepositAccountsChart(reports: availableDeposits),
                    ],
                    if (availableDeposits.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const _SectionTitle(
                        title: 'Deposit accounts',
                        trailing: 'Estimated maturity value',
                      ),
                      const SizedBox(height: 10),
                      for (final report in availableDeposits)
                        _DepositSummaryCard(
                          report: report,
                          onOpen: () => widget.onNavigate(report.pageIndex),
                        ),
                    ],
                    const SizedBox(height: 12),
                    _SectionTitle(
                      title: 'Recent ledger activity',
                      trailing: data.ledger.error == null
                          ? '${data.ledger.records.length} records'
                          : 'Unavailable',
                    ),
                    const SizedBox(height: 10),
                    if (data.ledger.error != null)
                      _SourceErrorCard(
                        source: 'Ledger',
                        message: data.ledger.error!,
                      )
                    else if (data.ledger.records.isEmpty)
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.receipt_long_outlined),
                          title: Text('No ledger activity yet'),
                        ),
                      )
                    else
                      ...data.ledger.records.reversed.take(5).map((entry) {
                        final deposit = _number(entry['deposit']);
                        final withdrawal = _number(entry['withdrawal']);
                        final isDeposit = deposit > 0 || withdrawal == 0;
                        final amount = isDeposit ? deposit : withdrawal;
                        final color = isDeposit
                            ? const Color(0xFF078A6A)
                            : const Color(0xFFD25858);
                        final amountColor = isDeposit
                            ? Theme.of(context).colorScheme.tertiary
                            : Theme.of(context).colorScheme.error;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: .12),
                              foregroundColor: color,
                              child: Icon(
                                isDeposit
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded,
                              ),
                            ),
                            title: Text(
                              (entry['byWhom'] ?? '').toString().isEmpty
                                  ? 'General account'
                                  : entry['byWhom'].toString(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${entry['date'] ?? '-'} · ${entry['remarks'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              '${isDeposit ? '+' : '-'}${_currency(amount)}',
                              style: TextStyle(
                                color: amountColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('dashboard-open-ledger'),
                      onPressed: () => widget.onNavigate(1),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Open full ledger'),
                    ),
                    if (data.canReadLoans) ...[
                      const SizedBox(height: 16),
                      _LoanDashboardSection(
                        loans: data.loans.records,
                        error: data.loans.error,
                        onNavigate: widget.onNavigate,
                      ),
                    ],
                    const SizedBox(height: 20),
                    _SectionTitle(
                      title: 'Registered accounts',
                      trailing: data.users.error == null
                          ? '${data.users.records.length} accounts'
                          : 'Unavailable',
                    ),
                    const SizedBox(height: 10),
                    _RegisteredAccountsPanel(
                      users: data.users.records,
                      error: data.users.error,
                      onOpen: () => widget.onNavigate(5),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _metricGrid(BuildContext context, List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 520 ? 2 : 3;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  Widget _buildMemberDashboard(_DashboardData data) {
    final depositReports = data.deposits;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          _DashboardHero(
            name: widget.session.name,
            title: 'My dashboard',
            subtitle: 'Your loans, deposit accounts and account activity.',
          ),
          const SizedBox(height: 16),
          const _SectionTitle(
            title: 'My deposit accounts',
            trailing: 'Estimated maturity value',
          ),
          const SizedBox(height: 10),
          if (depositReports.isNotEmpty) ...[
            _DepositAccountsChart(reports: depositReports),
            const SizedBox(height: 12),
          ],
          if (depositReports.isEmpty)
            const PortalEmptyState(
              title: 'No deposit accounts available',
              subtitle: 'Ask an administrator if you expect to see an account.',
              icon: Icons.savings_outlined,
            )
          else
            for (final report in depositReports)
              _DepositSummaryCard(
                report: report,
                onOpen: () => widget.onNavigate(report.pageIndex),
                memberView: true,
              ),
          if (data.canReadLoans) ...[
            const SizedBox(height: 16),
            _LoanDashboardSection(
              loans: data.loans.records,
              error: data.loans.error,
              onNavigate: widget.onNavigate,
              memberView: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.name,
    required this.title,
    required this.subtitle,
  });

  final String name;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty ? 'there' : name.trim();
    final compact = MediaQuery.sizeOf(context).width < 380;
    final contentInset = compact ? 18.0 : 24.0;
    final sectionGap = compact ? 14.0 : 20.0;
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      < 12 => 'Good morning',
      < 17 => 'Good afternoon',
      _ => 'Good evening',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        compact ? 8 : 12,
        0,
        compact ? 12 : 16,
      ),
      child: ClipRRect(
        key: const Key('dashboard-hero-card'),
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: portalHeaderGradient(context),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -46,
                right: -24,
                child: IgnorePointer(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .07),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(contentInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .20),
                            ),
                          ),
                          child: const Icon(
                            Icons.account_balance_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'NTCCSL FINANCE SYSTEM',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: .88),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.auto_graph_rounded,
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: sectionGap),
                    Text(
                      '$greeting, $displayName',
                      key: const Key('dashboard-greeting'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: .78),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.4,
                              ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: .82),
                          ),
                    ),
                    SizedBox(height: compact ? 12 : 16),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 9 : 11,
                        vertical: compact ? 6 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: .9),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            DateFormat(
                                    compact ? 'd MMM yyyy' : 'EEE, d MMM yyyy')
                                .format(now),
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.ledger,
    required this.users,
    required this.loans,
    required this.canReadLoans,
    required this.deposits,
  });

  final _DashboardRecords ledger;
  final _DashboardRecords users;
  final _DashboardRecords loans;
  final bool canReadLoans;
  final List<_DashboardDepositReport> deposits;

  List<_DashboardRecords> get sources => [
        ledger,
        users,
        if (canReadLoans) loans,
        ...deposits.map((item) => item.result),
      ];
}

class _LoanDashboardSection extends StatelessWidget {
  const _LoanDashboardSection({
    required this.loans,
    required this.error,
    required this.onNavigate,
    this.memberView = false,
  });

  final List<Map<String, dynamic>> loans;
  final String? error;
  final ValueChanged<int> onNavigate;
  final bool memberView;

  @override
  Widget build(BuildContext context) {
    final approvedLoans = loans.where(_isApprovedLoan).toList();
    final pendingLoans = loans.where(_isPendingLoan).length;
    final approvedPrincipal = _sum(
      approvedLoans,
      'principal',
    );
    final recentLoans = loans.toList()
      ..sort((first, second) {
        return (second['createdAt']?.toString() ?? '')
            .compareTo(first['createdAt']?.toString() ?? '');
      });
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          title: 'Loan portfolio',
          trailing: 'Applications and approved loans',
        ),
        const SizedBox(height: 10),
        if (error != null)
          _SourceErrorCard(source: 'Loans', message: error!)
        else ...[
          Row(
            children: [
              Expanded(
                child: _LoanMetricCard(
                  key: const Key('dashboard-loan-count'),
                  label: memberView ? 'My loans' : 'Total loans',
                  value: '${loans.length}',
                  icon: Icons.request_quote_outlined,
                  accent: colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LoanMetricCard(
                  key: const Key('dashboard-loan-approved-principal'),
                  label: 'Approved principal',
                  value: _currency(approvedPrincipal),
                  icon: Icons.account_balance_wallet_outlined,
                  accent: const Color(0xFF078A6A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LoanMetricCard(
                  key: const Key('dashboard-loan-pending-count'),
                  label: 'Pending',
                  value: '$pendingLoans',
                  icon: Icons.hourglass_top_rounded,
                  accent: const Color(0xFFB45309),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (loans.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_balance_outlined),
                title: Text('No loan applications yet'),
              ),
            )
          else ...[
            for (final loan in recentLoans.take(5))
              _LoanDashboardListTile(loan: loan),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('dashboard-open-loans'),
                onPressed: () => onNavigate(15),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Open loan list'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _LoanMetricCard extends StatelessWidget {
  const _LoanMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: Color.alphaBlend(
        accent.withValues(alpha: .12),
        colors.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              key: Key(
                  'dashboard-loan-value-${label.toLowerCase().replaceAll(' ', '-')}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanDashboardListTile extends StatelessWidget {
  const _LoanDashboardListTile({required this.loan});

  final Map<String, dynamic> loan;

  @override
  Widget build(BuildContext context) {
    final status = _loanStatus(loan);
    final statusColor = switch (status.toLowerCase()) {
      'approved' => const Color(0xFF078A6A),
      'rejected' => Theme.of(context).colorScheme.error,
      _ => const Color(0xFFB45309),
    };
    final loanType = loan['loanType']?.toString().trim();
    final title = loan['memberName']?.toString().trim().isNotEmpty == true
        ? loan['memberName'].toString()
        : 'Loan applicant';
    final subtitle = [
      if (loanType != null && loanType.isNotEmpty)
        '${_capitalizeLoanType(loanType)} Loan',
      status,
      if (loan['createdAt']?.toString().isNotEmpty == true)
        loan['createdAt'].toString(),
    ].join(' · ');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: .12),
          foregroundColor: statusColor,
          child: Icon(
            loanType?.toLowerCase() == 'gold'
                ? Icons.diamond_outlined
                : Icons.account_balance_outlined,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(
          _currency(_number(loan['principal'])),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

bool _isApprovedLoan(Map<String, dynamic> loan) =>
    _loanStatus(loan).toLowerCase() == 'approved';

bool _isPendingLoan(Map<String, dynamic> loan) =>
    _loanStatus(loan).toLowerCase() == 'pending';

String _loanStatus(Map<String, dynamic> loan) {
  final status = loan['approvalStatus']?.toString().trim() ?? '';
  if (status.isEmpty) return 'Approved';
  return switch (status.toLowerCase()) {
    'approved' => 'Approved',
    'pending' => 'Pending',
    'rejected' => 'Rejected',
    _ => status,
  };
}

String _capitalizeLoanType(String loanType) =>
    loanType[0].toUpperCase() + loanType.substring(1);

class _DashboardDepositReport {
  const _DashboardDepositReport({
    required this.product,
    required this.cadence,
    required this.pageIndex,
    required this.result,
  });

  final String product;
  final String cadence;
  final int pageIndex;
  final _DashboardRecords result;

  String get title => switch (product) {
        'FD' => 'Fixed Deposit — Monthly',
        'RD' => 'Recurring Deposit — ${_capitalize(cadence)}',
        _ => 'Daily Recurring Deposit — ${_capitalize(cadence)}',
      };

  static String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);
}

class _DepositAccountsChart extends StatelessWidget {
  const _DepositAccountsChart({required this.reports});

  final List<_DashboardDepositReport> reports;

  @override
  Widget build(BuildContext context) {
    final availableReports =
        reports.where((report) => report.result.error == null).toList();
    if (availableReports.isEmpty) return const SizedBox.shrink();

    final counts = [
      for (final report in availableReports) report.result.records.length,
    ];
    final maxCount = counts.fold<int>(0, math.max);
    final accountCount = counts.fold<int>(0, (total, count) => total + count);
    final maturityTotal = availableReports.fold<double>(
      0,
      (total, report) =>
          total +
          report.result.records.fold<double>(
            0,
            (subtotal, account) =>
                subtotal + _number(account['maturityAmount']),
          ),
    );
    final theme = Theme.of(context);
    return Card(
      key: const Key('dashboard-deposit-account-chart'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deposit portfolio',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Accounts and estimated maturity by scheme',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _DepositPortfolioTotal(
                      label: 'Total accounts',
                      value: '$accountCount',
                      icon: Icons.savings_outlined,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: _DepositPortfolioTotal(
                      label: 'Est. maturity',
                      value: _currency(maturityTotal),
                      icon: Icons.trending_up_rounded,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DepositMaturityCharts(reports: availableReports),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 360 ? 2 : 3;
                final itemWidth =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final report in availableReports)
                      SizedBox(
                        width: itemWidth,
                        child: _DepositChartBar(
                          report: report,
                          maxCount: maxCount,
                          color: _depositChartColor(report.product),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _depositChartColor(String product) => switch (product) {
        'FD' => const Color(0xFF3458D4),
        'RD' => const Color(0xFF8E24AA),
        _ => const Color(0xFF078A6A),
      };
}

class _DepositMaturityCharts extends StatelessWidget {
  const _DepositMaturityCharts({required this.reports});

  final List<_DashboardDepositReport> reports;

  Color _colorFor(_DashboardDepositReport report) => switch (report.product) {
        'FD' => const Color(0xFF3458D4),
        'RD' => const Color(0xFF8E24AA),
        _ => const Color(0xFF078A6A),
      };

  double _maturityFor(_DashboardDepositReport report) =>
      report.result.records.fold<double>(
        0,
        (total, account) =>
            total + _number(account['maturityAmount']).toDouble(),
      );

  String _labelFor(_DashboardDepositReport report) =>
      '${report.product} ${_DashboardDepositReport._capitalize(report.cadence)}';

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final report in reports)
        _DepositChartValue(
          label: _labelFor(report),
          value: _maturityFor(report),
          color: _colorFor(report),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 680) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _DepositMaturityLineChart(values: values)),
              const SizedBox(width: 12),
              Expanded(child: _DepositMaturityPieChart(values: values)),
            ],
          );
        }
        return Column(
          children: [
            _DepositMaturityLineChart(values: values),
            const SizedBox(height: 12),
            _DepositMaturityPieChart(values: values),
          ],
        );
      },
    );
  }
}

class _DepositChartValue {
  const _DepositChartValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class _DepositMaturityLineChart extends StatelessWidget {
  const _DepositMaturityLineChart({required this.values});

  final List<_DepositChartValue> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = values
        .map((item) => '${item.label} ${_currency(item.value)}')
        .join('; ');
    return Card(
      key: const Key('dashboard-deposit-maturity-line-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Maturity trend',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Estimated value by scheme',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              key: const Key('dashboard-deposit-maturity-line'),
              label: 'Line chart of estimated maturity by scheme. $description',
              child: SizedBox(
                height: 132,
                width: double.infinity,
                child: CustomPaint(
                  painter: _DepositMaturityLinePainter(
                    values: values,
                    gridColor: theme.colorScheme.outlineVariant,
                    lineColor: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _DepositChartLegend(values: values, showValue: true),
          ],
        ),
      ),
    );
  }
}

class _DepositMaturityLinePainter extends CustomPainter {
  const _DepositMaturityLinePainter({
    required this.values,
    required this.gridColor,
    required this.lineColor,
  });

  final List<_DepositChartValue> values;
  final Color gridColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    const horizontalInset = 12.0;
    const verticalInset = 12.0;
    final plot = Rect.fromLTWH(
      horizontalInset,
      verticalInset,
      math.max(0, size.width - horizontalInset * 2),
      math.max(0, size.height - verticalInset * 2),
    );
    if (plot.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = plot.top + plot.height * row / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    final maxValue = values.fold<double>(
      0,
      (maximum, item) => math.max(maximum, item.value),
    );
    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          values.length == 1
              ? plot.center.dx
              : plot.left + plot.width * index / (values.length - 1),
          plot.bottom -
              plot.height *
                  (maxValue <= 0 ? 0 : values[index].value / maxValue),
        ),
    ];
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    for (var index = 0; index < points.length; index++) {
      canvas.drawCircle(
        points[index],
        5,
        Paint()..color = values[index].color,
      );
      canvas.drawCircle(
        points[index],
        2,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DepositMaturityLinePainter oldDelegate) =>
      oldDelegate.gridColor != gridColor ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.values.length != values.length ||
      values.indexed.any((entry) {
        final oldValue = oldDelegate.values[entry.$1];
        final value = entry.$2;
        return oldValue.label != value.label ||
            oldValue.value != value.value ||
            oldValue.color != value.color;
      });
}

class _DepositMaturityPieChart extends StatelessWidget {
  const _DepositMaturityPieChart({required this.values});

  final List<_DepositChartValue> values;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (sum, item) => sum + item.value);
    final theme = Theme.of(context);
    final description = values.map((item) {
      final share = total <= 0 ? 0 : (item.value * 100 / total).round();
      return '${item.label} ${_currency(item.value)}, $share percent';
    }).join('; ');
    return Card(
      key: const Key('dashboard-deposit-maturity-pie-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Portfolio share',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Estimated maturity by scheme',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              key: const Key('dashboard-deposit-maturity-pie'),
              label: 'Pie chart of estimated maturity by scheme. $description',
              child: SizedBox(
                height: 156,
                child: CustomPaint(
                  painter: _DepositMaturityPiePainter(
                    values: values,
                    total: total,
                    emptyColor: theme.colorScheme.outlineVariant,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(38),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currency(total),
                              key: const Key('dashboard-deposit-pie-total'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Estimated maturity',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _DepositChartLegend(values: values, showValue: false),
          ],
        ),
      ),
    );
  }
}

class _DepositMaturityPiePainter extends CustomPainter {
  const _DepositMaturityPiePainter({
    required this.values,
    required this.total,
    required this.emptyColor,
  });

  final List<_DepositChartValue> values;
  final double total;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: side / 2,
    );
    if (total <= 0) {
      canvas.drawCircle(
        rect.center,
        rect.width / 2,
        Paint()
          ..color = emptyColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20,
      );
      return;
    }

    var startAngle = -math.pi / 2;
    for (final item in values.where((item) => item.value > 0)) {
      final sweepAngle = item.value / total * math.pi * 2;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DepositMaturityPiePainter oldDelegate) =>
      oldDelegate.total != total ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.values.length != values.length ||
      values.indexed.any((entry) {
        final oldValue = oldDelegate.values[entry.$1];
        final value = entry.$2;
        return oldValue.label != value.label ||
            oldValue.value != value.value ||
            oldValue.color != value.color;
      });
}

class _DepositChartLegend extends StatelessWidget {
  const _DepositChartLegend({
    required this.values,
    required this.showValue,
  });

  final List<_DepositChartValue> values;
  final bool showValue;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final item in values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  showValue
                      ? '${item.label}: ${_currency(item.value)}'
                      : item.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
        ],
      );
}

class _DepositPortfolioTotal extends StatelessWidget {
  const _DepositPortfolioTotal({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DepositChartBar extends StatelessWidget {
  const _DepositChartBar({
    required this.report,
    required this.maxCount,
    required this.color,
  });

  final _DashboardDepositReport report;
  final int maxCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final count = report.result.records.length;
    final maturity = report.result.records.fold<double>(
      0,
      (total, account) => total + _number(account['maturityAmount']),
    );
    final ratio = maxCount == 0 ? 0.0 : count / maxCount;
    final cadence =
        report.cadence[0].toUpperCase() + report.cadence.substring(1);
    final label = '${report.product} $cadence';
    return Semantics(
      key: Key(
        'dashboard-deposit-chart-${report.product.toLowerCase()}-${report.cadence}',
      ),
      label:
          '$label: $count accounts, estimated maturity ${_currency(maturity)}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: .22),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  key: Key(
                    'dashboard-deposit-chart-count-${report.product.toLowerCase()}-${report.cadence}',
                  ),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: .12),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _currency(maturity),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              'Estimated maturity',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepositSummaryCard extends StatelessWidget {
  const _DepositSummaryCard({
    required this.report,
    required this.onOpen,
    this.memberView = false,
  });

  final _DashboardDepositReport report;
  final VoidCallback onOpen;
  final bool memberView;

  @override
  Widget build(BuildContext context) {
    if (report.result.error != null) {
      return _SourceErrorCard(
        source: report.title,
        message: report.result.error!,
      );
    }
    final accounts = report.result.records;
    final maturity = accounts.fold<double>(
      0,
      (total, account) => total + _number(account['maturityAmount']),
    );
    final paid = accounts.fold<int>(
      0,
      (total, account) =>
          total +
          (account['payments'] is List
              ? (account['payments'] as List)
                  .where((payment) => payment == true || payment == 1)
                  .length
              : 0),
    );
    final scheduled = accounts.fold<int>(
      0,
      (total, account) =>
          total +
          (account['payments'] is List
              ? (account['payments'] as List).length
              : 0),
    );
    final received = report.product == 'FD'
        ? 0
        : accounts.fold<num>(
            0,
            (total, account) {
              final payments = account['payments'];
              if (payments is! List) return total;
              final paidCount = payments
                  .where((payment) => payment == true || payment == 1)
                  .length;
              return total + (_number(account['amount']) * paidCount);
            },
          );
    final accountSummary = accounts.isEmpty
        ? 'No accounts yet'
        : '${accounts.length} accounts · '
            '${memberView ? 'My' : 'Total'} estimated maturity '
            '${_currency(maturity)}'
            '${report.product == 'FD' ? '' : ' · Total received ${_currency(received)}'}'
            '${scheduled == 0 ? '' : ' · $paid/$scheduled installments paid'}';
    const color = Color(0xFF078A6A);
    return Card(
      key: Key(
        'dashboard-deposit-${report.product.toLowerCase()}-${report.cadence}',
      ),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.savings_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accountSummary,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardRecords {
  const _DashboardRecords({
    required this.label,
    this.records = const [],
    this.error,
  });

  final String label;
  final List<Map<String, dynamic>> records;
  final String? error;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final titleStyle = Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800);
          final trailingStyle = TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          );
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: titleStyle),
                const SizedBox(height: 2),
                Text(
                  trailing,
                  style: trailingStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  trailing,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: trailingStyle,
                ),
              ),
            ],
          );
        },
      );
}

class _RegisteredAccountsPanel extends StatelessWidget {
  const _RegisteredAccountsPanel({
    required this.users,
    required this.error,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> users;
  final String? error;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Column(
        children: [
          _SourceErrorCard(source: 'Users', message: error!),
          _openDirectoryButton(),
        ],
      );
    }
    if (users.isEmpty) {
      return Column(
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.person_search_rounded),
              title: Text('No user accounts found'),
            ),
          ),
          _openDirectoryButton(),
        ],
      );
    }

    final normalizedRoles = users
        .map((user) => (user['role'] ?? 'Other').toString().trim())
        .map((role) => role.isEmpty ? 'Other' : role)
        .toList();
    final roles = <String>[
      'Admin',
      'Collector',
      'Member',
      if (normalizedRoles.any(
        (role) => !const ['admin', 'collector', 'member']
            .contains(role.toLowerCase()),
      ))
        'Other',
    ];
    final counts = <String, int>{
      for (final role in roles)
        role: normalizedRoles
            .where(
              (candidate) => role == 'Other'
                  ? !const ['admin', 'collector', 'member']
                      .contains(candidate.toLowerCase())
                  : candidate.toLowerCase() == role.toLowerCase(),
            )
            .length,
    };
    final colors = Theme.of(context).colorScheme;
    final chartCard = Card(
      key: const Key('registered-accounts-role-chart'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_rounded, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Accounts by role',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${users.length} total',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RolePieChart(
              roles: roles,
              counts: counts,
              total: users.length,
              colors: portalRoleColors,
            ),
          ],
        ),
      ),
    );
    Widget accountTable(bool compact) => compact
        ? Column(
            key: const Key('registered-accounts-cards'),
            children: [
              for (final user in users.take(5))
                _registeredAccountCard(
                  context,
                  user,
                  colors,
                ),
            ],
          )
        : Card(
            margin: EdgeInsets.zero,
            child: SingleChildScrollView(
              key: const Key('registered-accounts-table'),
              scrollDirection: Axis.horizontal,
              child: DataTable(
                dataRowMinHeight: 64,
                dataRowMaxHeight: 80,
                columns: const [
                  DataColumn(label: Text('Member Name')),
                  DataColumn(label: Text('Email Id')),
                  DataColumn(label: Text('Member ID')),
                  DataColumn(label: Text('Role')),
                  DataColumn(label: Text('Reports')),
                ],
                rows: [
                  for (final user in users.take(5))
                    _registeredAccountRow(
                      context: context,
                      user: user,
                      colors: colors,
                    ),
                ],
              ),
            ),
          );
    final accountList = Column(
      key: const Key('registered-accounts-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'All Members List',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                'Showing ${math.min(users.length, 5)} of ${users.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) =>
              accountTable(constraints.maxWidth < 500),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('dashboard-open-users'),
          onPressed: onOpen,
          icon: const Icon(Icons.people_alt_rounded),
          label: const Text('Open user directory'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: chartCard),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: accountList),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chartCard,
            const SizedBox(height: 16),
            accountList,
          ],
        );
      },
    );
  }

  Widget _openDirectoryButton() => OutlinedButton.icon(
        key: const Key('dashboard-open-users'),
        onPressed: onOpen,
        icon: const Icon(Icons.people_alt_rounded),
        label: const Text('Open user directory'),
      );

  Widget _registeredAccountCard(
    BuildContext context,
    Map<String, dynamic> user,
    ColorScheme colors,
  ) {
    final name = (user['name'] ?? 'Unnamed user').toString().trim();
    final accountId = user['id'] ?? name;
    final role = (user['role'] ?? 'Member').toString().trim();
    final accountNumber = (user['accountNo'] ?? 'Not assigned').toString();
    final email = (user['email'] ?? '').toString();
    final reportAccess = [
      ('Daily', 'dailyAccess'),
      ('Weekly', 'weeklyAccess'),
      ('Monthly', 'monthlyAccess'),
    ].map((report) {
      final value = user[report.$2];
      final enabled =
          value == null || value.toString().toLowerCase() != 'false';
      return '${report.$1} ${enabled ? 'On' : 'Off'}';
    }).join(' · ');
    return Card(
      key: Key('registered-account-card-$accountId'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _registeredAccountField(
              context,
              'Member Name',
              name.isEmpty ? 'Unnamed user' : name,
              key: Key('registered-account-$accountId'),
              valueColor: colors.onSurface,
              isEmphasized: true,
            ),
            const SizedBox(height: 6),
            _registeredAccountField(
              context,
              'Email Id',
              email.isEmpty ? 'Not provided' : email,
              key: Key('registered-account-email-$accountId'),
            ),
            const SizedBox(height: 4),
            _registeredAccountField(
              context,
              'Member ID',
              accountNumber,
              key: Key('registered-account-number-$accountId'),
            ),
            const SizedBox(height: 4),
            _registeredAccountField(
              context,
              'Role',
              role.isEmpty ? 'Member' : role,
              key: Key('registered-account-role-$accountId'),
              valueColor: portalRoleColor(role),
              isEmphasized: true,
            ),
            const SizedBox(height: 4),
            _registeredAccountField(
              context,
              'Reports',
              reportAccess,
              key: Key('registered-account-reports-$accountId'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registeredAccountField(
    BuildContext context,
    String label,
    String value, {
    Key? key,
    Color? valueColor,
    bool isEmphasized = false,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              key: key,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: valueColor,
                    fontWeight: isEmphasized ? FontWeight.w800 : null,
                  ),
            ),
          ),
        ],
      );

  DataRow _registeredAccountRow({
    required BuildContext context,
    required Map<String, dynamic> user,
    required ColorScheme colors,
  }) {
    final name = (user['name'] ?? 'Unnamed user').toString().trim();
    final role = (user['role'] ?? 'Member').toString().trim();
    final accountId = user['id'] ?? name;
    final reportAccess = [
      ('Daily', 'dailyAccess'),
      ('Weekly', 'weeklyAccess'),
      ('Monthly', 'monthlyAccess'),
    ].map((report) {
      final value = user[report.$2];
      final enabled =
          value == null || value.toString().toLowerCase() != 'false';
      return '${report.$1} ${enabled ? 'On' : 'Off'}';
    }).join(' · ');
    final roleColor = portalRoleColor(role);

    return DataRow(
      cells: [
        DataCell(
          Text(
            name.isEmpty ? 'Unnamed user' : name,
            key: Key('registered-account-$accountId'),
          ),
        ),
        DataCell(
          Text(
            (user['email'] ?? '').toString().isEmpty
                ? 'Not provided'
                : user['email'].toString(),
            key: Key('registered-account-email-$accountId'),
          ),
        ),
        DataCell(
          Text(
            (user['accountNo'] ?? 'Not assigned').toString(),
            key: Key('registered-account-number-$accountId'),
          ),
        ),
        DataCell(
          Text(
            role.isEmpty ? 'Member' : role,
            key: Key('registered-account-role-$accountId'),
            style: TextStyle(
              color: roleColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        DataCell(
          Text(
            reportAccess,
            key: Key('registered-account-reports-$accountId'),
          ),
        ),
      ],
    );
  }
}

class _RolePieChart extends StatelessWidget {
  const _RolePieChart({
    required this.roles,
    required this.counts,
    required this.total,
    required this.colors,
  });

  final List<String> roles;
  final Map<String, int> counts;
  final int total;
  final Map<String, Color> colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = [
      for (final role in roles)
        if ((counts[role] ?? 0) > 0)
          _RolePieSegment(
            role: role,
            count: counts[role]!,
            color: colors[role.toLowerCase()] ?? colors['other']!,
          ),
    ];
    final description = roles.map((role) {
      final count = counts[role] ?? 0;
      final share = total == 0 ? 0 : (count * 100 / total).round();
      return '$role $count, $share percent';
    }).join('; ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final chart = Semantics(
          key: const Key('registered-accounts-pie'),
          label: 'Account role pie chart. $description',
          child: SizedBox(
            width: 156,
            height: 156,
            child: CustomPaint(
              painter: _RolePiePainter(segments: segments, total: total),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      key: const Key('registered-accounts-pie-total'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'accounts',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final legend = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in roles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[role.toLowerCase()] ?? colors['other'],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        role,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${counts[role] ?? 0}',
                      key: Key('registered-role-count-${role.toLowerCase()}'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${total == 0 ? 0 : ((counts[role] ?? 0) * 100 / total).round()}%',
                        key: Key('registered-role-share-${role.toLowerCase()}'),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

        if (constraints.maxWidth >= 440) {
          return Row(
            children: [
              chart,
              const SizedBox(width: 20),
              Expanded(child: legend),
            ],
          );
        }
        return Column(
          children: [
            chart,
            const SizedBox(height: 8),
            legend,
          ],
        );
      },
    );
  }
}

class _RolePieSegment {
  const _RolePieSegment({
    required this.role,
    required this.count,
    required this.color,
  });

  final String role;
  final int count;
  final Color color;
}

class _RolePiePainter extends CustomPainter {
  const _RolePiePainter({required this.segments, required this.total});

  final List<_RolePieSegment> segments;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || segments.isEmpty) return;
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: side / 2,
    );
    var startAngle = -math.pi / 2;
    for (final segment in segments) {
      final sweepAngle = (segment.count / total) * math.pi * 2;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _RolePiePainter oldDelegate) =>
      total != oldDelegate.total ||
      segments.length != oldDelegate.segments.length ||
      segments.indexed.any((entry) {
        final oldSegment = oldDelegate.segments[entry.$1];
        final segment = entry.$2;
        return segment.role != oldSegment.role ||
            segment.count != oldSegment.count ||
            segment.color != oldSegment.color;
      });
}

class _SourceErrorCard extends StatelessWidget {
  const _SourceErrorCard({required this.source, required this.message});

  final String source;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text('$source data unavailable'),
          subtitle: Text(message),
        ),
      );
}

num _number(dynamic value) => num.tryParse(value?.toString() ?? '') ?? 0;

num _sum(List<Map<String, dynamic>> records, String field) =>
    records.fold<num>(0, (total, record) => total + _number(record[field]));

String _currency(num amount) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(amount);
