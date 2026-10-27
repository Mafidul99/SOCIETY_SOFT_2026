import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';
import 'payment_success_page.dart';

class CashfreePaymentPage extends StatefulWidget {
  const CashfreePaymentPage({
    super.key,
    required this.apiService,
    required this.session,
    this.onPaymentVerified,
    this.fixedAmountPaise,
    this.fixedMemberName,
    this.scheduleTarget,
  });

  final ApiService apiService;
  final AuthSession session;
  final VoidCallback? onPaymentVerified;
  final int? fixedAmountPaise;
  final String? fixedMemberName;
  final CashfreeScheduleTarget? scheduleTarget;

  @override
  State<CashfreePaymentPage> createState() => _CashfreePaymentPageState();
}

class _CashfreePaymentPageState extends State<CashfreePaymentPage> {
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cashfree = CFPaymentGatewayService();
  Future<List<Map<String, dynamic>>>? _membersFuture;
  Map<String, dynamic>? _selectedMember;
  String? _activeOrderId;
  bool _processing = false;
  bool _verifying = false;

  int? get _baseAmountPaise {
    if (widget.fixedAmountPaise != null) {
      final amountPaise = widget.fixedAmountPaise!;
      return amountPaise > 0 && amountPaise <= 100000000 ? amountPaise : null;
    }
    final text = _amountController.text.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text)) return null;
    final amount = double.tryParse(text);
    if (amount == null || amount <= 0 || amount > 1000000) return null;
    return (amount * 100).round();
  }

  bool get _isFixedSchedulePayment => widget.scheduleTarget != null;

  bool get _hasValidPaymentDetails {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    return _baseAmountPaise != null &&
        RegExp(r'^\d{10}$').hasMatch(phone) &&
        name.length <= 120 &&
        (email.isEmpty ||
            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email));
  }

  int get _serviceChargePaise =>
      _baseAmountPaise == null ? 0 : (_baseAmountPaise! * 2 / 100).round();

  int get _totalPaise => (_baseAmountPaise ?? 0) + _serviceChargePaise;

  String _formatPaise(int value) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
          .format(value / 100);

  @override
  void initState() {
    super.initState();
    if (widget.fixedAmountPaise != null) {
      _amountController.text =
          (widget.fixedAmountPaise! / 100).toStringAsFixed(2);
    }
    _nameController.text = widget.session.name;
    _emailController.text = widget.session.email;
    _phoneController.text = widget.session.phoneNumber;
    _membersFuture = _isStaff ? _loadMembers() : null;
    if (_isStaff && widget.fixedMemberName != null) {
      _prefillStaffMember();
    }
    _cashfree.setCallback(_onPaymentSuccess, _onPaymentError);
  }

  bool get _isStaff =>
      const {'admin', 'collector'}.contains(widget.session.role.toLowerCase());

  Future<List<Map<String, dynamic>>> _loadMembers() async {
    final users = await widget.apiService.fetchSheetData(
      'getUsers',
      widget.session,
    );
    return (users as List)
        .whereType<Map>()
        .map((user) => Map<String, dynamic>.from(user))
        .where((user) => user['role']?.toString().toLowerCase() == 'member')
        .toList(growable: false);
  }

  Future<void> _prefillStaffMember() async {
    try {
      final members = await _membersFuture!;
      final memberName = widget.fixedMemberName!.trim().toLowerCase();
      final matches = members
          .where((member) =>
              member['name']?.toString().trim().toLowerCase() == memberName)
          .toList(growable: false);
      if (!mounted) return;
      if (matches.length != 1) return;
      final member = matches.single;
      setState(() {
        _selectedMember = member;
        _nameController.text = member['name']?.toString() ?? '';
        _emailController.text = member['email']?.toString() ?? '';
        _phoneController.text = member['phoneNumber']?.toString() ?? '';
      });
    } on ApiException catch (error) {
      if (mounted) {
        showPortalToast(context, error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        showPortalToast(
          context,
          'Could not select the scheduled Member: $error',
          isError: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _startPayment() async {
    final amountPaise = _baseAmountPaise;
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final member = _selectedMember;
    if (amountPaise == null) {
      showPortalToast(
        context,
        'Enter an amount greater than ₹0, up to ₹10,00,000, with at most 2 decimals.',
        isError: true,
      );
      return;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
      showPortalToast(context, 'Enter a valid 10-digit mobile number.',
          isError: true);
      return;
    }
    if (name.length > 120) {
      showPortalToast(context, 'Customer name is too long.', isError: true);
      return;
    }
    if (email.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      showPortalToast(context, 'Enter a valid email address or leave it blank.',
          isError: true);
      return;
    }
    if (_isStaff && member == null) {
      showPortalToast(context, 'Select a Member account first.', isError: true);
      return;
    }

    setState(() => _processing = true);
    try {
      final order = await withPortalLoading(
        context,
        label: 'Preparing secure payment',
        action: () => widget.apiService.createCashfreeOrder(
          session: widget.session,
          baseAmount: amountPaise / 100,
          customerPhone: phone,
          customerName: name,
          customerEmail: email,
          memberId: member?['id']?.toString(),
          scheduleTarget: widget.scheduleTarget,
        ),
      );
      if (!mounted) return;

      final environment = switch (order.environment) {
        'sandbox' => CFEnvironment.SANDBOX,
        'production' => CFEnvironment.PRODUCTION,
        _ => throw const ApiException('Invalid Cashfree environment.'),
      };
      final session = CFSessionBuilder()
          .setEnvironment(environment)
          .setOrderId(order.orderId)
          .setPaymentSessionId(order.paymentSessionId)
          .build();
      final checkout =
          CFWebCheckoutPaymentBuilder().setSession(session).build();
      _activeOrderId = order.orderId;
      _cashfree.setCallback(_onPaymentSuccess, _onPaymentError);
      _cashfree.doPayment(checkout);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      if (error.message.toLowerCase().contains('cashfree is not configured')) {
        await _showCashfreeConfigurationHelp();
      } else {
        showPortalToast(context, error.message, isError: true);
      }
    } on CFException catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      showPortalToast(context, error.message, isError: true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      showPortalToast(
        context,
        error.message ?? 'Could not open Cashfree checkout.',
        isError: true,
      );
    }
  }

  Future<void> _showCashfreeConfigurationHelp() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cashfree setup required'),
        content: const Text(
          'In Project Settings → Script Properties for the Apps Script project '
          'used by this app, add:\n\n'
          'CASHFREE_APP_ID — your Cashfree App ID\n'
          'CASHFREE_SECRET_KEY — your current Cashfree Secret Key\n'
          'CASHFREE_ENVIRONMENT — production (or sandbox when testing with '
          'sandbox credentials)\n\n'
          'Enter each property name as the key and its value in the Value '
          'column. Save the properties. Do not put credentials in the app or '
          'source code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseMember(List<Map<String, dynamic>> members) async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = members.where((member) {
              final search = query.trim().toLowerCase();
              if (search.isEmpty) return true;
              return [
                member['name'],
                member['email'],
                member['phoneNumber'],
              ].any(
                (value) =>
                    value?.toString().toLowerCase().contains(search) == true,
              );
            }).toList(growable: false);
            return AlertDialog(
              title: const Text('Select Member'),
              content: SizedBox(
                width: 480,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      key: const Key('cashfree-member-search'),
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Search members',
                        hintText: 'Name, email, or phone',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No matching members.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final member = filtered[index];
                                final name =
                                    member['name']?.toString().trim() ?? '';
                                return ListTile(
                                  key: Key(
                                    'cashfree-member-${member['id']}',
                                  ),
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline_rounded),
                                  ),
                                  title: Text(
                                    name.isEmpty ? 'Unnamed member' : name,
                                  ),
                                  subtitle: Text(
                                    [
                                      if (member['email']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true)
                                        member['email'].toString(),
                                      if (member['phoneNumber']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true)
                                        member['phoneNumber'].toString(),
                                    ].join(' · '),
                                  ),
                                  onTap: () => Navigator.pop(context, member),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedMember = selected;
      _nameController.text = selected['name']?.toString() ?? '';
      _emailController.text = selected['email']?.toString() ?? '';
      _phoneController.text = selected['phoneNumber']?.toString() ?? '';
    });
  }

  void _onPaymentSuccess(String orderId) {
    _verifyPayment(orderId);
  }

  void _onPaymentError(CFErrorResponse error, String orderId) {
    final callbackOrderId =
        orderId == 'order_id_not_found' ? _activeOrderId : orderId;
    if (callbackOrderId == null || callbackOrderId.isEmpty) {
      if (!mounted) return;
      setState(() => _processing = false);
      showPortalToast(
        context,
        error.getMessage() ?? 'Cashfree checkout could not be opened.',
        isError: true,
      );
      return;
    }
    _verifyPayment(callbackOrderId, checkoutError: error.getMessage());
  }

  Future<void> _verifyPayment(
    String orderId, {
    String? checkoutError,
  }) async {
    if (!mounted || orderId != _activeOrderId || _verifying) return;
    setState(() => _verifying = true);
    var shouldClearOrder = false;
    try {
      final result = await withPortalLoading(
        context,
        label: 'Confirming payment with Cashfree',
        action: () => widget.apiService.verifyCashfreePayment(
          session: widget.session,
          orderId: orderId,
        ),
      );
      if (!mounted) return;
      if (result.paid) {
        shouldClearOrder = true;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PaymentSuccessPage(
            orderId: orderId,
            amount: _formatPaise(_totalPaise),
            scheduleApplied: result.scheduleApplied,
            scheduleDescription: result.scheduleDescription,
            memberName: _isStaff
                ? (_selectedMember?['name']?.toString() ?? '')
                : widget.session.name,
          ),
        );
        widget.onPaymentVerified?.call();
      } else if (const {'EXPIRED', 'TERMINATED'}
          .contains(result.paymentStatus)) {
        shouldClearOrder = true;
        showPortalToast(
          context,
          'This payment order is ${result.paymentStatus.toLowerCase()}. You can start a new payment.',
          isError: true,
        );
      } else {
        showPortalToast(
          context,
          checkoutError == null
              ? 'Payment is ${result.paymentStatus.toLowerCase()}. Check its status again before starting another payment.'
              : 'Payment was not confirmed: $checkoutError. Check its status again before starting another payment.',
          isError: true,
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      showPortalToast(
        context,
        'Could not confirm payment status: ${error.message}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          if (shouldClearOrder) _activeOrderId = null;
          _processing = false;
          _verifying = false;
        });
      }
    }
  }

  Widget _accountDetail({
    required IconData icon,
    required String label,
    required String value,
    bool compact = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                key:
                    compact ? const Key('cashfree-selected-member-name') : null,
                value.isEmpty ? 'Not available' : value,
                style: (compact
                        ? Theme.of(context).textTheme.bodyMedium
                        : Theme.of(context).textTheme.bodyLarge)
                    ?.copyWith(
                  fontSize: compact ? 14 : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _amountLine(String label, String value, {bool emphasized = false}) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
          fontSize: emphasized ? 18 : null,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style?.copyWith(
                color: emphasized
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canPay = !_processing &&
        _activeOrderId == null &&
        _hasValidPaymentDetails &&
        (_isStaff
            ? _selectedMemberReady
            : widget.session.role.toLowerCase() == 'member');
    final pendingOrderId = _activeOrderId;
    final memberName = _isStaff
        ? (_selectedMember?['name']?.toString() ?? '')
        : widget.session.name;

    return PortalGradientBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PortalPageHeader(
                    title: 'Make a payment',
                    subtitle: 'Secure online payment with Cashfree',
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Member details',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 18),
                          if (_isStaff)
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _membersFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        snapshot.error.toString(),
                                        style: TextStyle(color: colors.error),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => setState(
                                          () => _membersFuture = _loadMembers(),
                                        ),
                                        icon: const Icon(Icons.refresh_rounded),
                                        label:
                                            const Text('Retry loading members'),
                                      ),
                                    ],
                                  );
                                }
                                final members = snapshot.data ?? [];
                                if (members.isEmpty) {
                                  return const Text(
                                    'No active Member accounts are available.',
                                  );
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (!_isFixedSchedulePayment)
                                      OutlinedButton.icon(
                                        key:
                                            const Key('cashfree-select-member'),
                                        onPressed: _processing ||
                                                _activeOrderId != null
                                            ? null
                                            : () => _chooseMember(members),
                                        icon: const Icon(
                                          Icons.person_search_rounded,
                                        ),
                                        label: Text(
                                          _selectedMember == null
                                              ? 'Search and select a Member'
                                              : 'Change selected Member',
                                        ),
                                      )
                                    else if (_selectedMember == null)
                                      Text(
                                        'Could not find the Member for this schedule. Return and retry.',
                                        style: TextStyle(color: colors.error),
                                      ),
                                    if (_selectedMember != null) ...[
                                      const SizedBox(height: 14),
                                      _accountDetail(
                                        icon: Icons.person_outline_rounded,
                                        label: 'Selected member',
                                        value: memberName,
                                        compact: true,
                                      ),
                                    ],
                                  ],
                                );
                              },
                            )
                          else ...[
                            _accountDetail(
                              icon: Icons.person_outline_rounded,
                              label: 'Member name',
                              value: widget.session.name,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment details',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const Key('cashfree-customer-name'),
                            controller: _nameController,
                            enabled: !_processing,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 120,
                            decoration: const InputDecoration(
                              labelText: 'Customer name (optional)',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('cashfree-customer-email'),
                            controller: _emailController,
                            enabled: !_processing,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Customer email (optional)',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('cashfree-payment-amount'),
                            controller: _amountController,
                            enabled: !_processing,
                            readOnly: widget.fixedAmountPaise != null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: InputDecoration(
                              labelText: widget.fixedAmountPaise == null
                                  ? 'Amount (₹)'
                                  : 'Fixed installment amount (₹)',
                              hintText: 'Enter payment amount',
                              prefixIcon: const Icon(
                                Icons.currency_rupee_rounded,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('cashfree-payment-phone'),
                            controller: _phoneController,
                            enabled: !_processing,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Customer mobile number',
                              hintText: '10-digit number for Cashfree',
                              prefixIcon: Icon(Icons.phone_android_rounded),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 18),
                          Divider(color: colors.outlineVariant),
                          _amountLine(
                            'Payment amount',
                            _baseAmountPaise == null
                                ? '—'
                                : _formatPaise(_baseAmountPaise!),
                          ),
                          _amountLine(
                            'Service charge (2%)',
                            _formatPaise(_serviceChargePaise),
                          ),
                          Divider(color: colors.outlineVariant),
                          _amountLine(
                            'Total to pay',
                            _baseAmountPaise == null
                                ? '—'
                                : _formatPaise(_totalPaise),
                            emphasized: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!canPay && !_processing && pendingOrderId == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _isStaff && _selectedMember == null
                            ? 'Select a Member account to continue.'
                            : _isStaff && !_selectedMemberReady
                                ? 'The selected Member is missing an internal ID. Contact an administrator.'
                                : _baseAmountPaise == null
                                    ? 'Enter an amount greater than ₹0 and no more than ₹10,00,000.'
                                    : !RegExp(r'^\d{10}$').hasMatch(
                                            _phoneController.text.trim())
                                        ? 'Enter a valid 10-digit mobile number.'
                                        : 'Check the customer name and email details.',
                        key: const Key('cashfree-payment-requirements'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    key: const Key('cashfree-start-payment'),
                    onPressed: canPay ? _startPayment : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: _processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_rounded),
                    label: Text(
                      _processing
                          ? _verifying
                              ? 'Verifying payment...'
                              : 'Opening secure checkout...'
                          : canPay
                              ? 'Pay ${_formatPaise(_totalPaise)} securely'
                              : 'Complete payment details',
                    ),
                  ),
                  if (pendingOrderId != null && !_processing) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('cashfree-verify-payment'),
                      onPressed: _verifying
                          ? null
                          : () => _verifyPayment(pendingOrderId),
                      icon: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _verifying
                            ? 'Verifying payment...'
                            : 'Check payment status',
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    _isStaff
                        ? 'The payment will be recorded for the selected member. A 2% service charge is added and Cashfree confirms the payment status.'
                        : 'The 2% service charge is added to your payment. Your payment status is confirmed securely with Cashfree.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: _isStaff ? 11 : null,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _selectedMemberReady {
    return _selectedMember?['id']?.toString().trim().isNotEmpty == true;
  }
}
