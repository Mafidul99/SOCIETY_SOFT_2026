import { type PermissionKey, type Session } from './types';

export const money = (value: unknown) =>
  new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 })
    .format(Number(value) || 0);

export const text = (value: unknown) => (value === null || value === undefined ? '' : String(value));

export const dateToday = () => new Date().toISOString().slice(0, 10);

export const normalize = (value: unknown) => text(value).trim().toLowerCase();

export function allows(session: Session, permission: PermissionKey | string) {
  if (session.user.role === 'Admin' || session.permissions[permission]) return true;
  const legacy: Record<string, string> = {
    ledger_view: 'shared_data_read',
    user_view: 'shared_data_read',
    ledger_add: 'ledger_manage',
    ledger_edit: 'ledger_manage',
    ledger_delete: 'ledger_manage',
    ledger_update: 'ledger_manage',
    deposit_add: 'deposit_manage',
    deposit_edit: 'deposit_manage',
    deposit_delete: 'deposit_manage',
    deposit_update: 'deposit_manage',
    loan_edit: 'loan_manage',
    loan_delete: 'loan_manage',
    loan_update: 'loan_manage',
    user_add: 'user_manage',
    user_edit: 'user_manage',
    user_delete: 'user_manage',
  };
  return Boolean(legacy[permission] && session.permissions[legacy[permission]]);
}

export const hasLedgerAccess = (session: Session) =>
  ['shared_data_read', 'ledger_view', 'ledger_add', 'ledger_edit', 'ledger_delete', 'ledger_update']
    .some((permission) => allows(session, permission));
export const hasDepositAccess = (session: Session) =>
  ['deposit_view', 'deposit_add', 'deposit_edit', 'deposit_delete', 'deposit_update']
    .some((permission) => allows(session, permission));
export const hasLoanAccess = (session: Session) =>
  ['loan_view', 'loan_add', 'loan_edit', 'loan_delete', 'loan_update', 'loan_manage']
    .some((permission) => allows(session, permission));
export const hasUserAccess = (session: Session) =>
  ['shared_data_read', 'user_view', 'user_add', 'user_edit', 'user_delete']
    .some((permission) => allows(session, permission));

export type Field = {
  name: string;
  label: string;
  type?: 'text' | 'email' | 'password' | 'number' | 'date' | 'select' | 'checkbox' | 'tel';
  required?: boolean;
  options?: { value: string; label: string }[];
  min?: number;
  max?: number;
  step?: string;
  placeholder?: string;
  readOnly?: boolean;
};
