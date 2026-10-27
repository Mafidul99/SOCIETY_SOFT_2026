import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/cashfree_payment_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/deposit_account_page.dart';
import 'pages/bank_ladger_page.dart';
import 'pages/login_page.dart';
import 'pages/loan/approved_loans_page.dart';
import 'pages/loan/gold_loan_page.dart';
import 'pages/loan/loan_master_page.dart';
import 'pages/loan/personal_loan_page.dart';
import 'pages/profile_page.dart';
import 'pages/roles_permissions_page.dart';
import 'pages/splash_page.dart';
import 'pages/support_page.dart';
import 'pages/users_page.dart';
import 'services/api_service.dart';
import 'widgets/portal_widgets.dart';
import 'widgets/profile_image.dart';

const _depositRoutes = <String, int>{
  'fd-monthly': 4,
  'rd-weekly': 5,
  'rd-monthly': 6,
  'drd-daily': 7,
  'drd-weekly': 8,
  'drd-monthly': 9,
};

void main() => runApp(NtccslAccountApp(showSplashScreen: true));

String _themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return 'System default';
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
  }
}

IconData _themeModeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return Icons.settings_brightness_rounded;
    case ThemeMode.light:
      return Icons.light_mode_rounded;
    case ThemeMode.dark:
      return Icons.dark_mode_rounded;
  }
}

class NtccslAccountApp extends StatefulWidget {
  NtccslAccountApp({
    super.key,
    ApiService? apiService,
    this.showSplashScreen = false,
  }) : apiService = apiService ?? ApiService();

  final ApiService apiService;
  final bool showSplashScreen;

  @override
  State<NtccslAccountApp> createState() => _NtccslAccountAppState();
}

class _NtccslAccountAppState extends State<NtccslAccountApp> {
  AuthSession? _session;
  ThemeMode _themeMode = ThemeMode.system;
  late bool _showSplashScreen;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _showSplashScreen = widget.showSplashScreen;
    if (_showSplashScreen) {
      _splashTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showSplashScreen = false);
      });
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NTCCSL FINANCE SYSTEM',
      debugShowCheckedModeBanner: false,
      theme: _portalTheme(Brightness.light),
      darkTheme: _portalTheme(Brightness.dark),
      themeMode: _themeMode,
      home: _showSplashScreen
          ? const SplashPage()
          : _session == null
              ? LoginPage(
                  apiService: widget.apiService,
                  onLoggedIn: (session) => setState(() => _session = session),
                )
              : MainHomeScreen(
                  apiService: widget.apiService,
                  session: _session!,
                  onSessionUpdated: (session) =>
                      setState(() => _session = session),
                  themeMode: _themeMode,
                  onThemeModeChanged: (mode) => setState(() {
                    _themeMode = mode;
                  }),
                  onLogout: () => setState(() => _session = null),
                ),
    );
  }
}

ThemeData _portalTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  const darkAppBarBackground = Color(0xFF253B8C);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: isLight ? const Color(0xFF3458D4) : const Color(0xFF9EB4FF),
    brightness: brightness,
    surface: isLight ? Colors.white : const Color(0xFF191B23),
  );
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor:
        isLight ? const Color(0xFFF5F7FB) : const Color(0xFF11131A),
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: colorScheme.tertiary),
    primaryIconTheme: IconThemeData(color: colorScheme.onPrimary),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.secondary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      prefixIconColor: colorScheme.primary,
      suffixIconColor: colorScheme.tertiary,
      filled: true,
      fillColor: colorScheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.error),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: .55)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: states.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        );
      }),
      elevation: 8,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: isLight ? colorScheme.primary : darkAppBarBackground,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({
    super.key,
    required this.apiService,
    required this.session,
    this.onSessionUpdated,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    required this.onLogout,
  });

  final ApiService apiService;
  final AuthSession session;
  final ValueChanged<AuthSession>? onSessionUpdated;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback onLogout;

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _selectedIndex = 0;
  int _refreshVersion = 0;
  int _loanRefreshVersion = 0;
  int _dashboardRefreshVersion = 0;
  final Set<int> _visitedPages = {0};

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';
  bool get _canViewLedger =>
      widget.session.hasPermission('shared_data_read') ||
      widget.session.hasPermission('ledger_view') ||
      widget.session.hasPermission('ledger_add') ||
      widget.session.hasPermission('ledger_edit') ||
      widget.session.hasPermission('ledger_delete') ||
      widget.session.hasPermission('ledger_update');
  bool get _canViewUsers =>
      widget.session.hasPermission('shared_data_read') ||
      widget.session.hasPermission('user_view') ||
      widget.session.hasPermission('user_add') ||
      widget.session.hasPermission('user_edit') ||
      widget.session.hasPermission('user_delete');
  bool get _canViewDepositAccounts =>
      widget.session.hasPermission('deposit_view') ||
      widget.session.hasPermission('deposit_add') ||
      widget.session.hasPermission('deposit_edit') ||
      widget.session.hasPermission('deposit_delete') ||
      widget.session.hasPermission('deposit_update');
  bool get _canViewLoans =>
      (widget.session.role.toLowerCase() == 'member' &&
          (widget.session.hasPermission('loan_add') ||
              widget.session.hasPermission('loan_view'))) ||
      widget.session.hasPermission('loan_view') ||
      widget.session.hasPermission('loan_add') ||
      widget.session.hasPermission('loan_edit') ||
      widget.session.hasPermission('loan_delete') ||
      widget.session.hasPermission('loan_update') ||
      widget.session.hasPermission('loan_manage');

  List<int> get _loanMenuPageIndices {
    if (_isAdmin) return const [12, 13, 14, 15];
    if (widget.session.role.toLowerCase() == 'member') {
      return _canViewLoans ? const [13, 14, 15] : const [];
    }
    if (!_canViewLoans) return const [];
    return [
      if (widget.session.hasPermission('loan_update')) 12,
      13,
      14,
      if (widget.session.hasPermission('loan_view') ||
          widget.session.hasPermission('loan_edit') ||
          widget.session.hasPermission('loan_delete') ||
          widget.session.hasPermission('loan_update'))
        15,
    ];
  }

  List<int> get _visiblePageIndices => [
        0,
        if (_canViewLedger) 1,
        if (_canViewDepositAccounts && widget.session.canViewReport('monthly'))
          4,
        if (_canViewDepositAccounts && widget.session.canViewReport('weekly'))
          5,
        if (_canViewDepositAccounts && widget.session.canViewReport('monthly'))
          6,
        if (_canViewDepositAccounts && widget.session.canViewReport('daily')) 7,
        if (_canViewDepositAccounts && widget.session.canViewReport('weekly'))
          8,
        if (_canViewDepositAccounts && widget.session.canViewReport('monthly'))
          9,
        ..._loanMenuPageIndices,
        if (_canViewUsers) 2,
        if (_isAdmin) 3,
        11,
      ];
  static const _navigationLabels = [
    'Dashboard',
    'Accounts',
    'Users',
    'Roles & Permissions',
  ];

  void _selectPage(int index) {
    if (index == _supportPageIndex) {
      setState(() {
        _selectedIndex = index;
        _visitedPages.add(index);
      });
      return;
    }
    if (!_visiblePageIndices.contains(index)) return;
    setState(() {
      if (index == 0 && _selectedIndex != 0) {
        _dashboardRefreshVersion++;
      }
      _selectedIndex = index;
      _visitedPages.add(index);
      if (index >= 12 && index <= 15) _loanRefreshVersion++;
    });
  }

  void _handleCashfreePaymentVerified() {
    setState(() {
      _refreshVersion++;
      _selectedIndex = 0;
      _visitedPages.add(0);
    });
  }

  void _handleScheduledPaymentVerified() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _handleCashfreePaymentVerified();
  }

  Future<void> _startSchedulePayment({
    required String memberName,
    required int amountPaise,
    required CashfreeScheduleTarget target,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CashfreePaymentPage(
          apiService: widget.apiService,
          session: widget.session,
          fixedAmountPaise: amountPaise,
          fixedMemberName: memberName,
          scheduleTarget: target,
          onPaymentVerified: _handleScheduledPaymentVerified,
        ),
      ),
    );
  }

  List<int> get _availableDepositRoutes =>
      _visiblePageIndices.where((index) => index >= 4 && index <= 9).toList();

  List<int> _depositRoutesForProduct(String product) =>
      _availableDepositRoutes.where((index) {
        final route = _depositRouteForPage(index);
        return route?.$1 == product;
      }).toList();

  (String, String)? _depositRouteForPage(int index) => switch (index) {
        4 => ('FD', 'monthly'),
        5 => ('RD', 'weekly'),
        6 => ('RD', 'monthly'),
        7 => ('DRD', 'daily'),
        8 => ('DRD', 'weekly'),
        9 => ('DRD', 'monthly'),
        _ => null,
      };

  List<
      ({
        String label,
        IconData icon,
        IconData selectedIcon,
        Color color,
        int? pageIndex,
        String? depositProduct,
      })> get _bottomNavigationItems => [
        (
          label: 'Dashboard',
          icon: _navigationIcons[0],
          selectedIcon: _navigationSelectedIcons[0],
          color: _navigationColors[0],
          pageIndex: 0,
          depositProduct: null,
        ),
        if (_depositRoutesForProduct('FD').isNotEmpty)
          (
            label: 'FD',
            icon: _depositProductIcon('FD'),
            selectedIcon: Icons.savings_rounded,
            color: _depositProductColor('FD'),
            pageIndex: null,
            depositProduct: 'FD',
          ),
        if (_depositRoutesForProduct('RD').isNotEmpty)
          (
            label: 'RD',
            icon: _depositProductIcon('RD'),
            selectedIcon: Icons.event_repeat_rounded,
            color: _depositProductColor('RD'),
            pageIndex: null,
            depositProduct: 'RD',
          ),
        if (_depositRoutesForProduct('DRD').isNotEmpty)
          (
            label: 'DRD',
            icon: _depositProductIcon('DRD'),
            selectedIcon: Icons.calendar_month_rounded,
            color: _depositProductColor('DRD'),
            pageIndex: null,
            depositProduct: 'DRD',
          ),
        if (_canViewUsers)
          (
            label: 'Users',
            icon: _navigationIcons[2],
            selectedIcon: _navigationSelectedIcons[2],
            color: _navigationColors[2],
            pageIndex: 2,
            depositProduct: null,
          ),
        if (widget.session.role.toLowerCase() == 'member')
          (
            label: 'Pay',
            icon: Icons.payments_outlined,
            selectedIcon: Icons.payments_rounded,
            color: const Color(0xFF00897B),
            pageIndex: 11,
            depositProduct: null,
          ),
      ];

  int get _selectedBottomNavigationIndex {
    final items = _bottomNavigationItems;
    final route = _depositRouteForPage(_selectedIndex);
    final index = items.indexWhere(
      (item) =>
          item.pageIndex == _selectedIndex ||
          (route != null && item.depositProduct == route.$1),
    );
    if (index >= 0) return index;
    return 0;
  }

  void _onBottomNavigationSelected(int destinationIndex) {
    final item = _bottomNavigationItems[destinationIndex];
    final pageIndex = item.pageIndex;
    if (pageIndex != null) {
      _selectPage(pageIndex);
      return;
    }
    final product = item.depositProduct;
    if (product == null) return;
    final routes = _depositRoutesForProduct(product);
    if (routes.length == 1) {
      _selectPage(routes.single);
    } else if (routes.isNotEmpty) {
      _showDepositPicker(product);
    }
  }

  Future<void> _showDepositPicker(String product) async {
    final availableRoutes = _depositRoutesForProduct(product);
    if (availableRoutes.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$product accounts',
                key: Key('bottom-${product.toLowerCase()}-picker-title'),
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose a scheme to view its accounts.',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * .62,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final index in availableRoutes)
                      Builder(
                        builder: (context) {
                          final parts = _titles[index].split(' ');
                          final product = parts.first;
                          final cadence = parts.last.toLowerCase();
                          final accent = _depositProductColor(product);
                          return Card(
                            key: Key('bottom-deposit-option-$index'),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: accent.withValues(alpha: .12),
                                child: Icon(
                                  _depositCadenceIcon(cadence),
                                  color: accent,
                                ),
                              ),
                              title: Text('$product · ${_capitalize(cadence)}'),
                              subtitle: Text(
                                switch (product) {
                                  'FD' => 'One-time fixed deposit',
                                  'RD' => 'Recurring deposit',
                                  _ => 'Daily recurring deposit',
                                },
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                _selectPage(index);
                              },
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);

  Widget _navigationMenuTile(BuildContext context, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        key: Key('navigation-menu-${_navigationLabels[index].toLowerCase()}'),
        selected: _selectedIndex == index,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: _navigationColors[index].withValues(alpha: .12),
          child: Icon(
            _navigationIcons[index],
            color: _navigationColors[index],
            size: 20,
          ),
        ),
        title: Text(_navigationLabels[index]),
        onTap: () {
          _selectPage(index);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _depositRouteTile(
    BuildContext context,
    String product,
    String cadence,
  ) {
    final index = _depositRoutes['${product.toLowerCase()}-$cadence']!;
    if (!_visiblePageIndices.contains(index)) return const SizedBox.shrink();
    final color = _depositProductColor(product);
    return ListTile(
      key: Key('navigation-menu-${product.toLowerCase()}-$cadence'),
      selected: _selectedIndex == index,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(
          _depositCadenceIcon(cadence),
          color: color,
          size: 18,
        ),
      ),
      title: Text(cadence[0].toUpperCase() + cadence.substring(1)),
      onTap: () {
        _selectPage(index);
        Navigator.of(context).pop();
      },
    );
  }

  Color _depositProductColor(String product) => switch (product) {
        'FD' => const Color(0xFF3458D4),
        'RD' => const Color(0xFF8E24AA),
        _ => const Color(0xFF078A6A),
      };

  IconData _depositProductIcon(String product) => switch (product) {
        'FD' => Icons.savings_outlined,
        'RD' => Icons.event_repeat_rounded,
        _ => Icons.calendar_month_rounded,
      };

  IconData _depositCadenceIcon(String cadence) => switch (cadence) {
        'daily' => Icons.today_rounded,
        'weekly' => Icons.calendar_view_week_rounded,
        _ => Icons.calendar_month_rounded,
      };

  Widget _loanMenuTile(BuildContext context, int index, String title) {
    final selected = _selectedIndex == index;
    return ListTile(
      key: Key(
        'navigation-menu-${title.toLowerCase().replaceAll(' ', '-')}',
      ),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      leading: Icon(
        switch (index) {
          12 => Icons.dashboard_customize_outlined,
          13 => Icons.person_outline_rounded,
          14 => Icons.diamond_outlined,
          _ => Icons.verified_outlined,
        },
        color: const Color(0xFFB7791F),
      ),
      title: Text(title),
      onTap: () {
        _selectPage(index);
        Navigator.of(context).pop();
      },
    );
  }

  Widget _depositProductGroup(BuildContext context, String product) {
    final cadences = switch (product) {
      'FD' => const ['monthly'],
      'RD' => const ['weekly', 'monthly'],
      _ => const ['daily', 'weekly', 'monthly'],
    };
    final visibleCadences = cadences.where(
      (cadence) => _visiblePageIndices
          .contains(_depositRoutes['${product.toLowerCase()}-$cadence']),
    );
    if (visibleCadences.isEmpty) return const SizedBox.shrink();
    final color = _depositProductColor(product);
    return ExpansionTile(
      key: Key('navigation-menu-product-${product.toLowerCase()}'),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(
          _depositProductIcon(product),
          color: color,
          size: 18,
        ),
      ),
      title: Text(product),
      children: [
        for (final cadence in visibleCadences)
          _depositRouteTile(context, product, cadence),
      ],
    );
  }

  void _logout() {
    showPortalToast(context, 'Signed out successfully.');
    widget.onLogout();
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          apiService: widget.apiService,
          session: widget.session,
          onSessionUpdated: widget.onSessionUpdated,
        ),
      ),
    );
  }

  Future<void> _selectThemeMode() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const Key('theme-mode-dialog'),
        title: const Text('Appearance'),
        children: [
          for (final option in ThemeMode.values)
            SimpleDialogOption(
              key: Key('theme-mode-${option.name}'),
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  Icon(_themeModeIcon(option)),
                  const SizedBox(width: 16),
                  Expanded(child: Text(_themeModeLabel(option))),
                  if (widget.themeMode == option)
                    Icon(
                      Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) widget.onThemeModeChanged?.call(selected);
  }

  static const _navigationIcons = [
    Icons.dashboard_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.people_outline,
    Icons.admin_panel_settings_outlined,
  ];

  static const _navigationSelectedIcons = [
    Icons.dashboard_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.people,
    Icons.admin_panel_settings_rounded,
  ];

  static const _navigationColors = [
    Color(0xFF7C4DFF),
    Color(0xFF3458D4),
    Color(0xFF039BE5),
    Color(0xFFB45309),
  ];

  static const _supportPageIndex = 10;

  static const _titles = [
    'Dashboard',
    'Bank Ledger',
    'Users List',
    'Roles & Permissions',
    'FD Monthly',
    'RD Weekly',
    'RD Monthly',
    'DRD Daily',
    'DRD Weekly',
    'DRD Monthly',
    'Support',
    'Make a payment',
    'Loan Master',
    'Personal Loan',
    'Gold Loan',
    'Approved Loans',
  ];

  List<Widget> get _pages => [
        DashboardPage(
          key: ValueKey('dashboard-$_refreshVersion-$_dashboardRefreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          onNavigate: _selectPage,
        ),
        BankLadgerPage(
          key: ValueKey('ledger-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        UsersPage(
          key: ValueKey('users-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        RolesPermissionsPage(
          key: ValueKey('roles-permissions-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        for (final route in [
          ('FD', 'monthly'),
          ('RD', 'weekly'),
          ('RD', 'monthly'),
          ('DRD', 'daily'),
          ('DRD', 'weekly'),
          ('DRD', 'monthly'),
        ])
          DepositAccountPage(
            key: ValueKey(
              'deposit-${route.$1.toLowerCase()}-${route.$2}-$_refreshVersion',
            ),
            apiService: widget.apiService,
            session: widget.session,
            product: route.$1,
            cadence: route.$2,
            onSchedulePayment: _startSchedulePayment,
          ),
        SupportPage(
          key: ValueKey('support-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        CashfreePaymentPage(
          key: ValueKey('cashfree-payment-$_refreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          onPaymentVerified: _handleCashfreePaymentVerified,
        ),
        LoanMasterPage(
          key: ValueKey('loan-master-$_loanRefreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
        PersonalLoanPage(
          key: ValueKey('personal-loans-$_loanRefreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          onSchedulePayment: _startSchedulePayment,
        ),
        GoldLoanPage(
          key: ValueKey('gold-loans-$_loanRefreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
          onSchedulePayment: _startSchedulePayment,
        ),
        ApprovedLoansPage(
          key: ValueKey('approved-loans-$_loanRefreshVersion'),
          apiService: widget.apiService,
          session: widget.session,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final headerGradient = portalHeaderGradient(context);
    final displayName = widget.session.name.trim().isEmpty
        ? 'Portal user'
        : widget.session.name.trim();
    final profileInitial = displayName.characters.first.toUpperCase();
    final profileImage = profileImageProvider(widget.session.profileImageUrl);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: headerGradient,
            ),
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            key: const Key('open-navigation-menu'),
            tooltip: 'Open navigation menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        title: Text(
          _titles[_selectedIndex],
        ),
        titleSpacing: 12,
        actions: [
          IconButton(
            tooltip: 'Reload page data',
            onPressed: () => setState(() => _refreshVersion++),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .18),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            key: const Key('open-profile'),
            tooltip: 'Account: $displayName',
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _openProfile();
                case 'logout':
                  _logout();
              }
            },
            itemBuilder: (context) {
              final colors = Theme.of(context).colorScheme;
              return [
                PopupMenuItem<String>(
                  key: const Key('profile-menu-profile'),
                  value: 'profile',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.account_circle_outlined,
                      color: colors.primary,
                    ),
                    title: Text(
                      'Profile',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                PopupMenuItem<String>(
                  key: const Key('profile-menu-logout'),
                  value: 'logout',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.logout_rounded,
                      color: colors.error,
                    ),
                    title: Text(
                      'Logout',
                      style: TextStyle(
                        color: colors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ];
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    key: const Key('open-profile-avatar'),
                    radius: 16,
                    backgroundColor: Colors.white,
                    foregroundImage: profileImage,
                    child: Text(
                      profileInitial,
                      style: const TextStyle(
                        color: Color(0xFF3458D4),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: Drawer(
        width: MediaQuery.sizeOf(context).width * .82,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: headerGradient,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          key: const Key('ntccsl-app-icon'),
                          width: 52,
                          height: 52,
                          child: profileImage == null
                              ? ColoredBox(
                                  color: Colors.white.withValues(alpha: .18),
                                  child: Center(
                                    child: Text(
                                      profileInitial,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                )
                              : Image(
                                  key: const Key('navigation-user-image'),
                                  image: profileImage,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      ColoredBox(
                                    color: Colors.white.withValues(alpha: .18),
                                    child: Center(
                                      child: Text(
                                        profileInitial,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NTCCSL FINANCE SYSTEM',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .6,
                              ),
                            ),
                            Text(
                              displayName,
                              key: const Key('navigation-user-name'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Account No: ${widget.session.accountNumber.trim().isEmpty ? 'Not assigned' : widget.session.accountNumber.trim()}',
                              key: const Key('navigation-user-account-number'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Email: ${widget.session.email.trim().isEmpty ? 'Not available' : widget.session.email.trim()}',
                              key: const Key('navigation-user-email'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              'Role: ${widget.session.role}',
                              key: const Key('navigation-user-role'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('close-navigation-menu'),
                        tooltip: 'Close navigation menu',
                        onPressed: () => Navigator.of(context).pop(),
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'NAVIGATION',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final index in _visiblePageIndices)
                      if (index < 2) _navigationMenuTile(context, index),
                    if (_visiblePageIndices
                        .any((index) => index >= 4 && index <= 9))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ExpansionTile(
                          key: const Key('navigation-menu-deposit'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                const Color(0xFF00897B).withValues(alpha: .12),
                            child: const Icon(
                              Icons.savings_outlined,
                              color: Color(0xFF00897B),
                              size: 20,
                            ),
                          ),
                          title: const Text('Deposit'),
                          childrenPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            _depositProductGroup(context, 'FD'),
                            _depositProductGroup(context, 'RD'),
                            _depositProductGroup(context, 'DRD'),
                          ],
                        ),
                      ),
                    if (_loanMenuPageIndices.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ExpansionTile(
                          key: const Key('navigation-menu-loans'),
                          leading: const CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0x1FB7791F),
                            child: Icon(
                              Icons.account_balance_outlined,
                              color: Color(0xFFB7791F),
                              size: 20,
                            ),
                          ),
                          title: const Text('Loans'),
                          childrenPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          children: [
                            for (final index in _loanMenuPageIndices)
                              _loanMenuTile(
                                context,
                                index,
                                switch (index) {
                                  12 => 'Loan Master',
                                  13 => 'Personal Loan',
                                  14 => 'Gold Loan',
                                  _ => 'Approved Loans',
                                },
                              ),
                          ],
                        ),
                      ),
                    for (final index in _visiblePageIndices)
                      if (index == 2 || index == 3)
                        _navigationMenuTile(context, index),
                    ListTile(
                      key: const Key('navigation-menu-cashfree-payment'),
                      selected: _selectedIndex == 11,
                      selectedTileColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            const Color(0xFF00897B).withValues(alpha: .12),
                        child: const Icon(
                          Icons.payments_outlined,
                          color: Color(0xFF00897B),
                          size: 20,
                        ),
                      ),
                      title: const Text('Make a payment'),
                      onTap: () {
                        _selectPage(11);
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  key: const Key('navigation-menu-support'),
                  selected: _selectedIndex == _supportPageIndex,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        const Color(0xFF3458D4).withValues(alpha: .12),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: Color(0xFF3458D4),
                      size: 20,
                    ),
                  ),
                  title: const Text('Support'),
                  onTap: () {
                    _selectPage(_supportPageIndex);
                    Navigator.of(context).pop();
                  },
                ),
              ),
              ListTile(
                key: const Key('open-theme-mode'),
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Appearance'),
                subtitle: Text(_themeModeLabel(widget.themeMode)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _selectThemeMode,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: ListTile(
                  key: const Key('navigation-menu-logout'),
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  textColor: Theme.of(context).colorScheme.error,
                  iconColor: Theme.of(context).colorScheme.error,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: _logout,
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var index = 0; index < _titles.length; index++)
            if (_visitedPages.contains(index))
              pages[index]
            else
              const SizedBox(),
        ],
      ),
      bottomNavigationBar: _bottomNavigationItems.length > 1
          ? NavigationBar(
              selectedIndex: _selectedBottomNavigationIndex,
              onDestinationSelected: _onBottomNavigationSelected,
              destinations: [
                for (final item in _bottomNavigationItems)
                  NavigationDestination(
                    key: ValueKey(
                      'bottom-navigation-${item.label.toLowerCase()}',
                    ),
                    icon: Icon(item.icon, color: item.color),
                    selectedIcon: Icon(item.selectedIcon, color: item.color),
                    label: item.label,
                    tooltip: item.label == 'Pay' ? 'Payment..' : null,
                  ),
              ],
            )
          : null,
    );
  }
}
