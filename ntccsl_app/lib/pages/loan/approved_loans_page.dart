import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/portal_loading.dart';
import '../../widgets/portal_widgets.dart';
import 'loan_calculations.dart';

class ApprovedLoansPage extends StatefulWidget {
  const ApprovedLoansPage({
    super.key,
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;
  String? get loanType => null;
  bool get approvedOnly => session.role.toLowerCase() != 'admin';

  @override
  State<ApprovedLoansPage> createState() => _ApprovedLoansPageState();
}

class _ApprovedLoansPageState extends State<ApprovedLoansPage> {
  late Future<List<Map<String, dynamic>>> _loans;
  final Set<String> _updatingLoanIds = {};

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';
  bool get _isMember => widget.session.role.toLowerCase() == 'member';
  bool get _canUpdateLoan => _isAdmin;
  bool get _canUpdateLoanPayments => _isAdmin;
  bool get _canAddLoan => false;
  bool get _canEditLoan => false;
  bool get _canDeleteLoan => false;
  bool get _canApply => false;
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
        _ => 'Approved Loans',
      };

  Widget _loanHeroHeader(String subtitle) {
    final colors = Theme.of(context).colorScheme;
    final isGold = widget.loanType == 'gold';
    final accent = isGold ? const Color(0xFF9A650F) : colors.primary;
    final icon = isGold
        ? Icons.diamond_outlined
        : widget.loanType == 'personal'
            ? Icons.person_outline_rounded
            : Icons.account_balance_rounded;
    final eyebrow = widget.loanType == 'gold'
        ? 'GOLD LOAN PORTFOLIO'
        : widget.loanType == 'personal'
            ? 'PERSONAL LOAN PORTFOLIO'
            : 'LOAN PORTFOLIO';
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
                child: Icon(icon, color: Colors.white, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
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
              Icon(
                Icons.trending_up_rounded,
                color: Colors.white.withValues(alpha: .48),
                size: 28,
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

  Widget _approvalSection(List<Map<String, dynamic>> loans) {
    final applications = loans.toList()
      ..sort((first, second) {
        final firstPending = _approvalStatus(first) == 'Pending';
        final secondPending = _approvalStatus(second) == 'Pending';
        if (firstPending != secondPending) return firstPending ? -1 : 1;
        return (second['createdAt']?.toString() ?? '')
            .compareTo(first['createdAt']?.toString() ?? '');
      });
    final pendingCount =
        applications.where((loan) => _approvalStatus(loan) == 'Pending').length;
    final colors = Theme.of(context).colorScheme;
    final pendingColor =
        pendingCount == 0 ? colors.tertiary : portalToastWarningColor;
    return Card(
      key: const Key('loan-approval-section'),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                    color: colors.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.fact_check_outlined,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending review',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        pendingCount == 0
                            ? 'You are all caught up.'
                            : 'Review applications and record a decision.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  key: const Key('pending-loan-count'),
                  avatar: Icon(
                    pendingCount == 0
                        ? Icons.check_circle_outline_rounded
                        : Icons.hourglass_top_rounded,
                    size: 16,
                    color: pendingColor,
                  ),
                  label: Text('$pendingCount pending'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(
                    color: pendingColor.withValues(alpha: .25),
                  ),
                  backgroundColor: pendingColor.withValues(alpha: .07),
                ),
              ],
            ),
            if (applications.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No loan applications are waiting for review.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final loan in applications) _loanApplicationCard(loan),
          ],
        ),
      ),
    );
  }

  Widget _loanApplicationCard(Map<String, dynamic> loan) {
    final id = loan['id']?.toString() ?? '';
    final status = _approvalStatus(loan);
    final pending = status == 'Pending';
    final updating = _updatingLoanIds.contains(id);
    final isGold = loan['loanType'] == 'gold';
    final statusColor = portalApprovalStatusColor(context, status);
    return Card(
      key: Key('loan-application-$id'),
      elevation: 0,
      margin: const EdgeInsets.only(top: 14),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: statusColor.withValues(alpha: .10),
                  child: Icon(
                    isGold
                        ? Icons.diamond_outlined
                        : Icons.person_outline_rounded,
                    color: statusColor,
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
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${isGold ? 'Gold' : 'Personal'} Loan'
                        '${(loan['schemeName']?.toString() ?? '').isEmpty ? '' : ' · ${loan['schemeName']}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  key: Key('application-status-$id'),
                  label: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: statusColor.withValues(alpha: .3)),
                  backgroundColor: statusColor.withValues(alpha: .07),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                if (status == 'Approved' &&
                    (loan['loanNumber']?.toString().trim().isNotEmpty ?? false))
                  _detail(
                    'Loan number',
                    loan['loanNumber'].toString(),
                    key: Key('loan-number-$id'),
                  ),
                _detail('Principal', _money(_number(loan['principal']))),
                _detail('Annual rate', '${_number(loan['annualRate'])}%'),
                _detail('Term', '${_number(loan['tenureYears'])} years'),
                _detail(
                  loan['repaymentMethod'] == 'interest_only'
                      ? 'Monthly interest'
                      : 'Monthly installment',
                  _money(_number(loan['monthlyInstallment'])),
                ),
                _detail(
                  'Total repayment',
                  _money(_number(loan['totalPayable'])),
                ),
                _detail(
                  'Applied on',
                  loan['createdAt']?.toString().isNotEmpty == true
                      ? loan['createdAt'].toString()
                      : loan['startDate']?.toString() ?? '—',
                ),
              ],
            ),
            if (pending) ...[
              Divider(
                height: 28,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Wrap(
                alignment: WrapAlignment.end,
                runAlignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: Key('reject-loan-$id'),
                    onPressed: updating
                        ? null
                        : () => _setLoanApproval(loan, 'Rejected'),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reject'),
                  ),
                  FilledButton.icon(
                    key: Key('approve-loan-$id'),
                    onPressed: updating
                        ? null
                        : () => _setLoanApproval(loan, 'Approved'),
                    icon: updating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(updating ? 'Saving…' : 'Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setLoanApproval(
    Map<String, dynamic> loan,
    String approvalStatus,
  ) async {
    if (!_canUpdateLoan) return;
    if (_approvalStatus(loan) != 'Pending') return;
    final id = loan['id']?.toString() ?? '';
    if (id.isEmpty || _updatingLoanIds.contains(id)) return;
    setState(() => _updatingLoanIds.add(id));
    try {
      final saved = await widget.apiService.sendPostRequest({
        'action': 'approveLoan',
        'id': id,
        'approvalStatus': approvalStatus,
      }, widget.session);
      if (!saved) {
        throw const ApiException('The server did not update loan approval.');
      }
      if (mounted) {
        setState(() {
          _updatingLoanIds.remove(id);
          _load();
        });
        showPortalToast(
          context,
          approvalStatus == 'Approved' ? 'Loan approved.' : 'Loan rejected.',
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _updatingLoanIds.remove(id));
        showPortalToast(context, error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _updatingLoanIds.remove(id));
        showPortalToast(context, 'Could not update loan approval: $error',
            isError: true);
      }
    }
  }

  Widget _dialogSectionLabel(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      );

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
            color: const Color(0xFFB7791F).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFFB7791F)),
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
                        fontWeight: FontWeight.w800,
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
            final loans = snapshot.data!.where(
              (loan) {
                if (_isMember &&
                    !widget.session.matchesMemberName(loan['memberName'])) {
                  return false;
                }
                if (widget.approvedOnly &&
                    _approvalStatus(loan) != 'Approved') {
                  return false;
                }
                return widget.loanType == null ||
                    loan['loanType']?.toString().trim().toLowerCase() ==
                        widget.loanType!.trim().toLowerCase();
              },
            ).toList(growable: false);
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
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  _loanHeroHeader(
                    _isMember
                        ? 'View your approved Personal and Gold Loan records.'
                        : widget.approvedOnly
                            ? 'View approved Personal and Gold Loan records.'
                            : 'View all Personal and Gold Loan applications by their current status.',
                  ),
                  if (_canUpdateLoan)
                    _approvalSection(
                      loans
                          .where((loan) => _approvalStatus(loan) == 'Pending')
                          .toList(growable: false),
                    ),
                  if (!_isAdmin)
                    for (final loan in displayedLoans)
                      _loanApplicationCard(loan),
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
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> showLoanSchedule(Map<String, dynamic> loan) async {
    final loanId = loan['id']?.toString() ?? '';
    if (loanId.isEmpty) return;
    final Map<String, dynamic> response;
    try {
      response = await withPortalLoading(
        context,
        label: 'Loading loan payment schedule',
        action: () => widget.apiService.fetchLoanPaymentSchedule(
          loanId: loanId,
          session: widget.session,
        ),
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
    final pending = <int>{};
    String? errorMessage;
    final dialogHeight =
        (MediaQuery.sizeOf(context).height * .55).clamp(280.0, 420.0);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
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
                            'EMI payment schedule',
                            key: const Key('loan-schedule-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            response['memberName']?.toString() ?? 'Borrower',
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
                            const Expanded(child: Text('Payments received')),
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
                      'Monthly payment details',
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
                            'Payment ${index + 1} · ${payment['dueDate'] ?? ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Total ${_money(_number(payment['installmentAmount']))} · '
                            'Principal ${_money(_number(payment['principalAmount']))} · '
                            'Interest ${_money(_number(payment['interestAmount']))}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: Text(
                            paid ? 'Paid' : 'Unpaid',
                            style: TextStyle(
                              color: paid
                                  ? Theme.of(context).colorScheme.tertiary
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
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

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
      schemes = await withPortalLoading(
        context,
        label: 'Loading loan schemes',
        action: () => widget.apiService.fetchLoanSchemes(
          session: widget.session,
        ),
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
            horizontal: 20,
            vertical: 24,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
            width: 520,
            child: SingleChildScrollView(
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
                        decoration:
                            const InputDecoration(labelText: 'Loan type'),
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
                      decoration:
                          const InputDecoration(labelText: 'Loan scheme'),
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
                          decoration:
                              const InputDecoration(labelText: 'Applicant'),
                          child: Text(widget.session.name),
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
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
                          icon: const Icon(Icons.calendar_today_rounded),
                          label: Text(
                            'Loan date: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                          ),
                        ),
                      ),
                    TextFormField(
                      key: const Key('loan-borrower-name'),
                      initialValue: memberName,
                      readOnly: _isMember,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Borrower name'),
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
                      decoration: InputDecoration(
                        labelText: 'Loan amount',
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
                      decoration: InputDecoration(
                        labelText: 'Annual interest rate',
                        suffixText: '% p.a. ($schemeMinRate–$schemeMaxRate)',
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
                      decoration:
                          const InputDecoration(labelText: 'Period (years)'),
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

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _money(double value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);
}
