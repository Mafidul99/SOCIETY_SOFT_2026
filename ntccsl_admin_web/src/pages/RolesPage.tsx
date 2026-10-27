import { useCallback, useEffect, useState } from 'react';
import { mutate, request } from '../api';
import { PERMISSION_KEYS, type Session } from '../types';
import { PageHeading, PortalLoader, StatePanel } from '../components/ui';

export function RolesPage({ session, onNotice }: { session: Session; onNotice: (message: string) => void }) {
  const [permissions, setPermissions] = useState<Record<string, Record<string, boolean>> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [savingPermission, setSavingPermission] = useState(false);
  const groups: [string, string[]][] = [
    ['Shared data', ['shared_data_read']],
    ['Bank ledger', ['ledger_view', 'ledger_add', 'ledger_edit', 'ledger_delete', 'ledger_update']],
    ['Deposit accounts', ['deposit_view', 'deposit_add', 'deposit_edit', 'deposit_delete', 'deposit_update']],
    ['Loans', ['loan_view', 'loan_add', 'loan_edit', 'loan_delete', 'loan_update']],
    ['User accounts', ['user_view', 'user_add', 'user_edit', 'user_delete', 'user_update']],
  ];
  const load = useCallback(async () => {
    setLoading(true); setError('');
    try {
      const result = await request<{ status?: string; permissions?: Record<string, Record<string, boolean>> }>('getRolePermissions', {}, session);
      if (!result.permissions) throw new Error('The server returned incomplete role permissions.');
      setPermissions(result.permissions);
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Could not load permissions.'); }
    finally { setLoading(false); }
  }, [session]);
  useEffect(() => { void load(); }, [load]);

  const change = async (role: string, key: string, enabled: boolean) => {
    if (!permissions || savingPermission) return;
    const before = permissions;
    const next = { ...permissions, [role]: { ...permissions[role], [key]: enabled } };
    setSavingPermission(true);
    setPermissions(next);
    try {
      await mutate('setRolePermissions', session, { permissions: next });
      onNotice(`${role} access saved.`);
    } catch (cause) {
      setPermissions(before);
      onNotice(cause instanceof Error ? cause.message : 'The permission could not be saved.');
    } finally { setSavingPermission(false); }
  };

  return <>
    <PageHeading title="Roles & permissions" subtitle="Grant Collector and Member accounts only the actions they need." />
    {savingPermission && <div className="save-progress" role="status"><PortalLoader label="Saving permissions" inline size={17} />Saving role permissions…</div>}
    <StatePanel loading={loading} error={error} retry={() => void load()}>
      {!permissions ? null : <div className="permissions-layout">
        {groups.map(([group, keys]) => <section className="panel permission-panel" key={group}>
          <h2>{group}</h2>
          {keys.map((key) => <div className="permission-row" key={key}>
            <span>{key === 'shared_data_read' ? 'View shared data' : key.split('_').slice(1).map((part) => part[0].toUpperCase() + part.slice(1)).join(' ')}</span>
            <div className="permission-switches">{(['Collector', 'Member'] as const).map((role) => (
              <label key={role}><span>{role}</span><input type="checkbox" disabled={savingPermission} checked={permissions[role]?.[key] === true}
                onChange={(event) => void change(role, key, event.target.checked)} /></label>
            ))}</div>
          </div>)}
        </section>)}
        <section className="notice-card"><strong>Access is enforced by the server</strong><span>Changes are saved immediately. Admin accounts retain full access; Members remain read-only.</span><small>{PERMISSION_KEYS.length} permission flags are available.</small></section>
      </div>}
    </StatePanel>
  </>;
}
