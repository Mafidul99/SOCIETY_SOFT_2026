import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

const int maxDepositTenureMonths = 120;

DateTime depositMaturityDate(DateTime startDate, int tenureMonths) {
  final monthIndex = startDate.month - 1 + tenureMonths;
  final year = startDate.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final day = startDate.day.clamp(1, DateUtils.getDaysInMonth(year, month));
  return DateTime(year, month, day);
}

List<DateTime> depositPeriodDates({
  required DateTime startDate,
  required DateTime maturityDate,
  required String cadence,
}) {
  final dates = <DateTime>[];
  if (cadence == 'monthly') {
    for (var period = 1; period <= maxDepositTenureMonths; period++) {
      final date = depositMaturityDate(startDate, period);
      if (date.isAfter(maturityDate)) break;
      dates.add(date);
    }
    return dates;
  }
  final interval = cadence == 'weekly' ? 7 : 1;
  for (var date = DateTime(
    startDate.year,
    startDate.month,
    startDate.day + interval,
  );
      !date.isAfter(maturityDate);
      date = DateTime(date.year, date.month, date.day + interval)) {
    dates.add(date);
  }
  return dates;
}

double depositMaturityAmount({
  required String product,
  required String cadence,
  required double amount,
  required double annualRate,
  required int tenureMonths,
  required int periodCount,
}) {
  final rate = annualRate / 100;
  if (product == 'FD') {
    return (amount * _power(1 + rate / 12, tenureMonths) * 100).round() / 100;
  }
  if (product == 'DRD' && cadence == 'daily') {
    final contributions = amount * periodCount;
    final maturity = contributions * (1 + rate * tenureMonths / 12);
    return (maturity * 100).round() / 100;
  }
  final periodsPerYear = cadence == 'daily'
      ? 365
      : cadence == 'weekly'
          ? 52
          : 12;
  final periodRate = rate / periodsPerYear;
  final maturity = periodRate == 0
      ? amount * periodCount
      : amount * (_power(1 + periodRate, periodCount) - 1) / periodRate;
  return (maturity * 100).round() / 100;
}

double _power(double base, int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= base;
  }
  return value;
}

class DepositAccountPage extends StatefulWidget {
  const DepositAccountPage({
    super.key,
    required this.apiService,
    required this.session,
    required this.product,
    required this.cadence,
    this.onSchedulePayment,
  });

  final ApiService apiService;
  final AuthSession session;
  final String product;
  final String cadence;
  final SchedulePaymentCallback? onSchedulePayment;

  @override
  State<DepositAccountPage> createState() => _DepositAccountPageState();
}

class _DepositAccountPageState extends State<DepositAccountPage> {
  late Future<List<Map<String, dynamic>>> _accounts;
  final _searchController = TextEditingController();
  final _memberController = TextEditingController();
  final _amountController = TextEditingController();
  final _rateController = TextEditingController();
  final _tenureController = TextEditingController(text: '12');
  final Set<String> _deletingAccountIds = {};
  bool _isRefreshing = false;
  String _query = '';

  bool get _canAddAccount =>
      widget.session.hasPermission('deposit_add') &&
      widget.session.role.toLowerCase() != 'member';
  bool get _canEditAccount =>
      widget.session.hasPermission('deposit_edit') &&
      widget.session.role.toLowerCase() != 'member';
  bool get _canDeleteAccount =>
      widget.session.hasPermission('deposit_delete') &&
      widget.session.role.toLowerCase() != 'member';
  bool get _canUpdatePayments =>
      widget.session.hasPermission('deposit_update') &&
      widget.session.role.toLowerCase() != 'member';
  bool get _canPayWithCashfree =>
      widget.session.role.toLowerCase() == 'member' ||
      widget.session.hasPermission('shared_data_read') ||
      widget.session.hasPermission('user_view');

  String get _productName => switch (widget.product) {
        'FD' => 'Fixed Deposit',
        'RD' => 'Recurring Deposit',
        _ => 'Daily Recurring Deposit',
      };

  String get _amountName =>
      widget.product == 'FD' ? 'Principal' : 'Installment';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _memberController.dispose();
    _amountController.dispose();
    _rateController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  void _load() {
    _accounts = widget.apiService.fetchDepositAccounts(
      product: widget.product,
      cadence: widget.cadence,
      session: widget.session,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      _load();
    });
    try {
      await _accounts;
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canAddAccount
          ? FloatingActionButton.extended(
              key: const Key('add-deposit-account'),
              onPressed: _showAccountForm,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New account'),
            )
          : null,
      body: PortalGradientBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PortalPageHeader(
                title: '$_productName — ${_capitalize(widget.cadence)}',
                subtitle: widget.product == 'FD'
                    ? 'One-time principal with monthly compounding.'
                    : 'Track installments and estimated maturity value.',
                icon: Icons.savings_rounded,
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _accounts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return PortalLoadingState(
                      label: 'Loading ${widget.product} accounts',
                    );
                  }
                  if (snapshot.hasError) {
                    return PortalErrorState(
                      message: snapshot.error.toString(),
                      onRetry: () => setState(_load),
                    );
                  }
                  final accounts = snapshot.data;
                  if (accounts == null) {
                    return PortalErrorState(
                      message: 'The server returned no deposit account data.',
                      onRetry: () => setState(_load),
                    );
                  }
                  final visibleAccounts = accounts.where((account) {
                    if (widget.session.role.toLowerCase() == 'member' &&
                        !widget.session
                            .matchesMemberName(account['memberName'])) {
                      return false;
                    }
                    if (_query.isEmpty) return true;
                    final memberName =
                        account['memberName']?.toString().toLowerCase() ?? '';
                    return memberName.contains(_query);
                  }).toList();
                  if (accounts.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: PortalEmptyState(
                              title: 'No $_productName accounts yet',
                              subtitle: _canAddAccount
                                  ? 'Create an account to start tracking deposits.'
                                  : 'Deposit accounts will appear here when available.',
                              icon: Icons.savings_outlined,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        if (_isRefreshing)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: PortalMetricCard(
                                label: 'Deposit accounts',
                                value: '${visibleAccounts.length}',
                                icon: Icons.account_balance_rounded,
                                accent: const Color(0xFF3458D4),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PortalMetricCard(
                                label: 'Estimated maturity',
                                value: _money(visibleAccounts.fold<double>(
                                  0,
                                  (total, account) =>
                                      total +
                                      _number(account['maturityAmount']),
                                )),
                                icon: Icons.trending_up_rounded,
                                accent: const Color(0xFF078A6A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          key: const Key('deposit-account-search'),
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search member accounts',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                  ),
                          ),
                          onChanged: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (visibleAccounts.isEmpty)
                          const PortalEmptyState(
                            title: 'No matching accounts',
                            subtitle:
                                'Try another member name or clear search.',
                            icon: Icons.search_off_rounded,
                          )
                        else ...[
                          for (final account in visibleAccounts)
                            _accountCard(account),
                          const SizedBox(height: 6),
                          _DepositPortfolioChart(
                            accounts: visibleAccounts,
                            product: widget.product,
                            accent: widget.product == 'FD'
                                ? const Color(0xFF3458D4)
                                : widget.product == 'RD'
                                    ? const Color(0xFF8E24AA)
                                    : const Color(0xFF078A6A),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> account) {
    final payments = account['payments'] is List
        ? account['payments'] as List
        : const <dynamic>[];
    final paidCount = payments.where(_isPaid).length;
    final rawPaymentRows = account['paymentRows'];
    final paymentRowCount = account['paymentRowCount'] is num
        ? (account['paymentRowCount'] as num).toInt()
        : rawPaymentRows is List
            ? rawPaymentRows.length
            : payments.length;
    final amount = _number(account['amount']);
    final receivedAmount = amount * paidCount;
    final maturityAmount = _number(account['maturityAmount']);
    final accent = widget.product == 'FD'
        ? const Color(0xFF3458D4)
        : widget.product == 'RD'
            ? const Color(0xFF8E24AA)
            : const Color(0xFF078A6A);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.savings_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account['memberName']?.toString() ?? 'Unknown member',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _AccountTag(
                            label: widget.product,
                            color: accent,
                          ),
                          _AccountTag(
                            label: _capitalize(widget.cadence),
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_canEditAccount || _canDeleteAccount)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_canEditAccount)
                        IconButton(
                          key: Key('edit-deposit-${account['id']}'),
                          tooltip: 'Edit account',
                          style: IconButton.styleFrom(
                            foregroundColor: portalEditColor,
                          ),
                          onPressed: () => _showAccountForm(account: account),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (_canDeleteAccount)
                        IconButton(
                          key: Key('delete-deposit-${account['id']}'),
                          tooltip: 'Delete account',
                          style: IconButton.styleFrom(
                            foregroundColor: portalDeleteColor,
                          ),
                          onPressed:
                              _deletingAccountIds.contains('${account['id']}')
                                  ? null
                                  : () => _deleteAccount(account),
                          icon: _deletingAccountIds.contains('${account['id']}')
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: portalDeleteColor,
                                  ),
                                )
                              : const Icon(Icons.delete_outline_rounded),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AccountDetail(
                  icon: Icons.calendar_today_rounded,
                  label: 'Started',
                  value: account['startDate']?.toString() ?? '-',
                ),
                _AccountDetail(
                  icon: Icons.event_available_rounded,
                  label: 'Matures',
                  value: account['maturityDate']?.toString() ?? '-',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _AccountDetail(
                    icon: Icons.currency_rupee_rounded,
                    label: _amountName,
                    value: _money(amount),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AccountDetail(
                    icon: Icons.percent_rounded,
                    label: 'Annual rate',
                    value:
                        '${_number(account['annualRate']).toStringAsFixed(2)}%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AccountDetail(
                    icon: Icons.timelapse_rounded,
                    label: 'Tenure',
                    value: '${account['tenureMonths']} mo.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: .16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated maturity',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _money(maturityAmount),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.product != 'FD') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Installments',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$paidCount of ${payments.length} paid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: payments.isEmpty ? 0 : paidCount / payments.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$paymentRowCount payment rows',
                  key: Key('deposit-payment-row-count-${account['id']}'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total received: ${_money(receivedAmount)}',
                  key: Key('deposit-received-amount-${account['id']}'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF078A6A),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  key: Key('deposit-schedule-${account['id']}'),
                  onPressed: () => _showSchedule(account),
                  icon: const Icon(Icons.event_note_rounded),
                  label: const Text('View payment schedule'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountForm({Map<String, dynamic>? account}) async {
    final isEditing = account != null;
    if (isEditing ? !_canEditAccount : !_canAddAccount) return;
    final initialDate = isEditing
        ? DateTime.tryParse(account['startDate']?.toString() ?? '')
        : DateTime.now();
    if (initialDate == null) {
      showPortalToast(
        context,
        'This account has an invalid start date and cannot be edited.',
        isError: true,
      );
      return;
    }
    _memberController.text =
        isEditing ? account['memberName']?.toString() ?? '' : '';
    _amountController.text =
        isEditing ? account['amount']?.toString() ?? '' : '';
    _rateController.text =
        isEditing ? account['annualRate']?.toString() ?? '' : '';
    _tenureController.text =
        isEditing ? account['tenureMonths']?.toString() ?? '12' : '12';
    var startDate = DateUtils.dateOnly(initialDate);
    var saving = false;
    String? errorMessage;
    var estimate = 0.0;
    var estimatePeriods = 0;

    void updateEstimate(void Function(void Function()) setDialogState) {
      final amount = double.tryParse(_amountController.text.trim());
      final rate = double.tryParse(_rateController.text.trim());
      final tenure = int.tryParse(_tenureController.text.trim());
      if (amount == null ||
          rate == null ||
          tenure == null ||
          amount <= 0 ||
          rate < 0 ||
          rate > 100 ||
          tenure < 1 ||
          tenure > maxDepositTenureMonths) {
        setDialogState(() {
          estimate = 0;
          estimatePeriods = 0;
        });
        return;
      }
      final dates = widget.product == 'FD'
          ? const <DateTime>[]
          : depositPeriodDates(
              startDate: startDate,
              maturityDate: depositMaturityDate(startDate, tenure),
              cadence: widget.cadence,
            );
      setDialogState(() {
        estimatePeriods = dates.length;
        estimate = depositMaturityAmount(
          product: widget.product,
          cadence: widget.cadence,
          amount: amount,
          annualRate: rate,
          tenureMonths: tenure,
          periodCount: dates.length,
        );
      });
    }

    if (isEditing) {
      final amount = double.tryParse(_amountController.text.trim()) ?? 0;
      final rate = double.tryParse(_rateController.text.trim()) ?? 0;
      final tenure = int.tryParse(_tenureController.text.trim()) ?? 0;
      final dates = widget.product == 'FD'
          ? const <DateTime>[]
          : depositPeriodDates(
              startDate: startDate,
              maturityDate: depositMaturityDate(startDate, tenure),
              cadence: widget.cadence,
            );
      estimatePeriods = dates.length;
      estimate = depositMaturityAmount(
        product: widget.product,
        cadence: widget.cadence,
        amount: amount,
        annualRate: rate,
        tenureMonths: tenure,
        periodCount: dates.length,
      );
    }

    final formKey = GlobalKey<FormState>();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            '${isEditing ? 'Edit' : 'New'} $_productName account',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('deposit-start-date'),
                      onPressed: saving
                          ? null
                          : () async {
                              final selected = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (selected != null) {
                                setDialogState(
                                  () =>
                                      startDate = DateUtils.dateOnly(selected),
                                );
                                updateEstimate(setDialogState);
                              }
                            },
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text(
                        'Start date: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-member-name'),
                      controller: _memberController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Member name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a member name'
                              : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-amount'),
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '$_amountName amount',
                        prefixText: '₹ ',
                      ),
                      onChanged: (_) => updateEstimate(setDialogState),
                      validator: (value) {
                        final amount = double.tryParse(value?.trim() ?? '');
                        return amount == null || !amount.isFinite || amount <= 0
                            ? 'Enter an amount greater than zero'
                            : null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-annual-rate'),
                      controller: _rateController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Annual interest rate',
                        suffixText: '% p.a.',
                      ),
                      onChanged: (_) => updateEstimate(setDialogState),
                      validator: (value) {
                        final rate = double.tryParse(value?.trim() ?? '');
                        return rate == null ||
                                !rate.isFinite ||
                                rate < 0 ||
                                rate > 100
                            ? 'Enter a rate from 0% to 100%'
                            : null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('deposit-tenure-months'),
                      controller: _tenureController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tenure',
                        suffixText: 'months (1–120)',
                      ),
                      onChanged: (_) => updateEstimate(setDialogState),
                      validator: (value) {
                        final months = int.tryParse(value?.trim() ?? '');
                        return months == null ||
                                months < 1 ||
                                months > maxDepositTenureMonths
                            ? 'Enter a tenure from 1 to $maxDepositTenureMonths months'
                            : null;
                      },
                    ),
                    if (estimate > 0) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Estimated maturity on '
                          '${DateFormat('yyyy-MM-dd').format(depositMaturityDate(startDate, int.parse(_tenureController.text)))}: '
                          '${_money(estimate)}'
                          '${widget.product == 'FD' ? '' : ' · $estimatePeriods installments'}',
                          key: const Key('deposit-maturity-estimate'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.product == 'DRD' && widget.cadence == 'daily')
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Total scheduled contributions: '
                            '${_money(_number(_amountController.text) * estimatePeriods)}',
                            key: const Key(
                              'deposit-total-scheduled-contributions',
                            ),
                          ),
                        ),
                    ],
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Illustrative estimate only. Actual returns depend on the approved scheme terms and payment history.',
                        key: Key('deposit-estimate-disclaimer'),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        key: const Key('deposit-form-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('save-deposit-account'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final tenure = int.parse(_tenureController.text.trim());
                      final periodDates = widget.product == 'FD'
                          ? const <DateTime>[]
                          : depositPeriodDates(
                              startDate: startDate,
                              maturityDate:
                                  depositMaturityDate(startDate, tenure),
                              cadence: widget.cadence,
                            );
                      setDialogState(() {
                        saving = true;
                        errorMessage = null;
                      });
                      try {
                        final saved = await withPortalLoading(
                          context,
                          label: isEditing
                              ? 'Updating deposit account'
                              : 'Creating deposit account',
                          action: () => widget.apiService.sendPostRequest({
                            'action': isEditing
                                ? 'editDepositAccount'
                                : 'addDepositAccount',
                            if (isEditing) 'id': account['id'],
                            'memberName': _memberController.text.trim(),
                            'product': widget.product,
                            'cadence': widget.cadence,
                            'startDate':
                                DateFormat('yyyy-MM-dd').format(startDate),
                            'amount':
                                double.parse(_amountController.text.trim()),
                            'annualRate':
                                double.parse(_rateController.text.trim()),
                            'tenureMonths': tenure,
                            if (!isEditing)
                              'payments': List<bool>.filled(
                                periodDates.length,
                                false,
                              ),
                          }, widget.session),
                        );
                        if (!saved) {
                          throw const ApiException(
                            'The server did not save the deposit account.',
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } on ApiException catch (error) {
                        setDialogState(() {
                          saving = false;
                          errorMessage = error.message;
                        });
                      } catch (error) {
                        setDialogState(() {
                          saving = false;
                          errorMessage = 'Could not save the account: $error';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEditing ? 'Save changes' : 'Create account'),
            ),
          ],
        ),
      ),
    );
    if (created == true && mounted) {
      setState(_load);
      showPortalToast(
        context,
        isEditing ? 'Deposit account updated.' : 'Deposit account created.',
      );
    }
  }

  Future<void> _showSchedule(Map<String, dynamic> account) async {
    final rawDates = account['periodDates'];
    final rawPayments = account['payments'];
    if (rawDates is! List ||
        rawPayments is! List ||
        rawDates.length != rawPayments.length) {
      showPortalToast(
        context,
        'The server returned an invalid payment schedule.',
        isError: true,
      );
      return;
    }
    final dates = List<String>.from(rawDates.map((date) => date.toString()));
    final payments = List<bool>.from(rawPayments.map(_isPaid));
    final rawPaymentRows = account['paymentRows'];
    final paymentRows = List<Map<String, dynamic>>.generate(
      dates.length,
      (index) {
        if (rawPaymentRows is List &&
            index < rawPaymentRows.length &&
            rawPaymentRows[index] is Map) {
          return Map<String, dynamic>.from(rawPaymentRows[index] as Map);
        }
        return {
          'periodIndex': index + 1,
          'dueDate': dates[index],
          'installmentAmount': account['amount'],
          'paid': payments[index],
          'status': payments[index] ? 'Paid' : 'Unpaid',
        };
      },
      growable: false,
    );
    final pending = <int>{};
    final amountPaise = (_number(account['amount']) * 100).round();
    final dialogHeight =
        (MediaQuery.sizeOf(context).height * .55).clamp(280.0, 420.0);
    String? errorMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Material(
            key: const Key('deposit-schedule-header'),
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.event_note_rounded,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment schedule',
                          key: const Key('deposit-schedule-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          account['memberName']?.toString() ?? 'Unknown member',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: dialogHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: const Key('deposit-schedule-summary'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Installments paid',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          Text(
                            '${payments.where((paid) => paid).length} of ${payments.length}',
                            key: const Key('deposit-schedule-paid-count'),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Payment rows: ${account['paymentRowCount'] is num ? (account['paymentRowCount'] as num).toInt() : paymentRows.length}',
                        key: const Key('deposit-schedule-row-count'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: payments.isEmpty
                            ? 0
                            : payments.where((paid) => paid).length /
                                payments.length,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_money(_number(account['amount']))} per installment',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      errorMessage!,
                      key: const Key('deposit-schedule-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                  child: Text(
                    'Payment details',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 6),
                    itemCount: dates.length,
                    itemBuilder: (context, index) {
                      final paid = payments[index];
                      final isPending = pending.contains(index);
                      return ListTile(
                        key: Key('deposit-payment-${account['id']}-$index'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        leading: isPending
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Checkbox(
                                value: paid,
                                onChanged: !_canUpdatePayments || isPending
                                    ? null
                                    : (value) async {
                                        setDialogState(() {
                                          pending.add(index);
                                          errorMessage = null;
                                        });
                                        try {
                                          final saved = await widget.apiService
                                              .sendPostRequest({
                                            'action': 'toggleDepositPayment',
                                            'id': account['id'],
                                            'periodIndex': index + 1,
                                          }, widget.session);
                                          if (!saved) {
                                            throw const ApiException(
                                              'The server did not save this payment.',
                                            );
                                          }
                                          setDialogState(() {
                                            payments[index] = value ?? false;
                                            pending.remove(index);
                                          });
                                          if (mounted) setState(_load);
                                          if (context.mounted) {
                                            showPortalToast(
                                              context,
                                              'Installment ${index + 1} '
                                              '${value == true ? 'marked as paid' : 'marked as unpaid'}.',
                                            );
                                          }
                                        } on ApiException catch (error) {
                                          setDialogState(() {
                                            pending.remove(index);
                                            errorMessage = error.message;
                                          });
                                        } catch (error) {
                                          setDialogState(() {
                                            pending.remove(index);
                                            errorMessage =
                                                'Could not update payment: $error';
                                          });
                                        }
                                      },
                              ),
                        title: Text(
                          'Installment ${index + 1}',
                          key: Key(
                            'deposit-payment-installment-${account['id']}-$index',
                          ),
                        ),
                        subtitle: SizedBox(
                          height: 38,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _PaymentScheduleColumn(
                                  label: 'Due date',
                                  value: dates[index],
                                ),
                                _PaymentScheduleColumn(
                                  label: 'Amount',
                                  value: _money(
                                    _number(
                                      paymentRows[index]['installmentAmount'],
                                    ),
                                  ),
                                ),
                                _PaymentScheduleColumn(
                                  label: 'Paid (TRUE/FALSE)',
                                  value: paid ? 'TRUE' : 'FALSE',
                                ),
                                _PaymentScheduleColumn(
                                  label: 'Status',
                                  value: paid ? 'Paid' : 'Unpaid',
                                ),
                              ],
                            ),
                          ),
                        ),
                        trailing: Text(
                          paid ? 'Paid' : 'Unpaid',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: paid
                                        ? const Color(0xFF078A6A)
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Material(
              key: const Key('deposit-schedule-footer'),
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    if (payments.contains(false) &&
                        _canPayWithCashfree &&
                        widget.onSchedulePayment != null)
                      FilledButton.icon(
                        key: Key('pay-deposit-${account['id']}'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: pending.contains(payments.indexOf(false)) ||
                                amountPaise <= 0
                            ? null
                            : () => _payDepositInstallment(
                                  dialogContext: dialogContext,
                                  account: account,
                                  index: payments.indexOf(false),
                                  amountPaise: amountPaise,
                                ),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text('Pay next · ${_money(amountPaise / 100)}'),
                      ),
                    TextButton(
                      key: const Key('deposit-schedule-close-action'),
                      style: TextButton.styleFrom(
                        backgroundColor: portalDeleteColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount(Map<String, dynamic> account) async {
    if (!_canDeleteAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete deposit account?'),
        content: Text(
          'Delete the ${account['product']} account for '
          '${account['memberName']} and its payment history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-deposit'),
            style: FilledButton.styleFrom(
              backgroundColor: portalDeleteColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final accountId = '${account['id']}';
    setState(() => _deletingAccountIds.add(accountId));
    try {
      final deleted = await withPortalLoading(
        context,
        label: 'Deleting deposit account',
        action: () => widget.apiService.sendPostRequest({
          'action': 'deleteDepositAccount',
          'id': account['id'],
        }, widget.session),
      );
      if (!deleted) {
        throw const ApiException('The server did not delete this account.');
      }
      if (mounted) {
        setState(() {
          _deletingAccountIds.remove(accountId);
          _load();
        });
        showPortalToast(context, 'Deposit account deleted.');
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _deletingAccountIds.remove(accountId));
        showPortalToast(context, error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _deletingAccountIds.remove(accountId));
        showPortalToast(
          context,
          'Could not delete the account: $error',
          isError: true,
        );
      }
    }
  }

  Future<void> _payDepositInstallment({
    required BuildContext dialogContext,
    required Map<String, dynamic> account,
    required int index,
    required int amountPaise,
  }) async {
    final accountId = account['id']?.toString().trim() ?? '';
    final memberName = account['memberName']?.toString().trim() ?? '';
    final callback = widget.onSchedulePayment;
    if (accountId.isEmpty || memberName.isEmpty || callback == null) return;
    Navigator.of(dialogContext).pop();
    await callback(
      memberName: memberName,
      amountPaise: amountPaise,
      target: CashfreeScheduleTarget.deposit(
        depositId: accountId,
        periodIndex: index + 1,
      ),
    );
  }

  bool _isPaid(dynamic value) => value == true || value == 1;

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _money(double value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);

  String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);
}

class _DepositPortfolioChart extends StatelessWidget {
  const _DepositPortfolioChart({
    required this.accounts,
    required this.product,
    required this.accent,
  });

  final List<Map<String, dynamic>> accounts;
  final String product;
  final Color accent;

  bool _isPaid(dynamic value) => value == true || value == 1;

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _money(double value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isFixedDeposit = product == 'FD';
    final maturity = accounts.fold<double>(
      0,
      (total, account) => total + _number(account['maturityAmount']),
    );
    final principal = accounts.fold<double>(
      0,
      (total, account) => total + _number(account['amount']),
    );
    final scheduled = accounts.fold<int>(
      0,
      (total, account) =>
          total +
          (account['payments'] is List
              ? (account['payments'] as List).length
              : 0),
    );
    final paid = accounts.fold<int>(
      0,
      (total, account) =>
          total +
          (account['payments'] is List
              ? (account['payments'] as List).where(_isPaid).length
              : 0),
    );
    final progress = isFixedDeposit
        ? (maturity <= 0 ? 0.0 : (principal / maturity).clamp(0.0, 1.0))
        : (scheduled == 0 ? 0.0 : paid / scheduled);
    final growth = (maturity - principal).clamp(0.0, double.infinity);
    final description = isFixedDeposit
        ? 'Principal ${_money(principal)}; estimated growth ${_money(growth)}; estimated maturity ${_money(maturity)}.'
        : '$paid of $scheduled installments paid; ${scheduled - paid} remaining.';

    return Semantics(
      key: const Key('deposit-account-progress-chart'),
      label: description,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      isFixedDeposit
                          ? Icons.trending_up_rounded
                          : Icons.donut_small_rounded,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isFixedDeposit
                              ? 'Principal & growth'
                              : 'Installment progress',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isFixedDeposit
                              ? 'Portfolio estimate'
                              : '$paid of $scheduled installments paid',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    isFixedDeposit
                        ? '${accounts.length} ${accounts.length == 1 ? 'account' : 'accounts'}'
                        : '${(progress * 100).round()}%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 12,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: .14),
                ),
              ),
              const SizedBox(height: 12),
              if (isFixedDeposit)
                Row(
                  children: [
                    Expanded(
                      child: _ChartLegendValue(
                        color: accent,
                        label: 'Principal',
                        value: _money(principal),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ChartLegendValue(
                        color: accent.withValues(alpha: .25),
                        label: 'Estimated growth',
                        value: _money(growth),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _ChartLegendValue(
                        color: accent,
                        label: 'Paid',
                        value: '$paid installments',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ChartLegendValue(
                        color: colors.outlineVariant,
                        label: 'Remaining',
                        value: '${scheduled - paid} installments',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartLegendValue extends StatelessWidget {
  const _ChartLegendValue({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentScheduleColumn extends StatelessWidget {
  const _PaymentScheduleColumn({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 112,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 9,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ),
      );
}

class _AccountTag extends StatelessWidget {
  const _AccountTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(height: 4),
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
    );
  }
}
