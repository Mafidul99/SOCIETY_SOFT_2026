import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String kGoogleAppScriptUrl = String.fromEnvironment(
  'GOOGLE_SCRIPT_URL',
  defaultValue:
      'https://script.google.com/macros/s/AKfycbxUydf0GjWv6cEfEDWM7sd4UonrKsoaGwELUtkxajegoKcL28ata5FWJIvP5IYHP-DG/exec',
);

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    this.phoneNumber = '',
    this.accountNumber = '',
    this.profileImageUrl = '',
    this.permissions = const {},
    this.reportAccess = const {
      'daily': true,
      'weekly': true,
      'monthly': true,
    },
  });

  final String token;
  final String userId;
  final String name;
  final String email;
  final String role;
  final String phoneNumber;
  final String accountNumber;
  final String profileImageUrl;
  final Map<String, bool> permissions;
  final Map<String, bool> reportAccess;

  bool hasPermission(String permission) {
    if (role.toLowerCase() == 'admin' || permissions[permission] == true) {
      return true;
    }
    if (permission == 'loan_add' &&
        role.toLowerCase() == 'member' &&
        !permissions.containsKey('loan_add')) {
      return true;
    }
    final legacyFallback = switch (permission) {
      'ledger_view' ||
      'ledger_add' ||
      'ledger_edit' ||
      'ledger_delete' ||
      'ledger_update' =>
        (
          'ledger_manage',
          const [
            'ledger_view',
            'ledger_add',
            'ledger_edit',
            'ledger_delete',
            'ledger_update',
          ]
        ),
      'deposit_add' ||
      'deposit_edit' ||
      'deposit_delete' ||
      'deposit_update' =>
        (
          'deposit_manage',
          const [
            'deposit_add',
            'deposit_edit',
            'deposit_delete',
            'deposit_update',
          ]
        ),
      'user_add' || 'user_edit' || 'user_delete' => (
          'user_manage',
          const ['user_add', 'user_edit', 'user_delete']
        ),
      _ => (null, const <String>[]),
    };
    if (legacyFallback.$1 != null &&
        !legacyFallback.$2.any(permissions.containsKey) &&
        permissions[legacyFallback.$1] == true) {
      return true;
    }
    final aliases = switch (permission) {
      'ledger_manage' => const [
          'ledger_add',
          'ledger_edit',
          'ledger_delete',
          'ledger_update',
        ],
      'deposit_manage' => const [
          'deposit_add',
          'deposit_edit',
          'deposit_delete',
          'deposit_update',
        ],
      'loan_manage' => const [
          'loan_edit',
          'loan_delete',
          'loan_update',
        ],
      'user_manage' => const ['user_add', 'user_edit', 'user_delete'],
      'ledger_view' => const ['shared_data_read'],
      'user_view' => const ['shared_data_read'],
      _ => const <String>[],
    };
    return aliases.any((key) => permissions[key] == true);
  }

  bool canViewReport(String report) =>
      role.toLowerCase() != 'member' || reportAccess[report] == true;

  bool matchesMemberName(Object? rowMemberName) {
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return normalize(rowMemberName?.toString() ?? '') == normalize(name);
  }

  AuthSession copyWith({
    String? name,
    String? email,
    String? phoneNumber,
    String? profileImageUrl,
  }) =>
      AuthSession(
        token: token,
        userId: userId,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        accountNumber: accountNumber,
        profileImageUrl: profileImageUrl ?? this.profileImageUrl,
        permissions: permissions,
        reportAccess: reportAccess,
      );
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CashfreeOrder {
  const CashfreeOrder({
    required this.orderId,
    required this.paymentSessionId,
    required this.environment,
  });

  final String orderId;
  final String paymentSessionId;
  final String environment;
}

class CashfreeScheduleTarget {
  const CashfreeScheduleTarget.deposit({
    required String depositId,
    required this.periodIndex,
  })  : kind = 'deposit',
        id = depositId;

  const CashfreeScheduleTarget.loan({
    required String loanId,
    required this.periodIndex,
  })  : kind = 'loan',
        id = loanId;

  final String kind;
  final String id;
  final int periodIndex;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'periodIndex': periodIndex,
      };
}

typedef SchedulePaymentCallback = Future<void> Function({
  required String memberName,
  required int amountPaise,
  required CashfreeScheduleTarget target,
});

class CashfreePaymentVerification {
  const CashfreePaymentVerification({
    required this.orderId,
    required this.paymentStatus,
    required this.paid,
    this.scheduleApplied = false,
    this.scheduleDescription = '',
  });

  final String orderId;
  final String paymentStatus;
  final bool paid;
  final bool scheduleApplied;
  final String scheduleDescription;
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<dynamic> _request(
    Map<String, dynamic> payload, {
    bool authenticationAction = false,
    bool retryOnBusy = true,
  }) async {
    try {
      var response = await _client
          .post(
            Uri.parse(kGoogleAppScriptUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if ((response.statusCode == 301 || response.statusCode == 302) &&
          response.headers['location'] != null) {
        response = await _client
            .get(Uri.parse(response.headers['location']!))
            .timeout(const Duration(seconds: 20));
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException('Server returned status ${response.statusCode}.');
      }

      final dynamic data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        if (response.body.toLowerCase().contains('unknown post action')) {
          throw ApiException(_unsupportedActionMessage(payload['action']));
        }
        throw const ApiException('The server returned an invalid response.');
      }

      if (data is String &&
          data.toLowerCase().contains('unknown post action')) {
        throw ApiException(_unsupportedActionMessage(payload['action']));
      }
      if (data is Map && data['status'] == 'error') {
        final message = data['message']?.toString() ?? 'The request failed.';
        final normalized = message.toLowerCase();
        if (retryOnBusy &&
            normalized == 'the service is busy. please try again.') {
          // Lock failures happen before the server runs the action, so retrying
          // this response cannot duplicate a successful write.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return _request(
            payload,
            authenticationAction: authenticationAction,
            retryOnBusy: false,
          );
        }
        if (normalized.contains('unknown post action') ||
            (authenticationAction &&
                (normalized.contains('unknown action') ||
                    normalized.contains('invalid action') ||
                    normalized.contains('unsupported action')))) {
          throw ApiException(_unsupportedActionMessage(payload['action']));
        }
        throw ApiException(message);
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (error) {
      debugPrint('API request failed: $error');
      throw const ApiException(
        'Could not connect to the service. Check your connection and try again.',
      );
    }
  }

  String _unsupportedActionMessage(dynamic action) {
    switch (action) {
      case 'login':
        return 'The server does not support email/password login yet. Add a login action to Apps Script doPost and redeploy.';
      case 'register':
        return 'The server does not support registration yet. Add a register action to Apps Script doPost and redeploy.';
      case 'getRolePermissions':
      case 'setRolePermissions':
        return 'The deployed Apps Script does not support role permissions yet. Update it with the current Code.gs, run setupAccountPortal in the bound project, deploy a new web-app version, and make sure this app uses that deployment URL.';
      case 'updateMyProfile':
        return 'The deployed Apps Script does not support profile editing yet. Update it with the current Code.gs and deploy a new web-app version.';
      default:
        return 'The deployed Apps Script does not support the "$action" action. Update Code.gs and deploy a new web-app version.';
    }
  }

  Future<AuthSession> login(
    String identifier,
    String password, {
    String loginType = 'staff',
  }) async {
    if (loginType != 'staff' && loginType != 'member') {
      throw const ApiException('Select a valid account type to sign in.');
    }
    final normalizedIdentifier = identifier.trim();
    final data = await _request(
      {
        'action': 'login',
        'identifier': normalizedIdentifier,
        // Keep `email` for compatibility with Apps Script deployments that
        // have not yet been updated to read the identifier field.
        'email': normalizedIdentifier,
        'password': password,
        'loginType': loginType,
      },
      authenticationAction: true,
    );
    if (data is! Map || data['user'] is! Map) {
      throw const ApiException(
        'The server returned an invalid login response. Expected a session token and user.',
      );
    }

    final user = data['user'] as Map;
    final token = data['token']?.toString() ?? '';
    final userId = user['id']?.toString() ?? '';
    if (data['status'] != 'success' ||
        token.isEmpty ||
        userId.isEmpty ||
        user['email'] == null ||
        user['role'] == null) {
      throw const ApiException(
        'The server returned an invalid login response.',
      );
    }
    final role = user['role'].toString();
    final normalizedRole = role.toLowerCase();
    final isMember = normalizedRole == 'member';
    final isStaff = normalizedRole == 'admin' || normalizedRole == 'collector';
    if ((loginType == 'member' && !isMember) ||
        (loginType == 'staff' && !isStaff)) {
      throw ApiException(
        loginType == 'member'
            ? 'This login is for Member accounts. Choose Admin / Collector login instead.'
            : 'This login is for Admin and Collector accounts. Choose Member login instead.',
      );
    }
    return AuthSession(
      token: token,
      userId: userId,
      name: user['name']?.toString() ?? '',
      email: user['email'].toString(),
      role: role,
      phoneNumber: user['phoneNumber']?.toString() ?? '',
      accountNumber: user['accountNo']?.toString() ?? '',
      profileImageUrl: user['profileImageUrl']?.toString() ?? '',
      permissions: data['permissions'] is Map
          ? (data['permissions'] as Map).map(
              (key, value) => MapEntry(key.toString(), value == true),
            )
          : const {},
      reportAccess: data['reportAccess'] is Map
          ? (data['reportAccess'] as Map).map(
              (key, value) => MapEntry(key.toString(), value == true),
            )
          : const {
              'daily': true,
              'weekly': true,
              'monthly': true,
            },
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final data = await _request(
      {
        'action': 'register',
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
      },
      authenticationAction: true,
    );
    if (data is! Map || data['status'] != 'success') {
      throw const ApiException(
        'The server did not confirm registration. Please try again.',
      );
    }
  }

  Future<dynamic> fetchSheetData(String action, AuthSession session) async {
    final data = await _request({
      'action': action,
      'token': session.token,
    });
    if (data is! List) {
      throw ApiException('The server returned invalid data for $action.');
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> fetchDepositAccounts({
    required String product,
    required String cadence,
    required AuthSession session,
  }) async {
    final data = await _request({
      'action': 'getDepositAccounts',
      'token': session.token,
      'product': product,
      'cadence': cadence,
    });
    if (data is! List || data.any((record) => record is! Map)) {
      throw const ApiException(
        'The server returned invalid deposit account data.',
      );
    }
    final accounts = data
        .map((record) => Map<String, dynamic>.from(record as Map))
        .toList(growable: false);
    if (session.role.toLowerCase() == 'member') {
      return accounts
          .where((record) => session.matchesMemberName(record['memberName']))
          .toList(growable: false);
    }
    return accounts;
  }

  Future<List<Map<String, dynamic>>> fetchLoans({
    required AuthSession session,
    String? loanType,
    bool approvedOnly = false,
  }) async {
    final data = await _request({
      'action': 'getLoans',
      'token': session.token,
      if (loanType != null) 'loanType': loanType,
      if (approvedOnly) 'approvedOnly': true,
    });
    if (data is! List || data.any((record) => record is! Map)) {
      throw const ApiException('The server returned invalid loan data.');
    }
    final loans = data.map((record) {
      final loan = Map<String, dynamic>.from(record as Map);
      final type = loan['loanType']?.toString().trim().toLowerCase() ?? '';
      final rawStatus = loan['approvalStatus']?.toString().trim() ?? '';
      final status = switch (rawStatus.toLowerCase()) {
        'pending' => 'Pending',
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        '' => 'Approved',
        _ => rawStatus,
      };
      final repaymentMethod =
          loan['repaymentMethod']?.toString().trim().toLowerCase();
      return {
        ...loan,
        'loanType': type,
        'approvalStatus': status,
        'repaymentMethod':
            repaymentMethod == 'interest_only' ? 'interest_only' : 'fixed_emi',
      };
    }).where((record) {
      return (loanType == null ||
              record['loanType'] == loanType.trim().toLowerCase()) &&
          (!approvedOnly || record['approvalStatus'] == 'Approved');
    }).toList(growable: false);
    if (session.role.toLowerCase() == 'member') {
      return loans
          .where((record) => session.matchesMemberName(record['memberName']))
          .toList(growable: false);
    }
    return loans;
  }

  Future<List<Map<String, dynamic>>> fetchLoanSchemes({
    required AuthSession session,
    String? loanType,
    bool includeInactive = false,
  }) async {
    final data = await _request({
      'action': 'getLoanSchemes',
      'token': session.token,
      if (loanType != null) 'loanType': loanType,
      if (includeInactive) 'includeInactive': true,
    });
    if (data is! List || data.any((record) => record is! Map)) {
      throw const ApiException('The server returned invalid loan schemes.');
    }
    return data.map((record) {
      final scheme = Map<String, dynamic>.from(record as Map);
      final method =
          scheme['calculationMethod']?.toString().trim().toLowerCase();
      return {
        ...scheme,
        'calculationMethod':
            method == 'interest_only' ? 'interest_only' : 'fixed_emi',
      };
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchLoanPaymentSchedule({
    required String loanId,
    required AuthSession session,
  }) async {
    final data = await _request({
      'action': 'getLoanPaymentSchedule',
      'token': session.token,
      'id': loanId,
    });
    if (data is! Map ||
        data['loanId']?.toString() != loanId ||
        data['payments'] is! List ||
        (data['payments'] as List).any((payment) => payment is! Map)) {
      throw const ApiException(
        'The server returned an invalid loan payment schedule.',
      );
    }
    return {
      ...Map<String, dynamic>.from(data),
      'payments': (data['payments'] as List)
          .map((payment) => Map<String, dynamic>.from(payment as Map))
          .toList(growable: false),
    };
  }

  Future<CashfreeOrder> createCashfreeOrder({
    required AuthSession session,
    required double baseAmount,
    required String customerPhone,
    String? customerName,
    String? customerEmail,
    String? memberId,
    CashfreeScheduleTarget? scheduleTarget,
  }) async {
    final payload = <String, dynamic>{
      'action': 'createCashfreeOrder',
      'token': session.token,
      'baseAmount': baseAmount.toStringAsFixed(2),
      'customerPhone': customerPhone,
      if (customerName != null) 'customerName': customerName,
      if (customerEmail != null) 'customerEmail': customerEmail,
    };
    if (memberId != null) payload['memberId'] = memberId;
    if (scheduleTarget != null) {
      payload['scheduleTarget'] = scheduleTarget.toJson();
    }
    final data = await _request(payload);
    if (data is! Map ||
        data['status'] != 'success' ||
        data['orderId'] is! String ||
        data['paymentSessionId'] is! String ||
        data['environment'] is! String) {
      throw const ApiException(
        'The server returned invalid Cashfree order details.',
      );
    }
    final environment = data['environment'] as String;
    if (environment != 'sandbox' && environment != 'production') {
      throw const ApiException(
        'The server returned an invalid Cashfree environment.',
      );
    }
    return CashfreeOrder(
      orderId: data['orderId'] as String,
      paymentSessionId: data['paymentSessionId'] as String,
      environment: environment,
    );
  }

  Future<CashfreePaymentVerification> verifyCashfreePayment({
    required AuthSession session,
    required String orderId,
  }) async {
    final data = await _request({
      'action': 'verifyCashfreePayment',
      'token': session.token,
      'orderId': orderId,
    });
    if (data is! Map ||
        data['status'] != 'success' ||
        data['orderId'] != orderId ||
        data['paymentStatus'] is! String ||
        data['paid'] is! bool) {
      throw const ApiException(
        'The server returned invalid Cashfree payment status.',
      );
    }
    return CashfreePaymentVerification(
      orderId: orderId,
      paymentStatus: data['paymentStatus'] as String,
      paid: data['paid'] as bool,
      scheduleApplied: data['scheduleApplied'] == true,
      scheduleDescription: data['scheduleDescription'] is String
          ? data['scheduleDescription'] as String
          : 'The backend did not confirm a schedule update. Deploy the updated Apps Script backend.',
    );
  }

  Future<Map<String, Map<String, bool>>> fetchRolePermissions(
    AuthSession session,
  ) async {
    final data = await _request({
      'action': 'getRolePermissions',
      'token': session.token,
    });
    if (data is! Map || data['permissions'] is! Map) {
      throw const ApiException(
        'The server returned invalid role permission settings.',
      );
    }
    final roles = data['permissions'] as Map;
    final result = <String, Map<String, bool>>{};
    for (final role in ['Collector', 'Member']) {
      final settings = roles[role];
      if (settings is! Map) {
        throw ApiException('The server returned invalid settings for $role.');
      }
      result[role] = {
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
          'loan_add',
          'deposit_manage',
          'loan_view',
          'loan_edit',
          'loan_delete',
          'loan_update',
          'user_view',
          'user_add',
          'user_edit',
          'user_delete',
          'user_update',
          'ledger_manage',
          'loan_manage',
          'user_manage',
        ])
          if (settings[permission] is bool)
            permission: settings[permission] as bool,
      };
      if (result[role]!.length != 25) {
        throw ApiException(
            'The server returned incomplete settings for $role.');
      }
    }
    return result;
  }

  Future<void> saveRolePermissions(
    Map<String, Map<String, bool>> permissions,
    AuthSession session,
  ) async {
    final saved = await sendPostRequest({
      'action': 'setRolePermissions',
      'permissions': permissions,
    }, session);
    if (!saved) {
      throw const ApiException('The server did not save role permissions.');
    }
  }

  Future<void> updateMyProfile({
    required AuthSession session,
    required String name,
    required String email,
    required String phoneNumber,
    required bool profileImageChanged,
    String? profileImageData,
    String? profileImageMimeType,
  }) async {
    final saved = await sendPostRequest({
      'action': 'updateMyProfile',
      'name': name.trim(),
      'email': email.trim(),
      'phoneNumber': phoneNumber.trim(),
      if (profileImageChanged) 'profileImageChanged': true,
      if (profileImageData != null) ...{
        'profileImageData': profileImageData,
        'profileImageMimeType': profileImageMimeType,
      },
    }, session);
    if (!saved) {
      throw const ApiException('The server did not update your profile.');
    }
  }

  Future<bool> sendPostRequest(
    Map<String, dynamic> body,
    AuthSession session,
  ) async {
    final data = await _request({...body, 'token': session.token});
    return data is Map &&
        (data['status'] == 'success' || data['success'] == true);
  }
}
