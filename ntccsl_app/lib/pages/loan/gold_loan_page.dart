import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/portal_loading.dart';
import '../../widgets/portal_widgets.dart';
import 'loan_calculations.dart';

class GoldLoanPage extends StatefulWidget {
  const GoldLoanPage({
    super.key,
    required this.apiService,
    required this.session,
    this.onSchedulePayment,
  });

  final ApiService apiService;
  final AuthSession session;
  final SchedulePaymentCallback? onSchedulePayment;
  String? get loanType => 'gold';
  bool get approvedOnly => false;

  @override
  State<GoldLoanPage> createState() => _GoldLoanPageState();
}

class _GoldLoanPageState extends State<GoldLoanPage> {
  late Future<List<Map<String, dynamic>>> _loans;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';
  bool get _isCollector => widget.session.role.toLowerCase() == 'collector';
  bool get _isMember => widget.session.role.toLowerCase() == 'member';
  bool get _canAddLoan =>
      !widget.approvedOnly &&
      (_isAdmin || (_isCollector && widget.session.hasPermission('loan_add')));
  bool get _canEditLoan =>
      !widget.approvedOnly &&
      (_isAdmin || (_isCollector && widget.session.hasPermission('loan_edit')));
  bool get _canDeleteLoan =>
      !widget.approvedOnly &&
      (_isAdmin ||
          (_isCollector && widget.session.hasPermission('loan_delete')));
  bool get _canUpdateLoan =>
      !widget.approvedOnly &&
      (_isAdmin ||
          (_isCollector && widget.session.hasPermission('loan_update')));
  bool get _canUpdateLoanPayments =>
      _isAdmin || (_isCollector && widget.session.hasPermission('loan_update'));
  bool get _canPayWithCashfree =>
      _isMember ||
      widget.session.hasPermission('shared_data_read') ||
      widget.session.hasPermission('user_view');
  bool get _canApply =>
      _isMember &&
      !widget.approvedOnly &&
      widget.session.hasPermission('loan_add');
  String _approvalStatus(Map<String, dynamic> loan) {
    final value = loan['approvalStatus']?.toString().trim() ?? '';
    return switch (value.toLowerCase()) {
      'pending' => 'Pending',
      'approved' || '' => 'Approved',
      'rejected' => 'Rejected',
      _ => value,
    };
  }

  String get _title => switch (widget.loanType) {
        'personal' => 'Personal Loan',
        'gold' => 'Gold Loan',
        _ => widget.approvedOnly ? 'Approved Loans' : 'Loan Master',
      };

  Widget _loanHeroHeader(String subtitle) {
    final colors = Theme.of(context).colorScheme;
    final accent =
        widget.loanType == 'gold' ? const Color(0xFF9A650F) : colors.primary;
    final isGold = widget.loanType == 'gold';
    return Container(
      key: const Key('loan-page-header'),
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: portalAccentHeaderGradient(context, accent: accent),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  isGold
                      ? Icons.diamond_outlined
                      : Icons.person_outline_rounded,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isGold ? 'GOLD' : 'PERSONAL'} LOAN PORTFOLIO',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: .76),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .9),
                ),
          ),
        ],
      ),
    );
  }

  Widget _portfolioSnapshot({
    required List<Map<String, dynamic>> loans,
    required int visibleCount,
    required double principal,
    required double payable,
  }) {
    final colors = Theme.of(context).colorScheme;
    int countFor(String status) =>
        loans.where((loan) => _approvalStatus(loan) == status).length;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isMember) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Portfolio snapshot',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$visibleCount visible ${visibleCount == 1 ? 'record' : 'records'}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.insights_rounded, color: colors.primary),
                ],
              ),
              const SizedBox(height: 14),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 480 ? 3 : 2;
                const spacing = 8.0;
                final width =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;
                final metrics = [
                  _snapshotMetric(
                    'Principal',
                    _money(principal),
                    Icons.account_balance_wallet_outlined,
                    colors.primary,
                  ),
                  _snapshotMetric(
                    'Scheduled',
                    _money(payable),
                    Icons.payments_outlined,
                    colors.tertiary,
                    valueKey: const Key('loan-total-payable'),
                  ),
                  if (!_isMember)
                    _snapshotMetric(
                      'Approved',
                      '${countFor('Approved')}',
                      Icons.verified_outlined,
                      colors.tertiary,
                    ),
                  if (!_isMember) ...[
                    _snapshotMetric(
                      'Pending',
                      '${countFor('Pending')}',
                      Icons.hourglass_top_rounded,
                      colors.primary,
                    ),
                    _snapshotMetric(
                      'Rejected',
                      '${countFor('Rejected')}',
                      Icons.cancel_outlined,
                      colors.error,
                    ),
                  ],
                ];
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final metric in metrics)
                      SizedBox(width: width, child: metric),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _snapshotMetric(
    String label,
    String value,
    IconData icon,
    Color accent, {
    Key? valueKey,
  }) =>
      Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: accent.withValues(alpha: .15)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    key: valueKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _loans = widget.apiService.fetchLoans(
      session: widget.session,
      loanType: widget.loanType,
      approvedOnly: widget.approvedOnly,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _load();
    });
    await _loans;
  }

  Widget _dialogSectionLabel(BuildContext context, String title) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              title == 'Loan selection'
                  ? Icons.category_outlined
                  : title == 'Loan terms'
                      ? Icons.tune_rounded
                      : Icons.person_outline_rounded,
              size: 16,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _loanInputDecoration(
    BuildContext context,
    String label, {
    IconData? icon,
    String? prefixText,
    String? suffixText,
    String? helperText,
  }) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 19),
      prefixText: prefixText,
      suffixText: suffixText,
      helperText: helperText,
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    );
  }

  Widget _dialogHeading(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: (_canAddLoan || _canApply)
          ? FloatingActionButton.extended(
              key: const Key('add-loan'),
              onPressed: () => _showLoanForm(),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _canApply ? 'Apply for loan' : 'New loan',
              ),
            )
          : null,
      body: PortalGradientBackground(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _loans,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return PortalLoadingState(label: 'Loading $_title');
            }
            if (snapshot.hasError || snapshot.data == null) {
              return PortalErrorState(
                message: snapshot.error?.toString() ??
                    'The server returned no loan data.',
                onRetry: () => setState(_load),
              );
            }
            final loans = snapshot.data!
                .where(
                  (loan) =>
                      widget.loanType == null ||
                      loan['loanType']?.toString().trim().toLowerCase() ==
                          widget.loanType!.trim().toLowerCase(),
                )
                .toList(growable: false);
            final displayedLoans = widget.loanType == null
                ? loans
                : loans.where((loan) {
                    if (_isMember) return true;
                    if (_canUpdateLoan) {
                      return _approvalStatus(loan) == 'Approved';
                    }
                    if (_canEditLoan || _canDeleteLoan) return true;
                    return _approvalStatus(loan) == 'Approved';
                  }).toList(growable: false);
            final principal = displayedLoans.fold<double>(
              0,
              (total, loan) => total + _number(loan['principal']),
            );
            final outstandingPayable = displayedLoans.fold<double>(
              0,
              (total, loan) => total + _number(loan['totalPayable']),
            );
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  _loanHeroHeader(
                    widget.approvedOnly
                        ? 'View loan records approved by an Admin.'
                        : _isMember
                            ? 'Apply for a Personal or Gold Loan and track its approval status.'
                            : 'Manage Personal and Gold Loans with transparent flat-rate calculations.',
                  ),
                  if (displayedLoans.isNotEmpty)
                    _portfolioSnapshot(
                      loans: loans,
                      visibleCount: displayedLoans.length,
                      principal: principal,
                      payable: outstandingPayable,
                    ),
                  if (displayedLoans.isEmpty)
                    SizedBox(
                      height: 340,
                      child: PortalEmptyState(
                        title: 'No $_title records',
                        subtitle: _isMember
                            ? 'Apply for a loan to see your application status here.'
                            : _canAddLoan
                                ? 'Add a loan to calculate flat interest and monthly installments.'
                                : 'Loan records will appear here when available.',
                        icon: Icons.account_balance_outlined,
                      ),
                    )
                  else
                    for (final loan in displayedLoans) _loanCard(loan),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _loanCard(Map<String, dynamic> loan) {
    final type = loan['loanType']?.toString() ?? '';
    final loanName = type == 'gold' ? 'Gold Loan' : 'Personal Loan';
    final color =
        type == 'gold' ? const Color(0xFFB7791F) : const Color(0xFF3458D4);
    final status = _approvalStatus(loan);
    final statusColor = portalApprovalStatusColor(context, status);
    return Card(
      key: Key('loan-card-${loan['id']}'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  child: Icon(
                    type == 'gold'
                        ? Icons.diamond_outlined
                        : Icons.person_outline_rounded,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan['memberName']?.toString() ?? 'Borrower',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '$loanName · ${loan['schemeName'] ?? ''} · ${loan['startDate'] ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_canEditLoan)
                  IconButton(
                    key: Key('edit-loan-${loan['id']}'),
                    tooltip: 'Edit loan',
                    onPressed: () => _showLoanForm(loan: loan),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                if (_canDeleteLoan)
                  IconButton(
                    key: Key('delete-loan-${loan['id']}'),
                    tooltip: 'Delete loan',
                    onPressed: () => _deleteLoan(loan),
                    color: Theme.of(context).colorScheme.error,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                key: Key('loan-status-${loan['id']}'),
                label: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                backgroundColor: statusColor.withValues(alpha: .09),
                side: BorderSide(color: statusColor.withValues(alpha: .28)),
                avatar: Icon(
                  status == 'Pending'
                      ? Icons.hourglass_top_rounded
                      : status == 'Rejected'
                          ? Icons.cancel_outlined
                          : Icons.verified_outlined,
                  size: 18,
                  color: statusColor,
                ),
              ),
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                if (status == 'Approved' &&
                    (loan['loanNumber']?.toString().trim().isNotEmpty ?? false))
                  _detail(
                    'Loan number',
                    loan['loanNumber'].toString(),
                    key: Key('loan-number-${loan['id']}'),
                  ),
                _detail('Principal', _money(_number(loan['principal']))),
                _detail('Annual rate', '${_number(loan['annualRate'])}% p.a.'),
                _detail(
                  'Repayment method',
                  loanCalculationMethodLabel(
                    loan['repaymentMethod']?.toString() ??
                        loan['calculationMethod']?.toString() ??
                        'flat',
                  ),
                ),
                _detail('Period', '${loan['tenureYears']} years'),
                _detail(
                    'Total interest', _money(_number(loan['totalInterest']))),
                _detail(
                    loan['repaymentMethod'] == 'interest_only'
                        ? 'Monthly interest'
                        : 'Monthly installment',
                    _money(_number(loan['monthlyInstallment']))),
                if (loan['repaymentMethod'] == 'interest_only')
                  _detail(
                    'Final principal payment',
                    _money(_number(loan['principal'])),
                  ),
                _detail(
                    'Total repayment', _money(_number(loan['totalPayable']))),
                if (widget.approvedOnly ||
                    _approvalStatus(loan) == 'Approved') ...[
                  _detail(
                    'File charge (${_number(loan['fileChargePercent'])}%)',
                    _money(_number(loan['fileCharge'])),
                  ),
                  _detail(
                    'Processing fee (${_number(loan['processingFeePercent'])}%)',
                    _money(_number(loan['processingFee'])),
                  ),
                  _detail(
                    'Disbursed amount',
                    _money(_number(loan['disbursedAmount'])),
                    key: Key('loan-disbursed-${loan['id']}'),
                  ),
                ],
              ],
            ),
            if (_approvalStatus(loan) == 'Approved') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  key: Key('loan-schedule-button-${loan['id']}'),
                  onPressed: () => _showLoanSchedule(loan),
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

  Future<void> _payLoanInstallment({
    required BuildContext dialogContext,
    required String loanId,
    required String memberName,
    required int periodIndex,
    required int amountPaise,
  }) async {
    final callback = widget.onSchedulePayment;
    if (loanId.isEmpty || memberName.isEmpty || callback == null) return;
    Navigator.of(dialogContext).pop();
    await callback(
      memberName: memberName,
      amountPaise: amountPaise,
      target: CashfreeScheduleTarget.loan(
        loanId: loanId,
        periodIndex: periodIndex,
      ),
    );
  }

  Future<void> _showLoanSchedule(Map<String, dynamic> loan) async {
    final loanId = loan['id']?.toString() ?? '';
    if (loanId.isEmpty) return;
    final Map<String, dynamic> response;
    try {
      response = await widget.apiService.fetchLoanPaymentSchedule(
        loanId: loanId,
        session: widget.session,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showPortalToast(context, error.message, isError: true);
      return;
    } catch (error) {
      if (!mounted) return;
      showPortalToast(
        context,
        'Could not load the loan payment schedule: $error',
        isError: true,
      );
      return;
    }
    final rawPayments = response['payments'];
    if (rawPayments is! List || rawPayments.any((payment) => payment is! Map)) {
      if (!mounted) return;
      showPortalToast(
        context,
        'The server returned an invalid loan payment schedule.',
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    final payments = rawPayments
        .map((payment) => Map<String, dynamic>.from(payment as Map))
        .toList(growable: true);
    final memberName =
        response['memberName']?.toString().trim().isNotEmpty == true
            ? response['memberName'].toString().trim()
            : loan['memberName']?.toString().trim() ?? '';
    final pending = <int>{};
    String? errorMessage;
    final dialogHeight =
        (MediaQuery.sizeOf(context).height * .55).clamp(280.0, 420.0);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final nextUnpaidIndex =
              payments.indexWhere((payment) => payment['paid'] != true);
          final nextAmountPaise = nextUnpaidIndex < 0
              ? 0
              : (_number(payments[nextUnpaidIndex]['installmentAmount']) * 100)
                  .round();
          final paidCount =
              payments.where((payment) => payment['paid'] == true).length;
          final totalAmount = payments.fold<double>(
            0,
            (total, payment) => total + _number(payment['installmentAmount']),
          );
          final paidAmount = payments.fold<double>(
            0,
            (total, payment) =>
                total +
                (payment['paid'] == true
                    ? _number(payment['installmentAmount'])
                    : 0),
          );
          return AlertDialog(
            title: Material(
              key: const Key('loan-schedule-header'),
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
                            key: const Key('loan-schedule-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            response['memberName']?.toString() ??
                                loan['memberName']?.toString() ??
                                'Borrower',
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
                    key: const Key('loan-schedule-summary'),
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
                            const Expanded(child: Text('Installments paid')),
                            Text(
                              '$paidCount of ${payments.length}',
                              key: const Key('loan-schedule-paid-count'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Payment rows: ${payments.length}',
                          key: const Key('loan-schedule-row-count'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: payments.isEmpty
                              ? 0
                              : paidCount / payments.length,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_money(paidAmount)} received of ${_money(totalAmount)}',
                          key: const Key('loan-schedule-amount-summary'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${loanCalculationMethodLabel(response['repaymentMethod']?.toString() ?? 'fixed_emi')} · '
                          '${_money(_number(response['totalPayable']))} total repayment',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorMessage!,
                        key: const Key('loan-schedule-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                    child: Text(
                      'Payment details',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 6),
                      itemCount: payments.length,
                      itemBuilder: (context, index) {
                        final payment = payments[index];
                        final paid = payment['paid'] == true;
                        final isPending = pending.contains(index);
                        return ListTile(
                          key: Key('loan-payment-$loanId-$index'),
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
                                  onChanged: !_canUpdateLoanPayments ||
                                          isPending
                                      ? null
                                      : (value) async {
                                          setDialogState(() {
                                            pending.add(index);
                                            errorMessage = null;
                                          });
                                          try {
                                            final saved = await widget
                                                .apiService
                                                .sendPostRequest({
                                              'action': 'toggleLoanPayment',
                                              'id': loanId,
                                              'periodIndex': index + 1,
                                            }, widget.session);
                                            if (!saved) {
                                              throw const ApiException(
                                                'The server did not save this loan payment.',
                                              );
                                            }
                                            setDialogState(() {
                                              payment['paid'] = value ?? false;
                                              payment['status'] =
                                                  payment['paid'] == true
                                                      ? 'Paid'
                                                      : 'Unpaid';
                                              pending.remove(index);
                                            });
                                            if (mounted) setState(_load);
                                            if (dialogContext.mounted) {
                                              showPortalToast(
                                                context,
                                                'Payment ${index + 1} '
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
                                                  'Could not update this loan payment: $error';
                                            });
                                          }
                                        },
                                ),
                          title: Text(
                            'Installment ${index + 1}',
                            key: Key(
                              'loan-payment-installment-$loanId-$index',
                            ),
                          ),
                          subtitle: SizedBox(
                            height: 38,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _loanScheduleColumn(
                                    'Due date',
                                    payment['dueDate']?.toString() ?? '',
                                  ),
                                  _loanScheduleColumn(
                                    'Amount',
                                    _money(
                                      _number(payment['installmentAmount']),
                                    ),
                                  ),
                                  _loanScheduleColumn(
                                    'Principal',
                                    _money(_number(payment['principalAmount'])),
                                  ),
                                  _loanScheduleColumn(
                                    'Interest',
                                    _money(_number(payment['interestAmount'])),
                                  ),
                                  _loanScheduleColumn(
                                    'Paid (TRUE/FALSE)',
                                    paid ? 'TRUE' : 'FALSE',
                                  ),
                                  _loanScheduleColumn(
                                    'Status',
                                    paid ? 'Paid' : 'Unpaid',
                                    valueColor: paid
                                        ? portalToastSuccessColor
                                        : portalToastErrorColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          trailing: Text(
                            paid ? 'Paid' : 'Unpaid',
                            style: TextStyle(
                              color: paid
                                  ? portalToastSuccessColor
                                  : portalToastErrorColor,
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
                key: const Key('loan-schedule-footer'),
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      if (nextUnpaidIndex >= 0 &&
                          _canPayWithCashfree &&
                          widget.onSchedulePayment != null)
                        FilledButton.icon(
                          key: Key('pay-loan-$loanId'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: pending.contains(nextUnpaidIndex) ||
                                  nextAmountPaise <= 0 ||
                                  memberName.isEmpty
                              ? null
                              : () => _payLoanInstallment(
                                    dialogContext: dialogContext,
                                    loanId: loanId,
                                    memberName: memberName,
                                    periodIndex: nextUnpaidIndex + 1,
                                    amountPaise: nextAmountPaise,
                                  ),
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(
                            'Pay next · ${_money(nextAmountPaise / 100)}',
                          ),
                        ),
                      TextButton(
                        key: const Key('loan-schedule-close-action'),
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
          );
        },
      ),
    );
  }

  Widget _loanScheduleColumn(
    String label,
    String value, {
    Color? valueColor,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 16),
        child: SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: valueColor),
              ),
            ],
          ),
        ),
      );

  Widget _detail(String label, String value, {Key? key}) => SizedBox(
        key: key,
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 3),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Future<void> _showLoanForm({Map<String, dynamic>? loan}) async {
    final editing = loan != null;
    if (editing ? !_canEditLoan : !_canAddLoan && !_canApply) return;
    if (_isMember && editing) return;
    final List<Map<String, dynamic>> schemes;
    try {
      schemes = await widget.apiService.fetchLoanSchemes(
        session: widget.session,
      );
    } on ApiException catch (error) {
      if (mounted) showPortalToast(context, error.message, isError: true);
      return;
    } catch (error) {
      if (mounted) {
        showPortalToast(context, 'Could not load loan schemes: $error',
            isError: true);
      }
      return;
    }
    if (!mounted) return;
    if (schemes.isEmpty) {
      showPortalToast(
        context,
        'No active loan schemes are configured. Ask an administrator to check Loan_Schemes.',
        isError: true,
      );
      return;
    }
    var memberName = _isMember
        ? widget.session.name
        : editing
            ? loan['memberName']?.toString() ?? ''
            : '';
    var principalText = editing ? loan['principal']?.toString() ?? '' : '';
    var loanType =
        loan?['loanType']?.toString() ?? widget.loanType ?? 'personal';
    Map<String, dynamic>? schemeForType(String type, [String? preferredId]) {
      final options = schemes.where((scheme) => scheme['loanType'] == type);
      for (final scheme in options) {
        if (scheme['schemeId'] == preferredId) return scheme;
      }
      return options.isEmpty ? null : options.first;
    }

    final selectedScheme = schemeForType(
      loanType,
      loan?['schemeId']?.toString(),
    );
    if (selectedScheme == null) {
      showPortalToast(
        context,
        'No active ${loanType == 'gold' ? 'Gold' : 'Personal'} Loan scheme is configured.',
        isError: true,
      );
      return;
    }
    var selectedSchemeId = selectedScheme['schemeId'].toString();
    var selectedCalculationMethod = loan?['repaymentMethod']?.toString() ??
        selectedScheme['calculationMethod']?.toString() ??
        'flat';
    if (!['interest_only'].contains(selectedCalculationMethod)) {
      selectedCalculationMethod = 'fixed_emi';
    }
    var rateText = editing
        ? loan['annualRate']?.toString() ??
            selectedScheme['minAnnualRate'].toString()
        : selectedScheme['minAnnualRate'].toString();
    var tenureYears = editing
        ? _number(loan['tenureYears']).toInt()
        : (selectedScheme['minTenureYears'] as num).toInt();
    var schemeMinRate = _number(selectedScheme['minAnnualRate']);
    var schemeMaxRate = _number(selectedScheme['maxAnnualRate']);
    var schemeMinAmount = _number(selectedScheme['minAmount']);
    var schemeMaxAmount = _number(selectedScheme['maxAmount']);
    var schemeMinYears = _number(selectedScheme['minTenureYears']).toInt();
    var schemeMaxYears = _number(selectedScheme['maxTenureYears']).toInt();
    var startDate = DateTime.tryParse(loan?['startDate']?.toString() ?? '') ??
        DateUtils.dateOnly(DateTime.now());
    var saving = false;
    String? error;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
          contentPadding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          title: _dialogHeading(
            context,
            icon: Icons.account_balance_rounded,
            title: _isMember
                ? 'Apply for a loan'
                : '${editing ? 'Edit' : 'New'} loan',
            subtitle: _isMember
                ? 'Choose a scheme and review your repayment estimate.'
                : 'Enter borrower and loan details for a repayment estimate.',
          ),
          content: SizedBox(
            width: 620,
            height: MediaQuery.sizeOf(context).height * .68,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dialogSectionLabel(context, 'Loan selection'),
                    if (widget.loanType == null)
                      DropdownButtonFormField<String>(
                        key: const Key('loan-type'),
                        initialValue: loanType,
                        isExpanded: true,
                        decoration: _loanInputDecoration(
                          context,
                          'Loan type',
                          icon: Icons.account_balance_outlined,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'personal',
                            child: Text('Personal Loan'),
                          ),
                          DropdownMenuItem(
                            value: 'gold',
                            child: Text('Gold Loan'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                final type = value ?? loanType;
                                final nextScheme = schemeForType(type);
                                if (nextScheme == null) return;
                                setDialogState(() {
                                  loanType = type;
                                  selectedSchemeId =
                                      nextScheme['schemeId'].toString();
                                  selectedCalculationMethod =
                                      nextScheme['calculationMethod'] ==
                                              'interest_only'
                                          ? 'interest_only'
                                          : 'fixed_emi';
                                  schemeMinRate =
                                      _number(nextScheme['minAnnualRate']);
                                  schemeMaxRate =
                                      _number(nextScheme['maxAnnualRate']);
                                  schemeMinAmount =
                                      _number(nextScheme['minAmount']);
                                  schemeMaxAmount =
                                      _number(nextScheme['maxAmount']);
                                  schemeMinYears =
                                      _number(nextScheme['minTenureYears'])
                                          .toInt();
                                  schemeMaxYears =
                                      _number(nextScheme['maxTenureYears'])
                                          .toInt();
                                  rateText = schemeMinRate.toString();
                                  tenureYears = schemeMinYears;
                                });
                              },
                      ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: Key('loan-scheme-$loanType'),
                      initialValue: selectedSchemeId,
                      isExpanded: true,
                      decoration: _loanInputDecoration(
                        context,
                        'Loan scheme',
                        icon: Icons.description_outlined,
                      ),
                      items: [
                        for (final scheme in schemes
                            .where((scheme) => scheme['loanType'] == loanType))
                          DropdownMenuItem(
                            value: scheme['schemeId'].toString(),
                            child: Text(scheme['schemeName'].toString()),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (schemeId) {
                              final nextScheme = schemeForType(
                                loanType,
                                schemeId,
                              );
                              if (nextScheme == null) return;
                              setDialogState(() {
                                selectedSchemeId =
                                    nextScheme['schemeId'].toString();
                                selectedCalculationMethod =
                                    nextScheme['calculationMethod'] ==
                                            'interest_only'
                                        ? 'interest_only'
                                        : 'fixed_emi';
                                schemeMinRate =
                                    _number(nextScheme['minAnnualRate']);
                                schemeMaxRate =
                                    _number(nextScheme['maxAnnualRate']);
                                schemeMinAmount =
                                    _number(nextScheme['minAmount']);
                                schemeMaxAmount =
                                    _number(nextScheme['maxAmount']);
                                schemeMinYears =
                                    _number(nextScheme['minTenureYears'])
                                        .toInt();
                                schemeMaxYears =
                                    _number(nextScheme['maxTenureYears'])
                                        .toInt();
                                final currentRate =
                                    double.tryParse(rateText) ?? 0;
                                if (currentRate < schemeMinRate ||
                                    currentRate > schemeMaxRate) {
                                  rateText = schemeMinRate.toString();
                                }
                                if (tenureYears < schemeMinYears ||
                                    tenureYears > schemeMaxYears) {
                                  tenureYears = schemeMinYears;
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    _dialogSectionLabel(
                      context,
                      _isMember ? 'Applicant details' : 'Borrower details',
                    ),
                    if (_isMember)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InputDecorator(
                          decoration: _loanInputDecoration(
                            context,
                            'Applicant',
                            icon: Icons.person_outline_rounded,
                          ),
                          child: Text(widget.session.name),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const Key('loan-start-date'),
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
                                      () => startDate =
                                          DateUtils.dateOnly(selected),
                                    );
                                  }
                                },
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Loan date: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    TextFormField(
                      key: const Key('loan-borrower-name'),
                      initialValue: memberName,
                      readOnly: _isMember,
                      textCapitalization: TextCapitalization.words,
                      decoration: _loanInputDecoration(
                        context,
                        'Borrower name',
                        icon: Icons.person_outline_rounded,
                      ),
                      onChanged: (value) => memberName = value,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a borrower name'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    _dialogSectionLabel(context, 'Loan terms'),
                    TextFormField(
                      key: const Key('loan-principal'),
                      initialValue: principalText,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _loanInputDecoration(
                        context,
                        'Loan amount',
                        icon: Icons.currency_rupee_rounded,
                        prefixText: '₹ ',
                        helperText:
                            '${_money(schemeMinAmount)} to ${_money(schemeMaxAmount)}',
                      ),
                      onChanged: (value) => setDialogState(
                        () => principalText = value,
                      ),
                      validator: (value) {
                        final amount = double.tryParse(value?.trim() ?? '');
                        return amount == null ||
                                !amount.isFinite ||
                                amount < schemeMinAmount ||
                                amount > schemeMaxAmount
                            ? 'Enter an amount from ${_money(schemeMinAmount)} to ${_money(schemeMaxAmount)}'
                            : null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: Key('loan-annual-rate-$selectedSchemeId'),
                      initialValue: rateText,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _loanInputDecoration(
                        context,
                        'Annual interest rate',
                        icon: Icons.percent_rounded,
                        helperText:
                            'Allowed: $schemeMinRate–$schemeMaxRate% p.a.',
                      ),
                      onChanged: (value) => setDialogState(
                        () => rateText = value,
                      ),
                      validator: (value) {
                        final rate = double.tryParse(value?.trim() ?? '');
                        return rate == null ||
                                !rate.isFinite ||
                                rate < schemeMinRate ||
                                rate > schemeMaxRate
                            ? 'Enter a rate from $schemeMinRate% to $schemeMaxRate%'
                            : null;
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: Key('loan-tenure-years-$selectedSchemeId'),
                      initialValue: tenureYears,
                      isExpanded: true,
                      decoration: _loanInputDecoration(
                        context,
                        'Period (years)',
                        icon: Icons.calendar_month_outlined,
                      ),
                      items: [
                        for (var year = schemeMinYears;
                            year <= schemeMaxYears;
                            year++)
                          DropdownMenuItem(
                            value: year,
                            child:
                                Text('$year ${year == 1 ? 'year' : 'years'}'),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(
                                () => tenureYears = value ?? tenureYears,
                              ),
                    ),
                    const SizedBox(height: 12),
                    _estimate(
                      _number(principalText),
                      double.tryParse(rateText) ?? 0,
                      tenureYears,
                      selectedCalculationMethod,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        key: const Key('loan-form-error'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
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
            FilledButton.icon(
              key: const Key('save-loan'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final saved = await widget.apiService.sendPostRequest({
                          'action': editing ? 'editLoan' : 'addLoan',
                          if (editing) 'id': loan['id'],
                          'schemeId': selectedSchemeId,
                          'loanType': loanType,
                          'memberName': memberName.trim(),
                          'startDate':
                              DateFormat('yyyy-MM-dd').format(startDate),
                          'principal': double.parse(principalText.trim()),
                          'annualRate': double.parse(rateText.trim()),
                          'tenureYears': tenureYears,
                        }, widget.session);
                        if (!saved) {
                          throw const ApiException(
                            'The server did not save the loan.',
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } on ApiException catch (exception) {
                        setDialogState(() {
                          saving = false;
                          error = exception.message;
                        });
                      } catch (exception) {
                        setDialogState(() {
                          saving = false;
                          error = 'Could not save the loan: $exception';
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isMember
                          ? Icons.send_rounded
                          : editing
                              ? Icons.save_outlined
                              : Icons.add_rounded,
                    ),
              label: Text(
                saving
                    ? 'Saving…'
                    : _isMember
                        ? 'Submit application'
                        : editing
                            ? 'Save changes'
                            : 'Create loan',
              ),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(_load);
      showPortalToast(
        context,
        editing
            ? 'Loan updated and returned to Pending approval.'
            : _isMember
                ? 'Loan application submitted for Admin approval.'
                : 'Loan created and awaiting Admin approval.',
      );
    }
  }

  Widget _estimate(
    double principal,
    double rate,
    int years,
    String calculationMethod,
  ) {
    if (principal <= 0 || rate < 18 || rate > 37) {
      return const SizedBox.shrink();
    }
    final result = calculateLoanRepayment(
      principal: principal,
      annualRate: rate,
      tenureYears: years,
      calculationMethod: calculationMethod,
    );
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: Key(
        calculationMethod == 'interest_only'
            ? 'loan-interest-only-estimate'
            : 'loan-flat-rate-estimate',
      ),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, color: colors.primary, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Repayment estimate',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _estimateValue(
                'Flat interest',
                _money(result['totalInterest']!),
              ),
              _estimateValue(
                'Total repayment',
                _money(result['totalPayable']!),
              ),
              _estimateValue(
                calculationMethod == 'interest_only'
                    ? 'Monthly interest'
                    : 'Monthly installment',
                _money(result['monthlyInstallment']!),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            calculationMethod == 'interest_only'
                ? 'Interest is paid monthly; the full principal is due with the final payment.'
                : 'Each fixed installment includes principal and flat-rate interest.',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _estimateValue(String label, String value) => SizedBox(
        width: 145,
        child: Text(
          '$label: $value',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      );

  Future<void> _deleteLoan(Map<String, dynamic> loan) async {
    if (!_canDeleteLoan) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Delete loan?'),
        content: Text(
          'Delete the loan for ${loan['memberName']}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-delete-loan'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final deleted = await widget.apiService.sendPostRequest({
        'action': 'deleteLoan',
        'id': loan['id'],
      }, widget.session);
      if (!deleted) {
        throw const ApiException('The server did not delete the loan.');
      }
      if (mounted) {
        setState(_load);
        showPortalToast(context, 'Loan deleted.');
      }
    } on ApiException catch (error) {
      if (mounted) showPortalToast(context, error.message, isError: true);
    } catch (error) {
      if (mounted) {
        showPortalToast(context, 'Could not delete the loan: $error',
            isError: true);
      }
    }
  }

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _money(double value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);
}
