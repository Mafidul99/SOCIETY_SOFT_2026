// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/portal_loading.dart';
import '../widgets/portal_widgets.dart';

class RolesPermissionsPage extends StatefulWidget {
  const RolesPermissionsPage({
    super.key,
    required this.apiService,
    required this.session,
  });

  final ApiService apiService;
  final AuthSession session;

  @override
  State<RolesPermissionsPage> createState() => _RolesPermissionsPageState();
}

class _RolesPermissionsPageState extends State<RolesPermissionsPage> {
  static const _permissionModules = [
    (
      key: 'shared',
      title: 'Shared data',
      subtitle: 'Read shared data available to this role.',
      actions: [
        (label: 'View', key: 'shared_data_read', hint: 'View shared data.'),
      ],
    ),
    (
      key: 'ledger',
      title: 'Bank ledger',
      subtitle: 'Control ledger records and balances.',
      actions: [
        (label: 'View', key: 'ledger_view', hint: 'View ledger entries.'),
        (label: 'Add', key: 'ledger_add', hint: 'Create ledger entries.'),
        (label: 'Edit', key: 'ledger_edit', hint: 'Edit entry details.'),
        (label: 'Delete', key: 'ledger_delete', hint: 'Delete entries.'),
        (
          label: 'Update',
          key: 'ledger_update',
          hint: 'Update amounts and balances.',
        ),
      ],
    ),
    (
      key: 'deposits',
      title: 'Deposit accounts',
      subtitle: 'Control FD, RD, and DRD accounts and installment payments.',
      actions: [
        (label: 'View', key: 'deposit_view', hint: 'View deposit accounts.'),
        (label: 'Add', key: 'deposit_add', hint: 'Create deposit accounts.'),
        (label: 'Edit', key: 'deposit_edit', hint: 'Edit account details.'),
        (label: 'Delete', key: 'deposit_delete', hint: 'Delete accounts.'),
        (
          label: 'Update',
          key: 'deposit_update',
          hint: 'Mark installments paid or unpaid.',
        ),
      ],
    ),
    (
      key: 'loans',
      title: 'Loans',
      subtitle:
          'Configure Collector loan records and approval actions; Members can apply.',
      actions: [
        (label: 'View', key: 'loan_view', hint: 'View permitted loan records.'),
        (
          label: 'Add',
          key: 'loan_add',
          hint: 'Create a loan record; Members submit applications.',
        ),
        (
          label: 'Edit',
          key: 'loan_edit',
          hint: 'Edit loan records.',
        ),
        (
          label: 'Delete',
          key: 'loan_delete',
          hint: 'Delete loan records.',
        ),
        (
          label: 'Update',
          key: 'loan_update',
          hint: 'Approve or reject pending loans.',
        ),
      ],
    ),
    (
      key: 'users',
      title: 'User accounts',
      subtitle:
          'Manage account records. Role and status changes stay Admin-only.',
      actions: [
        (label: 'View', key: 'user_view', hint: 'View user accounts.'),
        (label: 'Add', key: 'user_add', hint: 'Create user accounts.'),
        (label: 'Edit', key: 'user_edit', hint: 'Edit account details.'),
        (label: 'Delete', key: 'user_delete', hint: 'Delete user accounts.'),
        (
          label: 'Update',
          key: 'user_update',
          hint: 'Admin-only role and account access changes.',
        ),
      ],
    ),
  ];

  static const _adminOnlyPermissions = {
    'user_update',
  };
  static const _memberEditablePermissions = {
    'shared_data_read',
    'deposit_view',
    'loan_view',
    'loan_add',
  };

  late Future<Map<String, Map<String, bool>>> _future;
  Map<String, Map<String, bool>>? _permissions;
  bool _saving = false;

  bool get _isAdmin => widget.session.role.toLowerCase() == 'admin';

  bool _isPermissionEditableForRole(String role, String key) =>
      !_adminOnlyPermissions.contains(key) &&
      (role == 'Collector' || _memberEditablePermissions.contains(key));

  bool _canChangePermission(String role, String key) =>
      !_saving && _isPermissionEditableForRole(role, key);

  @override
  void initState() {
    super.initState();
    _future = _isAdmin ? _loadPermissions() : Future.value({});
  }

  Future<Map<String, Map<String, bool>>> _loadPermissions() async {
    final data = await widget.apiService.fetchRolePermissions(widget.session);
    return data;
  }

  Future<void> _reload() async {
    if (!_isAdmin) return;
    setState(() {
      _permissions = null;
      _future = _loadPermissions();
    });
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _setPermission(String role, String key, bool enabled) async {
    final permissions = _permissions;
    if (!_isAdmin || _saving || permissions == null) return;
    final previousValue = permissions[role]![key] ?? false;
    if (previousValue == enabled) return;
    final updated = {
      for (final entry in permissions.entries)
        entry.key: Map<String, bool>.from(entry.value),
    };
    updated[role]![key] = enabled;
    setState(() {
      permissions[role]![key] = enabled;
      _saving = true;
    });
    try {
      await widget.apiService.saveRolePermissions(updated, widget.session);
      if (!mounted) return;
      showPortalToast(
        context,
        '$role permission updated. Users should sign in again to refresh access.',
      );
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => permissions[role]![key] = previousValue);
        showPortalToast(context, error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => permissions[role]![key] = previousValue);
        showPortalToast(
          context,
          'Failed to update $role permission: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      final colors = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings_outlined,
                size: 48,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                'Admin access required',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Only Admins can view or change role permissions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return PortalGradientBackground(
      child: FutureBuilder<Map<String, Map<String, bool>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const PortalLoadingState(
              label: 'Loading permissions',
            );
          }
          if (snapshot.hasError) {
            return PortalErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          if (_permissions == null && snapshot.hasData) {
            _permissions = snapshot.data;
          }
          final permissions = _permissions;
          if (permissions == null) {
            return PortalErrorState(
              message: 'No permission data available.',
              onRetry: _reload,
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              children: [
                const PortalPageHeader(
                  title: 'Roles & Permissions',
                  subtitle:
                      'Open a permission group, then switch each action on or off.',
                  icon: Icons.admin_panel_settings_rounded,
                ),
                const SizedBox(height: 8),
                _AdminInfoCard(theme: theme),
                for (final role in ['Collector', 'Member']) ...[
                  const SizedBox(height: 20),
                  _RoleHeader(
                    role: role,
                    enabledCount: _permissionModules
                        .expand((module) => module.actions)
                        .where((action) =>
                            _isPermissionEditableForRole(role, action.key) &&
                            permissions[role]![action.key] == true)
                        .length,
                    totalCount: _permissionModules
                        .expand((module) => module.actions)
                        .where((action) =>
                            _isPermissionEditableForRole(role, action.key))
                        .length,
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  for (final module in _permissionModules)
                    Card(
                      key: Key(
                        'permission-group-${role.toLowerCase()}-${module.key}',
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        key: Key(
                          'permission-dropdown-${role.toLowerCase()}-${module.key}',
                        ),
                        title: Text(
                          module.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(module.subtitle),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          for (final action in module.actions)
                            _PermissionCard(
                              role: role,
                              permissionKey: action.key,
                              title: role == 'Collector' &&
                                      action.key == 'loan_view'
                                  ? 'Enable Loans section'
                                  : action.label,
                              subtitle: role == 'Collector' &&
                                      action.key == 'loan_view'
                                  ? 'Turn Collector access to the Loans section on or off.'
                                  : _adminOnlyPermissions.contains(action.key)
                                      ? '${action.hint} This remains Admin-only.'
                                      : role == 'Member' &&
                                              [
                                                'loan_edit',
                                                'loan_delete',
                                                'loan_update',
                                              ].contains(action.key)
                                          ? '${action.hint} This remains Admin-only.'
                                          : action.hint,
                              value:
                                  _adminOnlyPermissions.contains(action.key) ||
                                          (role == 'Member' &&
                                              [
                                                'loan_edit',
                                                'loan_delete',
                                                'loan_update',
                                              ].contains(action.key))
                                      ? false
                                      : permissions[role]![action.key] ?? false,
                              enabled: _canChangePermission(role, action.key),
                              onChanged: (enabled) =>
                                  _setPermission(role, action.key, enabled),
                              theme: theme,
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AdminInfoCard extends StatelessWidget {
  const _AdminInfoCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.verified_user_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin access is always enabled',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only Admins can change permissions or assign account roles. Edit, Delete, and Update access includes visibility of records needed for those actions; Add alone does not show existing records.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleHeader extends StatelessWidget {
  const _RoleHeader({
    required this.role,
    required this.enabledCount,
    required this.totalCount,
    required this.theme,
  });

  final String role;
  final int enabledCount;
  final int totalCount;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final isCollector = role == 'Collector';
    final roleColor = portalRoleColor(role);
    return Row(
      children: [
        Icon(
          isCollector ? Icons.engineering_rounded : Icons.person_rounded,
          size: 20,
          color: roleColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          key: Key('role-permission-color-${role.toLowerCase()}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: roleColor.withValues(alpha: .12),
            border: Border.all(color: roleColor.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$enabledCount / $totalCount',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: roleColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.role,
    required this.permissionKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.theme,
  });

  final String role;
  final String permissionKey;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final roleColor = portalRoleColor(role);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: value
              ? roleColor.withValues(alpha: .38)
              : theme.dividerColor.withOpacity(0.4),
        ),
      ),
      color: value ? roleColor.withValues(alpha: .035) : theme.cardColor,
      child: SwitchListTile.adaptive(
        key: Key('permission-${role.toLowerCase()}-$permissionKey'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ),
        value: value,
        activeTrackColor: roleColor,
        activeThumbColor: theme.colorScheme.onPrimary,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
