import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:intl/intl.dart';
import 'package:ntccsl/main.dart';
import 'package:ntccsl/pages/cashfree_payment_page.dart';
import 'package:ntccsl/pages/dashboard_page.dart';
import 'package:ntccsl/pages/deposit_account_page.dart';
import 'package:ntccsl/pages/login_page.dart';
import 'package:ntccsl/pages/loan/approved_loans_page.dart';
import 'package:ntccsl/pages/loan/gold_loan_page.dart';
import 'package:ntccsl/pages/loan/loan_calculations.dart';
import 'package:ntccsl/pages/loan/loan_master_page.dart';
import 'package:ntccsl/pages/loan/personal_loan_page.dart';
import 'package:ntccsl/pages/payment_success_page.dart';
import 'package:ntccsl/pages/profile_page.dart';
import 'package:ntccsl/pages/register_page.dart';
import 'package:ntccsl/pages/roles_permissions_page.dart';
import 'package:ntccsl/pages/splash_page.dart';
import 'package:ntccsl/pages/support_page.dart';
import 'package:ntccsl/services/api_service.dart';
import 'package:ntccsl/widgets/portal_loading.dart';
import 'package:ntccsl/widgets/portal_widgets.dart';
import 'package:ntccsl/widgets/profile_image.dart';

const _packageInfoChannel =
    MethodChannel('dev.fluttercommunity.plus/package_info');
const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

void _mockPackageInfo() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    _packageInfoChannel,
    (call) async => <String, dynamic>{
      'appName': 'ntccsl',
      'packageName': 'ntccsl',
      'version': '1.2.2',
      'buildNumber': '2',
    },
  );
}

void main() {
  test('flat-rate loan calculation uses simple interest and monthly terms', () {
    final result = calculateFlatLoan(
      principal: 100000,
      annualRate: 18,
      tenureYears: 3,
    );
    expect(result['totalInterest'], 54000);
    expect(result['totalPayable'], 154000);
    expect(result['monthlyInstallment'], 4277.78);
  });

  test('interest-only loan payments exclude principal until maturity', () {
    final result = calculateInterestOnlyLoan(
      principal: 100000,
      annualRate: 18,
      tenureYears: 1,
    );
    expect(result['totalInterest'], 18000);
    expect(result['totalPayable'], 118000);
    expect(result['monthlyInstallment'], 1500);
  });

  test('loan API requests pass the selected type and return loan records',
      () async {
    final client = _RecordingHttpClient([
      [
        {
          'id': 'gold-1',
          'memberName': 'Jordan Member',
          'loanType': ' GOLD ',
          'approvalStatus': ' approved ',
          'principal': 100000,
          'annualRate': 18,
          'tenureYears': 1,
          'totalInterest': 18000,
          'totalPayable': 118000,
          'monthlyInstallment': 9833.33,
          'fileChargePercent': 2,
          'processingFeePercent': 1,
          'fileCharge': 2000,
          'processingFee': 1000,
          'disbursedAmount': 97000,
        },
        {
          'id': 'personal-1',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'approvalStatus': 'Approved',
          'principal': 50000,
        },
        {
          'id': 'gold-pending',
          'memberName': 'Jordan Member',
          'loanType': 'gold',
          'approvalStatus': 'Pending',
          'principal': 10000,
        },
        {
          'id': 'gold-rejected',
          'memberName': 'Jordan Member',
          'loanType': 'gold',
          'approvalStatus': 'Rejected',
          'principal': 20000,
        },
      ],
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'collector-token',
      userId: 'collector-1',
      name: 'Collector',
      email: 'collector@example.com',
      role: 'Collector',
    );

    final loans = await apiService.fetchLoans(
      session: session,
      loanType: 'gold',
      approvedOnly: true,
    );

    expect(loans.single['loanType'], 'gold');
    expect(loans.single['approvalStatus'], 'Approved');
    expect(loans.single['id'], 'gold-1');
    expect(loans.single['disbursedAmount'], 97000);
    expect(client.payloads.single, {
      'action': 'getLoans',
      'token': 'collector-token',
      'loanType': 'gold',
      'approvedOnly': true,
    });
  });

  test('loan schemes load with the authenticated session and loan type',
      () async {
    final client = _RecordingHttpClient([
      [
        {
          'schemeId': 'gold-standard',
          'schemeName': 'Gold Loan Standard',
          'loanType': 'gold',
          'minAnnualRate': 18,
          'maxAnnualRate': 37,
          'minAmount': 1,
          'maxAmount': 1000000000,
          'minTenureYears': 1,
          'maxTenureYears': 7,
          'fileChargePercent': 2,
          'processingFeePercent': 1,
          'calculationMethod': 'flat',
        },
      ],
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final schemes = await apiService.fetchLoanSchemes(
      session: session,
      loanType: 'gold',
      includeInactive: true,
    );

    expect(schemes.single['schemeName'], 'Gold Loan Standard');
    expect(schemes.single['fileChargePercent'], 2);
    expect(schemes.single['processingFeePercent'], 1);
    expect(client.payloads.single, {
      'action': 'getLoanSchemes',
      'token': 'admin-token',
      'loanType': 'gold',
      'includeInactive': true,
    });
  });

  test('loan schedule API returns generated payments for a loan', () async {
    final client = _RecordingHttpClient([
      {
        'loanId': 'loan-1',
        'memberName': 'Jordan Member',
        'repaymentMethod': 'interest_only',
        'principal': 100000,
        'totalPayable': 118000,
        'payments': [
          {
            'periodIndex': 1,
            'dueDate': '2026-02-01',
            'installmentAmount': 1500,
            'principalAmount': 0,
            'interestAmount': 1500,
            'paid': false,
          },
        ],
      },
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final schedule = await apiService.fetchLoanPaymentSchedule(
      loanId: 'loan-1',
      session: session,
    );

    expect(schedule['repaymentMethod'], 'interest_only');
    expect((schedule['payments'] as List).single['interestAmount'], 1500);
    expect(client.payloads.single, {
      'action': 'getLoanPaymentSchedule',
      'token': 'admin-token',
      'id': 'loan-1',
    });
  });

  testWidgets('loan records calculate and save a Personal Loan',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.loanSchemes.first
      ..['fileChargePercent'] = 2
      ..['processingFeePercent'] = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-loan')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('loan-borrower-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('loan-principal')), '100000');
    await tester.enterText(
      find.byKey(const Key('loan-annual-rate-personal-loan-standard')),
      '18',
    );
    await tester.pumpAndSettle();
    expect(find.text('Flat interest: ₹18,000.00'), findsOneWidget);
    expect(find.text('Total repayment: ₹1,18,000.00'), findsOneWidget);
    expect(find.text('Monthly installment: ₹9,833.33'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-loan')));
    await tester.tap(find.byKey(const Key('save-loan')));
    await tester.pumpAndSettle();
    expect(apiService.loanRecords, hasLength(1));
    expect(apiService.loanRecords.single['loanType'], 'personal');
    expect(apiService.loanRecords.single['schemeId'], 'personal-loan-standard');
    expect(apiService.loanRecords.single['totalInterest'], 18000);
    expect(apiService.loanRecords.single['approvalStatus'], 'Pending');
    expect(apiService.loanRecords.single['loanNumber'], isNull);
    expect(apiService.loanRecords.single['fileCharge'], 2000);
    expect(apiService.loanRecords.single['processingFee'], 1000);
    expect(apiService.loanRecords.single['disbursedAmount'], 97000);
    expect(find.byKey(const Key('loan-card-loan-1')), findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedLoansPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final approveLoan = find.byKey(const Key('approve-loan-loan-1'));
    await Scrollable.ensureVisible(tester.element(approveLoan));
    await tester.pumpAndSettle();
    await tester.tap(approveLoan);
    await tester.pumpAndSettle();
    expect(apiService.loanRecords.single['approvalStatus'], 'Approved');
    expect(apiService.loanRecords.single['loanNumber'], 'LN-2026-123456');
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('loan-card-loan-1')),
      250,
    );
    expect(find.byKey(const Key('loan-card-loan-1')), findsOneWidget);
    expect(find.byKey(const Key('loan-number-loan-1')), findsOneWidget);
    expect(find.text('LN-2026-123456'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gold Interest EMI scheme shows interest-only payments',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.loanSchemes.firstWhere((scheme) => scheme['loanType'] == 'gold')[
        'calculationMethod'] = 'interest_only';
    await tester.pumpWidget(
      MaterialApp(
        home: GoldLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-loan')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('loan-borrower-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('loan-principal')), '100000');
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('loan-interest-only-estimate')), findsOneWidget);
    expect(find.text('Monthly interest: ₹1,500.00'), findsOneWidget);
    expect(
      find.text(
        'Interest is paid monthly; the full principal is due with the final payment.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('save-loan')));
    await tester.tap(find.byKey(const Key('save-loan')));
    await tester.pumpAndSettle();

    expect(apiService.loanRecords.single['repaymentMethod'], 'interest_only');
    expect(apiService.loanRecords.single['monthlyInstallment'], 1500);
    expect(apiService.loanRecords.single['totalPayable'], 118000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gold Loan schedule matches deposit UI and tracks payment',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService();
    CashfreeScheduleTarget? paymentTarget;
    int? paymentAmountPaise;
    apiService.loanRecords.add({
      'id': 'approved-gold',
      'memberName': 'Jordan Member',
      'schemeName': 'Gold Loan Standard',
      'schemeId': 'gold-loan-standard',
      'loanType': 'gold',
      'startDate': '2026-01-15',
      'principal': 100000,
      'annualRate': 18,
      'tenureYears': 1,
      'totalInterest': 18000,
      'totalPayable': 118000,
      'monthlyInstallment': 1500,
      'repaymentMethod': 'interest_only',
      'approvalStatus': 'Approved',
      'fileChargePercent': 0,
      'processingFeePercent': 0,
      'fileCharge': 0,
      'processingFee': 0,
      'disbursedAmount': 100000,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: GoldLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onSchedulePayment: ({
            required memberName,
            required amountPaise,
            required target,
          }) async {
            paymentAmountPaise = amountPaise;
            paymentTarget = target;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scheduleButton =
        find.byKey(const Key('loan-schedule-button-approved-gold'));
    await tester.ensureVisible(scheduleButton);
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-schedule-title')), findsOneWidget);
    expect(find.text('Installments paid'), findsOneWidget);
    expect(find.text('Payment rows: 12'), findsOneWidget);
    expect(find.text('Payment details'), findsOneWidget);
    expect(
      find.byKey(const Key('loan-payment-installment-approved-gold-0')),
      findsOneWidget,
    );
    final firstPaymentRow =
        find.byKey(const Key('loan-payment-approved-gold-0'));
    expect(
      (tester.widget<ListTile>(firstPaymentRow).trailing as Text).style?.color,
      portalToastErrorColor,
    );
    expect(find.text('Due date'), findsWidgets);
    expect(find.text('Paid (TRUE/FALSE)'), findsWidgets);
    expect(find.byKey(const Key('loan-schedule-footer')), findsOneWidget);
    expect(
      find.byKey(const Key('loan-schedule-close-action')),
      findsOneWidget,
    );
    final amountSummary = find.byKey(
      const Key('loan-schedule-amount-summary'),
    );
    expect(tester.widget<Text>(amountSummary).data, contains('received of'));
    final paymentCheckbox = find.descendant(
      of: find.byKey(const Key('loan-payment-approved-gold-0')),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(paymentCheckbox);
    await tester.tap(paymentCheckbox);
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(amountSummary).data,
      contains('1,500.00 received of'),
    );
    expect(apiService.loanActions.last['action'], 'toggleLoanPayment');
    expect(
      apiService.loanRecords.single['paymentSchedule'][0]['paid'],
      isTrue,
    );
    expect(
      (tester.widget<ListTile>(firstPaymentRow).trailing as Text).style?.color,
      portalToastSuccessColor,
    );
    expect(find.text('TRUE'), findsOneWidget);
    final payButton = find.byKey(const Key('pay-loan-approved-gold'));
    expect(payButton, findsOneWidget);
    await tester.tap(payButton);
    await tester.pumpAndSettle();
    expect(paymentAmountPaise, 150000);
    expect(paymentTarget?.toJson(), {
      'kind': 'loan',
      'id': 'approved-gold',
      'periodIndex': 2,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('Personal Loan schedule matches Deposit Accounts UI',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService()
      ..loanRecords.add({
        'id': 'approved-personal-schedule',
        'memberName': 'Jordan Member',
        'schemeName': 'Personal Loan Standard',
        'loanType': 'personal',
        'startDate': '2026-01-15',
        'principal': 100000,
        'annualRate': 18,
        'tenureYears': 1,
        'totalInterest': 18000,
        'totalPayable': 118000,
        'monthlyInstallment': 9833.33,
        'repaymentMethod': 'fixed_emi',
        'approvalStatus': 'Approved',
        'fileChargePercent': 0,
        'processingFeePercent': 0,
        'fileCharge': 0,
        'processingFee': 0,
        'disbursedAmount': 100000,
      });
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scheduleButton = find.byKey(
      const Key('loan-schedule-button-approved-personal-schedule'),
    );
    await tester.ensureVisible(scheduleButton);
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-schedule-title')), findsOneWidget);
    expect(find.text('Installments paid'), findsOneWidget);
    expect(find.text('Payment rows: 12'), findsOneWidget);
    expect(find.text('Payment details'), findsOneWidget);
    expect(
      find.byKey(
        const Key('loan-payment-installment-approved-personal-schedule-0'),
      ),
      findsOneWidget,
    );
    final firstPaymentRow = find.byKey(
      const Key('loan-payment-approved-personal-schedule-0'),
    );
    expect(
      (tester.widget<ListTile>(firstPaymentRow).trailing as Text).style?.color,
      portalToastErrorColor,
    );
    expect(find.text('Due date'), findsWidgets);
    expect(find.text('Paid (TRUE/FALSE)'), findsWidgets);
    expect(find.byKey(const Key('loan-schedule-footer')), findsOneWidget);
    expect(
      find.byKey(const Key('loan-schedule-close-action')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member can pay the next personal loan installment',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService()
      ..loanRecords.add({
        'id': 'member-personal-schedule',
        'memberName': 'Jordan Member',
        'schemeName': 'Personal Loan Standard',
        'loanType': 'personal',
        'startDate': '2026-01-15',
        'principal': 100000,
        'annualRate': 18,
        'tenureYears': 1,
        'totalInterest': 18000,
        'totalPayable': 118000,
        'monthlyInstallment': 9833.33,
        'repaymentMethod': 'fixed_emi',
        'approvalStatus': 'Approved',
        'fileChargePercent': 0,
        'processingFeePercent': 0,
        'fileCharge': 0,
        'processingFee': 0,
        'disbursedAmount': 100000,
      });
    String? paymentMember;
    int? paymentAmountPaise;
    CashfreeScheduleTarget? paymentTarget;
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
          onSchedulePayment: ({
            required memberName,
            required amountPaise,
            required target,
          }) async {
            paymentMember = memberName;
            paymentAmountPaise = amountPaise;
            paymentTarget = target;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scheduleButton = find.byKey(
      const Key('loan-schedule-button-member-personal-schedule'),
    );
    await tester.ensureVisible(scheduleButton);
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    final payButton = find.byKey(
      const Key('pay-loan-member-personal-schedule'),
    );
    expect(payButton, findsOneWidget);
    await tester.tap(payButton);
    await tester.pumpAndSettle();

    expect(paymentMember, 'Jordan Member');
    expect(paymentAmountPaise, 983333);
    expect(paymentTarget?.toJson(), {
      'kind': 'loan',
      'id': 'member-personal-schedule',
      'periodIndex': 1,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member can submit a loan application for their own account',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-loan')), findsOneWidget);
    expect(find.text('Apply for loan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-loan')));
    await tester.pumpAndSettle();
    expect(find.text('Apply for a loan'), findsOneWidget);
    expect(find.text('Jordan Member'), findsNWidgets(2));
    expect(find.byKey(const Key('loan-start-date')), findsNothing);
    expect(find.byKey(const Key('save-loan')), findsOneWidget);
    final applicantField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('loan-borrower-name')),
        matching: find.byType(TextField),
      ),
    );
    expect(applicantField.readOnly, isTrue);
    await tester.enterText(find.byKey(const Key('loan-principal')), '10000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-loan')));
    await tester.pumpAndSettle();

    expect(apiService.loanActions.single['action'], 'addLoan');
    expect(apiService.loanActions.single['memberName'], 'Jordan Member');
    expect(apiService.loanRecords.single['approvalStatus'], 'Pending');
    expect(find.byKey(const Key('loan-card-loan-1')), findsOneWidget);
    expect(find.byKey(const Key('loan-status-loan-1')), findsOneWidget);
    expect(find.text('Loan application submitted for Admin approval.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member sees an approved application on its loan type page',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.add({
        'id': 'member-approved-personal',
        'memberName': 'Jordan Member',
        'loanType': 'personal',
        'approvalStatus': 'Approved',
        'principal': 10000,
      });
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('loan-card-member-approved-personal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('loan-status-member-approved-personal')),
      findsOneWidget,
    );
    final approvedLabel = find.descendant(
      of: find.byKey(
        const Key('loan-status-member-approved-personal'),
      ),
      matching: find.text('Approved'),
    );
    expect(
      tester.widget<Text>(approvedLabel).style?.color,
      portalToastSuccessColor,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member sees only own loan-type applications and statuses',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'member-personal-pending',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'approvalStatus': 'Pending',
          'principal': 12000,
        },
        {
          'id': 'member-personal-rejected',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'approvalStatus': 'Rejected',
          'principal': 15000,
        },
        {
          'id': 'member-gold-approved',
          'memberName': 'Jordan Member',
          'loanType': 'gold',
          'approvalStatus': 'Approved',
          'principal': 20000,
        },
        {
          'id': 'other-member-personal',
          'memberName': 'Other Member',
          'loanType': 'personal',
          'approvalStatus': 'Approved',
          'principal': 25000,
        },
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-card-member-personal-pending')),
        findsOneWidget);
    expect(find.byKey(const Key('loan-card-member-personal-rejected')),
        findsOneWidget);
    expect(
        find.byKey(const Key('loan-card-member-gold-approved')), findsNothing);
    expect(
        find.byKey(const Key('loan-card-other-member-personal')), findsNothing);
    expect(find.byKey(const Key('loan-status-member-personal-pending')),
        findsOneWidget);
    expect(find.byKey(const Key('loan-status-member-personal-rejected')),
        findsOneWidget);
    final rejectedLabel = find.descendant(
      of: find.byKey(
        const Key('loan-status-member-personal-rejected'),
      ),
      matching: find.text('Rejected'),
    );
    expect(
      tester.widget<Text>(rejectedLabel).style?.color,
      portalToastErrorColor,
    );
    expect(find.byKey(const Key('approve-loan-member-personal-pending')),
        findsNothing);
    expect(find.byKey(const Key('reject-loan-member-personal-pending')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member can reach loan applications without loan permissions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-loans')), findsOneWidget);
    await tester.tap(find.byKey(const Key('navigation-menu-loans')));
    await tester.pumpAndSettle();
    final personalLoanItem =
        find.byKey(const Key('navigation-menu-personal-loan'));
    await _ensureDrawerItemVisible(tester, personalLoanItem);
    await tester.tap(personalLoanItem);
    await tester.pumpAndSettle();

    expect(find.text('Personal Loan'), findsNWidgets(2));
    expect(find.text('Apply for loan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member with loans explicitly disabled has no Loans menu',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
            permissions: {
              'loan_add': false,
              'loan_view': false,
            },
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('navigation-menu-loans')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Collector without loan action grants cannot manage loans',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.add({
        'id': 'loan-pending',
        'memberName': 'Jordan Member',
        'loanType': 'personal',
        'principal': 10000,
        'approvalStatus': 'Pending',
      });
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'loan_manage': true, 'loan_view': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-loan')), findsNothing);
    expect(find.byKey(const Key('loan-scheme-management')), findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(find.byKey(const Key('edit-loan-loan-pending')), findsNothing);
    expect(find.byKey(const Key('delete-loan-loan-pending')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view-only Collector sees approved loans without actions',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'view-approved-personal',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'approvalStatus': 'Approved',
          'principal': 10000,
        },
        {
          'id': 'view-pending-personal',
          'memberName': 'Taylor Member',
          'loanType': 'personal',
          'approvalStatus': 'Pending',
          'principal': 12000,
        },
        {
          'id': 'view-approved-gold',
          'memberName': 'Morgan Member',
          'loanType': 'gold',
          'approvalStatus': 'Approved',
          'principal': 15000,
        },
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'loan_view': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-card-view-approved-personal')),
        findsOneWidget);
    expect(find.byKey(const Key('loan-status-view-approved-personal')),
        findsOneWidget);
    expect(
        find.byKey(const Key('loan-card-view-pending-personal')), findsNothing);
    expect(find.byKey(const Key('loan-card-view-approved-gold')), findsNothing);
    expect(find.byKey(const Key('add-loan')), findsNothing);
    expect(find.byKey(const Key('edit-loan-view-approved-personal')),
        findsNothing);
    expect(find.byKey(const Key('delete-loan-view-approved-personal')),
        findsNothing);
    expect(find.byKey(const Key('approve-loan-view-pending-personal')),
        findsNothing);
    expect(find.byKey(const Key('reject-loan-view-pending-personal')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permission-enabled Collector can use loan actions',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.add({
        'id': 'loan-pending',
        'memberName': 'Jordan Member',
        'loanType': 'personal',
        'schemeId': 'personal-loan-standard',
        'schemeName': 'Personal Loan Standard',
        'startDate': '2026-10-01',
        'principal': 10000,
        'annualRate': 18,
        'tenureYears': 1,
        'approvalStatus': 'Approved',
      });
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {
              'loan_view': true,
              'loan_add': true,
              'loan_edit': true,
              'loan_delete': true,
              'loan_update': true,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-loan')), findsOneWidget);
    expect(find.byKey(const Key('loan-scheme-management')), findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(find.byKey(const Key('edit-loan-loan-pending')), findsOneWidget);
    expect(find.byKey(const Key('delete-loan-loan-pending')), findsOneWidget);

    final editLoanButton = find.byKey(const Key('edit-loan-loan-pending'));
    await Scrollable.ensureVisible(tester.element(editLoanButton));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(editLoanButton).onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('edit-loan-loan-pending')));
    await tester.pumpAndSettle();
    expect(find.text('Edit loan'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('loan-borrower-name')),
      'Updated Member',
    );
    await tester.tap(find.byKey(const Key('save-loan')));
    await tester.pumpAndSettle();
    expect(apiService.loanActions.last['action'], 'editLoan');
    expect(
      apiService.loanRecords.first['memberName'],
      'Updated Member',
    );
    final toastDismiss = find.byKey(const Key('portal-toast-dismiss'));
    if (toastDismiss.evaluate().isNotEmpty) {
      await tester.tap(toastDismiss);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedLoansPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {
              'loan_view': true,
              'loan_add': true,
              'loan_edit': true,
              'loan_delete': true,
              'loan_update': true,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      apiService.fetchActions,
      contains('getLoans:all:approved'),
    );
    expect(
        find.byKey(const Key('loan-application-loan-pending')), findsNothing);
    expect(
      find.byKey(const Key('approve-loan-loan-pending')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reject-loan-loan-pending')),
      findsNothing,
    );
    expect(apiService.loanRecords.first['approvalStatus'], 'Pending');
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {
              'loan_view': true,
              'loan_add': true,
              'loan_edit': true,
              'loan_delete': true,
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (toastDismiss.evaluate().isNotEmpty) {
      await tester.tap(toastDismiss);
      await tester.pumpAndSettle();
    }

    final deleteLoanButton = find.byKey(const Key('delete-loan-loan-pending'));
    await Scrollable.ensureVisible(tester.element(deleteLoanButton));
    await tester.pumpAndSettle();
    await tester.tap(deleteLoanButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-loan')));
    await tester.pumpAndSettle();
    expect(apiService.loanActions.last['action'], 'deleteLoan');
    expect(
      apiService.loanRecords.any((loan) => loan['id'] == 'loan-pending'),
      isFalse,
    );

    await tester.tap(find.byKey(const Key('add-loan')));
    await tester.pumpAndSettle();
    expect(find.text('New loan'), findsNWidgets(2));
    await tester.enterText(
      find.byKey(const Key('loan-borrower-name')),
      'Taylor Member',
    );
    await tester.enterText(find.byKey(const Key('loan-principal')), '12000');
    await tester.tap(find.byKey(const Key('save-loan')));
    await tester.pumpAndSettle();
    expect(apiService.loanActions.last['action'], 'addLoan');
    expect(apiService.loanRecords.last['approvalStatus'], 'Pending');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Approved Loans does not render loan detail cards',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.add({
        'id': 'loan-approved-fees',
        'memberName': 'Jordan Member',
        'loanType': 'personal',
        'schemeName': 'Personal Loan Standard',
        'principal': 100000,
        'annualRate': 18,
        'tenureYears': 1,
        'totalInterest': 18000,
        'totalPayable': 118000,
        'monthlyInstallment': 9833.33,
        'approvalStatus': 'Approved',
        'fileChargePercent': 2,
        'processingFeePercent': 1,
        'fileCharge': 2000,
        'processingFee': 1000,
        'disbursedAmount': 97000,
      });
    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedLoansPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'loan_view': true},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Approved Loans'), findsOneWidget);
    expect(
      find.byKey(const Key('loan-card-loan-approved-fees')),
      findsNothing,
    );
    expect(find.text('File charge (2.0%)'), findsNothing);
    expect(find.text('Disbursed amount'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Approved Loans shows all statuses to staff who can review',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'pending-review',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'schemeName': 'Personal Loan Standard',
          'principal': 10000,
          'approvalStatus': 'Pending',
        },
        {
          'id': 'approved-review',
          'memberName': 'Casey Member',
          'loanType': 'gold',
          'schemeName': 'Gold Loan Standard',
          'principal': 20000,
          'approvalStatus': 'Approved',
        },
        {
          'id': 'rejected-review',
          'memberName': 'Riley Member',
          'loanType': 'personal',
          'schemeName': 'Personal Loan Standard',
          'principal': 15000,
          'approvalStatus': 'Rejected',
        },
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedLoansPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(apiService.fetchActions, contains('getLoans:all'));
    expect(
        find.text(
            'View all Personal and Gold Loan applications by their current status.'),
        findsOneWidget);
    expect(find.byKey(const Key('loan-approval-section')), findsOneWidget);
    expect(find.byKey(const Key('loan-application-pending-review')),
        findsOneWidget);
    final statusContext =
        tester.element(find.byKey(const Key('loan-approval-section')));
    expect(
      portalApprovalStatusColor(statusContext, 'Pending'),
      portalToastWarningColor,
    );
    expect(
      portalApprovalStatusColor(statusContext, 'Rejected'),
      portalToastErrorColor,
    );
    expect(
      portalApprovalStatusColor(statusContext, 'Approved'),
      portalToastSuccessColor,
    );
    expect(
      portalApprovalStatusColor(statusContext, 'Active'),
      portalToastSuccessColor,
    );
    final pendingStatusChip = tester.widget<Chip>(
      find.byKey(const Key('application-status-pending-review')),
    );
    expect(
      pendingStatusChip.backgroundColor,
      portalToastWarningColor.withValues(alpha: .07),
    );
    expect(
      (pendingStatusChip.label as Text).style?.color,
      portalToastWarningColor,
    );
    final pendingCountChip =
        tester.widget<Chip>(find.byKey(const Key('pending-loan-count')));
    expect(
      (pendingCountChip.avatar as Icon).color,
      portalToastWarningColor,
    );
    expect(
        find.byKey(const Key('approve-loan-pending-review')), findsOneWidget);
    expect(
      find.byKey(const Key('loan-schedule-button-approved-review')),
      findsNothing,
    );
    expect(find.text('Application ID: approved-review'), findsNothing);
    expect(find.byKey(const Key('add-loan')), findsNothing);
    expect(find.byKey(const Key('edit-loan-pending-review')), findsNothing);
    expect(find.byKey(const Key('delete-loan-pending-review')), findsNothing);

    for (final loanId in [
      'pending-review',
      'approved-review',
      'rejected-review',
    ]) {
      expect(find.byKey(Key('loan-card-$loanId')), findsNothing);
      expect(find.byKey(Key('loan-status-$loanId')), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin can add a loan scheme from the Loan Master page',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LoanMasterPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final addScheme = find.byKey(const Key('add-loan-scheme-overview'));
    await tester.ensureVisible(addScheme);
    await tester.tap(addScheme);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scheme-name')),
      'Custom Personal Scheme',
    );
    await tester.enterText(
      find.byKey(const Key('scheme-file-charge-percent')),
      '2',
    );
    await tester.enterText(
      find.byKey(const Key('scheme-processing-fee-percent')),
      '1',
    );
    await tester.tap(find.byKey(const Key('save-loan-scheme')));
    await tester.pumpAndSettle();

    expect(
      apiService.loanSchemes
          .any((scheme) => scheme['schemeName'] == 'Custom Personal Scheme'),
      isTrue,
    );
    expect(
      apiService.loanActions.last,
      containsPair('action', 'addLoanScheme'),
    );
    expect(apiService.loanSchemes.last['fileChargePercent'], 2);
    expect(apiService.loanSchemes.last['processingFeePercent'], 1);
    expect(
      find.text('Custom Personal Scheme', skipOffstage: false),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Loan Master uses portal loading while schemes are loading',
      (WidgetTester tester) async {
    final apiService = _DelayedLoanSchemesApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LoanMasterPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('loan-scheme-loading')), findsOneWidget);
    expect(find.text('Loading loan schemes'), findsOneWidget);

    apiService.schemesCompleter.complete(apiService.loanSchemes);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loan-scheme-overview')), findsOneWidget);
    expect(find.byKey(const Key('loan-scheme-loading')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loan pages maintain header contrast in light and dark themes',
      (WidgetTester tester) async {
    const session = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );
    final pages = <(String, Widget Function(_FakeApiService))>[
      (
        'loan-master-header',
        (apiService) =>
            LoanMasterPage(apiService: apiService, session: session),
      ),
      (
        'loan-page-header',
        (apiService) =>
            PersonalLoanPage(apiService: apiService, session: session),
      ),
      (
        'loan-page-header',
        (apiService) => GoldLoanPage(apiService: apiService, session: session),
      ),
      (
        'loan-page-header',
        (apiService) =>
            ApprovedLoansPage(apiService: apiService, session: session),
      ),
    ];

    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final (headerKey, buildPage) in pages) {
        final apiService = _FakeApiService()
          ..loanRecords.addAll([
            {
              'id': 'theme-personal-loan',
              'memberName': 'Jordan Member',
              'loanType': 'personal',
              'schemeName': 'Personal Loan Standard',
              'principal': 10000,
              'annualRate': 18,
              'tenureYears': 1,
              'totalInterest': 1800,
              'totalPayable': 11800,
              'monthlyInstallment': 983.33,
              'approvalStatus': 'Approved',
            },
            {
              'id': 'theme-gold-loan',
              'memberName': 'Taylor Member',
              'loanType': 'gold',
              'schemeName': 'Gold Loan Standard',
              'principal': 20000,
              'annualRate': 18,
              'tenureYears': 1,
              'totalInterest': 3600,
              'totalPayable': 23600,
              'monthlyInstallment': 1966.67,
              'approvalStatus': 'Approved',
            },
          ]);
        final seedColor = brightness == Brightness.light
            ? const Color(0xFF3458D4)
            : const Color(0xFF9EB4FF);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: brightness,
                surface: brightness == Brightness.light
                    ? Colors.white
                    : const Color(0xFF191B23),
              ),
              brightness: brightness,
              useMaterial3: true,
            ),
            home: buildPage(apiService),
          ),
        );
        await tester.pumpAndSettle();

        final header = tester.widget<Container>(
          find.byKey(Key(headerKey)),
        );
        final gradient =
            (header.decoration! as BoxDecoration).gradient! as LinearGradient;
        for (final background in gradient.colors) {
          final whiteContrast = 1.05 / (background.computeLuminance() + .05);
          expect(
            whiteContrast,
            greaterThanOrEqualTo(4.5),
            reason: '$headerKey needs readable white text in $brightness mode.',
          );
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('Loan list pages show loading until records are available',
      (WidgetTester tester) async {
    const session = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    Future<void> verifyLoading(
      String title,
      Widget Function(ApiService apiService) pageBuilder,
    ) async {
      final apiService = _DelayedLoanRecordsApiService();
      await tester.pumpWidget(
        MaterialApp(home: pageBuilder(apiService)),
      );
      await tester.pump();

      expect(find.text('Loading $title'), findsOneWidget);
      expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);

      apiService.loansCompleter.complete([]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('portal-loading-state')), findsNothing);
      expect(find.byType(PortalEmptyState), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await verifyLoading(
      'Personal Loan',
      (apiService) => PersonalLoanPage(
        apiService: apiService,
        session: session,
      ),
    );
    await verifyLoading(
      'Gold Loan',
      (apiService) => GoldLoanPage(
        apiService: apiService,
        session: session,
      ),
    );
    await verifyLoading(
      'Approved Loans',
      (apiService) => ApprovedLoansPage(
        apiService: apiService,
        session: session,
      ),
    );
  });

  testWidgets('Loan Master shows active, inactive, and edit colors',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.loanSchemes[1]['active'] = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoanMasterPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activeStatus = tester.widget<Chip>(
      find.byKey(const Key('loan-scheme-status-personal-loan-standard')),
    );
    expect(
      activeStatus.backgroundColor,
      portalToastSuccessColor.withValues(alpha: .09),
    );
    expect((activeStatus.label as Text).data, 'Active');

    final inactiveStatus = tester.widget<Chip>(
      find.byKey(const Key('loan-scheme-status-gold-loan-standard')),
    );
    expect(
      inactiveStatus.backgroundColor,
      portalToastErrorColor.withValues(alpha: .09),
    );
    expect((inactiveStatus.label as Text).data, 'Inactive');

    final editButton = tester.widget<TextButton>(
      find.byKey(const Key('edit-loan-scheme-personal-loan-standard')),
    );
    expect(
      editButton.style?.foregroundColor?.resolve({}),
      portalEditColor,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin can edit and delete a loan scheme', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LoanMasterPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const schemeId = 'personal-loan-standard';
    const editScheme = ValueKey('edit-loan-scheme-personal-loan-standard');
    final editSchemeFinder = find.byKey(editScheme);
    await tester.ensureVisible(editSchemeFinder);
    await tester.tap(editSchemeFinder);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scheme-name')),
      'Updated Personal Scheme',
    );
    await tester.tap(find.byKey(const Key('save-loan-scheme')));
    await tester.pumpAndSettle();

    expect(
      apiService.loanSchemes.singleWhere(
          (scheme) => scheme['schemeId'] == schemeId)['schemeName'],
      'Updated Personal Scheme',
    );
    expect(apiService.loanActions.last['action'], 'editLoanScheme');
    expect(
      find.text('Updated Personal Scheme', skipOffstage: false),
      findsOneWidget,
    );

    const deleteScheme = ValueKey('delete-loan-scheme-personal-loan-standard');
    final deleteSchemeFinder = find.byKey(deleteScheme);
    await tester.ensureVisible(deleteSchemeFinder);
    await tester.tap(deleteSchemeFinder);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('confirm-delete-scheme-$schemeId')),
    );
    await tester.tap(find.byKey(const Key('confirm-delete-scheme-$schemeId')));
    await tester.pumpAndSettle();

    expect(
      apiService.loanSchemes.any((scheme) => scheme['schemeId'] == schemeId),
      isFalse,
    );
    expect(apiService.loanActions.last['action'], 'deleteLoanScheme');
    expect(
      find.byKey(const Key('loan-scheme-overview-$schemeId')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Loan Master overview supports direct scheme CRUD actions', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LoanMasterPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('add-loan-scheme-overview')),
    );
    await tester.tap(find.byKey(const Key('add-loan-scheme-overview')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scheme-name')),
      'Overview Test Scheme',
    );
    await tester.tap(find.byKey(const Key('save-loan-scheme')));
    await tester.pumpAndSettle();

    final added = apiService.loanSchemes.singleWhere(
      (scheme) => scheme['schemeName'] == 'Overview Test Scheme',
    );
    final schemeId = added['schemeId'] as String;
    expect(apiService.loanActions.last['action'], 'addLoanScheme');
    await tester.pumpAndSettle();
    expect(
      apiService.fetchActions.where((action) => action == 'getLoanSchemes:all'),
      hasLength(2),
    );
    expect(find.byKey(const Key('loan-scheme-overview')), findsOneWidget);
    expect(find.text('3 schemes configured'), findsOneWidget);
    expect(
      find.text('Overview Test Scheme', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(Key('loan-scheme-overview-$schemeId')), findsOneWidget);

    await tester.ensureVisible(find.byKey(Key('edit-loan-scheme-$schemeId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('edit-loan-scheme-$schemeId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('scheme-name')),
      'Overview Updated Scheme',
    );
    await tester.tap(find.byKey(const Key('save-loan-scheme')));
    await tester.pumpAndSettle();
    expect(apiService.loanActions.last['action'], 'editLoanScheme');
    expect(
      apiService.loanSchemes.singleWhere(
          (scheme) => scheme['schemeId'] == schemeId)['schemeName'],
      'Overview Updated Scheme',
    );

    await tester.ensureVisible(find.byKey(Key('delete-loan-scheme-$schemeId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('delete-loan-scheme-$schemeId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('confirm-delete-scheme-$schemeId')));
    await tester.pumpAndSettle();
    expect(apiService.loanActions.last['action'], 'deleteLoanScheme');
    expect(
      apiService.loanSchemes.any((scheme) => scheme['schemeId'] == schemeId),
      isFalse,
    );
    expect(find.byKey(Key('loan-scheme-overview-$schemeId')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admin can set a Gold scheme to Interest EMI', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: LoanMasterPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editGoldScheme =
        find.byKey(const Key('edit-loan-scheme-gold-loan-standard'));
    await tester.ensureVisible(editGoldScheme);
    await tester.tap(editGoldScheme);
    await tester.pumpAndSettle();
    final calculationMethod =
        find.byKey(const Key('scheme-calculation-method'));
    await tester.ensureVisible(calculationMethod);
    await tester.tap(calculationMethod);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Interest EMI (principal due at the end)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-loan-scheme')));
    await tester.pumpAndSettle();

    final goldScheme = apiService.loanSchemes
        .singleWhere((scheme) => scheme['schemeId'] == 'gold-loan-standard');
    expect(goldScheme['calculationMethod'], 'interest_only');
    expect(
      apiService.loanActions.last['calculationMethod'],
      'interest_only',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Loan Master does not load or show loan applications', (
    WidgetTester tester,
  ) async {
    final apiService = _FakeApiService()
      ..loanFetchError = StateError('Loan records are unavailable.');
    await tester.pumpWidget(
      MaterialApp(
        home: LoanMasterPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan-scheme-overview')), findsOneWidget);
    expect(find.byKey(const Key('loan-scheme-management')), findsNothing);
    expect(find.text('Personal Loan Standard'), findsOneWidget);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(find.text('Loan applications'), findsNothing);
    expect(
      apiService.fetchActions.where((action) => action.startsWith('getLoans:')),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loan form applies the selected scheme amount boundaries',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.loanSchemes.first
      ..['minAmount'] = 5000
      ..['maxAmount'] = 50000;
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-loan')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('loan-borrower-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('loan-principal')), '4999');
    await tester.ensureVisible(find.byKey(const Key('save-loan')));
    await tester.tap(find.byKey(const Key('save-loan')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount from ₹5,000.00 to ₹50,000.00'),
        findsOneWidget);
    expect(apiService.loanRecords, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gold Loan honors the maximum rate and seven-year period',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: GoldLoanPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-loan')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('loan-borrower-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('loan-principal')), '20000');
    await tester.enterText(
      find.byKey(const Key('loan-annual-rate-gold-loan-standard')),
      '37',
    );
    final tenureField =
        find.byKey(const Key('loan-tenure-years-gold-loan-standard'));
    await tester.ensureVisible(tenureField);
    await tester.pumpAndSettle();
    await tester.tap(tenureField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 years').last);
    await tester.pumpAndSettle();
    expect(find.text('Flat interest: ₹51,800.00'), findsOneWidget);
    expect(find.text('Total repayment: ₹71,800.00'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-loan')));
    await tester.tap(find.byKey(const Key('save-loan')));
    await tester.pumpAndSettle();
    expect(apiService.loanRecords.single['loanType'], 'gold');
    expect(apiService.loanRecords.single['schemeId'], 'gold-loan-standard');
    expect(apiService.loanRecords.single['tenureYears'], 7);
    expect(apiService.loanRecords.single['annualRate'], 37);
    expect(tester.takeException(), isNull);
  });

  test('Admin has every loan permission enabled', () {
    const session = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    for (final permission in [
      'loan_view',
      'loan_add',
      'loan_edit',
      'loan_delete',
      'loan_update',
    ]) {
      expect(session.hasPermission(permission), isTrue, reason: permission);
    }
  });

  testWidgets('Admin loan navigation shows every loan menu and action',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService()
      ..loanRecords.add({
        'id': 'pending-loan-master',
        'memberName': 'Jordan Member',
        'loanType': 'personal',
        'approvalStatus': 'Pending',
        'principal': 10000,
      });
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initialLoanFetchCount = apiService.fetchActions
        .where((action) => action.startsWith('getLoans:'))
        .length;
    await _openDrawerPage(tester, 'navigation-menu-loan-master');
    expect(find.text('Loan Master'), findsWidgets);
    expect(find.byKey(const Key('loan-scheme-overview')), findsOneWidget);
    expect(find.byKey(const Key('loan-scheme-overview-personal-loan-standard')),
        findsOneWidget);
    expect(find.byKey(const Key('loan-scheme-overview-gold-loan-standard')),
        findsOneWidget);
    expect(find.byKey(const Key('add-loan')), findsNothing);
    expect(
        find.byKey(const Key('loan-card-pending-loan-master')), findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(find.text('Loan applications'), findsNothing);
    expect(
      apiService.fetchActions
          .where((action) => action.startsWith('getLoans:'))
          .length,
      initialLoanFetchCount,
    );
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-loans')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('navigation-menu-loan-master')), findsOneWidget);
    expect(
        find.byKey(const Key('navigation-menu-personal-loan')), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-gold-loan')), findsOneWidget);
    final approvedLoansMenuItem =
        find.byKey(const Key('navigation-menu-approved-loans'));
    await _ensureDrawerItemVisible(tester, approvedLoansMenuItem);
    await tester.tap(approvedLoansMenuItem);
    await tester.pumpAndSettle();
    expect(find.text('Approved Loans'), findsWidgets);
    expect(apiService.fetchActions, contains('getLoans:all'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Personal and Gold pages show only approved loans of their type',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'approved-personal',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'approvalStatus': 'Approved',
          'principal': 10000,
        },
        {
          'id': 'approved-gold',
          'memberName': 'Taylor Member',
          'loanType': 'gold',
          'approvalStatus': 'Approved',
          'principal': 20000,
        },
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openDrawerPage(tester, 'navigation-menu-personal-loan');
    await tester.scrollUntilVisible(
      find.byKey(const Key('loan-card-approved-personal')),
      250,
    );
    expect(
        find.byKey(const Key('loan-card-approved-personal')), findsOneWidget);
    expect(find.byKey(const Key('loan-card-approved-gold')), findsNothing);

    await _openDrawerPage(tester, 'navigation-menu-gold-loan');
    await tester.scrollUntilVisible(
      find.byKey(const Key('loan-card-approved-gold')),
      250,
    );
    expect(find.byKey(const Key('loan-card-approved-gold')), findsOneWidget);
    expect(find.byKey(const Key('loan-card-approved-personal')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new Personal and Gold applications appear after approval in matching loan pages',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    const memberSession = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
    );
    const adminSession = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );
    Future<void> showPage(Widget page) async {
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: page));
      await tester.pumpAndSettle();
    }

    Future<String> submitApplication(Widget page) async {
      await showPage(page);
      await tester.tap(find.byKey(const Key('add-loan')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('loan-principal')), '10000');
      await tester.ensureVisible(find.byKey(const Key('save-loan')));
      await tester.tap(find.byKey(const Key('save-loan')));
      await tester.pumpAndSettle();
      expect(apiService.loanRecords.last['approvalStatus'], 'Pending');
      expect(apiService.loanRecords.last['memberName'], 'Jordan Member');
      expect(find.byKey(const Key('loan-approval-section')), findsNothing);
      return apiService.loanRecords.last['id'] as String;
    }

    Future<void> approveApplication(String loanId) async {
      await showPage(
        ApprovedLoansPage(apiService: apiService, session: adminSession),
      );
      final approveButton = find.byKey(Key('approve-loan-$loanId'));
      await _scrollUntilBuilt(
        tester,
        approveButton,
        find.byType(ListView).first,
      );
      await Scrollable.ensureVisible(tester.element(approveButton));
      await tester.pumpAndSettle();
      await tester.tap(approveButton);
      await tester.pumpAndSettle();
      expect(
        apiService.loanRecords
            .singleWhere((loan) => loan['id'] == loanId)['approvalStatus'],
        'Approved',
      );
    }

    final personalId = await submitApplication(
      PersonalLoanPage(apiService: apiService, session: memberSession),
    );
    expect(apiService.loanRecords.single['loanType'], 'personal');
    expect(apiService.loanRecords.single['id'], personalId);
    await approveApplication(personalId);

    await showPage(
      ApprovedLoansPage(apiService: apiService, session: adminSession),
    );
    expect(find.byKey(Key('loan-card-$personalId')), findsNothing);

    final goldId = await submitApplication(
      GoldLoanPage(apiService: apiService, session: memberSession),
    );
    expect(apiService.loanRecords.last['loanType'], 'gold');
    await approveApplication(goldId);

    await showPage(
      ApprovedLoansPage(apiService: apiService, session: adminSession),
    );
    expect(find.byKey(Key('loan-card-$personalId')), findsNothing);
    expect(find.byKey(Key('loan-card-$goldId')), findsNothing);
    expect(apiService.fetchActions, contains('getLoans:all'));

    await showPage(
      PersonalLoanPage(apiService: apiService, session: adminSession),
    );
    await tester.scrollUntilVisible(
      find.byKey(Key('loan-card-$personalId')),
      300,
    );
    expect(
      find.byKey(Key('loan-card-$personalId')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('loan-card-$goldId')),
      findsNothing,
    );
    await showPage(
      GoldLoanPage(apiService: apiService, session: adminSession),
    );
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(Key('loan-card-$goldId')),
      300,
    );
    expect(
      find.byKey(Key('loan-card-$goldId')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('loan-card-$personalId')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Collector loan menu shows Personal, Gold, and Approved only',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {
              'loan_view': true,
              'loan_add': true,
            },
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-loans')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('navigation-menu-loan-master')), findsNothing);
    expect(
      find.byKey(const Key('navigation-menu-personal-loan')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('navigation-menu-gold-loan')), findsOneWidget);
    expect(
      find.byKey(const Key('navigation-menu-approved-loans')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('navigation-menu-personal-loan')));
    await tester.pumpAndSettle();
    expect(find.text('Personal Loan'), findsWidgets);
    expect(find.byKey(const Key('loan-scheme-management')), findsNothing);
    await _openDrawerPage(tester, 'navigation-menu-approved-loans');
    expect(find.text('Approved Loans'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Loan Master hides applications while Collector reviews pending loans by type',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'pending-review',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'schemeName': 'Personal Loan Standard',
          'startDate': '2026-10-20',
          'createdAt': '2026-10-20',
          'principal': 50000,
          'annualRate': 18,
          'tenureYears': 2,
          'monthlyInstallment': 2833.33,
          'totalPayable': 68000,
          'approvalStatus': 'Pending',
        },
        {
          'id': 'approved-review',
          'memberName': 'Taylor Member',
          'loanType': 'gold',
          'principal': 30000,
          'approvalStatus': 'Approved',
        },
        {
          'id': 'rejected-review',
          'memberName': 'Morgan Member',
          'loanType': 'personal',
          'principal': 20000,
          'approvalStatus': 'Rejected',
        },
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'loan_update': true},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initialLoanFetchCount = apiService.fetchActions
        .where((action) => action.startsWith('getLoans:'))
        .length;
    await _openDrawerPage(tester, 'navigation-menu-loan-master');

    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(find.text('Loan applications'), findsNothing);
    expect(
      apiService.fetchActions
          .where((action) => action.startsWith('getLoans:'))
          .length,
      initialLoanFetchCount,
    );
    await _openDrawerPage(tester, 'navigation-menu-personal-loan');
    expect(find.byKey(const Key('loan-scheme-management')), findsNothing);
    expect(find.byKey(const Key('add-loan')), findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(
        find.byKey(const Key('loan-application-pending-review')), findsNothing);

    await _openDrawerPage(tester, 'navigation-menu-approved-loans');
    final approvedApplication =
        find.byKey(const Key('loan-application-approved-review'));
    await _scrollUntilBuilt(
      tester,
      approvedApplication,
      find.byType(ListView).first,
    );
    expect(approvedApplication, findsOneWidget);
    expect(
        find.byKey(const Key('loan-application-pending-review')), findsNothing);
    expect(find.byKey(const Key('loan-application-rejected-review')),
        findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(find.byKey(const Key('approve-loan-pending-review')), findsNothing);
    expect(find.byKey(const Key('reject-loan-pending-review')), findsNothing);
    expect(apiService.fetchActions, contains('getLoans:all:approved'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Collector and Member see only approved loan data',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'collector-approved-personal',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'schemeName': 'Personal Standard',
          'principal': 10000,
          'approvalStatus': 'Approved',
        },
        {
          'id': 'collector-pending',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'principal': 12000,
          'approvalStatus': 'Pending',
        },
        {
          'id': 'collector-approved-gold',
          'memberName': 'Taylor Member',
          'loanType': 'gold',
          'principal': 15000,
          'approvalStatus': 'Approved',
        },
      ]);
    const collector = AuthSession(
      token: 'collector-token',
      userId: 'collector-1',
      name: 'Collector',
      email: 'collector@example.com',
      role: 'Collector',
      permissions: {
        'loan_view': true,
        'loan_edit': true,
        'loan_delete': true,
        'loan_update': true,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedLoansPage(
          apiService: apiService,
          session: collector,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(apiService.fetchActions, contains('getLoans:all:approved'));
    expect(
      find.byKey(const Key('loan-application-collector-approved-personal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('loan-application-collector-approved-gold')),
      findsOneWidget,
    );
    final collectorApprovedLabel = find.descendant(
      of: find.byKey(
        const Key('application-status-collector-approved-personal'),
      ),
      matching: find.text('Approved'),
    );
    expect(
      tester.widget<Text>(collectorApprovedLabel).style?.color,
      portalToastSuccessColor,
    );
    expect(find.byKey(const Key('loan-application-collector-pending')),
        findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(
        find.byKey(const Key('approve-loan-collector-pending')), findsNothing);
    expect(
        find.byKey(const Key('reject-loan-collector-pending')), findsNothing);
    expect(find.byKey(const Key('add-loan')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: ApprovedLoansPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('loan-application-collector-approved-personal')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('loan-application-collector-approved-gold')),
        findsNothing);
    expect(find.byKey(const Key('loan-application-collector-pending')),
        findsNothing);
    expect(find.byKey(const Key('loan-approval-section')), findsNothing);
    expect(
        find.byKey(const Key('approve-loan-collector-pending')), findsNothing);
    expect(find.byKey(const Key('add-loan')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member loan menu shows own Personal, Gold, and Approved pages',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'member-approved-loan',
          'memberName': 'Jordan Member',
          'loanType': 'personal',
          'approvalStatus': 'Approved',
          'principal': 10000,
        },
        {
          'id': 'other-member-approved-loan',
          'memberName': 'Taylor Member',
          'loanType': 'gold',
          'approvalStatus': 'Approved',
          'principal': 20000,
        },
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-loans')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('navigation-menu-loan-master')), findsNothing);
    expect(
      find.byKey(const Key('navigation-menu-personal-loan')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('navigation-menu-gold-loan')), findsOneWidget);
    expect(
      find.byKey(const Key('navigation-menu-approved-loans')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('navigation-menu-gold-loan')));
    await tester.pumpAndSettle();
    expect(find.text('Gold Loan'), findsWidgets);
    expect(find.byKey(const Key('add-loan')), findsOneWidget);
    await _openDrawerPage(tester, 'navigation-menu-approved-loans');
    expect(
      find.byKey(const Key('loan-card-member-approved-loan')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('loan-card-other-member-approved-loan')),
      findsNothing,
    );
    expect(apiService.fetchActions, contains('getLoans:all:approved'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cashfree payment shows member details and 2% service charge',
      (WidgetTester tester) async {
    const cashfreeChannel = MethodChannel('flutter_cashfree_pg_sdk');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, (_) async => null);
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
            accountNumber: 'DRD000000001',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jordan Member'), findsNWidgets(2));
    expect(find.text('Account number'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '125',
    );
    await tester.pump();

    expect(find.text('₹2.50'), findsOneWidget);
    expect(find.text('₹127.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, null);
  });

  testWidgets('Cashfree order creation uses the shared portal loader',
      (WidgetTester tester) async {
    const cashfreeChannel = MethodChannel('flutter_cashfree_pg_sdk');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, (_) async => null);
    final apiService = _CashfreeTestApiService()
      ..createOrderCompleter = Completer<CashfreeOrder>();
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: '',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('cashfree-start-payment')));
    await tester.tap(find.byKey(const Key('cashfree-start-payment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    expect(find.text('Preparing secure payment'), findsOneWidget);
    expect(find.byType(PortalOrbitLoader), findsOneWidget);

    apiService.createOrderCompleter!.complete(
      const CashfreeOrder(
        orderId: 'NTC-no-account',
        paymentSessionId: 'test-session',
        environment: 'sandbox',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byKey(const Key('portal-loading-state')), findsNothing);
    expect(tester.takeException(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, null);
  });

  testWidgets('Cashfree checkout stays usable on a narrow phone screen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: '',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.byKey(const Key('cashfree-start-payment')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cashfree payment does not require a member account number',
      (WidgetTester tester) async {
    const cashfreeChannel = MethodChannel('flutter_cashfree_pg_sdk');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, (_) async => null);
    final apiService = _CashfreeTestApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jordan Member'), findsNWidgets(2));
    expect(find.text('Account number'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-customer-name')),
      'Updated customer',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-customer-email')),
      'customer@example.com',
    );
    await tester.ensureVisible(find.byKey(const Key('cashfree-start-payment')));
    await tester.tap(find.byKey(const Key('cashfree-start-payment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      apiService.createOrderCalls.single,
      containsPair('memberId', null),
    );
    expect(apiService.createOrderCalls.single['customerPhone'], '9876543210');
    expect(
        apiService.createOrderCalls.single['customerName'], 'Updated customer');
    expect(
      apiService.createOrderCalls.single['customerEmail'],
      'customer@example.com',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, null);
  });

  testWidgets('schedule checkout locks amount and sends selected installment',
      (WidgetTester tester) async {
    const cashfreeChannel = MethodChannel('flutter_cashfree_pg_sdk');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, (_) async => null);
    final apiService = _CashfreeTestApiService();
    const target = CashfreeScheduleTarget.deposit(
      depositId: 'deposit-1',
      periodIndex: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
            phoneNumber: '9876543210',
          ),
          fixedAmountPaise: 2500,
          scheduleTarget: target,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final amountField = tester.widget<TextField>(
      find.byKey(const Key('cashfree-payment-amount')),
    );
    expect(amountField.readOnly, isTrue);
    expect(amountField.controller!.text, '25.00');
    expect(find.text('₹25.50'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('cashfree-start-payment')));
    await tester.tap(find.byKey(const Key('cashfree-start-payment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(apiService.createOrderCalls.single['baseAmount'], 25);
    expect(apiService.createOrderCalls.single['scheduleTarget'], {
      'kind': 'deposit',
      'id': 'deposit-1',
      'periodIndex': 2,
    });
    expect(tester.takeException(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, null);
  });

  testWidgets('Cashfree checkout errors without an order ID release payment',
      (WidgetTester tester) async {
    const cashfreeChannel = MethodChannel('flutter_cashfree_pg_sdk');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, (call) async {
      if (call.method == 'doWebPayment') {
        return jsonEncode({
          'status': 'exception',
          'data': {'message': 'Checkout failed to launch'},
        });
      }
      return null;
    });
    final apiService = _CashfreeTestApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.byKey(const Key('cashfree-start-payment')));
    await tester.tap(find.byKey(const Key('cashfree-start-payment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(apiService.verifiedOrderIds, ['NTC-no-account']);
    expect(find.text('Check payment status'), findsOneWidget);
    expect(
      find.textContaining(
          'Payment was not confirmed: Checkout failed to launch'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('payment-success-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, null);
  });

  testWidgets('verified Cashfree success opens payment success page',
      (WidgetTester tester) async {
    const cashfreeChannel = MethodChannel('flutter_cashfree_pg_sdk');
    var responseCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, (call) async {
      if (call.method == 'response') {
        responseCalls++;
        if (responseCalls == 2) {
          return jsonEncode({
            'status': 'success',
            'data': {'order_id': 'NTC-no-account'},
          });
        }
      }
      return null;
    });
    final apiService = _CashfreeTestApiService(
      paid: true,
      scheduleApplied: true,
    );
    var paymentVerified = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          onPaymentVerified: () => paymentVerified = true,
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('cashfree-start-payment')));
    await tester.tap(find.byKey(const Key('cashfree-start-payment')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(apiService.verifiedOrderIds, ['NTC-no-account']);
    expect(find.byKey(const Key('payment-success-title')), findsOneWidget);
    expect(find.byKey(const Key('payment-success-dialog')), findsOneWidget);
    expect(find.text('₹102.00').last, findsOneWidget);
    expect(find.text('NTC-no-account'), findsOneWidget);
    expect(
      find.text('RD monthly installment 1 (2026-10-23)'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('payment-success-done')), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment-success-title')), findsNothing);
    expect(find.byKey(const Key('cashfree-start-payment')), findsOneWidget);
    expect(paymentVerified, isTrue);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cashfreeChannel, null);
  });

  testWidgets('payment success warns when its schedule was not updated',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-payment-warning'),
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const PaymentSuccessPage(
                  orderId: 'NTC-no-account',
                  amount: '₹102.00',
                  scheduleApplied: false,
                  scheduleDescription:
                      'No matching unpaid installment was available.',
                ),
              ),
              child: const Text('Show success'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-payment-warning')));
    await tester.pump();

    expect(find.byKey(const Key('payment-success-title')), findsOneWidget);
    expect(find.byKey(const Key('payment-success-dialog')), findsOneWidget);
    expect(find.byKey(const Key('payment-schedule-warning')), findsOneWidget);
    expect(
      find.text('No matching unpaid installment was available.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment success colors adapt with light and dark themes',
      (WidgetTester tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final colorScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF3458D4),
        brightness: brightness,
      );
      final theme = ThemeData(
        colorScheme: colorScheme,
        brightness: brightness,
      );
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(brightness),
          theme: theme,
          darkTheme: theme,
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  key: const Key('open-themed-payment-success'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const PaymentSuccessPage(
                      orderId: 'NTC-themed',
                      amount: '₹102.00',
                      scheduleApplied: true,
                      scheduleDescription: 'Schedule installment updated.',
                    ),
                  ),
                  child: const Text('Show success'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-themed-payment-success')));
      await tester.pump();

      final header = tester.widget<DecoratedBox>(
        find.byKey(const Key('payment-success-header')),
      );
      final gradient =
          (header.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors, [
        colorScheme.primaryContainer,
        colorScheme.tertiaryContainer,
      ]);

      final title = tester.widget<Text>(
        find.byKey(const Key('payment-success-title')),
      );
      expect(title.style?.color, colorScheme.onPrimaryContainer);
      expect(
        _contrastRatio(
          colorScheme.onPrimaryContainer,
          colorScheme.primaryContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(
          colorScheme.onPrimaryContainer,
          colorScheme.tertiaryContainer,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        tester
            .widget<Icon>(find.byKey(const Key('payment-success-check-icon')))
            .color,
        colorScheme.onPrimaryContainer,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('payment success shows countdown and redirects after ten seconds',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('Dashboard', key: Key('dashboard-home')),
              Builder(
                builder: (context) => TextButton(
                  key: const Key('open-payment-success'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const PaymentSuccessPage(
                      orderId: 'NTC-no-account',
                      amount: '₹102.00',
                      scheduleApplied: true,
                      scheduleDescription: 'RD monthly installment 1',
                    ),
                  ),
                  child: const Text('Open success page'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-payment-success')));
    await tester.pump();
    final initialIconScale = tester
        .widget<Transform>(
          find.byKey(const Key('payment-success-icon-transform')),
        )
        .transform
        .storage[0];
    expect(initialIconScale, closeTo(0.55, 0.01));
    await tester.pump(const Duration(milliseconds: 300));
    final animatedIconScale = tester
        .widget<Transform>(
          find.byKey(const Key('payment-success-icon-transform')),
        )
        .transform
        .storage[0];
    expect(animatedIconScale, greaterThan(initialIconScale));
    expect(animatedIconScale, lessThan(1));
    await tester.pump(const Duration(milliseconds: 300));
    final completedIconScale = tester
        .widget<Transform>(
          find.byKey(const Key('payment-success-icon-transform')),
        )
        .transform
        .storage[0];
    expect(completedIconScale, closeTo(1, 0.001));
    expect(find.byKey(const Key('payment-success-title')), findsOneWidget);
    expect(find.byKey(const Key('payment-success-dialog')), findsOneWidget);
    expect(find.byKey(const Key('payment-success-header')), findsOneWidget);
    expect(find.byKey(const Key('payment-success-amount')), findsOneWidget);
    expect(find.byKey(const Key('payment-success-progress')), findsOneWidget);
    expect(find.text('Returning to dashboard in 10 seconds…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9, milliseconds: 600));
    expect(find.byKey(const Key('payment-success-title')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-home')), findsOneWidget);
    expect(find.byKey(const Key('payment-success-title')), findsNothing);
    expect(find.byKey(const Key('payment-success-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cashfree payment requires amount and mobile, not name or email',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: '',
            email: '',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const Key('cashfree-payment-requirements')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNotNull,
    );
    expect(
        find.text('Your member account details are incomplete.'), findsNothing);
  });

  testWidgets('Cashfree configuration error explains Script Property setup',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: _CashfreeConfigurationFailureApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: '',
            role: 'Member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '100',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('cashfree-start-payment')));
    await tester.tap(find.byKey(const Key('cashfree-start-payment')));
    await tester.pumpAndSettle();

    expect(find.text('Cashfree setup required'), findsOneWidget);
    expect(find.textContaining('CASHFREE_APP_ID'), findsOneWidget);
    expect(find.textContaining('CASHFREE_SECRET_KEY'), findsOneWidget);
    expect(find.textContaining('CASHFREE_ENVIRONMENT'), findsOneWidget);
  });

  testWidgets('staff can search and select a member for Cashfree payment',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()..users[1].remove('accountNo');
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashfree-select-member')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cashfree-select-member')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashfree-member-search')),
      'taylor@example.com',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    expect(find.text('Morgan Member'), findsNothing);
    await tester.tap(find.byKey(const Key('cashfree-member-user-2')));
    await tester.pumpAndSettle();

    expect(find.text('Taylor Member'), findsNWidgets(2));
    expect(find.text('Account number'), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('cashfree-selected-member-name')),
          )
          .style
          ?.fontSize,
      14,
    );
    final staffPaymentNote = tester.widget<Text>(
      find.text(
        'The payment will be recorded for the selected member. '
        'A 2% service charge is added and Cashfree confirms the payment status.',
      ),
    );
    expect(staffPaymentNote.style?.fontSize, 11);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-amount')),
      '25',
    );
    await tester.enterText(
      find.byKey(const Key('cashfree-payment-phone')),
      '9876543210',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'staff can select a member without name, email, or account number',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..users[1].remove('name')
      ..users[1].remove('email')
      ..users[1].remove('accountNo');
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashfree-select-member')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cashfree-member-user-2')));
    await tester.pumpAndSettle();

    expect(find.text('Not available'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('staff cannot pay for a selected member without an internal ID',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()..users[1].remove('id');
    await tester.pumpWidget(
      MaterialApp(
        home: CashfreePaymentPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashfree-select-member')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taylor Member'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The selected Member is missing an internal ID. Contact an administrator.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('cashfree-start-payment')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('portal loading state uses the shared splash orbit loader',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PortalLoadingState(label: 'Loading accounts'),
      ),
    );

    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    expect(find.byType(PortalOrbitLoader), findsOneWidget);
    expect(find.text('Loading accounts'), findsOneWidget);
    expect(find.text('SECURE FINANCE PORTAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infinity loader animates and honors requested size',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PortalOrbitLoader(
              key: Key('test-infinity-loader'),
              size: 64,
              semanticsLabel: 'Loading data',
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('test-infinity-loader'))),
      const Size.square(64),
    );
    expect(find.bySemanticsLabel('Loading data'), findsOneWidget);
    final firstPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('test-infinity-loader')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;

    await tester.pump(const Duration(milliseconds: 500));
    final nextPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('test-infinity-loader')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    expect(firstPainter.shouldRepaint(nextPainter), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portal loading feedback stays visible during async actions',
      (WidgetTester tester) async {
    final completion = Completer<void>();
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('run-loading-action'),
              onPressed: () async {
                await withPortalLoading(
                  context,
                  label: 'Updating record',
                  action: () => completion.future,
                );
                finished = true;
              },
              child: const Text('Update'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('run-loading-action')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    expect(find.text('Updating record'), findsOneWidget);
    expect(finished, isFalse);

    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('portal-loading-state')), findsNothing);
    expect(finished, isTrue);
  });

  test('profile image data URLs use in-memory image providers', () {
    const image =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA9sAAAAASUVORK5CYII=';
    expect(profileImageProvider(image), isA<MemoryImage>());
    expect(profileImageProvider('data:image/png;base64,not-base64!'), isNull);
    expect(profileImageProvider('http://example.com/avatar.png'), isNull);
  });

  testWidgets('toastify styling distinguishes status and supports dismissal',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  key: const Key('show-success-toast'),
                  onPressed: () => showPortalToast(context, 'Saved.'),
                  child: const Text('Success'),
                ),
                TextButton(
                  key: const Key('show-error-toast'),
                  onPressed: () =>
                      showPortalToast(context, 'Failed.', isError: true),
                  child: const Text('Error'),
                ),
                TextButton(
                  key: const Key('show-delete-toast'),
                  onPressed: () => showPortalToast(
                    context,
                    'Deleted.',
                    isDestructive: true,
                  ),
                  child: const Text('Delete'),
                ),
                TextButton(
                  key: const Key('show-info-toast'),
                  onPressed: () =>
                      showPortalToast(context, 'Information.', isInfo: true),
                  child: const Text('Info'),
                ),
                TextButton(
                  key: const Key('show-warning-toast'),
                  onPressed: () => showPortalToast(
                    context,
                    'Warning.',
                    isWarning: true,
                  ),
                  child: const Text('Warning'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('show-success-toast')));
    await tester.pump();
    expect(
      tester.widget<Material>(find.byKey(const Key('portal-toast'))).color,
      Theme.of(tester.element(find.byKey(const Key('portal-toast'))))
          .colorScheme
          .surfaceContainerHigh,
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastSuccessColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastSuccessColor,
    );
    expect(find.byKey(const Key('portal-toast-timeout')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('portal-toast-message')))
          .style
          ?.fontSize,
      Theme.of(tester.element(find.byKey(const Key('portal-toast-message'))))
          .textTheme
          .titleSmall
          ?.fontSize,
    );
    expect(
      tester.getSize(find.byKey(const Key('portal-toast-icon-container'))),
      const Size(48, 48),
    );

    await tester.tap(find.byKey(const Key('show-error-toast')));
    await tester.pump();
    expect(
      tester.widget<Material>(find.byKey(const Key('portal-toast'))).color,
      Theme.of(tester.element(find.byKey(const Key('portal-toast'))))
          .colorScheme
          .surfaceContainerHigh,
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastErrorColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastErrorColor,
    );

    await tester.tap(find.byKey(const Key('show-delete-toast')));
    await tester.pump();
    expect(
      tester.widget<Material>(find.byKey(const Key('portal-toast'))).color,
      Theme.of(tester.element(find.byKey(const Key('portal-toast'))))
          .colorScheme
          .surfaceContainerHigh,
    );
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('portal-toast-dismiss')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('portal-toast')), findsNothing);

    await tester.tap(find.byKey(const Key('show-info-toast')));
    await tester.pump();
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastInfoColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastInfoColor,
    );
    await tester.tap(find.byKey(const Key('portal-toast-dismiss')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('show-warning-toast')));
    await tester.pump();
    expect(
      tester.widget<Icon>(find.byKey(const Key('portal-toast-icon'))).color,
      portalToastWarningColor,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('portal-toast-timeout')))
          .color,
      portalToastWarningColor,
    );
    await tester.tap(find.byKey(const Key('portal-toast-dismiss')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('show-success-toast')));
    await tester.pump();
    expect(find.byKey(const Key('portal-toast')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('portal-toast')), findsNothing);
  });

  testWidgets('registration has separate route and validates password',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));

    await tester.ensureVisible(find.byKey(const Key('open-register')));
    await tester.tap(find.byKey(const Key('open-register')));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.byKey(const Key('register-name')), findsOneWidget);
    expect(find.byKey(const Key('register-logo')), findsOneWidget);
    expect(find.text('NTCCSL FINANCE SYSTEM'), findsOneWidget);
    expect(find.text('Already have an account?'), findsOneWidget);
    expect(find.byKey(const Key('register-sign-in')), findsOneWidget);
    final signInButton = tester.widget<TextButton>(
      find.byKey(const Key('register-sign-in')),
    );
    expect(
      signInButton.style!.backgroundColor!.resolve({}),
      const Color(0xFF253B8C).withValues(alpha: .08),
    );
    expect(
      signInButton.style!.side!.resolve({})!.color,
      const Color(0xFF253B8C).withValues(alpha: .35),
    );
    final registerCard = tester.widget<Card>(
      find.byKey(const Key('register-account-card')),
    );
    final registerColors =
        Theme.of(tester.element(find.byType(RegisterPage))).colorScheme;
    expect(
      registerCard.color,
      Color.alphaBlend(
        const Color(0xFF253B8C).withValues(alpha: .07),
        registerColors.surface,
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('register-submit')))
          .style!
          .backgroundColor!
          .resolve({}),
      const Color(0xFF253B8C),
    );

    await tester.enterText(
        find.byKey(const Key('register-name')), 'Sam Member');
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secure-pass',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'different-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(apiService.didRegister, isFalse);

    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secure-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();
    expect(apiService.didRegister, isTrue);
    expect(
      find.text('Registration successful. You can now sign in.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SegmentedButton<String>>(
            find.byKey(const Key('login-account-type')),
          )
          .selected,
      {'member'},
    );
  });

  testWidgets('registration sign-in link returns to login page',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );
    await tester.ensureVisible(find.byKey(const Key('open-register')));
    await tester.tap(find.byKey(const Key('open-register')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('register-sign-in')));
    await tester.tap(find.byKey(const Key('register-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.byKey(const Key('register-name')), findsNothing);
  });

  testWidgets('registration accents adapt to light and dark themes',
      (WidgetTester tester) async {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9EB4FF),
      brightness: Brightness.dark,
      surface: const Color(0xFF191B23),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: darkScheme,
          brightness: Brightness.dark,
        ),
        themeMode: ThemeMode.dark,
        home: RegisterPage(apiService: _FakeApiService()),
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const Key('register-system-name')))
          .style
          ?.color,
      darkScheme.primary,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('register-sign-in')))
          .style!
          .foregroundColor!
          .resolve({}),
      darkScheme.primary,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3458D4),
            brightness: Brightness.light,
            surface: Colors.white,
          ),
          brightness: Brightness.light,
        ),
        themeMode: ThemeMode.light,
        home: RegisterPage(apiService: _FakeApiService()),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('register-system-name')))
          .style
          ?.color,
      const Color(0xFF253B8C),
    );
  });

  testWidgets('login displays server error when login action is unsupported',
      (WidgetTester tester) async {
    final apiService = ApiService(
      client: _RecordingHttpClient([
        {'status': 'error', 'message': 'unknown post action'},
      ]),
    );
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'member@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'password123',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('does not support email/password login yet'),
      findsOneWidget,
    );
    expect(find.text('Amount (Ledger)'), findsNothing);
  });

  testWidgets('registration button turns dark while creating account',
      (WidgetTester tester) async {
    final apiService = _PendingRegisterApiService();
    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(apiService: apiService)),
    );
    await tester.enterText(
      find.byKey(const Key('register-name')),
      'Sam Member',
    );
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secure-pass',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secure-pass',
    );

    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pump();

    expect(find.text('Creating account…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('register-submit')),
    );
    expect(button.onPressed, isNull);
    expect(
      button.style!.backgroundColor!.resolve({WidgetState.disabled}),
      const Color.fromARGB(255, 6, 9, 21),
    );

    apiService.completion.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('forgot password explains administrator reset process',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );

    await tester.ensureVisible(find.byKey(const Key('forgot-password')));
    await tester.tap(find.byKey(const Key('forgot-password')));
    await tester.pumpAndSettle();

    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.textContaining('Contact your portal administrator'),
        findsOneWidget);
    expect(find.textContaining('existing passwords cannot be viewed'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('forgot-password-dismiss')));
    await tester.pumpAndSettle();
  });

  testWidgets('login shows the NTCCSL logo', (WidgetTester tester) async {
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ntccsl-login-logo')), findsOneWidget);
    final accountTypeButton = tester.widget<SegmentedButton<String>>(
      find.byKey(const Key('login-account-type')),
    );
    final loginCard = tester.widget<Card>(
      find.byKey(const Key('login-account-card')),
    );
    final colors = Theme.of(tester.element(find.byType(LoginPage))).colorScheme;
    expect(
      loginCard.color,
      Color.alphaBlend(
        portalRoleColor('Admin').withValues(alpha: .08),
        colors.surface,
      ),
    );
    expect(
      accountTypeButton.style!.foregroundColor!.resolve({WidgetState.selected}),
      portalRoleColor('Admin'),
    );
    final signUpButton = tester.widget<TextButton>(
      find.byKey(const Key('open-register')),
    );
    expect(
      signUpButton.style!.backgroundColor!.resolve({}),
      portalRoleColor('Admin').withValues(alpha: .08),
    );
    expect(
      signUpButton.style!.side!.resolve({})!.color,
      portalRoleColor('Admin').withValues(alpha: .35),
    );
    await tester.tap(find.text('Member Login'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Card>(find.byKey(const Key('login-account-card'))).color,
      Color.alphaBlend(
        portalRoleColor('Member').withValues(alpha: .08),
        colors.surface,
      ),
    );
    final memberAccountTypeButton = tester.widget<SegmentedButton<String>>(
      find.byKey(const Key('login-account-type')),
    );
    expect(
      memberAccountTypeButton.style!.foregroundColor!
          .resolve({WidgetState.selected}),
      portalRoleColor('Member'),
    );
    expect(
      memberAccountTypeButton.style!.backgroundColor!
          .resolve({WidgetState.selected}),
      Color.alphaBlend(
        portalRoleColor('Member').withValues(alpha: .12),
        colors.surface,
      ),
    );
  });

  testWidgets('member login opens the individual member account',
      (WidgetTester tester) async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'token': 'member-session-token',
        'user': {
          'id': 'member-1',
          'accountNo': 'DRD000000001',
          'name': 'Jordan Member',
          'email': 'jordan@example.com',
          'role': 'Member',
        },
        'permissions': {
          'shared_data_read': false,
          'deposit_view': false,
          'deposit_manage': false,
          'loan_view': false,
          'loan_manage': false,
          'ledger_manage': false,
          'user_manage': false,
        },
        'reportAccess': {
          'daily': true,
          'weekly': false,
          'monthly': false,
        },
      },
      [
        {
          'memberName': 'Jordan Member',
          'date': '2026-01-01',
          'depAmt': 25,
          'totalCount': 1,
          'totalReceived': 25,
          'periods': [true],
          'rowIndex': 2,
        },
      ],
      [
        {
          'memberName': 'Jordan Member',
          'date': '2026-01-01',
          'depAmt': 25,
          'totalCount': 1,
          'totalReceived': 25,
          'periods': [true],
          'rowIndex': 2,
        },
      ],
      <dynamic>[],
      [
        {
          'memberName': 'Jordan Member',
          'date': '2026-01-01',
          'depAmt': 25,
          'totalCount': 1,
          'totalReceived': 25,
          'periods': [true],
          'rowIndex': 2,
        },
      ],
    ]);
    await tester.pumpWidget(
      NtccslAccountApp(apiService: ApiService(client: client)),
    );

    await tester.tap(find.text('Member Login'));
    await tester.pumpAndSettle();
    expect(find.text('Email or account number'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'jordan@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'member-password',
    );
    await tester.ensureVisible(find.byKey(const Key('login-submit')));
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(client.payloads.first['loginType'], 'member');
    expect(client.payloads.first['identifier'], 'jordan@example.com');
    expect(client.payloads.first['email'], 'jordan@example.com');
    expect(client.payloads.first['password'], 'member-password');
    expect(
      client.payloads.map((payload) => payload['action']),
      isNot(contains('getWeekly')),
    );
    expect(
      client.payloads.map((payload) => payload['action']),
      isNot(contains('getMonthly')),
    );
    expect(_bottomNavigationItems(), findsNWidgets(2));
    expect(_bottomNavigationLabels(), {'Dashboard', 'Pay'});
    expect(find.byKey(const Key('bottom-navigation-pay')), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation-deposit')), findsNothing);
    expect(client.payloads.map((payload) => payload['action']),
        isNot(contains('getDaily')));
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-existing-collections')),
        findsNothing);
    expect(find.byKey(const Key('navigation-menu-daily')), findsNothing);
  });

  test('member names normalize case and whitespace', () {
    const session = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
    );

    expect(session.matchesMemberName('  jordan   member  '), isTrue);
    expect(session.matchesMemberName('Other Member'), isFalse);
    expect(session.matchesMemberName(null), isFalse);
  });

  testWidgets('startup splash centers fitted logo and shows society name',
      (WidgetTester tester) async {
    _mockPackageInfo();
    await tester.pumpWidget(
      NtccslAccountApp(
        apiService: _FakeApiService(),
        showSplashScreen: true,
      ),
    );

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.text(SplashPage.appName), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(find.text('Version - 1.2.2'), findsOneWidget);
    expect(find.byKey(const Key('splash-logo')), findsOneWidget);
    expect(find.text('NoFino Thrift & Credit'), findsOneWidget);
    expect(find.text('Co-Operative Society Ltd.'), findsOneWidget);
    expect(find.text('Seeding Growth, Nurturing Futures'), findsOneWidget);
    final logo = tester.widget<Image>(find.byKey(const Key('splash-logo')));
    expect(logo.fit, BoxFit.contain);
    expect(
        tester.getCenter(find.byKey(const Key('splash-logo'))).dx,
        moreOrLessEquals(
            tester.view.physicalSize.width / tester.view.devicePixelRatio / 2));
    expect(find.byKey(const Key('splash-loading-indicator')), findsOneWidget);
    expect(find.byKey(const Key('splash-orbiting-loader')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Getting things ready'), findsOneWidget);
    expect(find.text('SECURE FINANCE PORTAL'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 4999));
    expect(find.byType(SplashPage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.byType(SplashPage), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('splash surfaces use dark theme colors',
      (WidgetTester tester) async {
    _mockPackageInfo();
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3458D4),
        brightness: Brightness.dark,
      ),
      brightness: Brightness.dark,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: const SplashPage(),
      ),
    );

    final colors = darkTheme.colorScheme;
    final splashContext = tester.element(find.byType(SplashPage));
    expect(Theme.of(splashContext).brightness, Brightness.dark);
    expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, isNull);
    expect(
      tester
          .widget<Container>(find.byKey(const Key('splash-logo-backdrop')))
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'color',
        colors.surfaceContainerHighest,
      ),
    );
    expect(
      (tester
              .widget<Container>(
                find.byKey(const Key('splash-loading-indicator')),
              )
              .decoration as BoxDecoration)
          .color,
      colors.surfaceContainerHighest,
    );
  });

  testWidgets('navigation header shows the signed-in user profile',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Admin Name',
            email: 'admin@example.com',
            role: 'Admin',
            accountNumber: 'ACC-1001',
            profileImageUrl:
                'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA9sAAAAASUVORK5CYII=',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ntccsl-app-icon')), findsOneWidget);
    expect(find.text('Admin Name'), findsOneWidget);
    expect(find.text('Account No: ACC-1001'), findsOneWidget);
    expect(find.text('Email: admin@example.com'), findsOneWidget);
    expect(find.text('Role: Admin'), findsOneWidget);
    expect(
      tester
          .widget<Image>(find.byKey(const Key('navigation-user-image')))
          .image,
      isA<MemoryImage>(),
    );
  });

  testWidgets('registration reports backend error without false success',
      (WidgetTester tester) async {
    final apiService = ApiService(
      client: _RecordingHttpClient(['unknown post action']),
    );
    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(apiService: apiService)),
    );

    await tester.enterText(find.byKey(const Key('register-name')), 'Sam');
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'sam@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secure-pass',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secure-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('register-submit')));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-error')), findsOneWidget);
    expect(find.text('Registration successful.'), findsNothing);
  });

  testWidgets('users can sign in and see account navigation',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));

    expect(find.text('Continue'), findsOneWidget);
    await _signIn(tester);

    expect(find.text('Signed in successfully.'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.byKey(const Key('open-navigation-menu')), findsOneWidget);
    expect(_bottomNavigationItems(), findsNWidgets(5));
    expect(
      _bottomNavigationLabels(),
      {'Dashboard', 'FD', 'RD', 'DRD', 'Users'},
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Accounts'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ntccsl-app-icon')), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-accounts')), findsOneWidget);
    await _ensureDrawerItemVisible(
      tester,
      find.byKey(const Key('navigation-menu-users')),
    );
    expect(find.byKey(const Key('navigation-menu-users')), findsOneWidget);
    await tester.tap(find.byKey(const Key('navigation-menu-users')));
    await tester.pumpAndSettle();
    expect(find.text('Users List'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-menu-profile')), findsOneWidget);
    expect(find.byKey(const Key('profile-menu-logout')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-menu-profile')));
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.byKey(const Key('profile-name')).evaluate().single.widget,
        isA<Text>());
    expect(find.byKey(const Key('profile-role')).evaluate().single.widget,
        isA<Text>());
    expect(find.text('Admin'), findsNWidgets(2));
    expect(find.text('admin@example.com'), findsOneWidget);
    expect(find.byKey(const Key('profile-account-number')), findsOneWidget);
    expect(
      (tester
          .widget<Text>(
            find.byKey(const Key('profile-account-number')),
          )
          .data!),
      matches(RegExp(r'^ADM\d{9}$')),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('navigation-menu-existing-collections')),
        findsNothing);
  });

  testWidgets('profile dropdown logs out the signed-in user',
      (WidgetTester tester) async {
    var didLogout = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
          ),
          onLogout: () => didLogout = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
    final colors =
        Theme.of(tester.element(find.byKey(const Key('open-profile'))))
            .colorScheme;
    final profileMenu = find.byKey(const Key('profile-menu-profile'));
    final profileIcon = tester.widget<Icon>(
      find.descendant(of: profileMenu, matching: find.byType(Icon)),
    );
    final profileTitle = tester.widget<Text>(
      find.descendant(of: profileMenu, matching: find.text('Profile')),
    );
    expect(profileIcon.color, colors.primary);
    expect(profileTitle.style?.color, colors.primary);
    final logoutMenu = find.byKey(const Key('profile-menu-logout'));
    final logoutIcon = tester.widget<Icon>(
      find.descendant(of: logoutMenu, matching: find.byType(Icon)),
    );
    final logoutTitle = tester.widget<Text>(
      find.descendant(of: logoutMenu, matching: find.text('Logout')),
    );
    expect(logoutIcon.color, colors.error);
    expect(logoutTitle.style?.color, colors.error);
    await tester.tap(find.byKey(const Key('profile-menu-logout')));
    await tester.pumpAndSettle();

    expect(didLogout, isTrue);
    expect(find.text('Signed out successfully.'), findsOneWidget);
  });

  testWidgets('support is a separate page outside the deposit menu',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byKey(const Key('navigation-menu-support')),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('navigation-menu-support')));
    await tester.pumpAndSettle();

    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Get in touch'), findsOneWidget);
    expect(find.text('+91 9282956845'), findsOneWidget);
    expect(find.text('support@ntccsl.in'), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation-support')), findsNothing);

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-deposit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-support')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('navigation-menu-support')),
        matching: find.byKey(const Key('navigation-menu-deposit')),
      ),
      findsNothing,
    );
  });

  testWidgets('support page adapts its hero to light and dark themes',
      (WidgetTester tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3458D4),
              brightness: brightness,
            ),
            useMaterial3: true,
          ),
          home: const TickerMode(
            enabled: false,
            child: SupportPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hero = tester.widget<Container>(
        find.byKey(const Key('support-hero')),
      );
      final decoration = hero.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      if (brightness == Brightness.dark) {
        expect(
          gradient.colors,
          const [Color(0xFF253B8C), Color(0xFF50346F)],
        );
      } else {
        expect(
          gradient.colors,
          isNot(const [Color(0xFF253B8C), Color(0xFF50346F)]),
        );
      }
      expect(find.text('Get in touch'), findsOneWidget);
      expect(find.text('Visit our website'), findsOneWidget);
      expect(find.text('ntccsl.in'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find
                  .ancestor(
                    of: find.text('ntccsl.in'),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .onTap,
        isNotNull,
      );
    }
  });

  testWidgets('support WhatsApp button opens a prefilled office message',
      (WidgetTester tester) async {
    String? launchedUrl;
    var launchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, (call) async {
      expect(call.method, 'launch');
      launchedUrl = (call.arguments as Map)['url'] as String;
      return launchResult;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_urlLauncherChannel, null),
    );

    await tester.pumpWidget(const MaterialApp(home: SupportPage()));
    await tester.pump(const Duration(milliseconds: 300));
    final animatedIcon = tester.widget<Transform>(
      find.byKey(const Key('support-whatsapp-icon-animation')),
    );
    expect(animatedIcon.transform.getMaxScaleOnAxis(), greaterThan(1));
    final brandIcon = animatedIcon.child! as FaIcon;
    expect(brandIcon.icon?.codePoint, FontAwesomeIcons.whatsapp.codePoint);
    await tester.pump(const Duration(milliseconds: 400));
    final nextPulse = tester.widget<Transform>(
      find.byKey(const Key('support-whatsapp-icon-animation')),
    );
    expect(nextPulse.transform.getMaxScaleOnAxis(), greaterThan(1.1));
    await tester.pump(const Duration(milliseconds: 700));
    final completedPulse = tester.widget<Transform>(
      find.byKey(const Key('support-whatsapp-icon-animation')),
    );
    expect(completedPulse.transform.getMaxScaleOnAxis(), closeTo(1, .01));
    await tester.pump(const Duration(milliseconds: 350));
    final continuingPulse = tester.widget<Transform>(
      find.byKey(const Key('support-whatsapp-icon-animation')),
    );
    expect(continuingPulse.transform.getMaxScaleOnAxis(), greaterThan(1));
    final button = find.byKey(const Key('support-whatsapp-button'));
    expect(button, findsOneWidget);
    final whatsappButton = tester.widget<FloatingActionButton>(button);
    expect(whatsappButton.tooltip, 'Message us on WhatsApp');
    expect(whatsappButton.backgroundColor, const Color(0xFF128C7E));
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      launchedUrl,
      Uri.https('wa.me', '/919282956845', {
        'text': 'Hello, I need help with my NTCCSL account.',
      }).toString(),
    );

    launchResult = false;
    await tester.tap(button);
    await tester.pump();
    expect(
      find.text('Could not open WhatsApp. Please try calling +91 9282956845.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('support office phone opens the dialer', (
    WidgetTester tester,
  ) async {
    String? launchedUrl;
    var launchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, (call) async {
      expect(call.method, 'launch');
      launchedUrl = (call.arguments as Map)['url'] as String;
      return launchResult;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_urlLauncherChannel, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(enabled: false, child: SupportPage()),
      ),
    );
    await tester.pumpAndSettle();
    final phone = find.text('+91 9282956845');
    await tester.ensureVisible(phone);
    await tester.tap(phone);
    await tester.pumpAndSettle();

    expect(launchedUrl, 'tel:+919282956845');

    launchResult = false;
    await tester.tap(phone);
    await tester.pump();
    expect(
      find.text('Could not start a call. Please dial +91 9282956845.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('support email opens a pre-addressed email composer', (
    WidgetTester tester,
  ) async {
    String? launchedUrl;
    var launchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, (call) async {
      expect(call.method, 'launch');
      launchedUrl = (call.arguments as Map)['url'] as String;
      return launchResult;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_urlLauncherChannel, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(enabled: false, child: SupportPage()),
      ),
    );
    await tester.pumpAndSettle();
    final email = find.text('support@ntccsl.in');
    await tester.ensureVisible(email);
    await tester.tap(email);
    await tester.pumpAndSettle();

    expect(
      launchedUrl,
      'mailto:support@ntccsl.in?subject=NTCCSL+account+support&body=Hello+NTCCSL+Support%2C%0A%0AI+need+help+with+my+account.%0A',
    );

    launchResult = false;
    await tester.tap(email);
    await tester.pump();
    expect(
      find.text(
        'Could not open your email app. Contact support@ntccsl.in.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('support chat answers loan and deposit questions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(enabled: false, child: SupportPage()),
      ),
    );
    await tester.pumpAndSettle();

    final chatButton = find.byKey(const Key('support-ai-chat-button'));
    await tester.ensureVisible(chatButton);
    await tester.tap(chatButton);
    await tester.pumpAndSettle();

    expect(find.text('AI Support Assistant'), findsOneWidget);
    expect(find.text('How do I apply for a loan?'), findsOneWidget);
    final sendButton = tester.widget<IconButton>(
      find.byKey(const Key('support-chat-send')),
    );
    expect(sendButton.tooltip, 'Send message');
    expect(sendButton.onPressed, isNull);
    expect(
      tester.getSize(find.byKey(const Key('support-chat-send-surface'))),
      const Size(52, 52),
    );
    await tester.tap(find.text('How do I apply for a loan?'));
    await tester.pumpAndSettle();
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Support assistant'), findsNWidgets(2));
    expect(find.textContaining('Applications stay Pending'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('support-chat-input')),
      'How do I view my deposits?',
    );
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('support-chat-send')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('support-chat-send')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Open the Deposit section'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('support-chat-send')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('top navigation menu opens, closes, and changes pages',
      (WidgetTester tester) async {
    var didLogout = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () => didLogout = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    final depositMenu = find.byKey(const Key('navigation-menu-deposit'));
    expect(depositMenu, findsOneWidget);
    await _expandDrawerTile(
      tester,
      depositMenu,
      find.byKey(const Key('navigation-menu-product-fd')),
    );
    expect(find.text('FD/RD/DRD'), findsNothing);

    final fdProduct = find.byKey(const Key('navigation-menu-product-fd'));
    final fdMonthly = find.byKey(const Key('navigation-menu-fd-monthly'));
    final fdProductTile = tester.widget<ExpansionTile>(fdProduct);
    final fdProductAvatar = fdProductTile.leading! as CircleAvatar;
    final fdProductIcon = fdProductAvatar.child! as Icon;
    expect(fdProductIcon.icon, Icons.savings_outlined);
    expect(fdProductIcon.color, const Color(0xFF3458D4));
    expect(
      fdProductAvatar.backgroundColor,
      const Color(0xFF3458D4).withValues(alpha: .12),
    );
    await _expandDrawerTile(tester, fdProduct, fdMonthly);
    expect(fdMonthly, findsOneWidget);
    final fdCadenceTile = tester.widget<ListTile>(fdMonthly);
    final fdCadenceAvatar = fdCadenceTile.leading! as CircleAvatar;
    final fdCadenceIcon = fdCadenceAvatar.child! as Icon;
    expect(fdCadenceIcon.icon, Icons.calendar_month_rounded);
    expect(fdCadenceIcon.color, const Color(0xFF3458D4));
    final rdProduct = find.byKey(const Key('navigation-menu-product-rd'));
    await _expandDrawerTile(tester, depositMenu, rdProduct);
    final rdProductTile = tester.widget<ExpansionTile>(rdProduct);
    final rdProductAvatar = rdProductTile.leading! as CircleAvatar;
    final rdProductIcon = rdProductAvatar.child! as Icon;
    expect(rdProductIcon.icon, Icons.event_repeat_rounded);
    expect(rdProductIcon.color, const Color(0xFF8E24AA));
    expect(
      rdProductAvatar.backgroundColor,
      const Color(0xFF8E24AA).withValues(alpha: .12),
    );
    final rdWeekly = find.byKey(const Key('navigation-menu-rd-weekly'));
    final rdMonthly = find.byKey(const Key('navigation-menu-rd-monthly'));
    await _expandDrawerTile(tester, rdProduct, rdWeekly);
    expect(rdWeekly, findsOneWidget);
    expect(rdMonthly, findsOneWidget);
    for (final cadence in ['weekly', 'monthly']) {
      final tile = tester.widget<ListTile>(
        find.byKey(Key('navigation-menu-rd-$cadence')),
      );
      final avatar = tile.leading! as CircleAvatar;
      final icon = avatar.child! as Icon;
      expect(
        icon.icon,
        cadence == 'weekly'
            ? Icons.calendar_view_week_rounded
            : Icons.calendar_month_rounded,
      );
      expect(icon.color, const Color(0xFF8E24AA));
    }
    final drdProduct = find.byKey(const Key('navigation-menu-product-drd'));
    await _expandDrawerTile(
      tester,
      depositMenu,
      drdProduct,
    );
    final drdProductTile = tester.widget<ExpansionTile>(drdProduct);
    final drdProductAvatar = drdProductTile.leading! as CircleAvatar;
    final drdProductIcon = drdProductAvatar.child! as Icon;
    expect(drdProductIcon.icon, Icons.calendar_month_rounded);
    expect(drdProductIcon.color, const Color(0xFF078A6A));
    expect(
      drdProductAvatar.backgroundColor,
      const Color(0xFF078A6A).withValues(alpha: .12),
    );
    await _ensureDrawerItemVisible(tester, drdProduct);
    await _expandDrawerTile(
      tester,
      drdProduct,
      find.byKey(const Key('navigation-menu-drd-daily')),
    );
    for (final cadence in ['daily', 'weekly', 'monthly']) {
      expect(
        find.byKey(Key('navigation-menu-drd-$cadence')),
        findsOneWidget,
      );
      final tile = tester.widget<ListTile>(
        find.byKey(Key('navigation-menu-drd-$cadence')),
      );
      final avatar = tile.leading! as CircleAvatar;
      final icon = avatar.child! as Icon;
      expect(
        icon.icon,
        switch (cadence) {
          'daily' => Icons.today_rounded,
          'weekly' => Icons.calendar_view_week_rounded,
          _ => Icons.calendar_month_rounded,
        },
      );
      expect(icon.color, const Color(0xFF078A6A));
    }
    expect(find.text('Test Admin'), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-drd-daily')), findsNothing);

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-existing-collections')),
        findsNothing);
    expect(find.byKey(const Key('navigation-menu-daily')), findsNothing);

    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-logout')));
    await tester.pumpAndSettle();
    expect(didLogout, isTrue);
    expect(find.text('Signed out successfully.'), findsOneWidget);
  });

  testWidgets('bottom navigation shows dashboard, deposit products, and users',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_bottomNavigationItems(), findsNWidgets(5));
    expect(
      _bottomNavigationLabels(),
      {'Dashboard', 'FD', 'RD', 'DRD', 'Users'},
    );
    expect(find.byKey(const Key('bottom-navigation-loans')), findsNothing);
    expect(find.byKey(const Key('bottom-navigation-scroll')), findsNothing);
    expect(find.byKey(const Key('bottom-navigation-fd')), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation-rd')), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation-drd')), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation-users')), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation-pay')), findsNothing);

    await tester.tap(find.byKey(const Key('bottom-navigation-rd')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('bottom-rd-picker-title')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bottom-deposit-option-4')), findsNothing);
    expect(find.byKey(const Key('bottom-deposit-option-5')), findsOneWidget);
    final rdMonthlyOption = find.byKey(const Key('bottom-deposit-option-6'));
    expect(rdMonthlyOption, findsOneWidget);
    await tester.tap(rdMonthlyOption);
    await tester.pumpAndSettle();
    expect(find.text('Recurring Deposit — Monthly'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await tester.tap(find.byKey(const Key('bottom-navigation-fd')));
    await tester.pumpAndSettle();
    expect(find.text('Fixed Deposit — Monthly'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bottom-navigation-drd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bottom-drd-picker-title')), findsOneWidget);
    expect(find.byKey(const Key('bottom-deposit-option-7')), findsOneWidget);
    await tester.tap(find.byKey(const Key('bottom-deposit-option-7')));
    await tester.pumpAndSettle();
    expect(find.text('Daily Recurring Deposit — Daily'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bottom-navigation-users')));
    await tester.pumpAndSettle();
    expect(find.text('Users List'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('deposit maturity calculations follow the confirmed terms', () {
    final startDate = DateTime(2026, 1, 31);
    final maturityDate = depositMaturityDate(startDate, 12);
    expect(maturityDate, DateTime(2027, 1, 31));
    expect(
      depositMaturityDate(startDate, 1),
      DateTime(2026, 2, 28),
    );
    expect(
      depositMaturityAmount(
        product: 'FD',
        cadence: 'monthly',
        amount: 10000,
        annualRate: 12,
        tenureMonths: 12,
        periodCount: 0,
      ),
      11268.25,
    );
    expect(
      depositMaturityAmount(
        product: 'RD',
        cadence: 'monthly',
        amount: 1000,
        annualRate: 12,
        tenureMonths: 12,
        periodCount: 12,
      ),
      12682.50,
    );
    final dailyDrdDates = depositPeriodDates(
      startDate: DateTime(2026, 1, 1),
      maturityDate: DateTime(2027, 1, 1),
      cadence: 'daily',
    );
    expect(dailyDrdDates, hasLength(365));
    expect(300 * dailyDrdDates.length, 109500);
    expect(
      depositMaturityAmount(
        product: 'DRD',
        cadence: 'daily',
        amount: 300,
        annualRate: 7,
        tenureMonths: 12,
        periodCount: dailyDrdDates.length,
      ),
      117165,
    );
    expect(
      depositPeriodDates(
        startDate: DateTime(2026, 1, 31),
        maturityDate: DateTime(2026, 4, 30),
        cadence: 'monthly',
      ),
      [DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30)],
    );
  });

  testWidgets('daily DRD form shows contribution and maturity estimates',
      (WidgetTester tester) async {
    final now = DateUtils.dateOnly(DateTime.now());
    final periodCount = depositPeriodDates(
      startDate: now,
      maturityDate: depositMaturityDate(now, 12),
      cadence: 'daily',
    ).length;
    final contributions = 300 * periodCount;
    final maturity = depositMaturityAmount(
      product: 'DRD',
      cadence: 'daily',
      amount: 300,
      annualRate: 7,
      tenureMonths: 12,
      periodCount: periodCount,
    );
    String money(num amount) => NumberFormat.currency(
          locale: 'en_IN',
          symbol: '₹',
          decimalDigits: 2,
        ).format(amount);

    await tester.pumpWidget(
      MaterialApp(
        home: DepositAccountPage(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          product: 'DRD',
          cadence: 'daily',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-deposit-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deposit-member-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('deposit-amount')), '300');
    await tester.enterText(find.byKey(const Key('deposit-annual-rate')), '7');
    await tester.pumpAndSettle();

    expect(
      find.text('Total scheduled contributions: ${money(contributions)}'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('deposit-maturity-estimate')))
          .data,
      contains(money(maturity)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('deposit menu respects member cadence access',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
            permissions: {'deposit_view': true},
            reportAccess: {
              'daily': true,
              'weekly': false,
              'monthly': false,
            },
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_bottomNavigationItems(), findsNWidgets(3));
    expect(_bottomNavigationLabels(), {'Dashboard', 'DRD', 'Pay'});
    expect(find.byKey(const Key('bottom-navigation-pay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('bottom-navigation-drd')));
    await tester.pumpAndSettle();
    expect(find.text('Daily Recurring Deposit — Daily'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bottom-navigation-pay')));
    await tester.pumpAndSettle();
    expect(find.text('Make a payment'), findsWidgets);
    expect(find.text('Payment details'), findsOneWidget);
  });

  testWidgets('deposit pages use dedicated view and manage permissions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'member-token',
            userId: 'member-1',
            name: 'Jordan Member',
            email: 'jordan@example.com',
            role: 'Member',
            permissions: {'deposit_view': true},
            reportAccess: {'daily': true, 'weekly': true, 'monthly': true},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigation-menu-deposit')), findsOneWidget);
    expect(find.byKey(const Key('navigation-menu-existing-collections')),
        findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'deposit_view': true},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDrawerPage(tester, 'navigation-menu-drd-daily');
    expect(find.byKey(const Key('add-deposit-account')), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Collector',
            email: 'collector@example.com',
            role: 'Collector',
            permissions: {'deposit_manage': true},
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDrawerPage(tester, 'navigation-menu-drd-daily');
    expect(find.byKey(const Key('add-deposit-account')), findsOneWidget);
  });

  testWidgets('deposit page supports retry and refresh from empty state',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..depositFetchError = StateError('offline');
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openDrawerPage(tester, 'navigation-menu-fd-monthly');

    expect(find.text('Could not load this page'), findsOneWidget);
    expect(find.text('Bad state: offline'), findsOneWidget);

    apiService.depositFetchError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No Fixed Deposit accounts yet'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);

    final initialFetchCount = apiService.depositFetchCount;
    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pumpAndSettle();
    await refresh;
    expect(apiService.depositFetchCount, initialFetchCount + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deposit portfolio charts summarize FD and installment accounts',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiService = _FakeApiService()
      ..depositAccounts.addAll([
        {
          'id': 'chart-fd-account',
          'product': 'FD',
          'cadence': 'monthly',
          'memberName': 'Jordan Member',
          'amount': 10000,
          'maturityAmount': 11268.25,
          'payments': <bool>[],
        },
        {
          'id': 'chart-rd-account',
          'product': 'RD',
          'cadence': 'monthly',
          'memberName': 'Jordan Member',
          'amount': 500,
          'maturityAmount': 1050,
          'payments': <bool>[true, false, false],
        },
      ]);
    const session = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DepositAccountPage(
          key: const ValueKey('fd-deposit-chart-test'),
          apiService: apiService,
          session: session,
          product: 'FD',
          cadence: 'monthly',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fdChart = find.byKey(const Key('deposit-account-progress-chart'));
    await tester.scrollUntilVisible(
      fdChart,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(fdChart, findsOneWidget);
    expect(
      tester.widget<Semantics>(fdChart).properties.label,
      contains('Principal ₹10,000.00; estimated growth ₹1,268.25'),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: DepositAccountPage(
          key: const ValueKey('rd-deposit-chart-test'),
          apiService: apiService,
          session: session,
          product: 'RD',
          cadence: 'monthly',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final installmentChart =
        find.byKey(const Key('deposit-account-progress-chart'));
    await tester.scrollUntilVisible(
      installmentChart,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(installmentChart, findsOneWidget);
    expect(
      tester.widget<Semantics>(installmentChart).properties.label,
      '1 of 3 installments paid; 2 remaining.',
    );
    expect(find.text('Installment progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RD monthly accounts can be created and payments tracked',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openDrawerPage(tester, 'navigation-menu-rd-monthly');
    expect(find.text('Recurring Deposit — Monthly'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-deposit-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deposit-member-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('deposit-amount')), '1000');
    await tester.enterText(
      find.byKey(const Key('deposit-annual-rate')),
      '12',
    );
    await tester.enterText(
      find.byKey(const Key('deposit-tenure-months')),
      '12',
    );
    expect(find.byKey(const Key('deposit-maturity-estimate')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-deposit-account')));
    await tester.pumpAndSettle();

    expect(apiService.depositAccounts, hasLength(1));
    expect(apiService.depositAccounts.single['product'], 'RD');
    expect(apiService.depositAccounts.single['cadence'], 'monthly');
    expect(apiService.depositAccounts.single['maturityAmount'], 12682.5);
    expect(apiService.depositAccounts.single['payments'], hasLength(12));
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('deposit-received-amount-deposit-1')),
          )
          .data,
      'Total received: ₹0.00',
    );

    final editButton = find.byKey(const Key('edit-deposit-deposit-1'));
    final deleteButton = find.byKey(const Key('delete-deposit-deposit-1'));
    expect(
      tester.widget<IconButton>(editButton).style!.foregroundColor!.resolve({}),
      portalEditColor,
    );
    expect(
      tester
          .widget<IconButton>(deleteButton)
          .style!
          .foregroundColor!
          .resolve({}),
      portalDeleteColor,
    );

    final scheduleButton = find.byKey(const Key('deposit-schedule-deposit-1'));
    await tester.ensureVisible(scheduleButton);
    await tester.pumpAndSettle();
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.text('Payment schedule'), findsOneWidget);
    expect(find.text('Jordan Member'), findsNWidgets(2));
    expect(find.text('Installments paid'), findsOneWidget);
    expect(find.text('0 of 12'), findsOneWidget);
    expect(find.text('Payment rows: 12'), findsOneWidget);
    expect(find.text('Paid (TRUE/FALSE)'), findsWidgets);
    expect(find.text('FALSE'), findsWidgets);
    expect(find.text('₹1,000.00 per installment'), findsOneWidget);
    expect(find.text('Payment details'), findsOneWidget);
    expect(find.text('Due date'), findsWidgets);
    expect(find.text('Amount'), findsWidgets);
    expect(find.text('Status'), findsWidgets);
    expect(
      tester
          .widget<ListTile>(
            find.byKey(const Key('deposit-payment-deposit-1-0')),
          )
          .dense,
      isTrue,
    );
    expect(
      tester
          .widget<Material>(find.byKey(const Key('deposit-schedule-header')))
          .elevation,
      0,
    );
    expect(
      tester
          .widget<Material>(find.byKey(const Key('deposit-schedule-footer')))
          .elevation,
      0,
    );
    final depositPayButton = tester.widget<FilledButton>(
      find.byKey(const Key('pay-deposit-deposit-1')),
    );
    expect(
      depositPayButton.style!.minimumSize!.resolve(const {}),
      const Size(0, 40),
    );
    final depositCloseButton = tester.widget<TextButton>(
      find.byKey(const Key('deposit-schedule-close-action')),
    );
    expect(
      depositCloseButton.style!.minimumSize!.resolve(const {}),
      depositPayButton.style!.minimumSize!.resolve(const {}),
    );
    expect(
      depositCloseButton.style!.backgroundColor!.resolve(const {}),
      portalDeleteColor,
    );
    expect(
      depositCloseButton.style!.foregroundColor!.resolve(const {}),
      Colors.white,
    );
    final firstPayment = find.byKey(const Key('deposit-payment-deposit-1-0'));
    await tester.ensureVisible(firstPayment);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: firstPayment, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(apiService.depositAccounts.single['payments'][0], isTrue);
    expect(
      find.byKey(const Key('pay-deposit-deposit-1')),
      findsOneWidget,
    );
    expect(
      apiService.depositActions.last['action'],
      'toggleDepositPayment',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('portal-toast-message'))).data,
      'Installment 1 marked as paid.',
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('deposit-received-amount-deposit-1')),
          )
          .data,
      'Total received: ₹1,000.00',
    );
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    expect(find.text('Edit Recurring Deposit account'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('deposit-member-name')))
          .controller!
          .text,
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('deposit-amount')), '1500');
    await tester.ensureVisible(find.byKey(const Key('save-deposit-account')));
    final editCompleter = Completer<bool>();
    apiService.depositMutationCompleter = editCompleter;
    await tester.tap(find.byKey(const Key('save-deposit-account')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Updating deposit account'), findsOneWidget);
    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    editCompleter.complete(true);
    await tester.pumpAndSettle();
    expect(apiService.depositActions.last['action'], 'editDepositAccount');
    expect(apiService.depositActions.last['id'], 'deposit-1');
    expect(apiService.depositAccounts.single['amount'], 1500);
    expect(apiService.depositAccounts.single['payments'][0], isTrue);

    await tester.tap(find.byKey(const Key('delete-deposit-deposit-1')));
    await tester.pumpAndSettle();
    final deleteConfirmation = tester
        .widget<FilledButton>(find.byKey(const Key('confirm-delete-deposit')));
    expect(
      deleteConfirmation.style!.backgroundColor!.resolve({}),
      portalDeleteColor,
    );
    final deleteCompleter = Completer<bool>();
    apiService.depositMutationCompleter = deleteCompleter;
    await tester.tap(find.byKey(const Key('confirm-delete-deposit')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Deleting deposit account'), findsOneWidget);
    expect(find.byKey(const Key('portal-loading-state')), findsOneWidget);
    deleteCompleter.complete(true);
    await tester.pumpAndSettle();
    expect(apiService.depositAccounts, isEmpty);
  });

  testWidgets('FD monthly accounts use a one-time principal and no schedule',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openDrawerPage(tester, 'navigation-menu-fd-monthly');
    expect(find.text('Fixed Deposit — Monthly'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-deposit-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('deposit-member-name')),
      'Jordan Member',
    );
    await tester.enterText(find.byKey(const Key('deposit-amount')), '10000');
    await tester.enterText(
      find.byKey(const Key('deposit-annual-rate')),
      '12',
    );
    await tester.enterText(
      find.byKey(const Key('deposit-tenure-months')),
      '12',
    );
    await tester.tap(find.byKey(const Key('save-deposit-account')));
    await tester.pumpAndSettle();

    expect(apiService.depositAccounts.single['product'], 'FD');
    expect(apiService.depositAccounts.single['amount'], 10000);
    expect(apiService.depositAccounts.single['maturityAmount'], 11268.25);
    expect(apiService.depositAccounts.single['payments'], isEmpty);
  });

  testWidgets('appearance menu switches between system, light, and dark',
      (WidgetTester tester) async {
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    await tester.pumpWidget(
      NtccslAccountApp(apiService: _FakeApiService()),
    );
    await _signIn(tester);

    for (final mode in ThemeMode.values) {
      await tester.tap(find.byKey(const Key('open-navigation-menu')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-theme-mode')));
      await tester.tap(find.byKey(const Key('open-theme-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme-mode-dialog')), findsOneWidget);

      await tester.tap(find.byKey(Key('theme-mode-${mode.name}')));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, mode);
      expect(app.theme!.brightness, Brightness.light);
      expect(app.darkTheme!.brightness, Brightness.dark);
      expect(
        app.theme!.appBarTheme.foregroundColor,
        Colors.white,
      );
      expect(
        app.darkTheme!.appBarTheme.foregroundColor,
        Colors.white,
      );
      expect(
        app.theme!.appBarTheme.backgroundColor,
        app.theme!.colorScheme.primary,
      );
      expect(
        app.darkTheme!.appBarTheme.backgroundColor,
        const Color(0xFF253B8C),
      );
      for (final theme in [app.theme!, app.darkTheme!]) {
        expect(
          _contrastRatio(
            theme.appBarTheme.foregroundColor!,
            theme.appBarTheme.backgroundColor!,
          ),
          greaterThan(4.5),
        );
      }
      expect(
        app.theme!.primaryIconTheme.color,
        app.theme!.colorScheme.onPrimary,
      );
      expect(
        app.darkTheme!.primaryIconTheme.color,
        app.darkTheme!.colorScheme.onPrimary,
      );
      expect(
        app.theme!.iconTheme.color,
        app.theme!.colorScheme.tertiary,
      );
      expect(
        app.darkTheme!.iconTheme.color,
        app.darkTheme!.colorScheme.tertiary,
      );
      expect(
        app.theme!.iconButtonTheme.style!.foregroundColor!.resolve(const {}),
        app.theme!.colorScheme.secondary,
      );
      expect(
        app.darkTheme!.iconButtonTheme.style!.foregroundColor!
            .resolve(const {}),
        app.darkTheme!.colorScheme.secondary,
      );
      expect(
        app.theme!.colorScheme.primary,
        isNot(app.darkTheme!.colorScheme.primary),
      );
      expect(
        app.theme!.navigationBarTheme.iconTheme!
            .resolve({WidgetState.selected})!.color,
        app.theme!.colorScheme.primary,
      );
      expect(
        app.darkTheme!.navigationBarTheme.iconTheme!
            .resolve({WidgetState.selected})!.color,
        app.darkTheme!.colorScheme.primary,
      );
      final effectiveTheme = Theme.of(
        tester.element(find.byKey(const Key('open-navigation-menu'))),
      );
      final expectedBrightness =
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      expect(effectiveTheme.brightness, expectedBrightness);
      expect(app.darkTheme!.scaffoldBackgroundColor, const Color(0xFF11131A));
      expect(
        app.darkTheme!.cardTheme.color,
        app.darkTheme!.colorScheme.surface,
      );
      final headerColors = portalHeaderGradient(
        tester.element(find.byKey(const Key('open-navigation-menu'))),
      );
      expect(headerColors, hasLength(2));
      for (final color in headerColors) {
        expect(_contrastRatio(Colors.white, color), greaterThan(4.5));
      }
      if (mode == ThemeMode.system) {
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            Brightness.dark;
        await tester.pumpAndSettle();
        expect(
          Theme.of(
            tester.element(find.byKey(const Key('open-navigation-menu'))),
          ).brightness,
          Brightness.dark,
        );
        tester.binding.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
      }
      if (find
          .byKey(const Key('close-navigation-menu'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byKey(const Key('close-navigation-menu')));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('dashboard summarizes account and deposit data',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.depositAccounts.addAll([
      {
        'id': 'dashboard-fd-1',
        'product': 'FD',
        'cadence': 'monthly',
        'memberName': 'Jordan Member',
        'amount': 10000,
        'maturityAmount': 11268.25,
        'payments': <bool>[],
      },
      {
        'id': 'dashboard-rd-1',
        'product': 'RD',
        'cadence': 'monthly',
        'memberName': 'Jordan Member',
        'amount': 1000,
        'maturityAmount': 12682.50,
        'payments': <bool>[true, false],
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ledger balance'), findsOneWidget);
    expect(find.text('₹100'), findsNWidgets(2));
    expect(find.text('User accounts'), findsOneWidget);
    final fdSummary = find.byKey(const Key('dashboard-deposit-fd-monthly'));
    final dashboardScrollable = find
        .descendant(
          of: find.byType(DashboardPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      fdSummary,
      300,
      scrollable: dashboardScrollable,
    );
    await tester.ensureVisible(fdSummary);
    expect(
        find.byKey(const Key('dashboard-deposit-fd-monthly')), findsOneWidget);
    expect(
      find.textContaining('Total estimated maturity ₹11,268'),
      findsOneWidget,
    );
    expect(apiService.fetchActions, contains('getDepositAccounts:RD:monthly'));
    final rdSummary = find.byKey(const Key('dashboard-deposit-rd-monthly'));
    final dashboardScrollState =
        tester.state<ScrollableState>(dashboardScrollable);
    for (var attempt = 0;
        rdSummary.evaluate().isEmpty && attempt < 60;
        attempt++) {
      final position = dashboardScrollState.position;
      position.jumpTo(
          (position.pixels + 80).clamp(0, position.maxScrollExtent).toDouble());
      await tester.pumpAndSettle();
    }
    expect(rdSummary, findsOneWidget);
    await tester.ensureVisible(rdSummary);
    expect(find.textContaining('Total received ₹1,000'), findsOneWidget);
    expect(find.text('Collections'), findsNothing);
    expect(find.byKey(const Key('navigation-menu-existing-collections')),
        findsNothing);
    final ledgerEntry = find.text('Office');
    await tester.scrollUntilVisible(
      ledgerEntry,
      300,
      scrollable: dashboardScrollable,
    );
    await tester.ensureVisible(ledgerEntry);
    await tester.pumpAndSettle();
    expect(find.text('Office'), findsOneWidget);

    expect(
        apiService.fetchActions,
        containsAll([
          'getAmount',
          'getUsers',
          'getDepositAccounts:FD:monthly',
          'getDepositAccounts:RD:weekly',
          'getDepositAccounts:RD:monthly',
          'getDepositAccounts:DRD:daily',
          'getDepositAccounts:DRD:weekly',
          'getDepositAccounts:DRD:monthly',
        ]));
    expect(
        apiService.fetchActions.any((action) => action.startsWith('getDaily')),
        isFalse);
  });

  testWidgets('dashboard summarizes and lists loan records',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..loanRecords.addAll([
        {
          'id': 'dashboard-approved-loan',
          'memberName': 'Dashboard Loan Borrower',
          'loanType': 'personal',
          'approvalStatus': 'Approved',
          'principal': 150000,
          'createdAt': '2026-10-20',
        },
        {
          'id': 'dashboard-pending-loan',
          'memberName': 'Dashboard Pending Borrower',
          'loanType': 'gold',
          'approvalStatus': 'Pending',
          'principal': 25000,
          'createdAt': '2026-10-22',
        },
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dashboardScrollable = find
        .descendant(
          of: find.byType(DashboardPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Loan portfolio'),
      300,
      scrollable: dashboardScrollable,
    );
    expect(find.text('Loan portfolio'), findsOneWidget);
    expect(find.text('Total loans'), findsOneWidget);
    expect(find.text('Approved principal'), findsOneWidget);
    final loanCountCard = tester.widget<Card>(
      find.descendant(
        of: find.byKey(const Key('dashboard-loan-count')),
        matching: find.byType(Card),
      ),
    );
    final approvedPrincipalCard = tester.widget<Card>(
      find.descendant(
        of: find.byKey(const Key('dashboard-loan-approved-principal')),
        matching: find.byType(Card),
      ),
    );
    final pendingCountCard = tester.widget<Card>(
      find.descendant(
        of: find.byKey(const Key('dashboard-loan-pending-count')),
        matching: find.byType(Card),
      ),
    );
    expect(loanCountCard.color, isNotNull);
    expect(approvedPrincipalCard.color, isNotNull);
    expect(pendingCountCard.color, isNotNull);
    expect(loanCountCard.color, isNot(equals(approvedPrincipalCard.color)));
    expect(approvedPrincipalCard.color, isNot(equals(pendingCountCard.color)));
    expect(
      find.byKey(const Key('dashboard-loan-value-approved-principal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('dashboard-loan-pending-count')),
      findsOneWidget,
    );
    expect(find.text('Dashboard Loan Borrower'), findsOneWidget);
    expect(find.text('Dashboard Pending Borrower'), findsOneWidget);
    expect(apiService.fetchActions, contains('getLoans:all'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard reloads newly added deposit data when reopened',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    const session = AuthSession(
      token: 'test-token',
      userId: 'admin-1',
      name: 'Test Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final initialFetchCount = apiService.depositFetchCount;
    await tester.tap(find.byKey(const Key('bottom-navigation-fd')));
    await tester.pumpAndSettle();
    apiService.depositAccounts.add({
      'id': 'new-dashboard-fd',
      'product': 'FD',
      'cadence': 'monthly',
      'memberName': 'Jordan Member',
      'amount': 25000,
      'maturityAmount': 28000,
      'payments': <bool>[],
    });
    await tester.tap(find.byKey(const Key('bottom-navigation-dashboard')));
    await tester.pumpAndSettle();

    expect(apiService.depositFetchCount, greaterThan(initialFetchCount));
    final fdSummary = find.byKey(const Key('dashboard-deposit-fd-monthly'));
    final dashboardScrollable = find
        .descendant(
          of: find.byType(DashboardPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      fdSummary,
      300,
      scrollable: dashboardScrollable,
    );
    expect(find.textContaining('Total estimated maturity ₹28,000'),
        findsOneWidget);
  });

  testWidgets('dashboard shows available data when a source fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _DashboardFailingApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-partial-error')), findsOneWidget);
    expect(
      find.textContaining('Ledger: Ledger is unavailable.'),
      findsOneWidget,
    );
  });

  testWidgets('dashboard and profile fit narrow phone screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const session = AuthSession(
      token: 'test-token',
      userId: 'admin-1',
      name: 'A Very Long Account Holder Name',
      email: 'a.very.long.email.address@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );
    final apiService = _FakeApiService();
    apiService.users.add({
      'id': 'narrow-account-1',
      'accountNo': 'MEM000000001',
      'name': 'Morgan Member',
      'email': 'morgan@example.com',
      'role': 'Member',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dashboardMetrics = find.byType(PortalMetricCard);
    expect(dashboardMetrics, findsNWidgets(4));
    final hero = tester.getRect(find.byKey(const Key('dashboard-hero-card')));
    expect(
      hero.left,
      closeTo(tester.getRect(dashboardMetrics.first).left, 0.1),
    );
    expect(hero.right, closeTo(304, 0.1));
    final topRowY = tester.getTopLeft(dashboardMetrics.first).dy;
    expect(tester.getTopLeft(dashboardMetrics.at(1)).dy, topRowY);
    final secondRowY = tester.getTopLeft(dashboardMetrics.at(2)).dy;
    expect(secondRowY, greaterThan(topRowY));
    expect(tester.getTopLeft(dashboardMetrics.at(3)).dy, secondRowY);
    final registeredChart =
        find.byKey(const Key('registered-accounts-role-chart'));
    final dashboardScrollable = find
        .descendant(
          of: find.byType(DashboardPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      registeredChart,
      250,
      scrollable: dashboardScrollable,
    );
    expect(find.byKey(const Key('registered-accounts-cards')), findsOneWidget);
    expect(find.byKey(const Key('registered-accounts-table')), findsNothing);
    expect(find.byKey(const Key('registered-account-card-narrow-account-1')),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(apiService: apiService, session: session),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-name')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard deposit chart shows live counts and maturity totals',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..depositAccounts.addAll([
        {
          'id': 'chart-fd',
          'product': 'FD',
          'cadence': 'monthly',
          'memberName': 'Jordan Member',
          'amount': 10000,
          'maturityAmount': 12000,
          'payments': <bool>[],
        },
        {
          'id': 'chart-rd',
          'product': 'RD',
          'cadence': 'monthly',
          'memberName': 'Jordan Member',
          'amount': 500,
          'maturityAmount': 650,
          'payments': <bool>[true],
        },
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('dashboard-deposit-account-chart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('dashboard-deposit-maturity-line-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('dashboard-deposit-maturity-pie-card')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const Key('dashboard-deposit-maturity-line')),
          )
          .properties
          .label,
      contains('FD Monthly ₹12,000'),
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const Key('dashboard-deposit-maturity-pie')),
          )
          .properties
          .label,
      contains('RD Monthly ₹650'),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('dashboard-deposit-pie-total')),
          )
          .data,
      NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      ).format(12650),
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const Key('dashboard-deposit-chart-count-fd-monthly'),
            ),
          )
          .data,
      '1',
    );
    final rdChart = find.byKey(
      const Key('dashboard-deposit-chart-rd-monthly'),
    );
    expect(rdChart, findsOneWidget);
    expect(
      tester.widget<Semantics>(rdChart).properties.label,
      contains('1 accounts, estimated maturity ₹650'),
    );
  });

  testWidgets('dashboard metrics use two rows on wide screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final metrics = find.byType(PortalMetricCard);
    expect(metrics, findsNWidgets(4));
    final firstRowY = tester.getTopLeft(metrics.at(0)).dy;
    for (var index = 1; index < 3; index++) {
      expect(tester.getTopLeft(metrics.at(index)).dy, firstRowY);
    }
    expect(tester.getTopLeft(metrics.at(3)).dy, greaterThan(firstRowY));
    final dashboardScrollable = find
        .descendant(
          of: find.byType(DashboardPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('registered-accounts-table')),
      300,
      scrollable: dashboardScrollable,
    );
    expect(find.text('Member Name'), findsOneWidget);
    expect(find.text('Email Id'), findsOneWidget);
    expect(find.text('Member ID'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registered accounts chart reflects user roles',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    apiService.users.addAll([
      {
        'id': 'user-3',
        'accountNo': 'EMP000000001',
        'name': 'Alex Collector',
        'email': 'alex@example.com',
        'role': 'Collector',
        'dailyAccess': false,
        'weeklyAccess': true,
        'monthlyAccess': false,
      },
      {
        'id': 'user-4',
        'accountNo': 'ADM123456789',
        'name': 'Riley Admin',
        'email': 'riley@example.com',
        'role': 'Admin',
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Test Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final roleChart = find.byKey(const Key('registered-accounts-role-chart'));
    final dashboardList = find.descendant(
      of: find.byType(RefreshIndicator).first,
      matching: find.byType(ListView),
    );
    for (var attempt = 0;
        roleChart.evaluate().isEmpty && attempt < 8;
        attempt++) {
      await tester.drag(dashboardList.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('registered-accounts-role-chart')),
        findsOneWidget);
    expect(find.byIcon(Icons.pie_chart_rounded), findsOneWidget);
    expect(find.byKey(const Key('registered-accounts-pie')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(
        find.byKey(const Key('registered-role-count-admin')), findsOneWidget);
    expect(find.byKey(const Key('registered-role-count-collector')),
        findsOneWidget);
    expect(
        find.byKey(const Key('registered-role-count-member')), findsOneWidget);
    expect(
        tester
            .widget<Text>(
              find.byKey(const Key('registered-role-count-admin')),
            )
            .data,
        '1');
    expect(
        tester
            .widget<Text>(
              find.byKey(const Key('registered-role-count-collector')),
            )
            .data,
        '1');
    expect(
        tester
            .widget<Text>(
              find.byKey(const Key('registered-role-count-member')),
            )
            .data,
        '2');
    expect(find.byKey(const Key('registered-accounts-list')), findsOneWidget);
    expect(find.byKey(const Key('registered-accounts-cards')), findsOneWidget);
    expect(find.byKey(const Key('registered-accounts-table')), findsNothing);
    expect(find.text('Member Name'), findsWidgets);
    expect(find.text('Email Id'), findsWidgets);
    expect(find.text('Member ID'), findsWidgets);
    expect(find.text('Role'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('EMP000000001'), findsOneWidget);
    expect(find.text('ADM123456789'), findsOneWidget);
    expect(find.text('alex@example.com'), findsOneWidget);
    expect(
      find.byKey(const Key('registered-account-user-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('registered-account-user-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('registered-account-permissions-user-3')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-account-reports-user-3')),
          )
          .data,
      'Daily Off · Weekly On · Monthly Off',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-admin')),
          )
          .data,
      '25%',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-collector')),
          )
          .data,
      '25%',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-member')),
          )
          .data,
      '50%',
    );
    expect(find.byKey(const Key('dashboard-open-users')), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var attempt = 0;
        find
                .byKey(const Key('dashboard-greeting'))
                .hitTestable()
                .evaluate()
                .isEmpty &&
            attempt < 8;
        attempt++) {
      await tester.drag(dashboardList.first, const Offset(0, 400));
      await tester.pumpAndSettle();
    }
    apiService.users.add({
      'id': 'user-5',
      'name': 'Casey New Member',
      'email': 'casey@example.com',
      'role': 'Member',
    });
    final refresh = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first)
        .show();
    await tester.pump();
    await tester.pumpAndSettle();
    await refresh;
    for (var attempt = 0;
        roleChart.evaluate().isEmpty && attempt < 8;
        attempt++) {
      await tester.drag(dashboardList.first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-accounts-pie-total')),
          )
          .data,
      '5',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('registered-role-share-member')),
          )
          .data,
      '60%',
    );
    expect(
      find.byKey(const Key('registered-account-user-5')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('portal theme gives default and form icons accent colors',
      (WidgetTester tester) async {
    await tester.pumpWidget(NtccslAccountApp(apiService: _FakeApiService()));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.theme!.iconTheme.color, app.theme!.colorScheme.tertiary);
    expect(
      app.theme!.inputDecorationTheme.prefixIconColor,
      app.theme!.colorScheme.primary,
    );
    expect(
      app.theme!.inputDecorationTheme.suffixIconColor,
      app.theme!.colorScheme.tertiary,
    );
  });

  testWidgets('page header respects its parent inset on narrow screens',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    PortalPageHeader(
                      title: 'Bank ledger',
                      subtitle: 'Track account activity in one place.',
                      icon: Icons.account_balance_wallet_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final header = tester.getRect(
      find.byKey(const Key('portal-page-header-card')),
    );
    expect(header.left, closeTo(12, 0.1));
    expect(header.right, closeTo(308, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ledger search filters records without hiding account totals',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    expect(find.text('Total deposits'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ledger-search')),
      'opening balance',
    );
    await tester.pumpAndSettle();
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('1 of 1 records'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('ledger-search')),
      'no matching transaction',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching transactions'), findsOneWidget);
    expect(find.text('Total deposits'), findsOneWidget);
  });

  testWidgets('collectors can view shared data but cannot manage collections',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    const session = AuthSession(
      token: 'test-token',
      userId: 'test-collector',
      name: 'Test Collector',
      email: 'collector@example.com',
      role: 'Collector',
      accountNumber: '100002',
      permissions: {
        'shared_data_read': true,
        'own_collection_read': true,
        'collection_manage': false,
        'deposit_view': true,
        'deposit_manage': false,
        'ledger_manage': false,
        'user_manage': false,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_bottomNavigationItems(), findsNWidgets(5));
    expect(
      _bottomNavigationLabels(),
      {'Dashboard', 'Daily', 'Weekly', 'Monthly', 'Deposit'},
    );
    expect(find.byKey(const Key('add-ledger-entry')), findsNothing);

    await _openDrawerPage(tester, 'navigation-menu-accounts');
    expect(find.text('Bank_ladger'), findsOneWidget);
    await _openDrawerPage(tester, 'navigation-menu-daily');
    expect(find.byKey(const Key('add-collection-entry')), findsNothing);
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-collection-2')), findsNothing);
    expect(find.byKey(const Key('delete-collection-2')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('payment-schedule-2')));
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();
    final paymentChip =
        tester.widget<FilterChip>(find.byKey(const Key('schedule-chip-2-0')));
    expect(paymentChip.onSelected, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    final cashfreeNavigationItem =
        find.byKey(const Key('navigation-menu-cashfree-payment'));
    await _ensureDrawerItemVisible(tester, cashfreeNavigationItem);
    expect(
      cashfreeNavigationItem,
      findsOneWidget,
    );
    await tester.tap(cashfreeNavigationItem);
    await tester.pumpAndSettle();
    expect(find.text('Payment details'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-users')));
    await tester.pumpAndSettle();
    expect(find.text('Morgan Member'), findsOneWidget);
    expect(find.text('Account No: DRD000000001'), findsOneWidget);
    expect(find.byKey(const Key('add-user')), findsNothing);
    expect(find.byKey(const Key('manage-user-user-1')), findsNothing);
  }, skip: true);

  testWidgets('members only see their own collections and cannot edit them',
      (WidgetTester tester) async {
    final apiService = _FakeApiService()
      ..collections['Daily_Collection']!.add({
        'memberName': 'Other Member',
        'date': '2026-01-02',
        'depAmt': 30,
        'totalCount': 1,
        'totalReceived': 30,
        'periods': [true],
        'rowIndex': 3,
      });
    const session = AuthSession(
      token: 'test-token',
      userId: 'test-member',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
      accountNumber: '100003',
      permissions: {
        'shared_data_read': false,
        'own_collection_read': true,
        'collection_manage': false,
        'deposit_view': false,
        'deposit_manage': false,
        'ledger_manage': false,
        'user_manage': false,
      },
      reportAccess: {
        'daily': true,
        'weekly': false,
        'monthly': false,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_bottomNavigationItems(), findsNWidgets(2));
    expect(
      _bottomNavigationLabels(),
      {'Dashboard', 'Daily'},
    );
    expect(find.byKey(const Key('bottom-navigation-daily')), findsOneWidget);
    expect(find.byKey(const Key('bottom-navigation-weekly')), findsNothing);
    expect(find.byKey(const Key('bottom-navigation-monthly')), findsNothing);
    expect(find.byKey(const Key('bottom-navigation-deposit')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-accounts')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-users')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-weekly')), findsNothing);
    expect(find.byKey(const Key('navigation-menu-monthly')), findsNothing);
    expect(apiService.fetchActions, isNot(contains('getAmount')));
    expect(apiService.fetchActions, isNot(contains('getUsers')));
    expect(apiService.fetchActions, isNot(contains('getWeekly')));
    expect(apiService.fetchActions, isNot(contains('getMonthly')));

    await _openDrawerPage(tester, 'navigation-menu-daily');
    expect(find.text('Jordan Member'), findsNWidgets(2));
    expect(find.text('Other Member'), findsNothing);
    expect(find.byKey(const Key('add-collection-entry')), findsNothing);
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('payment-schedule-2')));
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-collection-2')), findsNothing);
    expect(find.byKey(const Key('delete-collection-2')), findsNothing);
    final scheduleChip =
        tester.widget<FilterChip>(find.byKey(const Key('schedule-chip-2-0')));
    expect(scheduleChip.onSelected, isNull);
    expect(find.byKey(const Key('pay-collection-2')), findsOneWidget);
  }, skip: true);

  testWidgets('member dashboard shows matching report details only',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    for (final sheetName in [
      'Daily_Collection',
      'Weekly_Collection',
      'Monthly_Collection',
    ]) {
      apiService.collections[sheetName]!.add({
        'memberName': '  jordan   member ',
        'date': '2026-02-01',
        'depAmt': 35,
        'totalCount': 2,
        'totalReceived': 70,
        'periods': [true, true],
        'rowIndex': 2,
      });
      apiService.collections[sheetName]!.add({
        'memberName': 'Other Member',
        'date': '2026-01-02',
        'depAmt': 99,
        'totalCount': 3,
        'totalReceived': 297,
        'periods': [true, true, true],
        'rowIndex': 3,
      });
    }
    apiService.depositAccounts.addAll([
      {
        'id': 'member-deposit-own',
        'product': 'RD',
        'cadence': 'monthly',
        'memberName': '  jordan   member ',
        'maturityAmount': 420,
        'payments': <bool>[true, false],
      },
      {
        'id': 'member-deposit-other',
        'product': 'RD',
        'cadence': 'monthly',
        'memberName': 'Other Member',
        'maturityAmount': 999,
        'payments': <bool>[true],
      },
    ]);
    const session = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
      permissions: {
        'shared_data_read': true,
        'own_collection_read': true,
        'collection_manage': true,
        'deposit_view': true,
        'deposit_manage': true,
        'ledger_manage': true,
        'user_manage': true,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My dashboard'), findsOneWidget);
    expect(find.text('My total contributions'), findsOneWidget);
    final dashboardList = find.byType(ListView).first;
    final dailyDetails =
        find.byKey(const Key('member-report-detail-daily-2-2026-02-01'));
    await _scrollUntilBuilt(
      tester,
      dailyDetails,
      dashboardList,
    );
    await tester.ensureVisible(dailyDetails);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key('member-report-detail-daily-2-2026-02-01'),
      ),
      findsOneWidget,
    );
    final weeklyDetails =
        find.byKey(const Key('member-report-detail-weekly-2-2026-02-01'));
    await _scrollUntilBuilt(
      tester,
      weeklyDetails,
      dashboardList,
    );
    await tester.ensureVisible(weeklyDetails);
    expect(
      find.byKey(
        const Key('member-report-detail-weekly-2-2026-02-01'),
      ),
      findsOneWidget,
    );
    final monthlyDetails =
        find.byKey(const Key('member-report-detail-monthly-2-2026-02-01'));
    await _scrollUntilBuilt(
      tester,
      monthlyDetails,
      dashboardList,
    );
    await tester.ensureVisible(monthlyDetails);
    expect(
      find.byKey(
        const Key('member-report-detail-monthly-2-2026-02-01'),
      ),
      findsOneWidget,
    );
    final rdSummary = find.byKey(const Key('dashboard-deposit-rd-monthly'));
    await _scrollUntilBuilt(tester, rdSummary, dashboardList);
    await tester.ensureVisible(rdSummary);
    expect(
      find.textContaining('My estimated maturity ₹420'),
      findsOneWidget,
    );
    expect(find.text('Other Member'), findsNothing);
    expect(apiService.fetchActions, isNot(contains('getAmount')));
    expect(apiService.fetchActions, isNot(contains('getUsers')));
  }, skip: true);

  testWidgets('member dashboard shows only reports enabled for the account',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    const session = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
      permissions: {
        'own_collection_read': true,
      },
      reportAccess: {
        'daily': true,
        'weekly': false,
        'monthly': false,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: session,
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Jordan Member'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.byKey(const Key('dashboard-collection-daily')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Daily collection'), findsOneWidget);
    expect(find.text('Weekly collection'), findsNothing);
    expect(find.text('Monthly collection'), findsNothing);
    expect(apiService.fetchActions, contains('getDaily'));
    expect(apiService.fetchActions, isNot(contains('getWeekly')));
    expect(apiService.fetchActions, isNot(contains('getMonthly')));
    expect(apiService.fetchActions, isNot(contains('getAmount')));
    expect(apiService.fetchActions, isNot(contains('getUsers')));
  }, skip: true);

  testWidgets('ledger entry uses staff dropdown and saves selected person',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    await tester.tap(find.byKey(const Key('add-ledger-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-entry-by')), findsOneWidget);
    expect(find.byKey(const Key('ledger-pay-mode')), findsOneWidget);
    final balanceField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('ledger-balance')),
        matching: find.byType(TextField),
      ),
    );
    expect(balanceField.readOnly, isTrue);
    expect(
      balanceField.style?.color,
      Theme.of(tester.element(find.byKey(const Key('ledger-balance'))))
          .colorScheme
          .error,
    );
    await tester.enterText(find.byKey(const Key('ledger-by-whom')), 'Office');
    await tester.enterText(find.byKey(const Key('ledger-deposit')), '250');
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('ledger-balance')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '350',
    );
    await tester.tap(find.byKey(const Key('ledger-pay-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('G Pay').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ledger-entry-by')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur Mahammad').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-ledger-entry')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerRequests, hasLength(1));
    expect(apiService.ledgerRequests.single['action'], 'addAmount');
    expect(apiService.ledgerRequests.single['payMode'], 'G Pay');
    expect(apiService.ledgerRequests.single['entryBy'], 'Nur Mahammad');
    expect(apiService.ledgerRequests.single['deposit'], '250');
    expect(apiService.ledgerRequests.single['balance'], '350');
    expect(find.text('Ledger entry added.'), findsOneWidget);
  });

  testWidgets('ledger withdrawal subtracts from previous balance',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    await tester.tap(find.byKey(const Key('add-ledger-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ledger-withdrawal')), '40');

    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('ledger-balance')),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '60',
    );
    await tester.tap(find.byKey(const Key('save-ledger-entry')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerRequests.single['withdrawal'], '40');
    expect(apiService.ledgerRequests.single['balance'], '60');
  });

  testWidgets('ledger entry can be viewed, edited, and deleted',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await _openDrawerPage(tester, 'navigation-menu-accounts');

    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    expect(find.text('Ledger entry details'), findsOneWidget);
    expect(find.text('Opening balance'), findsOneWidget);
    expect(find.text('Entry by'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manage-ledger-2')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.edit_outlined)).color,
      portalEditColor,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color,
      portalDeleteColor,
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Ledger Entry'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('ledger-remarks')), 'Updated note');
    await tester.enterText(find.byKey(const Key('ledger-deposit')), '350');
    await tester.ensureVisible(find.byKey(const Key('save-ledger-entry')));
    await tester.tap(find.byKey(const Key('save-ledger-entry')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerActions.last['action'], 'editAmount');
    expect(apiService.ledgerActions.last['rowIndex'], 2);
    expect(apiService.ledgerEntries.single['remarks'], 'Updated note');
    expect(apiService.ledgerEntries.single['deposit'], '350');
    expect(find.text('Ledger entry updated.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('manage-ledger-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete ledger entry?'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('confirm-delete-ledger')))
          .style!
          .backgroundColor!
          .resolve({}),
      portalDeleteColor,
    );
    await tester.tap(find.byKey(const Key('confirm-delete-ledger')));
    await tester.pumpAndSettle();

    expect(apiService.ledgerEntries, isEmpty);
    expect(apiService.ledgerActions.last['action'], 'deleteAmount');
    expect(find.text('Ledger entry deleted.'), findsOneWidget);
  });

  testWidgets('profile changes password after confirming new password',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-menu-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-password')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('profile-current-password')),
      'old-password',
    );
    await tester.enterText(
      find.byKey(const Key('profile-new-password')),
      'new-password',
    );
    await tester.enterText(
      find.byKey(const Key('profile-confirm-password')),
      'not-the-same',
    );
    await tester.ensureVisible(find.byKey(const Key('save-profile-password')));
    await tester.tap(find.byKey(const Key('save-profile-password')));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(apiService.passwordChanges, isEmpty);

    await tester.enterText(
      find.byKey(const Key('profile-confirm-password')),
      'new-password',
    );
    await tester.ensureVisible(find.byKey(const Key('save-profile-password')));
    await tester.tap(find.byKey(const Key('save-profile-password')));
    await tester.pumpAndSettle();

    expect(apiService.passwordChanges, hasLength(1));
    expect(
        apiService.passwordChanges.single['currentPassword'], 'old-password');
    expect(apiService.passwordChanges.single['newPassword'], 'new-password');
    expect(apiService.passwordChanges.single['token'], 'test-token');
    expect(find.text('Password changed successfully.'), findsOneWidget);
  });

  testWidgets('profile can update name, email, and profile image',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    final originalImagePicker = ImagePickerPlatform.instance;
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
    );
    ImagePickerPlatform.instance = _FakeImagePickerPlatform(imageBytes);
    addTearDown(() {
      ImagePickerPlatform.instance = originalImagePicker;
    });
    AuthSession? updatedSession;
    const session = AuthSession(
      token: 'test-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          apiService: apiService,
          session: session,
          onSessionUpdated: (value) => updatedSession = value,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('edit-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-profile-name')),
      'Updated Admin',
    );
    await tester.enterText(
      find.byKey(const Key('edit-profile-email')),
      'updated@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('edit-profile-phone')),
      '9876543210',
    );
    await tester.tap(find.byKey(const Key('edit-profile-upload-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-profile-image-preview')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-profile')));
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Updated Admin'), findsOneWidget);
    expect(find.text('updated@example.com'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(updatedSession?.name, 'Updated Admin');
    expect(updatedSession?.email, 'updated@example.com');
    expect(updatedSession?.phoneNumber, '9876543210');
    expect(
        updatedSession?.profileImageUrl, startsWith('data:image/png;base64,'));
    expect(apiService.profileUpdates.single['action'], 'updateMyProfile');
    expect(apiService.profileUpdates.single['profileImageChanged'], isTrue);
    expect(apiService.profileUpdates.single['phoneNumber'], '9876543210');
    expect(
      apiService.profileUpdates.single['profileImageData'],
      base64Encode(imageBytes),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('admins can add, edit, and delete users',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    final originalImagePicker = ImagePickerPlatform.instance;
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
    );
    ImagePickerPlatform.instance = _FakeImagePickerPlatform(imageBytes);
    addTearDown(() {
      ImagePickerPlatform.instance = originalImagePicker;
    });
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);

    await _openDrawerPage(tester, 'navigation-menu-users');
    expect(find.text('Morgan Member'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('user-password')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );
    await tester.ensureVisible(
      find.byKey(const Key('user-password-visibility')),
    );
    await tester.tap(find.byKey(const Key('user-password-visibility')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('user-password')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('user-password-visibility')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('user-name')), 'New Person');
    await tester.enterText(
      find.byKey(const Key('user-email')),
      'new@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('user-phone-number')),
      '9876543210',
    );
    await tester.ensureVisible(
      find.byKey(const Key('upload-user-profile-image')),
    );
    await tester.tap(find.byKey(const Key('upload-user-profile-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('user-profile-image-preview')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('user-password')),
      'temporary-pass',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
        apiService.users.any((user) => user['name'] == 'New Person'), isTrue);
    expect(apiService.userRequests.last['phoneNumber'], '9876543210');
    expect(apiService.userRequests.last['profileImageChanged'], isTrue);
    expect(apiService.userRequests.last['profileImageMimeType'], 'image/png');
    expect(
      apiService.userRequests.last['profileImageData'],
      base64Encode(imageBytes),
    );
    expect(find.text('User added.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('users-search')),
      'taylor@example.com',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('manage-user-user-2')));
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-user-user-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('user-name')), 'Updated Person');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      apiService.users.any((user) => user['name'] == 'Updated Person'),
      isTrue,
    );
    expect(find.text('User updated.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('manage-user-user-2')));
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-user-user-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(apiService.users.any((user) => user['id'] == 'user-2'), isFalse);
    expect(find.text('User deleted.'), findsOneWidget);
  });

  testWidgets('admin user tabs filter accounts and preselect role on add',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'test-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-menu-users')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('users-search')),
      'taylor@example.com',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    await tester.tap(find.byKey(const Key('users-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Morgan Member'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('users-search')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.byKey(const Key('users-overview-card')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('users-total-count'))).data,
      '2',
    );
    expect(find.text('D On'), findsOneWidget);
    expect(find.text('W On'), findsOneWidget);
    expect(find.text('M On'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('users-search')),
      'taylor@example.com',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    expect(find.text('Morgan Member'), findsNothing);
    await tester.tap(find.byKey(const Key('users-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Morgan Member'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('users-visible-count'))).data,
      '2 members',
    );
    await tester.enterText(
      find.byKey(const Key('users-search')),
      'DRD000000002',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    expect(find.text('Morgan Member'), findsNothing);
    await tester.tap(find.byKey(const Key('users-search-clear')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('users-search')),
      '9876543210',
    );
    await tester.pumpAndSettle();
    expect(find.text('Taylor Member'), findsOneWidget);
    expect(find.byKey(const Key('user-phone-number-user-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('users-search-clear')));
    await tester.pumpAndSettle();
    final memberRoleChip = tester
        .widget<FilterChip>(find.byKey(const Key('user-role-chip-member')));
    expect(memberRoleChip.selected, isTrue);
    expect(
      memberRoleChip.selectedColor,
      portalRoleColor('Member').withValues(alpha: .10),
    );
    expect(
      tester
          .widget<Container>(
            find.byKey(const Key('user-role-badge-user-1')),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'member role tint',
        portalRoleColor('Member').withValues(alpha: .11),
      ),
    );
    await tester.tap(find.byKey(const Key('user-role-tab-collector')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const Key('user-role-chip-collector')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('user-role-chip-member')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const Key('user-role-chip-collector')),
          )
          .selectedColor,
      portalRoleColor('Collector').withValues(alpha: .10),
    );
    expect(find.text('No Collector accounts'), findsOneWidget);
    expect(find.text('Morgan Member'), findsNothing);
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(find.text('Add User'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('user-role')),
          )
          .initialValue,
      'Collector',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    tester
        .widget<FilterChip>(find.byKey(const Key('user-role-chip-member')))
        .onSelected!(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-user')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('user-role')),
          )
          .initialValue,
      'Member',
    );
    expect(find.byKey(const Key('member-daily-access')), findsOneWidget);
    expect(find.byKey(const Key('member-weekly-access')), findsOneWidget);
    expect(find.byKey(const Key('member-monthly-access')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('user-name')), 'New Member');
    await tester.enterText(
      find.byKey(const Key('user-email')),
      'new.member@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('user-password')),
      'secure-pass',
    );
    await tester.ensureVisible(find.byKey(const Key('member-weekly-access')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('member-weekly-access')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(apiService.userRequests.last['action'], 'addUser');
    expect(apiService.userRequests.last['dailyAccess'], isTrue);
    expect(apiService.userRequests.last['weeklyAccess'], isFalse);
    expect(apiService.userRequests.last['monthlyAccess'], isTrue);
  });

  testWidgets('admins can toggle each role permission and save immediately',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: MainHomeScreen(
          apiService: apiService,
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation-menu')));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('navigation-menu-roles & permissions')));
    await tester.pumpAndSettle();
    final permissionsScrollable = find
        .descendant(
          of: find.byType(RefreshIndicator).last,
          matching: find.byType(Scrollable),
        )
        .first;

    expect(find.text('Roles & Permissions'), findsNWidgets(2));
    expect(
      tester
          .widget<Container>(
            find.byKey(const Key('role-permission-color-collector')),
          )
          .decoration,
      isA<BoxDecoration>().having(
        (decoration) => decoration.color,
        'collector role color',
        portalRoleColor('Collector').withValues(alpha: .12),
      ),
    );
    final collectorLedgerGroup = find.byKey(
      const Key('permission-dropdown-collector-ledger'),
    );
    await tester.scrollUntilVisible(
      collectorLedgerGroup,
      300,
      scrollable: permissionsScrollable,
    );
    await Scrollable.ensureVisible(
      tester.element(collectorLedgerGroup),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    await tester.tap(collectorLedgerGroup);
    await tester.pumpAndSettle();
    final collectorLedgerPermission =
        find.byKey(const Key('permission-collector-ledger_delete'));
    await Scrollable.ensureVisible(
      tester.element(collectorLedgerPermission),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    final collectorPermission =
        tester.widget<SwitchListTile>(collectorLedgerPermission);
    expect(collectorPermission.value, isTrue);
    expect(collectorPermission.activeTrackColor, portalRoleColor('Collector'));
    await tester.tap(
      find.descendant(
        of: collectorLedgerPermission,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      apiService.savedRolePermissions!['Collector']!['ledger_delete'],
      isFalse,
    );
    expect(
        apiService.savedRolePermissions!['Collector']!['ledger_add'], isTrue);

    final collectorLoansGroup = find.byKey(
      const Key('permission-dropdown-collector-loans'),
    );
    await tester.scrollUntilVisible(
      collectorLoansGroup,
      300,
      scrollable: permissionsScrollable,
    );
    await Scrollable.ensureVisible(
      tester.element(collectorLoansGroup),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    await tester.tap(collectorLoansGroup);
    await tester.pumpAndSettle();
    final collectorLoanViewPermission =
        find.byKey(const Key('permission-collector-loan_view'));
    await Scrollable.ensureVisible(
      tester.element(collectorLoanViewPermission),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable Loans section'), findsOneWidget);
    var collectorLoanViewSwitch =
        tester.widget<SwitchListTile>(collectorLoanViewPermission);
    expect(collectorLoanViewSwitch.value, isTrue);
    expect(collectorLoanViewSwitch.onChanged, isNotNull);
    await tester.tap(
      find.descendant(
        of: collectorLoanViewPermission,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      apiService.savedRolePermissions!['Collector']!['loan_view'],
      isFalse,
    );
    await tester.tap(
      find.descendant(
        of: collectorLoanViewPermission,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    collectorLoanViewSwitch =
        tester.widget<SwitchListTile>(collectorLoanViewPermission);
    expect(collectorLoanViewSwitch.value, isTrue);
    expect(
      apiService.savedRolePermissions!['Collector']!['loan_view'],
      isTrue,
    );
    for (final permission in [
      'loan_add',
      'loan_edit',
      'loan_update',
      'loan_delete',
    ]) {
      final collectorLoanPermission =
          find.byKey(Key('permission-collector-$permission'));
      await Scrollable.ensureVisible(
        tester.element(collectorLoanPermission),
        alignment: 0.4,
      );
      await tester.pumpAndSettle();
      var permissionSwitch =
          tester.widget<SwitchListTile>(collectorLoanPermission);
      expect(permissionSwitch.onChanged, isNotNull, reason: permission);
      expect(permissionSwitch.value, isFalse, reason: permission);
      await tester.tap(
        find.descendant(
          of: collectorLoanPermission,
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        apiService.savedRolePermissions!['Collector']![permission],
        isTrue,
      );
      await tester.tap(
        find.descendant(
          of: collectorLoanPermission,
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        apiService.savedRolePermissions!['Collector']![permission],
        isFalse,
      );
    }

    final memberSharedReadPermission = find.byKey(
      const Key('permission-member-shared_data_read'),
    );
    final memberSharedGroup = find.byKey(
      const Key('permission-dropdown-member-shared'),
    );
    await tester.scrollUntilVisible(
      memberSharedGroup,
      300,
      scrollable: permissionsScrollable,
    );
    await Scrollable.ensureVisible(
      tester.element(memberSharedGroup),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    await tester.tap(memberSharedGroup);
    await tester.pumpAndSettle();
    final memberSharedReadSwitch =
        tester.widget<SwitchListTile>(memberSharedReadPermission);
    expect(memberSharedReadSwitch.value, isFalse);
    expect(memberSharedReadSwitch.onChanged, isNotNull);
    await tester.tap(
      find.descendant(
        of: memberSharedReadPermission,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(memberSharedReadPermission).value,
      isTrue,
    );
    expect(
      apiService.savedRolePermissions!['Member']!['shared_data_read'],
      isTrue,
    );
    final memberDepositViewPermission = find.byKey(
      const Key('permission-member-deposit_view'),
    );
    final memberDepositsGroup = find.byKey(
      const Key('permission-dropdown-member-deposits'),
    );
    await tester.scrollUntilVisible(
      memberDepositsGroup,
      300,
      scrollable: permissionsScrollable,
    );
    await Scrollable.ensureVisible(
      tester.element(memberDepositsGroup),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    await tester.tap(memberDepositsGroup);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(memberDepositViewPermission),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    final memberDepositViewSwitch =
        tester.widget<SwitchListTile>(memberDepositViewPermission);
    expect(memberDepositViewSwitch.value, isTrue);
    expect(memberDepositViewSwitch.onChanged, isNotNull);
    await tester.tap(
      find.descendant(
        of: memberDepositViewPermission,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      apiService.savedRolePermissions!['Member']!['deposit_view'],
      isFalse,
    );

    expect(apiService.savedRolePermissions, isNotNull);
    expect(apiService.savedRolePermissions!['Collector']!['ledger_delete'],
        isFalse);
    expect(apiService.savedRolePermissions!['Member']!['shared_data_read'],
        isTrue);
    expect(
        apiService.savedRolePermissions!['Member']!['deposit_view'], isFalse);
    expect(find.textContaining('should sign in again'), findsOneWidget);
  });

  testWidgets('non-admin role permissions page does not request admin data',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(
      MaterialApp(
        home: RolesPermissionsPage(
          apiService: apiService,
          session: const AuthSession(
            token: 'collector-token',
            userId: 'collector-1',
            name: 'Test Collector',
            email: 'collector@example.com',
            role: 'Collector',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Admin access required'), findsOneWidget);
    expect(find.text('Roles & Permissions'), findsNothing);
    expect(apiService.rolePermissionFetchCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('roles and permissions page fits a narrow phone screen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: RolesPermissionsPage(
          apiService: _FakeApiService(),
          session: const AuthSession(
            token: 'admin-token',
            userId: 'admin-1',
            name: 'Admin',
            email: 'admin@example.com',
            role: 'Admin',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Roles & Permissions'), findsOneWidget);
    final permissionsScrollable = find
        .descendant(
          of: find.byType(RefreshIndicator),
          matching: find.byType(Scrollable),
        )
        .first;
    final memberPermissionGroup = find.byKey(
      const Key('permission-dropdown-member-shared'),
    );
    await tester.scrollUntilVisible(
      memberPermissionGroup,
      200,
      scrollable: permissionsScrollable,
    );
    await tester.tap(memberPermissionGroup);
    await tester.pumpAndSettle();
    final memberPermission =
        find.byKey(const Key('permission-member-shared_data_read'));
    expect(
      memberPermission,
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('daily, weekly, and monthly pages add collection entries',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);

    const collectionPages = {
      'Daily': 'Daily_Collection',
      'Weekly': 'Weekly_Collection',
      'Monthly': 'Monthly_Collection',
    };
    for (final entry in collectionPages.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-collection-entry')), findsOneWidget);
      if (entry.key == 'Daily') {
        expect(find.text('Amount received'), findsOneWidget);
        expect(find.text('₹25'), findsNWidgets(2));
        expect(find.text('1 payment marked'), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('add-collection-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Add ${entry.key.toLowerCase()} entry'), findsOneWidget);
      expect(
        find.text('Select the periods that are already paid.'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('collection-start-date'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('collection-member-name'))).dy,
        ),
      );
      expect(find.textContaining('Start date:'), findsOneWidget);
      expect(find.byKey(const Key('form-schedule-chip-0')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('form-schedule-chip-0')),
      );
      await tester.tap(find.byKey(const Key('form-schedule-chip-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const Key('form-schedule-chip-0')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithFixedCrossAxisCount,
        isA<SliverGridDelegateWithFixedCrossAxisCount>().having(
          (delegate) => delegate.crossAxisCount,
          'crossAxisCount',
          3,
        ),
      );

      await tester
          .ensureVisible(find.byKey(const Key('save-collection-entry')));
      await tester.tap(find.byKey(const Key('save-collection-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a member name'), findsOneWidget);
      expect(
        apiService.collectionRequests.length,
        collectionPages.keys.toList().indexOf(entry.key),
      );

      await tester.enterText(
        find.byKey(const Key('collection-member-name')),
        'Jordan Member',
      );
      await tester.enterText(
        find.byKey(const Key('collection-amount')),
        '25',
      );
      await tester
          .ensureVisible(find.byKey(const Key('save-collection-entry')));
      await tester.tap(find.byKey(const Key('save-collection-entry')));
      await tester.pumpAndSettle();
      expect(find.text('Collection entry added.'), findsOneWidget);
    }

    expect(
      apiService.collectionRequests.map((request) => request['sheetName']),
      collectionPages.values,
    );
    expect(
      apiService.collectionRequests
          .every((request) => request['memberName'] == 'Jordan Member'),
      isTrue,
    );
    expect(
      apiService.collectionRequests.every((request) => request['depAmt'] == 25),
      isTrue,
    );
    expect(
      apiService.collectionRequests.every(
        (request) =>
            (request['periods'] as List).first == true &&
            (request['periods'] as List).skip(1).every((paid) => !paid),
      ),
      isTrue,
    );
    expect(
      apiService.collectionRequests.every(
        (request) =>
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(request['date'] as String),
      ),
      isTrue,
    );
  }, skip: true);

  testWidgets('collection entries can be edited and deleted',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    final grandTotal = tester.widget<Text>(
      find.byKey(const Key('collection-grand-total-2')),
    );
    expect(grandTotal.data, contains('Paid: 1 days'));
    final collectionColors = Theme.of(
            tester.element(find.byKey(const Key('collection-grand-total-2'))))
        .colorScheme;
    expect(grandTotal.style?.color, collectionColors.primary);
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('payment-schedule-2'))),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();
    final paymentChips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    final paidChip = paymentChips.singleWhere((chip) => chip.selected);
    expect(paidChip.selectedColor, collectionColors.primaryContainer);
    expect(paidChip.checkmarkColor, collectionColors.onPrimaryContainer);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('edit-collection-2')));
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('edit-collection-2')),
          )
          .style!
          .foregroundColor!
          .resolve({}),
      portalEditColor,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('delete-collection-2')),
          )
          .style!
          .foregroundColor!
          .resolve({}),
      portalDeleteColor,
    );
    await tester.tap(find.byKey(const Key('edit-collection-2')));
    await tester.pumpAndSettle();
    expect(find.text('Edit daily entry'), findsOneWidget);
    expect(find.byKey(const Key('collection-grand-total')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('collection-start-date'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('collection-member-name'))).dy,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('collection-member-name')),
      'Jordan Updated',
    );
    await tester.enterText(
      find.byKey(const Key('collection-amount')),
      '40',
    );
    await tester.ensureVisible(find.byKey(const Key('save-collection-entry')));
    await tester.tap(find.byKey(const Key('save-collection-entry')));
    await tester.pumpAndSettle();

    expect(apiService.collections['Daily_Collection']!.single['memberName'],
        'Jordan Updated');
    expect(apiService.collections['Daily_Collection']!.single['depAmt'], 40.0);
    expect(
      apiService.collections['Daily_Collection']!.single['grandTotal'],
      100,
    );
    expect(apiService.collectionActions.last['action'], 'editCollection');
    expect(
        apiService.collectionActions.last.containsKey('grandTotal'), isFalse);
    expect(find.text('Collection entry updated.'), findsOneWidget);

    await tester.tap(find.text('Jordan Updated'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete-collection-2')));
    await tester.tap(find.byKey(const Key('delete-collection-2')));
    await tester.pumpAndSettle();
    expect(find.text('Delete collection entry?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-collection')));
    await tester.pumpAndSettle();

    expect(apiService.collections['Daily_Collection'], isEmpty);
    expect(apiService.collectionActions.last['action'], 'deleteCollection');
    expect(find.text('Collection entry deleted.'), findsOneWidget);
  }, skip: true);

  testWidgets('payment schedule popup shows installment payment actions',
      (WidgetTester tester) async {
    final apiService = _FakeApiService();
    await tester.pumpWidget(NtccslAccountApp(apiService: apiService));
    await _signIn(tester);
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jordan Member'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('payment-schedule-2'))),
      alignment: 0.3,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment-schedule-2')));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    expect(find.text('Payment schedule'), findsOneWidget);
    expect(find.text('Jordan Member'), findsNWidgets(2));
    expect(find.text('Payments completed'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Received: ₹25.00'), findsOneWidget);
    expect(
      tester
          .widget<Material>(find.byKey(const Key('payment-schedule-header')))
          .elevation,
      0,
    );
    expect(
      tester
          .widget<Material>(find.byKey(const Key('payment-schedule-footer')))
          .elevation,
      0,
    );
    final closeButton = tester.widget<IconButton>(
      find.byKey(const Key('payment-schedule-close')),
    );
    expect(
      closeButton.style!.backgroundColor!.resolve(const {}),
      portalDeleteColor,
    );
    expect(
      closeButton.style!.foregroundColor!.resolve(const {}),
      Colors.white,
    );
    final payButton = tester.widget<FilledButton>(
      find.byKey(const Key('pay-collection-2')),
    );
    expect(payButton.style!.minimumSize!.resolve(const {}), const Size(0, 40));
    final closeAction = tester.widget<TextButton>(
      find.byKey(const Key('payment-schedule-close-action')),
    );
    expect(
      closeAction.style!.minimumSize!.resolve(const {}),
      payButton.style!.minimumSize!.resolve(const {}),
    );
    expect(
      closeAction.style!.backgroundColor!.resolve(const {}),
      portalDeleteColor,
    );
    expect(
      closeAction.style!.foregroundColor!.resolve(const {}),
      Colors.white,
    );
    final grid = tester.widget<GridView>(
      find.byKey(const Key('payment-schedule-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      3,
    );
    expect(find.byKey(const Key('schedule-chip-2-0')), findsOneWidget);
    expect(find.byKey(const Key('schedule-chip-2-1')), findsOneWidget);
    expect(find.byKey(const Key('pay-collection-2')), findsOneWidget);
    expect(find.byKey(const Key('pay-collection-2-0')), findsNothing);
    expect(find.byKey(const Key('pay-collection-2-1')), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: true);

  test('API login and authenticated actions use the session token', () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'token': 'session-token',
        'user': {
          'id': 'admin-1',
          'accountNo': 'ADM123456789',
          'name': 'Admin',
          'profileImageUrl':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA9sAAAAASUVORK5CYII=',
          'email': 'admin@example.com',
          'phoneNumber': '9876543210',
          'role': 'Admin',
        },
      },
      [
        {
          'id': 'user-1',
          'accountNo': 'DRD000000001',
          'name': 'Morgan Member',
          'phoneNumber': '9123456789',
          'email': 'morgan@example.com',
          'role': 'Member',
          'profileImageUrl': '',
        },
      ],
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);

    final session = await apiService.login('admin@example.com', 'password');
    expect(session.accountNumber, 'ADM123456789');
    expect(session.phoneNumber, '9876543210');
    expect(
      session.profileImageUrl,
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jA9sAAAAASUVORK5CYII=',
    );
    final users = await apiService.fetchSheetData('getUsers', session);
    final saved = await apiService.sendPostRequest({
      'action': 'editUser',
      'userId': 'user-1',
      'name': 'Morgan Updated',
    }, session);

    expect(users, hasLength(1));
    expect(saved, isTrue);
    expect(client.payloads.map((payload) => payload['action']), [
      'login',
      'getUsers',
      'editUser',
    ]);
    expect(client.payloads[0]['password'], 'password');
    expect(client.payloads[0]['loginType'], 'staff');
    expect(client.payloads[1]['token'], 'session-token');
    expect(client.payloads[2]['token'], 'session-token');
  });

  test('Cashfree API actions use the member session and verify the order',
      () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'orderId': 'NTC123',
        'paymentSessionId': 'session-id',
        'environment': 'sandbox',
      },
      {
        'status': 'success',
        'orderId': 'NTC123',
        'paymentStatus': 'PAID',
        'paid': true,
        'scheduleApplied': true,
        'scheduleDescription': 'RD monthly installment 3 (2026-10-23)',
      },
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'member-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
      accountNumber: 'DRD000000001',
    );

    final order = await apiService.createCashfreeOrder(
      session: session,
      baseAmount: 125,
      customerPhone: '9876543210',
      customerName: 'Jordan Member',
      customerEmail: 'jordan@example.com',
      scheduleTarget: const CashfreeScheduleTarget.deposit(
        depositId: 'deposit-1',
        periodIndex: 3,
      ),
    );
    final verification = await apiService.verifyCashfreePayment(
      session: session,
      orderId: order.orderId,
    );

    expect(order.paymentSessionId, 'session-id');
    expect(order.environment, 'sandbox');
    expect(verification.paid, isTrue);
    expect(verification.scheduleApplied, isTrue);
    expect(
      verification.scheduleDescription,
      'RD monthly installment 3 (2026-10-23)',
    );
    expect(client.payloads, [
      {
        'action': 'createCashfreeOrder',
        'token': 'member-token',
        'baseAmount': '125.00',
        'customerPhone': '9876543210',
        'customerName': 'Jordan Member',
        'customerEmail': 'jordan@example.com',
        'scheduleTarget': {
          'kind': 'deposit',
          'id': 'deposit-1',
          'periodIndex': 3,
        },
      },
      {
        'action': 'verifyCashfreePayment',
        'token': 'member-token',
        'orderId': 'NTC123',
      },
    ]);
  });

  test('Cashfree API surfaces sandbox credential rejection details', () async {
    final apiService = ApiService(
      client: _RecordingHttpClient([
        {
          'status': 'error',
          'message':
              'Cashfree rejected the API credentials for sandbox (HTTP 401). Use the matching sandbox App ID and Secret Key in Apps Script Script Properties.',
        },
      ]),
    );

    await expectLater(
      apiService.createCashfreeOrder(
        session: const AuthSession(
          token: 'member-token',
          userId: 'member-1',
          name: 'Jordan Member',
          email: 'jordan@example.com',
          role: 'Member',
        ),
        baseAmount: 125,
        customerPhone: '9876543210',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('Cashfree rejected the API credentials for sandbox'),
        ),
      ),
    );
  });

  test('Cashfree order request can target a selected member', () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'orderId': 'NTC456',
        'paymentSessionId': 'session-id',
        'environment': 'production',
      },
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'admin-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    await apiService.createCashfreeOrder(
      session: session,
      baseAmount: 125,
      customerPhone: '9876543210',
      memberId: 'member-2',
    );

    expect(client.payloads.single, {
      'action': 'createCashfreeOrder',
      'token': 'admin-token',
      'baseAmount': '125.00',
      'customerPhone': '9876543210',
      'memberId': 'member-2',
    });
  });

  test('role permissions read and save through authenticated API actions',
      () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'permissions': {
          for (final role in ['Collector', 'Member'])
            role: {
              for (final permission in [
                'shared_data_read',
                'ledger_view',
                'ledger_add',
                'ledger_edit',
                'ledger_delete',
                'ledger_update',
                'deposit_view',
                'deposit_add',
                'deposit_edit',
                'deposit_delete',
                'deposit_update',
                'loan_view',
                'loan_add',
                'loan_edit',
                'loan_delete',
                'loan_update',
                'user_view',
                'user_add',
                'user_edit',
                'user_delete',
                'user_update',
                'deposit_manage',
                'loan_manage',
                'ledger_manage',
                'user_manage',
              ])
                permission: switch (permission) {
                  'shared_data_read' => role == 'Collector',
                  'deposit_view' || 'loan_view' => role == 'Collector',
                  'deposit_manage' ||
                  'loan_manage' ||
                  'ledger_manage' ||
                  'user_manage' =>
                    false,
                  _ => false,
                },
            },
        },
      },
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'admin-session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final permissions = await apiService.fetchRolePermissions(session);
    await apiService.saveRolePermissions(permissions, session);

    expect(permissions['Collector']!['shared_data_read'], isTrue);
    expect(permissions['Member']!['deposit_view'], isFalse);
    expect(client.payloads.map((payload) => payload['action']), [
      'getRolePermissions',
      'setRolePermissions',
    ]);
    expect(client.payloads.first['token'], 'admin-session-token');
    expect(client.payloads.last['token'], 'admin-session-token');
    expect(client.payloads.last['permissions'], permissions);
  });

  test('unsupported role permissions action explains how to update deployment',
      () async {
    final apiService = ApiService(
      client: _RecordingHttpClient([
        {
          'status': 'error',
          'message': 'Unknown post action: getRolePermissions'
        },
      ]),
    );
    const session = AuthSession(
      token: 'admin-session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    await expectLater(
      apiService.fetchRolePermissions(session),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('does not support role permissions'),
            contains('deploy a new web-app version'),
          ),
        ),
      ),
    );
  });

  test('member login sends member type and rejects a staff response', () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'token': 'session-token',
        'user': {
          'id': 'staff-1',
          'name': 'Collector',
          'email': 'collector@example.com',
          'role': 'Collector',
        },
      },
    ]);
    final apiService = ApiService(client: client);

    await expectLater(
      apiService.login(
        'collector@example.com',
        'password',
        loginType: 'member',
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('Choose Admin / Collector login instead'),
        ),
      ),
    );
    expect(client.payloads.single['loginType'], 'member');
  });

  test('member login accepts account number as the identifier', () async {
    final client = _RecordingHttpClient([
      {
        'status': 'success',
        'token': 'member-session-token',
        'user': {
          'id': 'member-1',
          'accountNo': 'DRD000000001',
          'name': 'Jordan Member',
          'email': 'jordan@example.com',
          'role': 'Member',
        },
      },
    ]);
    final apiService = ApiService(client: client);

    final session = await apiService.login(
      'DRD000000001',
      'member-password',
      loginType: 'member',
    );

    expect(session.role, 'Member');
    expect(session.accountNumber, 'DRD000000001');
    expect(client.payloads.single['identifier'], 'DRD000000001');
    expect(client.payloads.single['email'], 'DRD000000001');
    expect(client.payloads.single['loginType'], 'member');
  });

  test('registration sends account details without a client-selected role',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);

    await apiService.register(
      name: 'Sam Member',
      email: 'sam@example.com',
      password: 'secure-pass',
    );

    expect(client.payloads.single, {
      'action': 'register',
      'name': 'Sam Member',
      'email': 'sam@example.com',
      'password': 'secure-pass',
    });
  });

  test('adding a collection entry sends its authenticated sheet fields',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final saved = await apiService.sendPostRequest({
      'action': 'addCollection',
      'sheetName': 'Weekly_Collection',
      'memberName': 'Jordan Member',
      'date': '2026-01-02',
      'depAmt': 25,
    }, session);

    expect(saved, isTrue);
    expect(client.payloads.single, {
      'action': 'addCollection',
      'sheetName': 'Weekly_Collection',
      'memberName': 'Jordan Member',
      'date': '2026-01-02',
      'depAmt': 25,
      'token': 'session-token',
    });
  }, skip: 'Collection functionality was removed.');

  test('deposit account reads include product, cadence, and session token',
      () async {
    final client = _RecordingHttpClient([
      [
        {
          'id': 'deposit-1',
          'product': 'RD',
          'cadence': 'monthly',
          'payments': [false],
          'paymentCount': 1,
          'paidCount': 0,
          'paymentRows': [
            {
              'periodIndex': 1,
              'dueDate': '2026-11-24',
              'installmentAmount': 500,
              'paid': false,
              'status': 'Unpaid',
            },
          ],
          'paymentRowCount': 1,
        },
      ],
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final accounts = await apiService.fetchDepositAccounts(
      product: 'RD',
      cadence: 'monthly',
      session: session,
    );

    expect(accounts.single['id'], 'deposit-1');
    expect(accounts.single['paymentCount'], 1);
    expect(accounts.single['paidCount'], 0);
    expect(
      (accounts.single['paymentRows'] as List).single['installmentAmount'],
      500,
    );
    expect(
      (accounts.single['paymentRows'] as List).single['paid'],
      isFalse,
    );
    expect(accounts.single['paymentRowCount'], 1);
    expect(client.payloads.single, {
      'action': 'getDepositAccounts',
      'token': 'session-token',
      'product': 'RD',
      'cadence': 'monthly',
    });
  });

  test('collection request retries once when the server lock is busy',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'error', 'message': 'The service is busy. Please try again.'},
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    final saved = await apiService.sendPostRequest({
      'action': 'toggleCollection',
      'sheetName': 'Daily_Collection',
      'rowIndex': 2,
      'periodIndex': 365,
    }, session);

    expect(saved, isTrue);
    expect(client.payloads, hasLength(2));
    expect(client.payloads[0], client.payloads[1]);
  }, skip: 'Collection functionality was removed.');

  test('editing and deleting collection entries include the session token',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
    );

    await apiService.sendPostRequest({
      'action': 'editCollection',
      'sheetName': 'Daily_Collection',
      'rowIndex': 2,
      'memberName': 'Jordan Updated',
      'date': '2026-01-02',
      'depAmt': 40,
    }, session);
    await apiService.sendPostRequest({
      'action': 'deleteCollection',
      'sheetName': 'Daily_Collection',
      'rowIndex': 2,
    }, session);

    expect(
      client.payloads.map((payload) => payload['action']),
      ['editCollection', 'deleteCollection'],
    );
    expect(
      client.payloads.every((payload) => payload['token'] == 'session-token'),
      isTrue,
    );
  }, skip: 'Collection functionality was removed.');

  test('change password sends current and new password with the session token',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );

    final saved = await apiService.sendPostRequest({
      'action': 'changePassword',
      'currentPassword': 'current-password',
      'newPassword': 'new-password',
    }, session);

    expect(saved, isTrue);
    expect(client.payloads.single, {
      'action': 'changePassword',
      'currentPassword': 'current-password',
      'newPassword': 'new-password',
      'token': 'session-token',
    });
  });

  test('profile updates include authenticated identity and changed image',
      () async {
    final client = _RecordingHttpClient([
      {'status': 'success'},
    ]);
    final apiService = ApiService(client: client);
    const session = AuthSession(
      token: 'session-token',
      userId: 'member-1',
      name: 'Jordan Member',
      email: 'jordan@example.com',
      role: 'Member',
    );

    await apiService.updateMyProfile(
      session: session,
      name: 'Jordan Updated',
      email: 'updated@example.com',
      phoneNumber: '9876543210',
      profileImageChanged: true,
      profileImageData: 'aW1hZ2U=',
      profileImageMimeType: 'image/png',
    );

    expect(client.payloads.single, {
      'action': 'updateMyProfile',
      'name': 'Jordan Updated',
      'email': 'updated@example.com',
      'phoneNumber': '9876543210',
      'profileImageChanged': true,
      'profileImageData': 'aW1hZ2U=',
      'profileImageMimeType': 'image/png',
      'token': 'session-token',
    });
  });

  test('unsupported login action reports that server setup is required',
      () async {
    for (final response in [
      {'status': 'error', 'message': 'Invalid action'},
      {'status': 'error', 'message': 'unknown post action'},
      'unknown post action',
    ]) {
      final apiService = ApiService(
        client: _RecordingHttpClient([response]),
      );

      await expectLater(
        apiService.login('admin@example.com', 'password'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('does not support email/password login yet'),
          ),
        ),
      );
    }
  });

  test('plain text unknown action response explains Apps Script setup',
      () async {
    final apiService = ApiService(
      client: _RecordingTextHttpClient('unknown post action'),
    );

    await expectLater(
      apiService.login('admin@example.com', 'password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('Add a login action'),
        ),
      ),
    );
  });
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email')),
    'admin@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'correct-horse',
  );
  await tester.ensureVisible(find.byKey(const Key('login-submit')));
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

Finder _bottomNavigationItems() => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byType(NavigationDestination),
    );

Set<String> _bottomNavigationLabels() => _bottomNavigationItems()
    .evaluate()
    .map((element) => (element.widget as NavigationDestination).label)
    .toSet();

Future<void> _openDrawerPage(WidgetTester tester, String itemKey) async {
  await tester.tap(find.byKey(const Key('open-navigation-menu')));
  await tester.pumpAndSettle();
  final item = find.byKey(Key(itemKey));
  if (itemKey == 'navigation-menu-daily' ||
      itemKey == 'navigation-menu-weekly' ||
      itemKey == 'navigation-menu-monthly') {
    final collections =
        find.byKey(const Key('navigation-menu-existing-collections'));
    await _expandDrawerTile(tester, collections, item);
  }
  if (itemKey.startsWith('navigation-menu-fd-') ||
      itemKey.startsWith('navigation-menu-rd-') ||
      itemKey.startsWith('navigation-menu-drd-')) {
    final deposit = find.byKey(const Key('navigation-menu-deposit'));
    final product = find.byKey(
      Key(
        'navigation-menu-product-${itemKey.split('-')[2]}',
      ),
    );
    await _expandDrawerTile(tester, deposit, product);
    await _expandDrawerTile(tester, product, item);
  }
  if (itemKey.startsWith('navigation-menu-loan-master') ||
      itemKey.startsWith('navigation-menu-personal-loan') ||
      itemKey.startsWith('navigation-menu-gold-loan') ||
      itemKey.startsWith('navigation-menu-approved-loans')) {
    await _expandDrawerTile(
      tester,
      find.byKey(const Key('navigation-menu-loans')),
      item,
    );
  }
  await _ensureDrawerItemVisible(tester, item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> _expandDrawerTile(
  WidgetTester tester,
  Finder tile,
  Finder child,
) async {
  if (child.evaluate().isNotEmpty) return;
  await _ensureDrawerItemVisible(tester, tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _ensureDrawerItemVisible(
  WidgetTester tester,
  Finder item,
) async {
  final drawerList = find
      .descendant(
        of: find.byType(Drawer),
        matching: find.byType(ListView),
      )
      .first;
  final drawerScrollable = find
      .descendant(
        of: drawerList,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(item, 200, scrollable: drawerScrollable);
  final listRect = tester.getRect(drawerList);
  final itemRect = tester.getRect(item);
  if (itemRect.bottom > listRect.bottom) {
    await tester.drag(
      drawerScrollable,
      Offset(0, listRect.bottom - itemRect.bottom - 8),
    );
    await tester.pumpAndSettle();
  } else if (itemRect.top < listRect.top) {
    await tester.drag(
      drawerScrollable,
      Offset(0, listRect.top - itemRect.top + 8),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollUntilBuilt(
  WidgetTester tester,
  Finder target,
  Finder scrollable,
) async {
  for (var attempt = 0; target.evaluate().isEmpty && attempt < 12; attempt++) {
    await tester.drag(scrollable, const Offset(0, -360));
    await tester.pumpAndSettle();
  }
  // ignore: avoid_print
  expect(target, findsOneWidget);
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform(this.bytes);

  final Uint8List bytes;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(bytes, name: 'profile.png', mimeType: 'image/png');
}

class _CashfreeTestApiService extends _FakeApiService {
  _CashfreeTestApiService({
    this.paid = false,
    this.scheduleApplied = false,
  });

  final bool paid;
  final bool scheduleApplied;
  final List<Map<String, dynamic>> createOrderCalls = [];
  final List<String> verifiedOrderIds = [];
  Completer<CashfreeOrder>? createOrderCompleter;

  @override
  Future<CashfreeOrder> createCashfreeOrder({
    required AuthSession session,
    required double baseAmount,
    required String customerPhone,
    String? customerName,
    String? customerEmail,
    String? memberId,
    CashfreeScheduleTarget? scheduleTarget,
  }) async {
    createOrderCalls.add({
      'session': session,
      'baseAmount': baseAmount,
      'customerPhone': customerPhone,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'memberId': memberId,
      'scheduleTarget': scheduleTarget?.toJson(),
    });
    const order = CashfreeOrder(
      orderId: 'NTC-no-account',
      paymentSessionId: 'test-session',
      environment: 'sandbox',
    );
    return createOrderCompleter == null
        ? order
        : await createOrderCompleter!.future;
  }

  @override
  Future<CashfreePaymentVerification> verifyCashfreePayment({
    required AuthSession session,
    required String orderId,
  }) async {
    verifiedOrderIds.add(orderId);
    return CashfreePaymentVerification(
      orderId: orderId,
      paymentStatus: paid ? 'PAID' : 'ACTIVE',
      paid: paid,
      scheduleApplied: scheduleApplied,
      scheduleDescription: scheduleApplied
          ? 'RD monthly installment 1 (2026-10-23)'
          : 'No matching unpaid installment was available.',
    );
  }
}

class _CashfreeConfigurationFailureApiService extends _FakeApiService {
  @override
  Future<CashfreeOrder> createCashfreeOrder({
    required AuthSession session,
    required double baseAmount,
    required String customerPhone,
    String? customerName,
    String? customerEmail,
    String? memberId,
    CashfreeScheduleTarget? scheduleTarget,
  }) async {
    throw const ApiException(
      'Cashfree is not configured. Ask an administrator to add the Cashfree credentials to Apps Script Script Properties.',
    );
  }
}

class _DelayedLoanSchemesApiService extends _FakeApiService {
  final Completer<List<Map<String, dynamic>>> schemesCompleter =
      Completer<List<Map<String, dynamic>>>();

  @override
  Future<List<Map<String, dynamic>>> fetchLoanSchemes({
    required AuthSession session,
    String? loanType,
    bool includeInactive = false,
  }) =>
      schemesCompleter.future;
}

class _DelayedLoanRecordsApiService extends _FakeApiService {
  final Completer<List<Map<String, dynamic>>> loansCompleter =
      Completer<List<Map<String, dynamic>>>();

  @override
  Future<List<Map<String, dynamic>>> fetchLoans({
    required AuthSession session,
    String? loanType,
    bool approvedOnly = false,
  }) =>
      loansCompleter.future;
}

class _FakeApiService extends ApiService {
  _FakeApiService() : super(client: _UnusedHttpClient());

  final List<Map<String, dynamic>> users = [
    {
      'id': 'user-1',
      'accountNo': 'DRD000000001',
      'name': 'Morgan Member',
      'email': 'morgan@example.com',
      'role': 'Member',
    },
    {
      'id': 'user-2',
      'accountNo': 'DRD000000002',
      'name': 'Taylor Member',
      'phoneNumber': '9876543210',
      'email': 'taylor@example.com',
      'role': 'Member',
      'profileImageUrl': '',
    },
  ];
  final List<Map<String, dynamic>> collectionRequests = [];
  final List<Map<String, dynamic>> collectionActions = [];
  final List<Map<String, dynamic>> depositRequests = [];
  final List<Map<String, dynamic>> depositActions = [];
  final List<Map<String, dynamic>> depositAccounts = [];
  final List<Map<String, dynamic>> loanRecords = [];
  final List<Map<String, dynamic>> loanActions = [];
  Object? loanFetchError;
  final List<Map<String, dynamic>> loanSchemes = [
    {
      'schemeId': 'personal-loan-standard',
      'schemeName': 'Personal Loan Standard',
      'loanType': 'personal',
      'minAnnualRate': 18,
      'maxAnnualRate': 37,
      'minAmount': 1,
      'maxAmount': 1000000000,
      'minTenureYears': 1,
      'maxTenureYears': 7,
      'fileChargePercent': 0,
      'processingFeePercent': 0,
      'calculationMethod': 'flat',
    },
    {
      'schemeId': 'gold-loan-standard',
      'schemeName': 'Gold Loan Standard',
      'loanType': 'gold',
      'minAnnualRate': 18,
      'maxAnnualRate': 37,
      'minAmount': 1,
      'maxAmount': 1000000000,
      'minTenureYears': 1,
      'maxTenureYears': 7,
      'fileChargePercent': 0,
      'processingFeePercent': 0,
      'calculationMethod': 'flat',
    },
  ];
  int rolePermissionFetchCount = 0;
  Completer<bool>? depositMutationCompleter;
  Object? depositFetchError;
  int depositFetchCount = 0;
  final List<Map<String, dynamic>> userRequests = [];
  final List<Map<String, dynamic>> passwordChanges = [];
  final List<Map<String, dynamic>> profileUpdates = [];
  Map<String, Map<String, bool>>? savedRolePermissions;
  final List<Map<String, dynamic>> ledgerRequests = [];
  final List<Map<String, dynamic>> ledgerActions = [];
  final List<String> fetchActions = [];
  final List<Map<String, dynamic>> ledgerEntries = [
    {
      '__rowIndex': 2,
      'byWhom': 'Office',
      'remarks': 'Opening balance',
      'date': '2026-10-17',
      'deposit': 100,
      'withdrawal': 0,
      'balance': 100,
      'payMode': 'Cash',
      'entryBy': '1 mafidul',
    },
  ];
  final Map<String, List<Map<String, dynamic>>> collections = {
    'Daily_Collection': [
      {
        'memberName': 'Jordan Member',
        'date': '2026-01-01',
        'depAmt': 25,
        'totalCount': 1,
        'totalReceived': 25,
        'grandTotal': 100,
        'periods': [true, false],
        'rowIndex': 2,
      },
    ],
    'Weekly_Collection': [],
    'Monthly_Collection': [],
  };
  bool didRegister = false;

  @override
  Future<AuthSession> login(
    String email,
    String password, {
    String loginType = 'staff',
  }) async {
    return const AuthSession(
      token: 'test-token',
      userId: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Admin',
      accountNumber: 'ADM123456789',
    );
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    didRegister = true;
  }

  @override
  Future<Map<String, Map<String, bool>>> fetchRolePermissions(
    AuthSession session,
  ) async {
    rolePermissionFetchCount++;
    return {
      for (final role in ['Collector', 'Member'])
        role: {
          'shared_data_read': role == 'Collector',
          'ledger_view': role == 'Collector',
          'ledger_add': role == 'Collector',
          'ledger_edit': role == 'Collector',
          'ledger_delete': role == 'Collector',
          'ledger_update': role == 'Collector',
          'deposit_view': true,
          'deposit_add': role == 'Collector',
          'deposit_edit': role == 'Collector',
          'deposit_delete': role == 'Collector',
          'deposit_update': role == 'Collector',
          'loan_view': role == 'Collector',
          'loan_add': role == 'Member',
          'loan_edit': false,
          'loan_delete': false,
          'loan_update': false,
          'user_view': role == 'Collector',
          'user_add': role == 'Collector',
          'user_edit': role == 'Collector',
          'user_delete': role == 'Collector',
          'user_update': false,
          'deposit_manage': role == 'Collector',
          'loan_manage': role == 'Collector',
          'ledger_manage': role == 'Collector',
          'user_manage': role == 'Collector',
        },
    };
  }

  @override
  Future<void> saveRolePermissions(
    Map<String, Map<String, bool>> permissions,
    AuthSession session,
  ) async {
    savedRolePermissions = {
      for (final entry in permissions.entries)
        entry.key: Map<String, bool>.from(entry.value),
    };
  }

  @override
  Future<dynamic> fetchSheetData(String action, AuthSession session) async {
    fetchActions.add(action);
    if (action == 'getUsers') return users;
    if (action == 'getAmount') return ledgerEntries;
    if (action.startsWith('get')) {
      final sheetName = '${action.substring(3)}_Collection';
      final records = collections[sheetName] ?? <Map<String, dynamic>>[];
      if (session.role.toLowerCase() == 'member') {
        return records
            .where((record) => session.matchesMemberName(record['memberName']))
            .toList();
      }
      return records;
    }
    return <dynamic>[];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDepositAccounts({
    required String product,
    required String cadence,
    required AuthSession session,
  }) async {
    depositFetchCount++;
    if (depositFetchError != null) throw depositFetchError!;
    fetchActions.add('getDepositAccounts:$product:$cadence');
    return depositAccounts
        .where(
          (account) =>
              account['product'] == product &&
              account['cadence'] == cadence &&
              (session.role.toLowerCase() != 'member' ||
                  session.matchesMemberName(account['memberName'])),
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLoans({
    required AuthSession session,
    String? loanType,
    bool approvedOnly = false,
  }) async {
    fetchActions.add(
      'getLoans:${loanType ?? 'all'}${approvedOnly ? ':approved' : ''}',
    );
    if (loanFetchError != null) throw loanFetchError!;
    return loanRecords
        .where(
          (loan) =>
              (loanType == null || loan['loanType'] == loanType) &&
              (!approvedOnly || loan['approvalStatus'] == 'Approved') &&
              (session.role.toLowerCase() != 'member' ||
                  session.matchesMemberName(loan['memberName'])),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>> fetchLoanPaymentSchedule({
    required String loanId,
    required AuthSession session,
  }) async {
    final loan = loanRecords.firstWhere((record) => record['id'] == loanId);
    final schedule = loan.putIfAbsent('paymentSchedule', () {
      final monthCount = (loan['tenureYears'] as num).toInt() * 12;
      final principal = (loan['principal'] as num).toDouble();
      final totalInterest = (loan['totalInterest'] as num).toDouble();
      final monthlyInterest = (totalInterest / monthCount * 100).round() / 100;
      final interestOnly = loan['repaymentMethod'] == 'interest_only';
      final monthlyInstallment = (loan['monthlyInstallment'] as num).toDouble();
      final startDate =
          DateTime.tryParse(loan['startDate']?.toString() ?? '') ??
              DateTime(2026, 1, 1);
      var interestPaid = 0.0;
      var principalPaid = 0.0;
      return List<Map<String, dynamic>>.generate(monthCount, (index) {
        final dueDate = DateTime(
          startDate.year,
          startDate.month + index + 1,
          startDate.day.clamp(
            1,
            DateTime(startDate.year, startDate.month + index + 2, 0).day,
          ),
        );
        final finalPeriod = index == monthCount - 1;
        final interestAmount =
            finalPeriod ? totalInterest - interestPaid : monthlyInterest;
        final principalAmount = interestOnly
            ? finalPeriod
                ? principal
                : 0.0
            : finalPeriod
                ? principal - principalPaid
                : monthlyInstallment - monthlyInterest;
        interestPaid += interestAmount;
        if (!interestOnly) principalPaid += principalAmount;
        return {
          'periodIndex': index + 1,
          'dueDate': DateFormat('yyyy-MM-dd').format(dueDate),
          'installmentAmount': principalAmount + interestAmount,
          'principalAmount': principalAmount,
          'interestAmount': interestAmount,
          'paid': false,
          'status': 'Unpaid',
        };
      });
    }) as List<Map<String, dynamic>>;
    return {
      'loanId': loanId,
      'memberName': loan['memberName'],
      'repaymentMethod': loan['repaymentMethod'] ?? 'fixed_emi',
      'principal': loan['principal'],
      'totalPayable': loan['totalPayable'],
      'payments': schedule,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLoanSchemes({
    required AuthSession session,
    String? loanType,
    bool includeInactive = false,
  }) async {
    fetchActions.add('getLoanSchemes:${loanType ?? 'all'}');
    return loanSchemes
        .where(
          (scheme) =>
              (includeInactive || scheme['active'] != false) &&
              (loanType == null || scheme['loanType'] == loanType),
        )
        .toList();
  }

  @override
  Future<bool> sendPostRequest(
    Map<String, dynamic> body,
    AuthSession session,
  ) async {
    if (body['action'] == 'editDepositAccount' ||
        body['action'] == 'deleteDepositAccount') {
      final completer = depositMutationCompleter;
      if (completer != null) {
        depositMutationCompleter = null;
        await completer.future;
      }
    }
    switch (body['action']) {
      case 'changePassword':
        passwordChanges.add({...body, 'token': session.token});
        return true;
      case 'updateMyProfile':
        profileUpdates.add({...body, 'token': session.token});
        return true;
      case 'addAmount':
        ledgerRequests.add(Map<String, dynamic>.from(body));
        ledgerEntries.add({
          ...body,
          '__rowIndex': ledgerEntries.length + 2,
          'date': '2026-10-18',
          'balance': body['balance'],
        });
        ledgerActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'editAmount':
        final entry = ledgerEntries.firstWhere(
          (item) => item['__rowIndex'] == body['rowIndex'],
        );
        entry
          ..['date'] = body['date']
          ..['byWhom'] = body['byWhom']
          ..['remarks'] = body['remarks']
          ..['deposit'] = body['deposit']
          ..['withdrawal'] = body['withdrawal']
          ..['balance'] = body['balance']
          ..['payMode'] = body['payMode']
          ..['entryBy'] = body['entryBy'];
        ledgerActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'deleteAmount':
        ledgerEntries.removeWhere(
          (item) => item['__rowIndex'] == body['rowIndex'],
        );
        ledgerActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'addCollection':
        collectionRequests.add(Map<String, dynamic>.from(body));
        final periods = List<bool>.from(
          body['periods'] as List? ?? const [],
        );
        final paidCount = periods.where((paid) => paid).length;
        collections[body['sheetName']]!.add({
          ...body,
          'rowIndex': collections[body['sheetName']]!.length + 2,
          'periods': periods,
          'totalCount': paidCount,
          'totalReceived': paidCount * (body['depAmt'] as num),
        });
        collectionActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'editCollection':
        final entries = collections[body['sheetName']]!;
        final entry = entries.firstWhere(
          (item) => item['rowIndex'] == body['rowIndex'],
        );
        entry
          ..['memberName'] = body['memberName']
          ..['date'] = body['date']
          ..['depAmt'] = body['depAmt'];
        collectionActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'deleteCollection':
        collections[body['sheetName']]!.removeWhere(
          (item) => item['rowIndex'] == body['rowIndex'],
        );
        collectionActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'addDepositAccount':
        depositRequests.add(Map<String, dynamic>.from(body));
        depositAccounts.add({
          ...body,
          'id': 'deposit-${depositAccounts.length + 1}',
          'maturityDate': DateFormat('yyyy-MM-dd').format(
            depositMaturityDate(
              DateFormat('yyyy-MM-dd').parse(body['startDate'] as String),
              body['tenureMonths'] as int,
            ),
          ),
          'maturityAmount': depositMaturityAmount(
            product: body['product'] as String,
            cadence: body['cadence'] as String,
            amount: (body['amount'] as num).toDouble(),
            annualRate: (body['annualRate'] as num).toDouble(),
            tenureMonths: body['tenureMonths'] as int,
            periodCount: (body['payments'] as List).length,
          ),
          'periodDates': body['product'] == 'FD'
              ? <String>[]
              : depositPeriodDates(
                  startDate: DateFormat('yyyy-MM-dd')
                      .parse(body['startDate'] as String),
                  maturityDate: depositMaturityDate(
                    DateFormat('yyyy-MM-dd').parse(body['startDate'] as String),
                    body['tenureMonths'] as int,
                  ),
                  cadence: body['cadence'] as String,
                ).map((date) => DateFormat('yyyy-MM-dd').format(date)).toList(),
        });
        depositActions.add(Map<String, dynamic>.from(body));
        return true;
      case 'editDepositAccount':
        depositActions.add(Map<String, dynamic>.from(body));
        final account =
            depositAccounts.firstWhere((item) => item['id'] == body['id']);
        account
          ..['memberName'] = body['memberName']
          ..['startDate'] = body['startDate']
          ..['amount'] = body['amount']
          ..['annualRate'] = body['annualRate']
          ..['tenureMonths'] = body['tenureMonths'];
        final startDate =
            DateFormat('yyyy-MM-dd').parse(body['startDate'] as String);
        final maturityDate = depositMaturityDate(
          startDate,
          body['tenureMonths'] as int,
        );
        final periodDates = body['product'] == 'FD'
            ? <DateTime>[]
            : depositPeriodDates(
                startDate: startDate,
                maturityDate: maturityDate,
                cadence: body['cadence'] as String,
              );
        account
          ..['maturityDate'] = DateFormat('yyyy-MM-dd').format(maturityDate)
          ..['periodDates'] = periodDates
              .map((date) => DateFormat('yyyy-MM-dd').format(date))
              .toList()
          ..['maturityAmount'] = depositMaturityAmount(
            product: body['product'] as String,
            cadence: body['cadence'] as String,
            amount: (body['amount'] as num).toDouble(),
            annualRate: (body['annualRate'] as num).toDouble(),
            tenureMonths: body['tenureMonths'] as int,
            periodCount: periodDates.length,
          );
        return true;
      case 'toggleDepositPayment':
        depositActions.add(Map<String, dynamic>.from(body));
        final account =
            depositAccounts.firstWhere((item) => item['id'] == body['id']);
        final payments = account['payments'] as List<dynamic>;
        final index = (body['periodIndex'] as int) - 1;
        payments[index] = !(payments[index] == true);
        return true;
      case 'deleteDepositAccount':
        depositActions.add(Map<String, dynamic>.from(body));
        depositAccounts.removeWhere((item) => item['id'] == body['id']);
        return true;
      case 'addLoan':
        loanActions.add(Map<String, dynamic>.from(body));
        final scheme = loanSchemes.firstWhere(
          (item) => item['schemeId'] == body['schemeId'],
        );
        final principal = (body['principal'] as num).toDouble();
        final fileChargePercent =
            (scheme['fileChargePercent'] as num?)?.toDouble() ?? 0;
        final processingFeePercent =
            (scheme['processingFeePercent'] as num?)?.toDouble() ?? 0;
        final fileCharge =
            (principal * fileChargePercent / 100 * 100).round() / 100;
        final processingFee =
            (principal * processingFeePercent / 100 * 100).round() / 100;
        final repaymentMethod = scheme['calculationMethod'] == 'interest_only'
            ? 'interest_only'
            : 'fixed_emi';
        loanRecords.add({
          ...body,
          'schemeName': scheme['schemeName'],
          'repaymentMethod': repaymentMethod,
          'id': 'loan-${loanRecords.length + 1}',
          'approvalStatus': 'Pending',
          'reviewedAt': '',
          'reviewedBy': '',
          'fileChargePercent': fileChargePercent,
          'processingFeePercent': processingFeePercent,
          'fileCharge': fileCharge,
          'processingFee': processingFee,
          'disbursedAmount': principal - fileCharge - processingFee,
          ...calculateLoanRepayment(
            principal: principal,
            annualRate: (body['annualRate'] as num).toDouble(),
            tenureYears: body['tenureYears'] as int,
            calculationMethod: repaymentMethod,
          ),
        });
        return true;
      case 'editLoan':
        loanActions.add(Map<String, dynamic>.from(body));
        final loan = loanRecords.firstWhere((item) => item['id'] == body['id']);
        final scheme = loanSchemes.firstWhere(
          (item) => item['schemeId'] == body['schemeId'],
        );
        final principal = (body['principal'] as num).toDouble();
        final fileChargePercent =
            (scheme['fileChargePercent'] as num?)?.toDouble() ?? 0;
        final processingFeePercent =
            (scheme['processingFeePercent'] as num?)?.toDouble() ?? 0;
        final fileCharge =
            (principal * fileChargePercent / 100 * 100).round() / 100;
        final processingFee =
            (principal * processingFeePercent / 100 * 100).round() / 100;
        final repaymentMethod = scheme['calculationMethod'] == 'interest_only'
            ? 'interest_only'
            : 'fixed_emi';
        loan
          ..['schemeId'] = body['schemeId']
          ..['schemeName'] = scheme['schemeName']
          ..['loanType'] = body['loanType']
          ..['repaymentMethod'] = repaymentMethod
          ..['memberName'] = body['memberName']
          ..['startDate'] = body['startDate']
          ..['principal'] = body['principal']
          ..['annualRate'] = body['annualRate']
          ..['tenureYears'] = body['tenureYears']
          ..['approvalStatus'] = 'Pending'
          ..['reviewedAt'] = ''
          ..['reviewedBy'] = ''
          ..['fileChargePercent'] = fileChargePercent
          ..['processingFeePercent'] = processingFeePercent
          ..['fileCharge'] = fileCharge
          ..['processingFee'] = processingFee
          ..['disbursedAmount'] = principal - fileCharge - processingFee
          ..addAll(
            calculateLoanRepayment(
              principal: principal,
              annualRate: (body['annualRate'] as num).toDouble(),
              tenureYears: body['tenureYears'] as int,
              calculationMethod: repaymentMethod,
            ),
          );
        return true;
      case 'deleteLoan':
        loanActions.add(Map<String, dynamic>.from(body));
        loanRecords.removeWhere((item) => item['id'] == body['id']);
        return true;
      case 'approveLoan':
        loanActions.add(Map<String, dynamic>.from(body));
        final loan = loanRecords.firstWhere((item) => item['id'] == body['id']);
        loan['approvalStatus'] = body['approvalStatus'];
        if (body['approvalStatus'] == 'Approved') {
          loan['loanNumber'] = 'LN-2026-123456';
        }
        return true;
      case 'toggleLoanPayment':
        loanActions.add(Map<String, dynamic>.from(body));
        final loan = loanRecords.firstWhere((item) => item['id'] == body['id']);
        final schedule = loan['paymentSchedule'] as List<dynamic>;
        final payment =
            schedule[(body['periodIndex'] as int) - 1] as Map<String, dynamic>;
        payment['paid'] = !(payment['paid'] == true);
        payment['status'] = payment['paid'] ? 'Paid' : 'Unpaid';
        return true;
      case 'addLoanScheme':
        loanActions.add(Map<String, dynamic>.from(body));
        loanSchemes.add({
          ...body,
          'schemeId': 'scheme-${loanSchemes.length + 1}',
          'calculationMethod': body['calculationMethod'] ?? 'fixed_emi',
        });
        return true;
      case 'editLoanScheme':
        loanActions.add(Map<String, dynamic>.from(body));
        final scheme = loanSchemes
            .firstWhere((item) => item['schemeId'] == body['schemeId']);
        scheme.addAll(body);
        return true;
      case 'deleteLoanScheme':
        loanActions.add(Map<String, dynamic>.from(body));
        loanSchemes.removeWhere((item) => item['schemeId'] == body['schemeId']);
        return true;
      case 'addUser':
        userRequests.add(Map<String, dynamic>.from(body));
        users.add({
          'id': 'user-${users.length + 1}',
          'name': body['name'],
          'phoneNumber': body['phoneNumber'] ?? '',
          'profileImageUrl': body['profileImageData'] == null
              ? ''
              : 'data:${body['profileImageMimeType']};base64,${body['profileImageData']}',
          'email': body['email'],
          'role': body['role'],
          'dailyAccess': body['dailyAccess'] ?? true,
          'weeklyAccess': body['weeklyAccess'] ?? true,
          'monthlyAccess': body['monthlyAccess'] ?? true,
        });
        return true;
      case 'editUser':
        userRequests.add(Map<String, dynamic>.from(body));
        final user = users.firstWhere((item) => item['id'] == body['userId']);
        user
          ..['name'] = body['name']
          ..['email'] = body['email']
          ..['phoneNumber'] = body['phoneNumber'] ?? ''
          ..['profileImageUrl'] = body['profileImageChanged'] == true
              ? body['profileImageData'] == null
                  ? ''
                  : 'data:${body['profileImageMimeType']};base64,${body['profileImageData']}'
              : user['profileImageUrl'] ?? ''
          ..['role'] = body['role']
          ..['dailyAccess'] = body['dailyAccess'] ?? user['dailyAccess'] ?? true
          ..['weeklyAccess'] =
              body['weeklyAccess'] ?? user['weeklyAccess'] ?? true
          ..['monthlyAccess'] =
              body['monthlyAccess'] ?? user['monthlyAccess'] ?? true;
        return true;
      case 'deleteUser':
        users.removeWhere((item) => item['id'] == body['userId']);
        return true;
      default:
        return true;
    }
  }
}

class _PendingRegisterApiService extends _FakeApiService {
  final completion = Completer<void>();

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) =>
      completion.future;
}

class _DashboardFailingApiService extends _FakeApiService {
  @override
  Future<dynamic> fetchSheetData(String action, AuthSession session) async {
    if (action == 'getAmount') {
      fetchActions.add(action);
      throw const ApiException('Ledger is unavailable.');
    }
    return super.fetchSheetData(action, session);
  }
}

class _UnusedHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('Network calls are replaced by the test service.');
  }
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this.responses);

  final List<dynamic> responses;
  final List<Map<String, dynamic>> payloads = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = (request as http.Request).body;
    payloads.add(jsonDecode(body) as Map<String, dynamic>);
    final response = jsonEncode(responses.removeAt(0));
    return http.StreamedResponse(
      Stream.value(utf8.encode(response)),
      200,
      request: request,
    );
  }
}

class _RecordingTextHttpClient extends http.BaseClient {
  _RecordingTextHttpClient(this.responseBody);

  final String responseBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(responseBody)),
      200,
      request: request,
    );
  }
}
