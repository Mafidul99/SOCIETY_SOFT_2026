export type Role = 'Admin' | 'Collector' | 'Member';

export type Session = {
  token: string;
  user: {
    id: string;
    accountNo: string;
    name: string;
    email: string;
    phoneNumber: string;
    role: Role;
    profileImageUrl?: string;
  };
  permissions: Record<string, boolean>;
  reportAccess: Record<string, boolean>;
};

export type RecordRow = Record<string, unknown>;

export type DepositRoute = {
  page: string;
  title: string;
  product: 'FD' | 'RD' | 'DRD';
  cadence: 'daily' | 'weekly' | 'monthly';
};

export const DEPOSIT_ROUTES: DepositRoute[] = [
  { page: 'fd-monthly', title: 'FD · Monthly', product: 'FD', cadence: 'monthly' },
  { page: 'rd-weekly', title: 'RD · Weekly', product: 'RD', cadence: 'weekly' },
  { page: 'rd-monthly', title: 'RD · Monthly', product: 'RD', cadence: 'monthly' },
  { page: 'drd-daily', title: 'DRD · Daily', product: 'DRD', cadence: 'daily' },
  { page: 'drd-weekly', title: 'DRD · Weekly', product: 'DRD', cadence: 'weekly' },
  { page: 'drd-monthly', title: 'DRD · Monthly', product: 'DRD', cadence: 'monthly' },
];

export const PERMISSION_KEYS = [
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
] as const;

export type PermissionKey = (typeof PERMISSION_KEYS)[number];

export type LoanPayment = {
  periodIndex: number;
  dueDate: string;
  installmentAmount: number;
  principalAmount?: number;
  interestAmount?: number;
  paid: boolean;
  status?: string;
};
