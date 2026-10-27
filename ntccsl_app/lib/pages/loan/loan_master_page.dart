import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/portal_loading.dart';
import '../../widgets/portal_widgets.dart';
import 'loan_calculations.dart';

class LoanMasterPage extends StatefulWidget {
  const LoanMasterPage({
    super.key,
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;

  @override
  State<LoanMasterPage> createState() => _LoanMasterPageState();
}

class _LoanMasterPageState extends State<LoanMasterPage> {
  late Future<List<Map<String, dynamic>>> _schemes;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _schemes = widget.apiService.fetchLoanSchemes(
      session: widget.session,
      includeInactive: _isAdmin,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _schemes;
  }

  Future<void> _refreshAfterChange() async {
    final refreshed = widget.apiService.fetchLoanSchemes(
      session: widget.session,
      includeInactive: _isAdmin,
    );
    if (mounted) {
      setState(() {
        _schemes = refreshed;
      });
    }
    try {
      await refreshed;
    } catch (error) {
      if (mounted) {
        showPortalToast(
          context,
          'Could not refresh loan schemes: $error',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PortalGradientBackground(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              children: [
                _loanMasterHeader(),
                _schemeOverview(),
              ],
            ),
          ),
        ),
      );

  Widget _loanMasterHeader() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('loan-master-header'),
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: portalAccentHeaderGradient(
            context,
            accent: colors.primary,
            blend: .62,
          ),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: .18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRODUCT CONFIGURATION',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: .76),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Loan Master',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Set clear terms for Personal and Gold Loan products.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: .88),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _schemeOverview() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _schemes,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const PortalLoadingState(
              key: Key('loan-scheme-loading'),
              label: 'Loading loan schemes',
            );
          }
          if (snapshot.hasError) {
            return Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Could not load loan schemes.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            snapshot.error.toString(),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retry loading schemes',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: () => setState(_load),
                    ),
                  ],
                ),
              ),
            );
          }
          final schemes = snapshot.data ?? const <Map<String, dynamic>>[];
          final activeCount =
              schemes.where((scheme) => scheme['active'] != false).length;
          return Container(
            key: const Key('loan-scheme-overview'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your loan products',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (_isAdmin)
                      IconButton.filledTonal(
                        key: const Key('add-loan-scheme-overview'),
                        tooltip: 'Add loan scheme',
                        onPressed: () async {
                          await _showSchemeForm();
                          if (mounted) await _refreshAfterChange();
                        },
                        icon: const Icon(Icons.add_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${schemes.length} ${schemes.length == 1 ? 'scheme' : 'schemes'} configured',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _schemeMetric(
                        'Total schemes',
                        '${schemes.length}',
                        Icons.layers_rounded,
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _schemeMetric(
                        'Active',
                        '$activeCount',
                        Icons.verified_rounded,
                        portalToastSuccessColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (schemes.isEmpty)
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.account_balance_outlined,
                            size: 38,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No loan schemes yet',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isAdmin
                                ? 'Add a scheme to set eligibility for new loan applications.'
                                : 'Loan schemes will appear here when available.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (var index = 0; index < schemes.length; index++) ...[
                    if (index > 0) const SizedBox(height: 12),
                    _schemeCard(schemes[index]),
                  ],
              ],
            ),
          );
        },
      );

  Widget _schemeMetric(
    String label,
    String value,
    IconData icon,
    Color accent,
  ) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: .16)),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _schemeCard(Map<String, dynamic> scheme) {
    final active = scheme['active'] != false;
    final isGold = scheme['loanType'] == 'gold';
    final colors = Theme.of(context).colorScheme;
    final accent = isGold ? const Color(0xFFB7791F) : colors.primary;
    final statusColor =
        active ? portalToastSuccessColor : portalToastErrorColor;
    final schemeId = scheme['schemeId']?.toString() ?? '';
    return Card(
      key: Key('loan-scheme-overview-$schemeId'),
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 5, color: accent),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: accent.withValues(alpha: .12),
                      child: Icon(
                        isGold ? Icons.diamond_outlined : Icons.person_outline,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scheme['schemeName']?.toString() ?? '',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${isGold ? 'Gold' : 'Personal'} Loan · '
                            '${loanCalculationMethodLabel(scheme['calculationMethod']?.toString() ?? 'fixed_emi')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      key: Key('loan-scheme-status-$schemeId'),
                      avatar: Icon(
                        active
                            ? Icons.check_circle_rounded
                            : Icons.pause_circle,
                        size: 16,
                        color: statusColor,
                      ),
                      label: Text(active ? 'Active' : 'Inactive'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: statusColor.withValues(alpha: .09),
                      side: BorderSide(
                        color: statusColor.withValues(alpha: .4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columnCount = constraints.maxWidth >= 600 ? 4 : 2;
                    const gap = 8.0;
                    final tileWidth =
                        (constraints.maxWidth - gap * (columnCount - 1)) /
                            columnCount;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        SizedBox(
                          width: tileWidth,
                          child: _schemeDetail(
                            'Loan amount',
                            '${_money(_number(scheme['minAmount']))} – ${_money(_number(scheme['maxAmount']))}',
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _schemeDetail(
                            'Annual rate',
                            '${scheme['minAnnualRate']}–${scheme['maxAnnualRate']}%',
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _schemeDetail(
                            'Term',
                            '${scheme['minTenureYears']}–${scheme['maxTenureYears']} years',
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _schemeDetail(
                            'Fees',
                            'File ${scheme['fileChargePercent'] ?? 0}% · '
                                'Processing ${scheme['processingFeePercent'] ?? 0}%',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 14),
                  Divider(height: 1, color: colors.outlineVariant),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Scheme controls',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            key: Key('edit-loan-scheme-$schemeId'),
                            style: TextButton.styleFrom(
                              foregroundColor: portalEditColor,
                            ),
                            onPressed: () async {
                              await _showSchemeForm(scheme: scheme);
                              if (mounted) await _refreshAfterChange();
                            },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                          TextButton.icon(
                            key: Key('delete-loan-scheme-$schemeId'),
                            onPressed: () async {
                              if (await _deleteScheme(scheme)) {
                                await _refreshAfterChange();
                              }
                            },
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: colors.error,
                            ),
                            label: Text(
                              'Delete',
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _schemeDetail(String label, String value) => Container(
        constraints: const BoxConstraints(minHeight: 66),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

  Future<bool?> _showSchemeForm({Map<String, dynamic>? scheme}) async {
    if (!_isAdmin) return false;
    final editing = scheme != null;
    final controllers = <String, TextEditingController>{
      'name': TextEditingController(
        text: scheme?['schemeName']?.toString() ?? '',
      ),
      'minRate': TextEditingController(
        text: scheme?['minAnnualRate']?.toString() ?? '18',
      ),
      'maxRate': TextEditingController(
        text: scheme?['maxAnnualRate']?.toString() ?? '37',
      ),
      'minAmount': TextEditingController(
        text: scheme?['minAmount']?.toString() ?? '1',
      ),
      'maxAmount': TextEditingController(
        text: scheme?['maxAmount']?.toString() ?? '1000000000',
      ),
      'minYears': TextEditingController(
        text: scheme?['minTenureYears']?.toString() ?? '1',
      ),
      'maxYears': TextEditingController(
        text: scheme?['maxTenureYears']?.toString() ?? '7',
      ),
      'fileFee': TextEditingController(
        text: scheme?['fileChargePercent']?.toString() ?? '0',
      ),
      'processingFee': TextEditingController(
        text: scheme?['processingFeePercent']?.toString() ?? '0',
      ),
    };
    final formKey = GlobalKey<FormState>();
    var loanType = scheme?['loanType']?.toString() ?? 'personal';
    var calculationMethod =
        scheme?['calculationMethod']?.toString() ?? 'fixed_emi';
    if (!['fixed_emi', 'interest_only'].contains(calculationMethod)) {
      calculationMethod = 'fixed_emi';
    }
    var active = scheme?['active'] != false;
    var saving = false;
    String? error;

    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colors = Theme.of(context).colorScheme;
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
            title: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    editing
                        ? Icons.edit_note_rounded
                        : Icons.add_business_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing ? 'Edit loan scheme' : 'New loan scheme',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        editing
                            ? 'Update product terms and eligibility.'
                            : 'Configure a product for loan applications.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 620,
              height: MediaQuery.sizeOf(context).height * .68,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _formSection(
                        context,
                        icon: Icons.category_outlined,
                        title: 'Product details',
                        subtitle:
                            'Choose the loan category and repayment plan.',
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final fields = <Widget>[
                              TextFormField(
                                key: const Key('scheme-name'),
                                controller: controllers['name'],
                                decoration: _schemeInputDecoration(
                                  context,
                                  'Scheme name',
                                  Icons.sell_outlined,
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Enter a scheme name'
                                        : null,
                              ),
                              DropdownButtonFormField<String>(
                                key: const Key('scheme-loan-type'),
                                initialValue: loanType,
                                isExpanded: true,
                                decoration: _schemeInputDecoration(
                                  context,
                                  'Loan type',
                                  Icons.account_balance_outlined,
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
                                    : (value) => setDialogState(() {
                                          loanType = value ?? loanType;
                                          if (loanType == 'personal') {
                                            calculationMethod = 'fixed_emi';
                                          }
                                        }),
                              ),
                              if (loanType == 'gold')
                                DropdownButtonFormField<String>(
                                  key: const Key('scheme-calculation-method'),
                                  initialValue: calculationMethod,
                                  isExpanded: true,
                                  decoration: _schemeInputDecoration(
                                    context,
                                    'Gold repayment method',
                                    Icons.autorenew_rounded,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'fixed_emi',
                                      child: Text(
                                        'Fixed EMI (principal + interest)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'interest_only',
                                      child: Text(
                                        'Interest EMI (principal due at the end)',
                                      ),
                                    ),
                                  ],
                                  onChanged: saving
                                      ? null
                                      : (value) => setDialogState(
                                            () => calculationMethod =
                                                value ?? calculationMethod,
                                          ),
                                ),
                            ];
                            return _formGrid(constraints.maxWidth, fields);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _formSection(
                        context,
                        icon: Icons.rule_folder_outlined,
                        title: 'Eligibility limits',
                        subtitle:
                            'Set the allowed annual rate, amount, and term range.',
                        child: LayoutBuilder(
                          builder: (context, constraints) => _formGrid(
                            constraints.maxWidth,
                            [
                              _numberField(
                                'scheme-min-rate',
                                'Minimum annual rate (18–37%)',
                                controllers['minRate']!,
                                icon: Icons.percent_rounded,
                              ),
                              _numberField(
                                'scheme-max-rate',
                                'Maximum annual rate (18–37%)',
                                controllers['maxRate']!,
                                icon: Icons.percent_rounded,
                              ),
                              _numberField(
                                'scheme-min-amount',
                                'Minimum amount',
                                controllers['minAmount']!,
                                icon: Icons.south_west_rounded,
                              ),
                              _numberField(
                                'scheme-max-amount',
                                'Maximum amount',
                                controllers['maxAmount']!,
                                icon: Icons.north_east_rounded,
                              ),
                              _numberField(
                                'scheme-min-years',
                                'Minimum period (1–7 years)',
                                controllers['minYears']!,
                                integer: true,
                                icon: Icons.calendar_today_outlined,
                              ),
                              _numberField(
                                'scheme-max-years',
                                'Maximum period (1–7 years)',
                                controllers['maxYears']!,
                                integer: true,
                                icon: Icons.event_available_outlined,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _formSection(
                        context,
                        icon: Icons.receipt_long_outlined,
                        title: 'Charges and availability',
                        subtitle:
                            'Define application charges and whether this product is available.',
                        child: Column(
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) => _formGrid(
                                constraints.maxWidth,
                                [
                                  _numberField(
                                    'scheme-file-charge-percent',
                                    'File charge (%)',
                                    controllers['fileFee']!,
                                    icon: Icons.description_outlined,
                                  ),
                                  _numberField(
                                    'scheme-processing-fee-percent',
                                    'Processing fee (%)',
                                    controllers['processingFee']!,
                                    icon: Icons.percent_rounded,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: CheckboxListTile(
                                key: const Key('scheme-active'),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                title: const Text(
                                  'Active',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Available for new loan applications',
                                ),
                                value: active,
                                onChanged: saving
                                    ? null
                                    : (value) => setDialogState(
                                          () => active = value ?? false,
                                        ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          key: const Key('scheme-form-error'),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 20,
                                color: colors.onErrorContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
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
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                key: const Key('save-loan-scheme'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final minRate =
                            double.parse(controllers['minRate']!.text.trim());
                        final maxRate =
                            double.parse(controllers['maxRate']!.text.trim());
                        final minAmount =
                            double.parse(controllers['minAmount']!.text.trim());
                        final maxAmount =
                            double.parse(controllers['maxAmount']!.text.trim());
                        final minYears =
                            int.parse(controllers['minYears']!.text.trim());
                        final maxYears =
                            int.parse(controllers['maxYears']!.text.trim());
                        final fileFee =
                            double.parse(controllers['fileFee']!.text.trim());
                        final processingFee = double.parse(
                          controllers['processingFee']!.text.trim(),
                        );
                        if (minRate < 18 ||
                            maxRate > 37 ||
                            minRate > maxRate ||
                            minAmount < 1 ||
                            maxAmount > 1000000000 ||
                            minAmount > maxAmount ||
                            minYears < 1 ||
                            maxYears > 7 ||
                            minYears > maxYears) {
                          setDialogState(() {
                            error =
                                'Rates, amounts, or loan terms are outside the allowed scheme limits.';
                          });
                          return;
                        }
                        if (fileFee > 100 ||
                            processingFee > 100 ||
                            fileFee + processingFee > 100) {
                          setDialogState(() {
                            error =
                                'File charge and processing fee cannot exceed 100% combined.';
                          });
                          return;
                        }
                        setDialogState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final success =
                              await widget.apiService.sendPostRequest({
                            'action':
                                editing ? 'editLoanScheme' : 'addLoanScheme',
                            if (editing) 'schemeId': scheme['schemeId'],
                            'schemeName': controllers['name']!.text.trim(),
                            'loanType': loanType,
                            'minAnnualRate': minRate,
                            'maxAnnualRate': maxRate,
                            'minAmount': minAmount,
                            'maxAmount': maxAmount,
                            'minTenureYears': minYears,
                            'maxTenureYears': maxYears,
                            'calculationMethod': loanType == 'gold'
                                ? calculationMethod
                                : 'fixed_emi',
                            'fileChargePercent': fileFee,
                            'processingFeePercent': processingFee,
                            'active': active,
                          }, widget.session);
                          if (!success) {
                            throw const ApiException(
                              'The server did not save the loan scheme.',
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
                            error = 'Could not save the scheme: $exception';
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
                        editing ? Icons.save_outlined : Icons.add_rounded,
                      ),
                label: Text(
                  saving
                      ? 'Saving...'
                      : editing
                          ? 'Save changes'
                          : 'Add scheme',
                ),
              ),
            ],
          );
        },
      ),
    );
    final saved = await Navigator.of(context).push(route);
    await route.completed;
    for (final controller in controllers.values) {
      controller.dispose();
    }
    return saved;
  }

  Widget _numberField(
    String key,
    String label,
    TextEditingController controller, {
    bool integer = false,
    required IconData icon,
  }) =>
      TextFormField(
        key: Key(key),
        controller: controller,
        keyboardType:
            TextInputType.numberWithOptions(decimal: !integer, signed: false),
        decoration: _schemeInputDecoration(context, label, icon),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty ||
              (integer ? int.tryParse(text) : double.tryParse(text)) == null) {
            return integer ? 'Enter a whole number' : 'Enter a valid number';
          }
          if (double.parse(text) < 0) return 'Value cannot be negative';
          return null;
        },
      );

  InputDecoration _schemeInputDecoration(
    BuildContext context,
    String label,
    IconData icon,
  ) {
    final colors = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 19),
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.primary, width: 1.6),
      ),
    );
  }

  Widget _formSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 29),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _formGrid(double maxWidth, List<Widget> fields) {
    const gap = 10.0;
    final columns = maxWidth >= 480 ? 2 : 1;
    final fieldWidth =
        columns == 1 ? maxWidth : (maxWidth - gap * (columns - 1)) / columns;
    return Wrap(
      spacing: gap,
      runSpacing: 12,
      children: [
        for (final field in fields) SizedBox(width: fieldWidth, child: field),
      ],
    );
  }

  Future<bool> _deleteScheme(Map<String, dynamic> scheme) async {
    if (!_isAdmin) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          icon: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: colors.onErrorContainer,
            ),
          ),
          title: const Text(
            'Delete loan scheme?',
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You are about to delete',
                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                scheme['schemeName']?.toString() ?? 'this scheme',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.errorContainer.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 19,
                      color: colors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Existing loans may prevent deletion. This action cannot be undone.',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep scheme'),
            ),
            FilledButton.icon(
              key: Key('confirm-delete-scheme-${scheme['schemeId']}'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete scheme'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return false;
    try {
      final deleted = await widget.apiService.sendPostRequest({
        'action': 'deleteLoanScheme',
        'schemeId': scheme['schemeId'],
      }, widget.session);
      if (!deleted) {
        throw const ApiException('The server did not delete the loan scheme.');
      }
      return true;
    } on ApiException catch (error) {
      if (mounted) showPortalToast(context, error.message, isError: true);
    } catch (error) {
      if (mounted) {
        showPortalToast(context, 'Could not delete the loan scheme: $error',
            isError: true);
      }
    }
    return false;
  }

  double _number(dynamic value) => double.tryParse('$value') ?? 0;

  String _money(double value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);
}
