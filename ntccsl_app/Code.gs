const CONFIG = Object.freeze({
  sessionTtlSeconds: 21600,
  loginAttemptsBeforeLock: 5,
  loginLockSeconds: 900,
  maxNameLength: 120,
  maxEmailLength: 254,
  maxPasswordLength: 256,
  maxProfileImageBytes: 307200,
});

const PORTAL_ROLES = Object.freeze(['Admin', 'Collector', 'Member']);
const ROLE_PERMISSION_KEYS = Object.freeze([
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
]);

const SHEETS = Object.freeze({
  Users: [
    'id',
    'accountNo',
    'name',
    'profileImageUrl',
    'profileImageFileId',
    'email',
    'phoneNumber',
    'role',
    'passwordSalt',
    'passwordHash',
    'active',
    'dailyAccess',
    'weeklyAccess',
    'monthlyAccess',
    'createdAt',
  ],
  Role_Permissions: ['role', ...ROLE_PERMISSION_KEYS],
  Bank_ladger: [
    'date',
    'byWhom',
    'remarks',
    'deposit',
    'withdrawal',
    'balance',
    'payMode',
    'entryBy',
  ],
  Deposit_Accounts: [
    'id',
    'memberName',
    'product',
    'cadence',
    'startDate',
    'amount',
    'annualRate',
    'tenureMonths',
    'maturityDate',
    'maturityAmount',
    'payment_count',
    'paid_count',
    'createdAt',
    'createdBy',
  ],
  Loan_Master: [
    'id',
    'loanNumber',
    'schemeId',
    'schemeName',
    'memberName',
    'loanType',
    'startDate',
    'principal',
    'annualRate',
    'tenureYears',
    'totalInterest',
    'totalPayable',
    'monthlyInstallment',
    'repaymentMethod',
    'paymentSchedule',
    'approvalStatus',
    'reviewedAt',
    'reviewedBy',
    'fileChargePercent',
    'processingFeePercent',
    'fileCharge',
    'processingFee',
    'disbursedAmount',
    'createdAt',
    'createdBy',
  ],
  Loan_Schemes: [
    'schemeId',
    'schemeName',
    'minAmount',
    'maxAmount',
    'loanType',
    'minAnnualRate',
    'maxAnnualRate',
    'minTenureYears',
    'maxTenureYears',
    'calculationMethod',
    'active',
    'fileChargePercent',
    'processingFeePercent',
  ],
  Payment_Transactions: [
    'orderId',
    'userId',
    'memberName',
    'customerName',
    'customerEmail',
    'customerPhone',
    'createdBy',
    'baseAmount',
    'serviceCharge',
    'totalAmount',
    'status',
    'createdAt',
    'updatedAt',
    'scheduleProcessed',
    'scheduleApplied',
    'scheduleDescription',
    'scheduleProcessing',
    'scheduleTarget',
  ],
});

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('NTCCSL Portal')
    .addItem('Set up portal sheets', 'setupAccountPortal')
    .addItem('Update deposit payment columns', 'migrateDepositPaymentRows')
    .addItem('Create first admin', 'createInitialAdmin')
    .addItem('Reset admin password', 'resetAdminPassword')
    .addToUi();
}

function onEdit(event) {
  if (!event || !event.range) return;
  const sheet = event.range.getSheet();
  if (
    ['Loan_Master', 'Approved_Loans'].includes(sheet.getName()) &&
    event.range.getRow() >= 2
  ) {
    syncApprovedLoans_();
    return;
  }
  if (
    sheet.getName() !== 'Deposit_Accounts' ||
    event.range.getRow() < 2 ||
    event.range.getNumRows() !== 1 ||
    event.range.getNumColumns() !== 1
  ) {
    return;
  }
  const headers = getHeaders_(sheet);
  const editedHeader = headers[event.range.getColumn() - 1] || '';
  if (!/^P\d+$/.test(editedHeader)) return;

  const rowIndex = event.range.getRow();
  const record = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const dates = depositPeriodDates_(
    formatDate_(record.startDate),
    formatDate_(record.maturityDate),
    String(record.cadence || '').toLowerCase(),
  );
  const periodIndex = Number(editedHeader.slice(1));
  if (periodIndex > dates.length) {
    throw new Error(`Deposit ${record.id} has no installment ${periodIndex}.`);
  }
  const value = event.range.getValue();
  if (typeof value !== 'boolean') {
    throw new Error('Installment cells must contain TRUE or FALSE.');
  }
  const payments = depositPaymentsFromRecord_(record, dates.length);
  payments[periodIndex - 1] = value;
  writeDepositPaymentColumns_(sheet, rowIndex, headers, payments);
  writeDepositPaymentCounts_(sheet, rowIndex, headers, payments);
}

function setupAccountPortal() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) {
    throw new Error('Open this script from the Google Sheet before running setup.');
  }
  const properties = PropertiesService.getScriptProperties();
  properties.setProperty('SPREADSHEET_ID', spreadsheet.getId());
  if (!properties.getProperty('PASSWORD_PEPPER')) {
    properties.setProperty(
      'PASSWORD_PEPPER',
      `${Utilities.getUuid()}${Utilities.getUuid()}${Utilities.getUuid()}`,
    );
  }
  migrateLegacyWorkbook_(spreadsheet);
  migrateAmountSheetName_(spreadsheet);
  deleteRemovedCollectionSheets_(spreadsheet);
  Object.keys(SHEETS).forEach((name) => {
    const sheet = spreadsheet.getSheetByName(name) || spreadsheet.insertSheet(name);
    ensureHeaders_(sheet, SHEETS[name]);
    sheet.setFrozenRows(1);
  });
  migrateLegacyDepositPayments_(spreadsheet);
  ensureDefaultLoanSchemes_(spreadsheet);
  ensureApprovedLoansSheet_(spreadsheet);
  migrateLoanSchemeLinks_(spreadsheet);
  migrateLoanDisbursementAmounts_(spreadsheet);
  migrateLoanApprovalStatuses_(spreadsheet);
  migrateLoanPaymentSchedules_(spreadsheet);
  syncApprovedLoans_();
  initializeRolePermissionsSheet_();
  backfillAccountNumbers_();
  getOrCreateProfileImagesFolder_();
  spreadsheet.toast('Portal sheets are ready.', 'NTCCSL Portal', 5);
}

function migrateDepositPaymentRows() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) {
    throw new Error(
      'Open this script from the Google Sheet before migrating deposit payments.',
    );
  }
  if (!spreadsheet.getSheetByName('Deposit_Accounts')) {
    throw new Error('Deposit_Accounts sheet is missing.');
  }
  PropertiesService.getScriptProperties().setProperty(
    'SPREADSHEET_ID',
    spreadsheet.getId(),
  );
  const accountsSheet = spreadsheet.getSheetByName('Deposit_Accounts');
  ensureHeaders_(accountsSheet, SHEETS.Deposit_Accounts);
  migrateLegacyDepositPayments_(spreadsheet);
  spreadsheet.toast(
    'Deposit payment TRUE/FALSE columns are ready.',
    'NTCCSL Portal',
    5,
  );
}

function createInitialAdmin() {
  const ui = SpreadsheetApp.getUi();
  const users = getSpreadsheet_().getSheetByName('Users');
  if (!users) {
    throw new Error('Run setupAccountPortal before creating the first admin.');
  }
  if (users.getLastRow() > 1) {
    throw new Error('The Users sheet is not empty. Use an existing admin account.');
  }
  const emailResponse = ui.prompt(
    'Create first admin',
    'Enter the admin email address:',
    ui.ButtonSet.OK_CANCEL,
  );
  if (emailResponse.getSelectedButton() !== ui.Button.OK) return;
  const nameResponse = ui.prompt(
    'Create first admin',
    'Enter the admin display name:',
    ui.ButtonSet.OK_CANCEL,
  );
  if (nameResponse.getSelectedButton() !== ui.Button.OK) return;
  const passwordResponse = ui.prompt(
    'Create first admin',
    'Enter a strong password (at least 12 characters):',
    ui.ButtonSet.OK_CANCEL,
  );
  if (passwordResponse.getSelectedButton() !== ui.Button.OK) return;
  const email = normalizeEmail_(emailResponse.getResponseText());
  const name = cleanText_(nameResponse.getResponseText(), CONFIG.maxNameLength);
  const password = passwordResponse.getResponseText();
  validateRegistration_(name, email, password, 12);
  createUser_({ name, email, password, role: 'Admin' });
  ui.alert('Admin account created. Sign in using the email and password.');
}

function resetAdminPassword() {
  const ui = SpreadsheetApp.getUi();
  const emailResponse = ui.prompt(
    'Reset admin password',
    'Enter the email address of an existing active admin:',
    ui.ButtonSet.OK_CANCEL,
  );
  if (emailResponse.getSelectedButton() !== ui.Button.OK) return;

  const user = findUserByEmail_(normalizeEmail_(emailResponse.getResponseText()));
  if (!user || user.role !== 'Admin' || !isActive_(user.active)) {
    throw new Error('No active admin account was found for that email.');
  }

  const passwordResponse = ui.prompt(
    'Reset admin password',
    'Enter a new password (at least 12 characters):',
    ui.ButtonSet.OK_CANCEL,
  );
  if (passwordResponse.getSelectedButton() !== ui.Button.OK) return;

  const password = passwordResponse.getResponseText();
  validatePassword_(password, 12);
  withScriptLock_(() => setUserPassword_(user.id, password));
  ui.alert('Admin password reset. Sign in using the new password.');
}

function setUserPassword_(userId, password) {
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User account was not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const salt = Utilities.getUuid();
  setField_(sheet, row, headers, 'passwordSalt', salt);
  setField_(
    sheet,
    row,
    headers,
    'passwordHash',
    passwordHash_(password, salt, getPasswordPepper_()),
  );
}

function migrateLegacyWorkbook_(spreadsheet) {
  ['Amount', 'Anount'].forEach((sheetName) => {
    const source = spreadsheet.getSheetByName(sheetName);
    if (!source || !isLegacyAmountSheet_(source)) return;
    const records = readLegacyAmountRecords_(source);
    archiveLegacySheet_(source);
    const target =
      spreadsheet.getSheetByName('Bank_ladger') ||
      spreadsheet.insertSheet('Bank_ladger');
    ensureHeaders_(target, SHEETS.Bank_ladger);
    appendRecords_(target, SHEETS.Bank_ladger, records);
  });
}

function migrateAmountSheetName_(spreadsheet) {
  const oldSheet = spreadsheet.getSheetByName('Amount');
  if (!oldSheet) return;
  const newSheet = spreadsheet.getSheetByName('Bank_ladger');
  if (!newSheet) {
    oldSheet.setName('Bank_ladger');
    return;
  }
  const oldHasData = oldSheet.getLastRow() > 1;
  const newHasData = newSheet.getLastRow() > 1;
  if (oldHasData && newHasData) {
    throw new Error(
      'Both Amount and Bank_ladger contain data. Merge the ledger rows, then run setupAccountPortal again.',
    );
  }
  if (oldHasData) {
    const oldHeaders = getHeaders_(oldSheet);
    ensureHeaders_(newSheet, SHEETS.Bank_ladger);
    const records = readRecords_('Amount');
    ensureHeaders_(newSheet, oldHeaders);
    appendRecords_(newSheet, getHeaders_(newSheet), records);
  }
  spreadsheet.deleteSheet(oldSheet);
}

function deleteRemovedCollectionSheets_(spreadsheet) {
  ['Daily_Collection', 'Weekly_Collection', 'Monthly_Collection'].forEach(
    (sheetName) => {
      const sheet = spreadsheet.getSheetByName(sheetName);
      if (sheet) spreadsheet.deleteSheet(sheet);
    },
  );
}

function isLegacyAmountSheet_(sheet) {
  const headers = getSheetHeaderValues_(sheet).map(normalizeHeaderKey_);
  return (
    legacyHeaderIndex_(headers, ['by whom']) >= 0 &&
    legacyHeaderIndex_(headers, ['withdrawal', 'withdrawl']) >= 0 &&
    legacyHeaderIndex_(headers, ['pay mode', 'payment mode']) >= 0
  );
}

function readLegacyAmountRecords_(sheet) {
  const headers = getSheetHeaderValues_(sheet);
  const fields = {
    date: ['date'],
    byWhom: ['by whom'],
    remarks: ['remarks'],
    deposit: ['deposit'],
    withdrawal: ['withdrawal', 'withdrawl'],
    balance: ['balance'],
    payMode: ['pay mode', 'payment mode'],
    entryBy: ['entry by'],
  };
  const columns = {};
  Object.keys(fields).forEach((field) => {
    columns[field] = legacyHeaderIndex_(headers, fields[field]);
  });
  ['date', 'deposit', 'withdrawal', 'payMode'].forEach((field) => {
    if (columns[field] < 0) {
      throw new Error(`Cannot import the legacy ledger: missing ${field} column.`);
    }
  });

  if (sheet.getLastRow() < 2) return [];
  return sheet
    .getRange(2, 1, sheet.getLastRow() - 1, sheet.getLastColumn())
    .getValues()
    .reduce((records, row) => {
      const hasEntry = [
        'date',
        'byWhom',
        'remarks',
        'deposit',
        'withdrawal',
        'payMode',
        'entryBy',
      ].some((field) => columns[field] >= 0 && row[columns[field]] !== '');
      if (!hasEntry) return records;
      const record = {};
      Object.keys(columns).forEach((field) => {
        if (columns[field] >= 0) record[field] = row[columns[field]];
      });
      records.push(record);
      return records;
    }, []);
}

function getSheetHeaderValues_(sheet) {
  if (sheet.getLastColumn() < 1) return [];
  return sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
}

function normalizeHeaderKey_(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function legacyHeaderIndex_(headers, aliases) {
  const normalizedAliases = aliases.map(normalizeHeaderKey_);
  return headers.findIndex((header) =>
    normalizedAliases.includes(normalizeHeaderKey_(header)),
  );
}

function archiveLegacySheet_(sheet) {
  const spreadsheet = sheet.getParent();
  const baseName = `${sheet.getName()}`;
  let archiveName = baseName;
  let suffix = 2;
  while (spreadsheet.getSheetByName(archiveName)) {
    archiveName = `${baseName}_${suffix}`;
    suffix += 1;
  }
  sheet.setName(archiveName);
}

function appendRecords_(sheet, headers, records) {
  if (records.length === 0) return;
  const firstRow = sheet.getLastRow() + 1;
  const rows = records.map((record) =>
    headers.map((header) =>
      Object.prototype.hasOwnProperty.call(record, header)
        ? safeCellValue_(record[header])
        : '',
    ),
  );
  sheet.getRange(firstRow, 1, rows.length, headers.length).setValues(rows);
}

function doGet(event) {
  if (event && event.parameter && event.parameter.panel === '1') {
    return HtmlService.createHtmlOutputFromFile('Admin')
      .setTitle('NTCCSL Admin Portal')
      .addMetaTag('viewport', 'width=device-width, initial-scale=1');
  }
  return jsonOutput_({
    status: 'success',
    service: 'NTCCSL Account Portal',
    message: 'Send application actions as JSON POST requests.',
  });
}

function adminApi(request) {
  try {
    if (!request || typeof request !== 'object' || Array.isArray(request)) {
      throw new Error('Request body must be a JSON object.');
    }
    if (String(request.action || '') === 'login') {
      const result = login_(
        Object.assign({}, request, {
          loginType: String(request.loginType || 'staff'),
        }),
      );
      return { status: 'success', data: result };
    }
    if (String(request.action || '') === 'register') {
      return { status: 'success', data: register_(request) };
    }
    requireRole_(request.token, PORTAL_ROLES);
    return { status: 'success', data: dispatch_(request) };
  } catch (error) {
    console.error(error && error.stack ? error.stack : String(error));
    return { status: 'error', message: safeErrorMessage_(error) };
  }
}

function doPost(event) {
  try {
    if (!event || !event.postData || !event.postData.contents) {
      throw new Error('Expected a JSON request body.');
    }
    const request = JSON.parse(event.postData.contents);
    if (!request || typeof request !== 'object' || Array.isArray(request)) {
      throw new Error('Request body must be a JSON object.');
    }
    return jsonOutput_(dispatch_(request));
  } catch (error) {
    console.error(error && error.stack ? error.stack : String(error));
    return jsonOutput_({ status: 'error', message: safeErrorMessage_(error) });
  }
}

function dispatch_(request) {
  const action = String(request.action || '');
  switch (action) {
    case 'login':
      return login_(request);
    case 'register':
      return register_(request);
    case 'getAmount':
      {
        const user = requireRole_(request.token, PORTAL_ROLES);
        const permissions = permissionsForUser_(user);
        if (!permissions.shared_data_read && !permissions.ledger_view) {
          if (
            ![
              'ledger_add',
              'ledger_edit',
              'ledger_delete',
              'ledger_update',
            ].some((permission) => permissions[permission])
          ) {
            throw new Error('You do not have permission to view ledger data.');
          }
          return [];
        }
        return readAmount_();
      }
    case 'getDepositAccounts': {
      const { product, cadence } = validateDepositProductCadence_(
        request.product,
        request.cadence,
      );
      const user = requireRole_(request.token, PORTAL_ROLES);
      const permissions = permissionsForUser_(user);
      if (
        !permissions.deposit_view &&
        ![
          'deposit_add',
          'deposit_edit',
          'deposit_delete',
          'deposit_update',
        ].some((permission) => permissions[permission])
      ) {
        requireDepositRead_(request.token, cadence);
      }
      requireMemberDepositCadence_(user, cadence);
      if (!permissions.deposit_view && user.role !== 'Admin') return [];
      const selectedMember = paymentReadMember_(request, user);
      return readDepositAccounts_(
        product,
        cadence,
        user,
        selectedMember ? selectedMember.id : '',
      );
    }
    case 'getLoans': {
      const user = requireLoanRead_(request.token);
      const selectedMember = paymentReadMember_(request, user);
      return readLoans_(
        request.loanType,
        user,
        request.approvedOnly === true,
        selectedMember,
      );
    }
    case 'getLoanPaymentSchedule': {
      const user = requireLoanRead_(request.token);
      return withScriptLock_(() => readLoanPaymentSchedule_(request.id, user));
    }
    case 'getLoanSchemes':
      {
        const user = requireLoanRead_(request.token);
        return readLoanSchemes_(
          request.loanType,
          user,
          request.includeInactive === true,
        );
      }
    case 'createCashfreeOrder': {
      const user = requireRole_(request.token, ['Admin', 'Collector', 'Member']);
      if (user.role !== 'Member') {
        requireAnyPermission_(request.token, ['shared_data_read', 'user_view']);
      }
      return createCashfreeOrder_(request, user);
    }
    case 'verifyCashfreePayment': {
      const user = requireRole_(request.token, ['Admin', 'Collector', 'Member']);
      return verifyCashfreePayment_(request, user);
    }
    case 'getUsers':
      {
        const user = requireRole_(request.token, PORTAL_ROLES);
        const permissions = permissionsForUser_(user);
        if (!permissions.user_view && !permissions.shared_data_read) {
          if (
            !['user_add', 'user_edit', 'user_delete'].some(
              (permission) => permissions[permission],
            )
          ) {
            throw new Error('You do not have permission to view user accounts.');
          }
          return [];
        }
      }
      return readUsers_();
    case 'getPaymentMembers': {
      const user = requireRole_(request.token, ['Admin', 'Collector']);
      requireAnyPermission_(request.token, ['shared_data_read', 'user_view']);
      return readPaymentMembers_();
    }
    case 'getMemberPaymentData': {
      const user = requireRole_(request.token, PORTAL_ROLES);
      return readMemberPaymentData_(request, user);
    }
    case 'addAmount':
      requirePermission_(request.token, 'ledger_add');
      return withScriptLock_(() => addAmount_(request));
    case 'editAmount': {
      requireLedgerEditAccess_(request);
      return withScriptLock_(() => editAmount_(request));
    }
    case 'deleteAmount':
      requirePermission_(request.token, 'ledger_delete');
      return withScriptLock_(() => deleteAmount_(request));
    case 'addDepositAccount': {
      const user = requirePermission_(request.token, 'deposit_add');
      return withScriptLock_(() => addDepositAccount_(request, user));
    }
    case 'editDepositAccount':
      requirePermission_(request.token, 'deposit_edit');
      return withScriptLock_(() => editDepositAccount_(request));
    case 'toggleDepositPayment':
      {
        const user = requirePermission_(request.token, 'deposit_update');
        return withScriptLock_(() => toggleDepositPayment_(request, user));
      }
    case 'deleteDepositAccount':
      requirePermission_(request.token, 'deposit_delete');
      return withScriptLock_(() => deleteDepositAccount_(request));
    case 'addLoan':
      {
        const user = requireRole_(request.token, PORTAL_ROLES);
        requirePermission_(request.token, 'loan_add');
        return withScriptLock_(() => addLoan_(request, user));
      }
    case 'editLoan':
      requirePermission_(request.token, 'loan_edit');
      return withScriptLock_(() => editLoan_(request));
    case 'deleteLoan':
      requirePermission_(request.token, 'loan_delete');
      return withScriptLock_(() => deleteLoan_(request));
    case 'approveLoan':
      {
        const user = requirePermission_(request.token, 'loan_update');
        return withScriptLock_(() => approveLoan_(request, user));
      }
    case 'toggleLoanPayment':
      {
        const user = requirePermission_(request.token, 'loan_update');
        return withScriptLock_(() => toggleLoanPayment_(request, user));
      }
    case 'addLoanScheme':
      requireRole_(request.token, ['Admin']);
      return withScriptLock_(() => addLoanScheme_(request));
    case 'editLoanScheme':
      requireRole_(request.token, ['Admin']);
      return withScriptLock_(() => editLoanScheme_(request));
    case 'deleteLoanScheme':
      requireRole_(request.token, ['Admin']);
      return withScriptLock_(() => deleteLoanScheme_(request));
    case 'addUser':
      {
        const user = requirePermission_(request.token, 'user_add');
        return withScriptLock_(() => addUser_(request, user));
      }
    case 'editUser':
      {
        const user = requirePermission_(request.token, 'user_edit');
        return withScriptLock_(() => editUser_(request, user));
      }
    case 'deleteUser':
      {
        const user = requirePermission_(request.token, 'user_delete');
        return withScriptLock_(() => deleteUser_(request, user));
      }
    case 'updateMyProfile': {
      const user = requireRole_(request.token, ['Admin', 'Collector', 'Member']);
      return withScriptLock_(() => updateMyProfile_(request, user));
    }
    case 'getRolePermissions':
      requireRole_(request.token, ['Admin']);
      return { status: 'success', permissions: rolePermissions_() };
    case 'setRolePermissions':
      requireRole_(request.token, ['Admin']);
      return withScriptLock_(() => setRolePermissions_(request.permissions));
    case 'changePassword': {
      const user = requireRole_(request.token, ['Admin', 'Collector', 'Member']);
      return withScriptLock_(() => changePassword_(request, user));
    }
    default:
      throw new Error(`Unknown post action: ${action || '(missing)'}`);
  }
}

function createCashfreeOrder_(request, user) {
  const member = paymentMember_(request, user);
  const baseAmount = parsePaymentAmount_(request.baseAmount);
  const scheduleTarget = findOldestUnpaidSchedule_(
    member.name,
    baseAmount,
    request.scheduleTarget,
  );
  if (!scheduleTarget) {
    throw new Error(
      request.scheduleTarget
        ? 'This installment is already paid or its amount has changed. Refresh the schedule and retry.'
        : 'No unpaid payment schedule installment matches this amount. Enter an installment amount that is currently unpaid.',
    );
  }
  const serviceCharge = Math.round(baseAmount * 2) / 100;
  const totalAmount = Math.round((baseAmount + serviceCharge) * 100) / 100;
  const phone = String(request.customerPhone || '').replace(/\D/g, '');
  const customerName = String(
    request.customerName === undefined
      ? member.name || ''
      : request.customerName || '',
  ).trim();
  const customerEmail = String(
    request.customerEmail === undefined
      ? member.email || ''
      : request.customerEmail || '',
  ).trim();
  if (!/^\d{10}$/.test(phone)) {
    throw new Error('Enter a valid 10-digit mobile number.');
  }
  if (customerName.length > CONFIG.maxNameLength) {
    throw new Error('Customer name is too long.');
  }
  if (
    customerEmail &&
    (customerEmail.length > CONFIG.maxEmailLength ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail))
  ) {
    throw new Error('Enter a valid customer email address or leave it blank.');
  }
  if (!member.id) {
    throw new Error('The selected Member account is missing an account ID.');
  }
  const customerId = String(member.id);

  const properties = PropertiesService.getScriptProperties();
  const appId = properties.getProperty('CASHFREE_APP_ID');
  const secretKey = properties.getProperty('CASHFREE_SECRET_KEY');
  const environment =
    String(properties.getProperty('CASHFREE_ENVIRONMENT') || 'production')
      .trim()
      .toLowerCase();
  if (!appId || !secretKey) {
    throw new Error(
      'Cashfree is not configured. Ask an administrator to add the Cashfree credentials to Apps Script Script Properties.',
    );
  }
  if (environment !== 'sandbox' && environment !== 'production') {
    throw new Error('CASHFREE_ENVIRONMENT must be sandbox or production.');
  }

  const orderId =
    `NTC${Date.now()}${Utilities.getUuid().replace(/-/g, '').slice(0, 12)}`;
  const url =
    environment === 'production'
      ? 'https://api.cashfree.com/pg/orders'
      : 'https://sandbox.cashfree.com/pg/orders';
  const response = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'x-client-id': appId,
      'x-client-secret': secretKey,
      'x-api-version': '2025-01-01',
      accept: 'application/json',
    },
    payload: JSON.stringify({
      order_id: orderId,
      order_amount: totalAmount,
      order_currency: 'INR',
      customer_details: {
        customer_id: customerId,
        customer_phone: phone,
        ...(customerName ? { customer_name: customerName } : {}),
        ...(customerEmail ? { customer_email: customerEmail } : {}),
      },
      order_note: `Member payment ${member.id}; base ₹${baseAmount}; 2% fee ₹${serviceCharge}`,
    }),
    muteHttpExceptions: true,
  });
  const statusCode = response.getResponseCode();
  let cashfreeOrder;
  try {
    cashfreeOrder = JSON.parse(response.getContentText());
  } catch (error) {
    console.error('Cashfree returned invalid order data.');
    throw new Error('Cashfree returned an invalid order response.');
  }
  if (
    statusCode < 200 ||
    statusCode >= 300 ||
    !cashfreeOrder ||
    cashfreeOrder.order_id !== orderId ||
    typeof cashfreeOrder.payment_session_id !== 'string' ||
    !cashfreeOrder.payment_session_id
  ) {
    const errorCode = String(
      cashfreeOrder && (cashfreeOrder.code || cashfreeOrder.type) || '',
    )
      .replace(/[^a-zA-Z0-9_.-]/g, '')
      .slice(0, 64);
    const errorMessage = String(
      cashfreeOrder &&
        (cashfreeOrder.message || cashfreeOrder.error_description) ||
        '',
    )
      .replace(/[\u0000-\u001f\u007f]/g, ' ')
      .split(appId)
      .join('[redacted]')
      .split(secretKey)
      .join('[redacted]')
      .trim()
      .slice(0, 200);
    console.error(
      `Cashfree order creation failed (${statusCode})${errorCode ? ` ${errorCode}` : ''}.`,
    );
    if (statusCode === 401) {
      throw new Error(
        `Cashfree rejected the API credentials for ${environment} (HTTP 401). ` +
          `Use the matching ${environment} App ID and Secret Key in Apps Script Script Properties.`,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw new Error(
        `Cashfree rejected the order (HTTP ${statusCode}` +
          `${errorCode ? `, ${errorCode}` : ''})` +
          `${errorMessage ? `: ${errorMessage}` : '. Check the order details and Cashfree configuration.'}`,
      );
    }
    throw new Error(
      'Cashfree did not return a valid payment session for the created order.',
    );
  }

  const now = new Date();
  const sheet = getSpreadsheet_().getSheetByName('Payment_Transactions');
  if (!sheet) {
    throw new Error(
      'Payment_Transactions sheet is missing. Run setupAccountPortal.',
    );
  }
  ensureHeaders_(sheet, SHEETS.Payment_Transactions);
  appendRecord_(sheet, getHeaders_(sheet), {
    orderId,
    userId: String(member.id),
    memberName: String(member.name || ''),
    customerName,
    customerEmail,
    customerPhone: phone,
    createdBy: String(user.id),
    baseAmount,
    serviceCharge,
    totalAmount,
    status: 'PENDING',
    createdAt: now,
    updatedAt: now,
    scheduleProcessed: false,
    scheduleApplied: false,
    scheduleDescription: '',
    scheduleProcessing: false,
    scheduleTarget: JSON.stringify(scheduleTarget),
  });
  return {
    status: 'success',
    orderId,
    paymentSessionId: cashfreeOrder.payment_session_id,
    environment,
  };
}

function paymentReadMember_(request, authenticatedUser) {
  const memberId = String(request.memberId || '').trim();
  if (!memberId) return null;
  if (authenticatedUser.role !== 'Member') {
    requireAnyPermission_(request.token, ['shared_data_read', 'user_view']);
    const member = findUserById_(memberId);
    if (!member || member.role !== 'Member' || !isActive_(member.active)) {
      throw new Error('Select an active Member account.');
    }
    return member;
  }
  if (String(authenticatedUser.id) !== memberId) {
    throw new Error('Members can only load their own payment schedules.');
  }
  return authenticatedUser;
}

function paymentMember_(request, authenticatedUser) {
  if (authenticatedUser.role === 'Member') return authenticatedUser;
  requireAnyPermission_(request.token, ['shared_data_read', 'user_view']);
  const memberId = requiredText_(request.memberId, 'Member');
  const member = findUserById_(memberId);
  if (!member || member.role !== 'Member' || !isActive_(member.active)) {
    throw new Error('Select an active Member account.');
  }
  return member;
}

function verifyCashfreePayment_(request, user) {
  const orderId = requiredText_(request.orderId, 'Order ID');
  const sheet = getSpreadsheet_().getSheetByName('Payment_Transactions');
  ensureHeaders_(sheet, SHEETS.Payment_Transactions);
  const headers = getHeaders_(sheet);
  const row = findPaymentTransactionRow_(sheet, headers, orderId);
  if (!row) throw new Error('Payment order was not found.');
  const transaction = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  if (
    String(transaction.userId) !== String(user.id) &&
    String(transaction.createdBy || '') !== String(user.id)
  ) {
    throw new Error('You do not have permission to verify this payment.');
  }

  const properties = PropertiesService.getScriptProperties();
  const appId = properties.getProperty('CASHFREE_APP_ID');
  const secretKey = properties.getProperty('CASHFREE_SECRET_KEY');
  const environment =
    String(properties.getProperty('CASHFREE_ENVIRONMENT') || 'production')
      .trim()
      .toLowerCase();
  if (!appId || !secretKey) {
    throw new Error('Cashfree is not configured. Contact an administrator.');
  }
  if (environment !== 'sandbox' && environment !== 'production') {
    throw new Error('CASHFREE_ENVIRONMENT must be sandbox or production.');
  }

  const baseUrl =
    environment === 'production'
      ? 'https://api.cashfree.com/pg/orders/'
      : 'https://sandbox.cashfree.com/pg/orders/';
  const response = UrlFetchApp.fetch(
    `${baseUrl}${encodeURIComponent(orderId)}`,
    {
      method: 'get',
      headers: {
        'x-client-id': appId,
        'x-client-secret': secretKey,
        'x-api-version': '2025-01-01',
        accept: 'application/json',
      },
      muteHttpExceptions: true,
    },
  );
  const statusCode = response.getResponseCode();
  let cashfreeOrder;
  try {
    cashfreeOrder = JSON.parse(response.getContentText());
  } catch (error) {
    console.error('Cashfree returned invalid verification data.');
    throw new Error('Cashfree returned an invalid verification response.');
  }
  if (statusCode < 200 || statusCode >= 300) {
    console.error(`Cashfree verification failed (${statusCode}).`);
    throw new Error('Could not verify the Cashfree payment. Try again.');
  }
  if (
    cashfreeOrder.order_id !== orderId ||
    Number(cashfreeOrder.order_amount) !== Number(transaction.totalAmount)
  ) {
    throw new Error('Cashfree order details do not match this payment.');
  }

  const orderStatus = String(cashfreeOrder.order_status || '').toUpperCase();
  if (orderStatus) {
    sheet.getRange(row, headers.indexOf('status') + 1).setValue(orderStatus);
    sheet.getRange(row, headers.indexOf('updatedAt') + 1).setValue(new Date());
  }
  const scheduleResult = orderStatus === 'PAID'
    ? processCashfreePaymentSchedule_(sheet, orderId)
    : {
        scheduleApplied: isPaid_(transaction.scheduleApplied),
        scheduleDescription: String(transaction.scheduleDescription || ''),
      };
  return {
    status: 'success',
    orderId,
    paymentStatus: orderStatus || 'PENDING',
    paid: orderStatus === 'PAID',
    scheduleApplied: scheduleResult.scheduleApplied,
    scheduleDescription: scheduleResult.scheduleDescription,
  };
}

function processCashfreePaymentSchedule_(paymentSheet, orderId) {
  return withScriptLock_(() => {
    const headers = getHeaders_(paymentSheet);
    const row = findPaymentTransactionRow_(paymentSheet, headers, orderId);
    if (!row) throw new Error('Payment order was not found.');
    let values = paymentSheet
      .getRange(row, 1, 1, headers.length)
      .getValues()[0];
    const transaction = rowToObject_(headers, values);
    if (isPaid_(transaction.scheduleProcessed)) {
      return {
        scheduleApplied: isPaid_(transaction.scheduleApplied),
        scheduleDescription: String(transaction.scheduleDescription || ''),
      };
    }

    let installment;
    if (
      isPaid_(transaction.scheduleProcessing) ||
      String(transaction.scheduleTarget || '').trim()
    ) {
      try {
        installment = JSON.parse(String(transaction.scheduleTarget || ''));
      } catch (error) {
        console.error(`Invalid schedule target for payment ${orderId}.`, error);
        throw new Error('The pending payment schedule update is invalid.');
      }
      if (installment && installment.kind === 'collection') {
        const scheduleDescription =
          'Collection schedules were removed and could not be updated for this payment. Contact an administrator to reconcile the schedule.';
        writePaymentScheduleResult_(
          paymentSheet,
          row,
          headers,
          values,
          {
            scheduleProcessed: true,
            scheduleApplied: false,
            scheduleDescription,
            scheduleProcessing: false,
            scheduleTarget: '',
          },
        );
        return { scheduleApplied: false, scheduleDescription };
      }
      if (
        !installment ||
        !['deposit', 'loan'].includes(installment.kind) ||
        !Number.isInteger(installment.periodIndex)
      ) {
        throw new Error('The pending payment schedule update is invalid.');
      }
    } else {
      installment = findOldestUnpaidSchedule_(
        transaction.memberName,
        transaction.baseAmount,
      );
    }

    if (!installment) {
      const scheduleDescription =
        'No unpaid installment matching this payment amount was available when payment was verified. Contact an administrator to reconcile the schedule.';
      writePaymentScheduleResult_(
        paymentSheet,
        row,
        headers,
        values,
        {
          scheduleProcessed: true,
          scheduleApplied: false,
          scheduleDescription,
          scheduleProcessing: false,
          scheduleTarget: '',
        },
      );
      return { scheduleApplied: false, scheduleDescription };
    }

    if (
      String(transaction.scheduleTarget || '').trim() &&
      !isPaid_(transaction.scheduleProcessing)
    ) {
      const availableInstallment = findOldestUnpaidSchedule_(
        transaction.memberName,
        transaction.baseAmount,
        installment,
      );
      if (!availableInstallment) {
        const scheduleDescription =
          'The selected installment is no longer unpaid or available. Contact an administrator to reconcile the payment.';
        writePaymentScheduleResult_(
          paymentSheet,
          row,
          headers,
          values,
          {
            scheduleProcessed: true,
            scheduleApplied: false,
            scheduleDescription,
            scheduleProcessing: false,
            scheduleTarget: JSON.stringify(installment),
          },
        );
        return { scheduleApplied: false, scheduleDescription };
      }
      installment = availableInstallment;
    }

    if (!isPaid_(transaction.scheduleProcessing)) {
      values = writePaymentScheduleResult_(
        paymentSheet,
        row,
        headers,
        values,
        {
          scheduleProcessed: false,
          scheduleApplied: false,
          scheduleDescription: 'Updating the matching payment schedule.',
          scheduleProcessing: true,
          scheduleTarget: JSON.stringify(installment),
        },
      );
    }

    const scheduleDescription = applyScheduleInstallment_(
      installment,
      transaction.orderId,
    );
    writePaymentScheduleResult_(
      paymentSheet,
      row,
      headers,
      values,
      {
        scheduleProcessed: true,
        scheduleApplied: true,
        scheduleDescription,
        scheduleProcessing: false,
        scheduleTarget: JSON.stringify(installment),
      },
    );
    return { scheduleApplied: true, scheduleDescription };
  });
}

function writePaymentScheduleResult_(
  sheet,
  row,
  headers,
  currentValues,
  result,
) {
  const values = currentValues.slice();
  Object.keys(result).forEach((field) => {
    const column = headers.indexOf(field);
    if (column < 0) throw new Error(`Missing sheet column: ${field}`);
    values[column] = safeCellValue_(result[field]);
  });
  const updatedAtColumn = headers.indexOf('updatedAt');
  if (updatedAtColumn >= 0) values[updatedAtColumn] = new Date();
  sheet.getRange(row, 1, 1, headers.length).setValues([values]);
  return values;
}

function findOldestUnpaidSchedule_(memberName, amount, requestedTarget) {
  const normalizedName = normalizeMemberName_(memberName);
  const amountCents = Math.round(Number(amount) * 100);
  if (!normalizedName || !Number.isFinite(amountCents)) return null;
  if (requestedTarget != null) {
    const validTarget =
      requestedTarget &&
      typeof requestedTarget === 'object' &&
      !Array.isArray(requestedTarget) &&
      Number.isInteger(Number(requestedTarget.periodIndex)) &&
      Number(requestedTarget.periodIndex) > 0 &&
      ['deposit', 'loan'].includes(requestedTarget.kind) &&
      String(requestedTarget.id || '').trim();
    if (!validTarget) throw new Error('Invalid payment schedule installment.');
  }

  const candidates = [];
  if (!requestedTarget || requestedTarget.kind === 'deposit') {
    readRecords_('Deposit_Accounts').forEach((record) => {
      if (
        normalizeMemberName_(record.memberName) !== normalizedName ||
        Math.round(Number(record.amount) * 100) !== amountCents ||
        !['RD', 'DRD'].includes(String(record.product || '').toUpperCase())
      ) {
        return;
      }
      const product = validDepositProduct_(record.product);
      const cadence = validDepositCadence_(record.cadence);
      if (!DEPOSIT_CADENCES[product].includes(cadence)) {
        throw new Error('A deposit account has an invalid payment frequency.');
      }
      const periodDates = depositPeriodDates_(
        formatDate_(record.startDate),
        formatDate_(record.maturityDate),
        cadence,
      );
      const payments = depositPaymentsFromRecord_(record, periodDates.length);
      payments.forEach((paid, index) => {
        if (paid) return;
        candidates.push({
          kind: 'deposit',
          id: String(record.id || ''),
          memberName: String(record.memberName || ''),
          amountCents,
          product,
          cadence,
          periodIndex: index + 1,
          dueDate: periodDates[index],
          description:
            `${product} ${cadence} installment ${index + 1} ` +
            `(${periodDates[index]})`,
        });
      });
    });
  }

  if (requestedTarget && requestedTarget.kind === 'loan') {
    readRecords_('Loan_Master').forEach((record) => {
      if (
        String(record.id || '') !== String(requestedTarget.id) ||
        normalizeMemberName_(record.memberName) !== normalizedName ||
        String(record.approvalStatus || '').trim().toLowerCase() !==
          'approved'
      ) {
        return;
      }
      const schedule =
        loanPaymentScheduleFromRecord_(record) ||
        generateLoanPaymentSchedule_(record);
      const index = Number(requestedTarget.periodIndex) - 1;
      if (index < 0 || index >= schedule.length) return;
      const payment = schedule[index];
      const installmentCents = Math.round(
        Number(payment.installmentAmount) * 100,
      );
      if (
        payment.paid ||
        !Number.isFinite(installmentCents) ||
        installmentCents !== amountCents
      ) {
        return;
      }
      const loanType = String(record.loanType || 'Loan').trim();
      candidates.push({
        kind: 'loan',
        id: String(record.id || ''),
        memberName: String(record.memberName || ''),
        amountCents: installmentCents,
        periodIndex: Number(payment.periodIndex),
        dueDate: String(payment.dueDate),
        description:
          `${loanType} loan installment ${payment.periodIndex} ` +
          `(${payment.dueDate})`,
      });
    });
  }

  candidates.sort(
    (left, right) =>
      left.dueDate.localeCompare(right.dueDate) ||
      left.description.localeCompare(right.description),
  );
  if (requestedTarget != null) {
    return candidates.find(
      (candidate) =>
        candidate.id === String(requestedTarget.id) &&
        candidate.periodIndex === Number(requestedTarget.periodIndex),
    ) || null;
  }
  return candidates[0] || null;
}

function applyScheduleInstallment_(installment, orderId) {
  if (installment.kind === 'loan') {
    const sheet = getSpreadsheet_().getSheetByName('Loan_Master');
    if (!sheet) throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
    const rowIndex = loanRow_(installment.id, sheet);
    if (!rowIndex) throw new Error('The selected loan schedule no longer exists.');
    const headers = getHeaders_(sheet);
    const loan = rowToObject_(
      headers,
      sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
    );
    if (
      String(loan.approvalStatus || '').trim().toLowerCase() !== 'approved' ||
      normalizeMemberName_(loan.memberName) !==
        normalizeMemberName_(installment.memberName)
    ) {
      throw new Error('The selected loan schedule is no longer available.');
    }
    const schedule =
      loanPaymentScheduleFromRecord_(loan) ||
      generateLoanPaymentSchedule_(loan);
    const index = installment.periodIndex - 1;
    const payment = schedule[index];
    if (
      !payment ||
      Number(payment.periodIndex) !== installment.periodIndex ||
      payment.paid ||
      Math.round(Number(payment.installmentAmount) * 100) !==
        installment.amountCents
    ) {
      throw new Error('The selected loan installment is no longer available.');
    }
    const now = new Date().toISOString();
    payment.paid = true;
    payment.status = 'Paid';
    payment.paidAt = now;
    payment.updatedAt = now;
    payment.updatedBy = 'Cashfree';
    setField_(sheet, rowIndex, headers, 'paymentSchedule', JSON.stringify(schedule));
    syncApprovedLoans_();
    return installment.description;
  }
  if (installment.kind !== 'deposit') {
    throw new Error('The selected payment schedule is no longer supported.');
  }
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  const rowIndex = depositAccountRow_(installment.id, sheet);
  if (!rowIndex) throw new Error('The selected deposit schedule no longer exists.');
  const headers = getHeaders_(sheet);
  const row = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const periodDates = depositPeriodDates_(
    formatDate_(row.startDate),
    formatDate_(row.maturityDate),
    String(row.cadence).toLowerCase(),
  );
  const payments = depositPaymentsFromRecord_(row, periodDates.length);
  const index = installment.periodIndex - 1;
  if (
    String(row.memberName || '') !== installment.memberName ||
    Math.round(Number(row.amount) * 100) !== installment.amountCents ||
    String(row.product || '').toUpperCase() !== installment.product ||
    String(row.cadence || '').toLowerCase() !== installment.cadence ||
    !Array.isArray(payments) ||
    index < 0 ||
    index >= payments.length
  ) {
    throw new Error('The selected deposit installment is no longer available.');
  }
  if (typeof payments[index] !== 'boolean') {
    throw new Error('A deposit payment schedule is invalid. Contact an administrator.');
  }
  payments[index] = true;
  upsertDepositPaymentRow_({
    depositId: String(installment.id),
    periodIndex: installment.periodIndex,
    dueDate: periodDates[index],
    installmentAmount: Number(row.amount) || 0,
    paid: true,
    status: 'Paid',
    paidAt: new Date(),
    paymentMethod: 'Cashfree',
    transactionId: String(orderId || ''),
    updatedAt: new Date(),
    updatedBy: 'Cashfree',
  });
  return installment.description;
}

function parsePaymentAmount_(value) {
  const amountText = String(value == null ? '' : value).trim();
  if (!/^\d+(?:\.\d{1,2})?$/.test(amountText)) {
    throw new Error('Enter an amount with no more than 2 decimal places.');
  }
  const amount = Number(amountText);
  if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000) {
    throw new Error('Amount must be greater than ₹0 and no more than ₹10,00,000.');
  }
  return Math.round(amount * 100) / 100;
}

function findPaymentTransactionRow_(sheet, headers, orderId) {
  const orderIdColumn = headers.indexOf('orderId') + 1;
  if (orderIdColumn < 1 || sheet.getLastRow() < 2) return 0;
  const found = sheet
    .getRange(2, orderIdColumn, sheet.getLastRow() - 1, 1)
    .createTextFinder(orderId)
    .matchEntireCell(true)
    .findNext();
  return found ? found.getRow() : 0;
}

function register_(request) {
  return withScriptLock_(() => {
    const name = cleanText_(request.name, CONFIG.maxNameLength);
    const email = normalizeEmail_(request.email);
    const password = String(request.password || '');
    validateRegistration_(name, email, password, 8);
    assertUniqueMemberName_(name);
    if (findUserByEmail_(email)) {
      throw new Error('An account with this email already exists.');
    }
    createUser_({ name, email, password, role: 'Member' });
    return { status: 'success' };
  });
}

function login_(request) {
  const identifier = String(request.identifier || request.email || '').trim();
  const loginType = String(request.loginType || '');
  const password = String(request.password || '');
  if (!identifier || !password) {
    throw new Error('Enter your email or account number and password.');
  }
  const normalizedIdentifier = identifier.includes('@')
    ? normalizeEmail_(identifier)
    : identifier.toUpperCase();

  const cache = CacheService.getScriptCache();
  const attemptKey = `login:${sha256Hex_(normalizedIdentifier)}`;
  const attempts = Number(cache.get(attemptKey) || 0);
  if (attempts >= CONFIG.loginAttemptsBeforeLock) {
    throw new Error('Too many sign-in attempts. Try again in 15 minutes.');
  }

  const user =
    loginType === 'member' && !identifier.includes('@')
      ? findUserByAccountNumber_(normalizedIdentifier)
      : findUserByEmail_(normalizeEmail_(identifier));
  const candidate = passwordHash_(
    password,
    user ? user.passwordSalt : 'unknown-user-salt',
    getPasswordPepper_(),
  );
  if (
    !user ||
    !isActive_(user.active) ||
    !constantTimeEquals_(candidate, user.passwordHash)
  ) {
    cache.put(attemptKey, String(attempts + 1), CONFIG.loginLockSeconds);
    throw new Error('Invalid email or password.');
  }

  if (
    (loginType === 'member' && user.role !== 'Member') ||
    (loginType === 'staff' &&
      user.role !== 'Admin' &&
      user.role !== 'Collector') ||
    (loginType && loginType !== 'member' && loginType !== 'staff')
  ) {
    throw new Error(
      loginType === 'member'
        ? 'This login is for Member accounts. Choose Admin / Collector login instead.'
        : 'This login is for Admin and Collector accounts. Choose Member login instead.',
    );
  }

  cache.remove(attemptKey);
  const token = `${Utilities.getUuid()}${Utilities.getUuid()}`;
  cache.put(
    `session:${sha256Hex_(token)}`,
    JSON.stringify({ userId: user.id }),
    CONFIG.sessionTtlSeconds,
  );
  return {
    status: 'success',
    token,
    user: publicUser_(user),
    permissions: permissionsForUser_(user),
    reportAccess: reportAccessForUser_(user),
  };
}

function reportAccessForUser_(user) {
  return {
    daily: isReportAccessEnabled_(user.dailyAccess),
    weekly: isReportAccessEnabled_(user.weeklyAccess),
    monthly: isReportAccessEnabled_(user.monthlyAccess),
  };
}

function isReportAccessEnabled_(value) {
  if (value === '' || value === null || value === undefined) return true;
  return value === true || String(value).toLowerCase() === 'true';
}

function defaultRolePermissions_() {
  const allPermissions = Object.fromEntries(
    ROLE_PERMISSION_KEYS.map((key) => [key, true]),
  );
  return {
    Collector: normalizeRolePermissions_('Collector', {
      ...allPermissions,
      loan_add: false,
      loan_edit: false,
      loan_delete: false,
      loan_update: false,
      user_update: false,
    }),
    Member: memberRolePermissions_(),
  };
}

function memberRolePermissions_() {
  return normalizeRolePermissions_('Member', {
    ...Object.fromEntries(ROLE_PERMISSION_KEYS.map((key) => [key, false])),
    deposit_view: true,
    loan_add: true,
  });
}

function normalizeMemberRolePermissions_(permissions) {
  const normalized = Object.fromEntries(
    ROLE_PERMISSION_KEYS.map((key) => [key, permissions[key] === true]),
  );
  for (const key of [
    'ledger_view',
    'ledger_add',
    'ledger_edit',
    'ledger_delete',
    'ledger_update',
    'deposit_add',
    'deposit_edit',
    'deposit_delete',
    'deposit_update',
    'loan_edit',
    'loan_delete',
    'loan_update',
    'user_view',
    'user_add',
    'user_edit',
    'user_delete',
    'user_update',
  ]) {
    normalized[key] = false;
  }
  return applyLegacyPermissionAliases_(normalized);
}

function normalizeRolePermissions_(role, permissions) {
  if (role === 'Member') return normalizeMemberRolePermissions_(permissions);
  const normalized = Object.fromEntries(
    ROLE_PERMISSION_KEYS.map((key) => [key, permissions[key] === true]),
  );
  normalized.user_update = false;
  return applyLegacyPermissionAliases_(normalized);
}

function applyLegacyPermissionAliases_(permissions) {
  permissions.deposit_manage = [
    'deposit_add',
    'deposit_edit',
    'deposit_delete',
    'deposit_update',
  ].some((key) => permissions[key]);
  permissions.loan_manage = [
    'loan_edit',
    'loan_delete',
    'loan_update',
  ].some((key) => permissions[key]);
  permissions.ledger_manage = [
    'ledger_add',
    'ledger_edit',
    'ledger_delete',
    'ledger_update',
  ].some((key) => permissions[key]);
  permissions.user_manage = [
    'user_add',
    'user_edit',
    'user_delete',
  ].some((key) => permissions[key]);
  return permissions;
}

function legacyRolePermissionDefault_(role, key, permissions) {
  if (key === 'ledger_view') {
    return permissions.shared_data_read === true || permissions.ledger_manage === true;
  }
  if (key.startsWith('ledger_') && key !== 'ledger_view') {
    return permissions.ledger_manage === true;
  }
  if (key.startsWith('deposit_') && key !== 'deposit_view') {
    return role !== 'Member' && permissions.deposit_manage === true;
  }
  if (key === 'loan_add') return role === 'Member';
  if (['loan_edit', 'loan_delete', 'loan_update'].includes(key)) return false;
  if (key === 'user_view') {
    return permissions.shared_data_read === true || permissions.user_manage === true;
  }
  if (['user_add', 'user_edit', 'user_delete'].includes(key)) {
    return role !== 'Member' && permissions.user_manage === true;
  }
  if (key === 'user_update') return false;
  if (key === 'deposit_manage') {
    return role !== 'Member' && permissions.collection_manage === true;
  }
  if (key === 'deposit_view') {
    return (
      permissions.shared_data_read === true ||
      permissions.own_collection_read === true ||
      permissions.collection_manage === true
    );
  }
  if (key === 'loan_view') return role === 'Collector';
  if (key === 'loan_manage') return false;
  return undefined;
}

function rolePermissionFromRecord_(record, role, key) {
  const value = record[key];
  if (value === '' || value === null || value === undefined) {
    const legacyDefault = legacyRolePermissionDefault_(role, key, record);
    if (legacyDefault !== undefined) return legacyDefault;
  }
  return parseRolePermissionValue_(value, role, key);
}

function rolePermissions_() {
  initializeRolePermissionsSheet_();
  const records = readRecords_('Role_Permissions');
  const permissions = Object.fromEntries(
    ['Collector', 'Member'].map((role) => {
      const matchingRecords = records.filter(
        (record) => String(record.role).trim().toLowerCase() === role.toLowerCase(),
      );
      if (matchingRecords.length !== 1) {
        throw new Error(
          `The Role_Permissions sheet must contain one ${role} row. Run setupAccountPortal.`,
        );
      }
      const record = matchingRecords[0];
      return [
        role,
        Object.fromEntries(
          ROLE_PERMISSION_KEYS.map((key) => [
            key,
            rolePermissionFromRecord_(record, role, key),
          ]),
        ),
      ];
    }),
  );
  permissions.Collector = normalizeRolePermissions_(
    'Collector',
    permissions.Collector,
  );
  permissions.Member = normalizeRolePermissions_('Member', permissions.Member);
  return permissions;
}

function permissionsForUser_(user) {
  if (user.role === 'Admin') {
    return Object.fromEntries(ROLE_PERMISSION_KEYS.map((key) => [key, true]));
  }
  return rolePermissions_()[user.role] || {};
}

function setRolePermissions_(permissions) {
  if (!permissions || typeof permissions !== 'object' || Array.isArray(permissions)) {
    throw new Error('Provide permission settings for each role.');
  }
  const normalized = {};
  ['Collector', 'Member'].forEach((role) => {
    const roleSettings = permissions[role];
    if (!roleSettings || typeof roleSettings !== 'object' || Array.isArray(roleSettings)) {
      throw new Error(`Provide permission settings for ${role}.`);
    }
    normalized[role] = {};
    ROLE_PERMISSION_KEYS.forEach((key) => {
      if (typeof roleSettings[key] !== 'boolean') {
        throw new Error(`Permission ${key} for ${role} must be true or false.`);
      }
      normalized[role][key] = roleSettings[key];
    });
  });
  normalized.Collector = normalizeRolePermissions_(
    'Collector',
    normalized.Collector,
  );
  normalized.Member = normalizeRolePermissions_('Member', normalized.Member);
  const sheet = ensureRolePermissionsSheet_();
  const headers = getHeaders_(sheet);
  ['Collector', 'Member'].forEach((role) => {
    const rows = readRecords_('Role_Permissions').filter(
      (record) => String(record.role).trim().toLowerCase() === role.toLowerCase(),
    );
    if (rows.length > 1) {
      throw new Error(`The Role_Permissions sheet contains duplicate ${role} rows.`);
    }
    const values = headers.map((header) =>
      header === 'role' ? role : normalized[role][header] ?? '',
    );
    if (rows.length === 1) {
      sheet.getRange(rows[0].__rowIndex, 1, 1, headers.length).setValues([values]);
    } else {
      sheet.appendRow(values);
    }
  });
  PropertiesService.getScriptProperties().setProperty(
    'ROLE_PERMISSIONS',
    JSON.stringify(normalized),
  );
  return { status: 'success', permissions: normalized };
}

function initializeRolePermissionsSheet_() {
  const sheet = ensureRolePermissionsSheet_();
  const records = readRecords_('Role_Permissions');
  let storedPermissions;
  const headers = getHeaders_(sheet);
  ['Collector', 'Member'].forEach((role) => {
    const matchingRecords = records.filter(
      (record) => String(record.role).trim().toLowerCase() === role.toLowerCase(),
    );
    if (matchingRecords.length > 1) {
      throw new Error(`The Role_Permissions sheet contains duplicate ${role} rows.`);
    }
    let settings;
    if (matchingRecords.length === 1) {
      settings = Object.fromEntries(
        ROLE_PERMISSION_KEYS.map((key) => [
          key,
          rolePermissionFromRecord_(matchingRecords[0], role, key),
        ]),
      );
    } else {
      if (!storedPermissions) {
        storedPermissions = rolePermissionsFromProperties_();
      }
      settings = storedPermissions[role];
    }
    settings = normalizeRolePermissions_(role, settings);
    const values = headers.map((header) =>
      header === 'role' ? role : settings[header] ?? '',
    );
    if (matchingRecords.length === 1) {
      sheet
        .getRange(matchingRecords[0].__rowIndex, 1, 1, headers.length)
        .setValues([values]);
    } else {
      sheet.appendRow(values);
    }
  });
}

function ensureRolePermissionsSheet_() {
    const spreadsheet = getSpreadsheet_();
    const sheet =
      spreadsheet.getSheetByName('Role_Permissions') ||
      spreadsheet.insertSheet('Role_Permissions');
    ensureHeaders_(sheet, SHEETS.Role_Permissions);
    sheet.setFrozenRows(1);
    return sheet;
}

function rolePermissionsFromProperties_() {
  const stored = PropertiesService.getScriptProperties().getProperty(
    'ROLE_PERMISSIONS',
  );
  if (!stored) return defaultRolePermissions_();
  let parsed;
  try {
    parsed = JSON.parse(stored);
  } catch (error) {
    console.error(`Invalid ROLE_PERMISSIONS setting: ${error}`);
    throw new Error('Role permissions are invalid. Contact an administrator.');
  }
  const permissions = Object.fromEntries(
    ['Collector', 'Member'].map((role) => [
      role,
      Object.fromEntries(
        ROLE_PERMISSION_KEYS.map((key) => {
          const value = parsed && parsed[role] && parsed[role][key];
          if (
            (value === undefined || value === null) &&
            legacyRolePermissionDefault_(
              role,
              key,
              parsed && parsed[role] ? parsed[role] : {},
            ) !== undefined
          ) {
            return [
              key,
              legacyRolePermissionDefault_(
                role,
                key,
                parsed && parsed[role] ? parsed[role] : {},
              ),
            ];
          }
          if (typeof value !== 'boolean') {
            throw new Error(
              `Stored permission ${key} for ${role} must be true or false.`,
            );
          }
          return [key, value];
        }),
      ),
    ]),
  );
  permissions.Collector = normalizeRolePermissions_(
    'Collector',
    permissions.Collector,
  );
  permissions.Member = normalizeRolePermissions_('Member', permissions.Member);
  return permissions;
}

function parseRolePermissionValue_(value, role, key) {
  if (typeof value === 'boolean') return value;
  if (value === 'TRUE' || value === 'true') return true;
  if (value === 'FALSE' || value === 'false') return false;
  throw new Error(
    `Permission ${key} for ${role} in Role_Permissions must be true or false.`,
  );
}

function readUsers_() {
  return readRecords_('Users')
    .filter((user) => isActive_(user.active))
    .map(publicUser_);
}

function readPaymentMembers_() {
  return readRecords_('Users')
    .filter((user) => isActive_(user.active) && user.role === 'Member')
    .map((user) => ({
      id: String(user.id || ''),
      accountNo: String(user.accountNo || ''),
      name: String(user.name || ''),
      email: String(user.email || ''),
      phoneNumber: String(user.phoneNumber || ''),
      role: String(user.role || ''),
    }));
}

function readMemberPaymentData_(request, user) {
  const member =
    user.role === 'Member'
      ? paymentReadMember_({ memberId: user.id, token: request.token }, user)
      : paymentReadMember_(request, user);
  if (!member) throw new Error('Select an active Member account.');

  const permissions = permissionsForUser_(user);
  const canReadDeposits =
    user.role === 'Admin' ||
    permissions.deposit_view ||
    [
      'deposit_add',
      'deposit_edit',
      'deposit_delete',
      'deposit_update',
    ].some((permission) => permissions[permission]);
  const paymentDepositRoutes = [
    { product: 'FD', cadence: 'monthly' },
    { product: 'RD', cadence: 'weekly' },
    { product: 'RD', cadence: 'monthly' },
    { product: 'DRD', cadence: 'daily' },
    { product: 'DRD', cadence: 'weekly' },
    { product: 'DRD', cadence: 'monthly' },
  ].filter(
    (route) =>
      user.role === 'Member'
        ? permissions.deposit_view &&
          isReportAccessEnabled_(member[`${route.cadence}Access`])
        : canReadDeposits,
  );
  const canReadLoans =
    user.role === 'Admin' ||
    (user.role === 'Member' &&
      (permissions.loan_view || permissions.loan_add)) ||
    permissions.loan_view ||
    permissions.loan_edit ||
    permissions.loan_delete ||
    permissions.loan_update;
  const paymentOptions = [];

  if (paymentDepositRoutes.length > 0) {
    const normalizedMemberName = normalizeMemberName_(member.name);
    readRecords_('Deposit_Accounts')
      .filter(
        (account) =>
          normalizeMemberName_(account.memberName) === normalizedMemberName &&
          paymentDepositRoutes.some(
            (route) =>
              route.product ===
                String(account.product || '').trim().toUpperCase() &&
              route.cadence ===
                String(account.cadence || '').trim().toLowerCase(),
          ),
      )
      .forEach((account) => {
        const product = String(account.product || '').trim().toUpperCase();
        const cadence = String(account.cadence || '').trim().toLowerCase();
        if (
          !Object.prototype.hasOwnProperty.call(DEPOSIT_CADENCES, product) ||
          !DEPOSIT_CADENCES[product].includes(cadence)
        ) {
          return;
        }
        const dates =
          product === 'FD'
            ? []
            : depositPeriodDates_(
                formatDate_(account.startDate),
                formatDate_(account.maturityDate),
                cadence,
              );
        const payments = depositPaymentsFromRecord_(account, dates.length);
        payments.forEach((paid, index) => {
          if (paid) return;
          paymentOptions.push({
            kind: 'deposit',
            label: `${product} ${cadence} deposit`,
            amount: Number(account.amount) || 0,
            dueDate: dates[index] || `Installment ${index + 1}`,
            target: {
              kind: 'deposit',
              id: String(account.id || ''),
              periodIndex: index + 1,
            },
          });
        });
      });
  }

  if (canReadLoans) {
    const loans = readLoans_(null, user, true, member);
    const loanRecords = new Map(
      readRecords_('Loan_Master').map((loan) => [String(loan.id || ''), loan]),
    );
    loans.forEach((loan) => {
      const loanRecord = loanRecords.get(loan.id);
      if (!loanRecord) return;
      const schedule =
        loanPaymentScheduleFromRecord_(loanRecord) ||
        generateLoanPaymentSchedule_(loanRecord);
      schedule.forEach((payment) => {
        if (payment.paid) return;
        paymentOptions.push({
          kind: 'loan',
          label: `${loan.loanType} loan · ${loan.loanNumber || loan.memberName}`,
          amount: Number(payment.installmentAmount) || 0,
          dueDate: payment.dueDate,
          target: {
            kind: 'loan',
            id: loan.id,
            periodIndex: Number(payment.periodIndex),
          },
        });
      });
    });
  }

  paymentOptions.sort(
    (left, right) =>
      String(left.dueDate).localeCompare(String(right.dueDate)) ||
      String(left.label).localeCompare(String(right.label)),
  );
  return {
    member: {
      id: String(member.id || ''),
      name: String(member.name || ''),
      accountNo: String(member.accountNo || ''),
      email: String(member.email || ''),
      phoneNumber: String(member.phoneNumber || ''),
    },
    payments: paymentOptions,
    sources: {
      deposits: paymentDepositRoutes.length > 0,
      loans: canReadLoans,
    },
  };
}

function addUser_(request, authenticatedUser) {
  const name = cleanText_(request.name, CONFIG.maxNameLength);
  const email = normalizeEmail_(request.email);
  const phoneNumber =
    request.phoneNumber === undefined
      ? ''
      : normalizePhoneNumber_(request.phoneNumber);
  const password = String(request.password || '');
  const role =
    authenticatedUser.role === 'Admin'
      ? normalizeRole_(request.role)
      : 'Member';
  validateRegistration_(name, email, password, 8);
  if (role === 'Member') assertUniqueMemberName_(name);
  if (findUserByEmail_(email)) {
    throw new Error('An account with this email already exists.');
  }
  createUser_({
    name,
    profileImageData: request.profileImageData,
    profileImageMimeType: request.profileImageMimeType,
    email,
    phoneNumber,
    password,
    role,
    dailyAccess:
      role === 'Member' && authenticatedUser.role === 'Admin'
        ? requestedReportAccess_(request, 'dailyAccess')
        : true,
    weeklyAccess:
      role === 'Member' && authenticatedUser.role === 'Admin'
        ? requestedReportAccess_(request, 'weeklyAccess')
        : true,
    monthlyAccess:
      role === 'Member' && authenticatedUser.role === 'Admin'
        ? requestedReportAccess_(request, 'monthlyAccess')
        : true,
  });
  return { status: 'success' };
}

function editUser_(request, authenticatedUser) {
  const userId = requiredText_(request.userId, 'User ID');
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  const name = cleanText_(request.name, CONFIG.maxNameLength);
  const email = normalizeEmail_(request.email);
  const phoneNumber =
    request.phoneNumber === undefined
      ? String(user.phoneNumber || '')
      : normalizePhoneNumber_(request.phoneNumber);
  const role =
    authenticatedUser.role === 'Admin'
      ? normalizeRole_(request.role)
      : String(user.role || '');
  if (
    role !== user.role &&
    authenticatedUser.role !== 'Admin' &&
    !permissionsForUser_(authenticatedUser).user_update
  ) {
    throw new Error('You do not have permission to update user roles.');
  }
  if (authenticatedUser.role !== 'Admin' && user.role === 'Admin') {
    throw new Error('Only an administrator can manage admin accounts.');
  }
  validateNameAndEmail_(name, email);
  if (role === 'Member') assertUniqueMemberName_(name, userId);
  const duplicate = findUserByEmail_(email);
  if (duplicate && String(duplicate.id) !== userId) {
    throw new Error('An account with this email already exists.');
  }
  if (isActive_(user.active) && user.role === 'Admin' && role !== 'Admin') {
    assertAnotherActiveAdmin_(userId);
  }
  const imageChanged = request.profileImageChanged === true;
  let replacementImageFileId = String(user.profileImageFileId || '');
  if (imageChanged) {
    if (!request.profileImageData && request.profileImageMimeType !== undefined) {
      throw new Error('Profile image data is required when a MIME type is provided.');
    }
    replacementImageFileId = request.profileImageData
      ? saveProfileImage_(
          request.profileImageData,
          request.profileImageMimeType,
          userId,
        )
      : '';
  } else if (
    request.profileImageChanged !== undefined ||
    request.profileImageData !== undefined ||
    request.profileImageMimeType !== undefined
  ) {
    throw new Error('profileImageChanged must be true or omitted.');
  }
  const updatedUser = Object.assign({}, user, {
    name,
    email,
    phoneNumber,
    role,
    accountNo:
      role === user.role ? String(user.accountNo || '') : nextAccountNumber_(role),
    profileImageFileId: replacementImageFileId,
    profileImageUrl: imageChanged ? '' : String(user.profileImageUrl || ''),
  });
  if (authenticatedUser.role === 'Admin') {
    updatedUser.dailyAccess = reportAccessForEdit_(
      role,
      user,
      request,
      'dailyAccess',
    );
    updatedUser.weeklyAccess = reportAccessForEdit_(
      role,
      user,
      request,
      'weeklyAccess',
    );
    updatedUser.monthlyAccess = reportAccessForEdit_(
      role,
      user,
      request,
      'monthlyAccess',
    );
  }
  if (request.password !== undefined && String(request.password) !== '') {
    const password = String(request.password);
    validatePassword_(password, 8);
    const salt = Utilities.getUuid();
    updatedUser.passwordSalt = salt;
    updatedUser.passwordHash = passwordHash_(
      password,
      salt,
      getPasswordPepper_(),
    );
  }
  const updatedValues = headers.map((header) =>
    Object.prototype.hasOwnProperty.call(updatedUser, header)
      ? safeCellValue_(updatedUser[header])
      : '',
  );
  try {
    sheet.getRange(row, 1, 1, headers.length).setValues([updatedValues]);
  } catch (error) {
    if (imageChanged && replacementImageFileId) {
      trashProfileImage_(replacementImageFileId);
    }
    throw error;
  }
  if (
    imageChanged &&
    user.profileImageFileId &&
    user.profileImageFileId !== replacementImageFileId
  ) {
    trashProfileImage_(user.profileImageFileId);
  }
  return { status: 'success' };
}

function updateMyProfile_(request, authenticatedUser) {
  const userId = String(authenticatedUser.id);
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User account was not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  const name = cleanText_(request.name, CONFIG.maxNameLength);
  const email = normalizeEmail_(request.email);
  const phoneNumber =
    request.phoneNumber === undefined
      ? String(user.phoneNumber || '')
      : normalizePhoneNumber_(request.phoneNumber);
  validateNameAndEmail_(name, email);
  if (user.role === 'Member') {
    if (normalizeMemberName_(name) !== normalizeMemberName_(user.name)) {
      throw new Error('Contact an administrator to change your member name.');
    }
    assertUniqueMemberName_(name, userId);
  }
  const duplicate = findUserByEmail_(email);
  if (duplicate && String(duplicate.id) !== userId) {
    throw new Error('An account with this email already exists.');
  }

  const imageChanged = request.profileImageChanged === true;
  let replacementImageFileId = String(user.profileImageFileId || '');
  if (imageChanged) {
    if (!request.profileImageData && request.profileImageMimeType !== undefined) {
      throw new Error('Profile image data is required when a MIME type is provided.');
    }
    replacementImageFileId = request.profileImageData
      ? saveProfileImage_(
          request.profileImageData,
          request.profileImageMimeType,
          userId,
        )
      : '';
  } else if (
    request.profileImageChanged !== undefined ||
    request.profileImageData !== undefined ||
    request.profileImageMimeType !== undefined
  ) {
    throw new Error('profileImageChanged must be true or omitted.');
  }

  const updatedUser = Object.assign({}, user, { name, email, phoneNumber });
  if (imageChanged) {
    updatedUser.profileImageFileId = replacementImageFileId;
    updatedUser.profileImageUrl = '';
  }
  const updatedValues = headers.map((header) =>
    Object.prototype.hasOwnProperty.call(updatedUser, header)
      ? safeCellValue_(updatedUser[header])
      : '',
  );
  try {
    sheet.getRange(row, 1, 1, headers.length).setValues([updatedValues]);
  } catch (error) {
    if (imageChanged && replacementImageFileId) {
      trashProfileImage_(replacementImageFileId);
    }
    throw error;
  }
  if (
    imageChanged &&
    user.profileImageFileId &&
    user.profileImageFileId !== replacementImageFileId
  ) {
    trashProfileImage_(user.profileImageFileId);
  }
  return { status: 'success' };
}

function requestedReportAccess_(request, key) {
  const value = request[key];
  if (value === undefined) return true;
  if (typeof value !== 'boolean') {
    throw new Error(`${key} must be true or false.`);
  }
  return value;
}

function reportAccessForEdit_(role, user, request, key) {
  if (role !== 'Member') return true;
  if (request[key] === undefined) {
    return isReportAccessEnabled_(user[key]);
  }
  return requestedReportAccess_(request, key);
}

function deleteUser_(request, authenticatedUser) {
  const userId = requiredText_(request.userId, 'User ID');
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  if (authenticatedUser.role !== 'Admin' && user.role === 'Admin') {
    throw new Error('Only an administrator can manage admin accounts.');
  }
  if (isActive_(user.active) && user.role === 'Admin') {
    assertAnotherActiveAdmin_(userId);
  }
  sheet.deleteRow(row);
  return { status: 'success' };
}

function changePassword_(request, authenticatedUser) {
  const userId = String(authenticatedUser.id);
  const row = findUserRowById_(userId);
  if (!row) throw new Error('User account was not found.');
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const user = rowToObject_(
    headers,
    sheet.getRange(row, 1, 1, headers.length).getValues()[0],
  );
  const currentPassword = String(request.currentPassword || '');
  const newPassword = String(request.newPassword || '');
  if (!currentPassword || !newPassword) {
    throw new Error('Enter your current password and a new password.');
  }
  const pepper = getPasswordPepper_();
  const currentHash = passwordHash_(
    currentPassword,
    user.passwordSalt,
    pepper,
  );
  if (!constantTimeEquals_(currentHash, user.passwordHash)) {
    throw new Error('Current password is incorrect.');
  }
  validatePassword_(newPassword, 8);
  if (constantTimeEquals_(
    passwordHash_(newPassword, user.passwordSalt, pepper),
    user.passwordHash,
  )) {
    throw new Error('Choose a new password different from your current one.');
  }
  const salt = Utilities.getUuid();
  setField_(sheet, row, headers, 'passwordSalt', salt);
  setField_(
    sheet,
    row,
    headers,
    'passwordHash',
    passwordHash_(newPassword, salt, pepper),
  );
  return { status: 'success' };
}

function addAmount_(request) {
  const deposit = parseNonNegativeNumber_(request.deposit, 'Deposit');
  const withdrawal = parseNonNegativeNumber_(request.withdrawal, 'Withdrawal');
  if ((deposit > 0) === (withdrawal > 0)) {
    throw new Error('Enter either a deposit or a withdrawal, but not both.');
  }
  const sheet = getSpreadsheet_().getSheetByName('Bank_ladger');
  if (!sheet) throw new Error('Missing sheet: Bank_ladger. Run setupAccountPortal.');
  const headers = getHeaders_(sheet);
  const balanceColumn = headers.indexOf('balance') + 1;
  if (balanceColumn < 1) throw new Error('The bank ledger is missing its balance column.');
  const lastRow = sheet.getLastRow();
  const previousBalance =
    lastRow < 2
      ? 0
      : Number(sheet.getRange(lastRow, balanceColumn).getValue()) || 0;
  const balance = roundCurrency_(previousBalance + deposit - withdrawal);
  if (balance < 0) throw new Error('The resulting balance cannot be negative.');
  appendRecord_(sheet, headers, {
    date: request.date
      ? parseDateField_(request.date, 'Date')
      : formatDate_(new Date()),
    byWhom: cleanText_(request.byWhom, CONFIG.maxNameLength),
    remarks: cleanText_(request.remarks, 1000),
    deposit,
    withdrawal,
    balance,
    payMode: requiredText_(request.payMode, 'Payment mode'),
    entryBy: cleanText_(request.entryBy, CONFIG.maxNameLength),
  });
  return { status: 'success' };
}

function editAmount_(request) {
  const sheet = getSpreadsheet_().getSheetByName('Bank_ladger');
  if (!sheet) throw new Error('Missing sheet: Bank_ladger. Run setupAccountPortal.');
  const headers = getHeaders_(sheet);
  const balanceColumn = headers.indexOf('balance') + 1;
  if (balanceColumn < 1) throw new Error('The bank ledger is missing its balance column.');
  const rowIndex = Number(request.rowIndex);
  if (
    !Number.isInteger(rowIndex) ||
    rowIndex < 2 ||
    rowIndex > sheet.getLastRow()
  ) {
    throw new Error('Invalid ledger row.');
  }

  const deposit = parseNonNegativeNumber_(request.deposit, 'Deposit');
  const withdrawal = parseNonNegativeNumber_(request.withdrawal, 'Withdrawal');
  if ((deposit > 0) === (withdrawal > 0)) {
    throw new Error('Enter either a deposit or a withdrawal, but not both.');
  }
  const lastRow = sheet.getLastRow();
  const currentRows = sheet
    .getRange(rowIndex, 1, lastRow - rowIndex + 1, headers.length)
    .getValues();
  const current = rowToObject_(headers, currentRows[0]);
  const openingBalance =
    rowIndex > 2
      ? Number(sheet.getRange(rowIndex - 1, balanceColumn).getValue()) || 0
      : (Number(current.balance) || 0) -
        (Number(current.deposit) || 0) +
        (Number(current.withdrawal) || 0);
  let runningBalance = openingBalance;
  const updatedBalances = currentRows.map((values, index) => {
    const record = rowToObject_(headers, values);
    const rowDeposit = index === 0 ? deposit : Number(record.deposit) || 0;
    const rowWithdrawal = index === 0 ? withdrawal : Number(record.withdrawal) || 0;
    runningBalance = roundCurrency_(runningBalance + rowDeposit - rowWithdrawal);
    if (runningBalance < 0) {
      throw new Error('This change would make a later running balance negative.');
    }
    return [runningBalance];
  });
  const date = parseDateField_(request.date, 'Date');
  setField_(sheet, rowIndex, headers, 'date', date);
  setField_(sheet, rowIndex, headers, 'byWhom', cleanText_(request.byWhom, CONFIG.maxNameLength));
  setField_(sheet, rowIndex, headers, 'remarks', cleanText_(request.remarks, 1000));
  setField_(sheet, rowIndex, headers, 'deposit', deposit);
  setField_(sheet, rowIndex, headers, 'withdrawal', withdrawal);
  sheet.getRange(rowIndex, balanceColumn, updatedBalances.length, 1).setValues(updatedBalances);
  setField_(sheet, rowIndex, headers, 'payMode', requiredText_(request.payMode, 'Payment mode'));
  setField_(sheet, rowIndex, headers, 'entryBy', requiredText_(request.entryBy, 'Entry by'));
  return { status: 'success' };
}

function requireLedgerEditAccess_(request) {
  const user = requireRole_(request.token, PORTAL_ROLES);
  const sheet = getSpreadsheet_().getSheetByName('Bank_ladger');
  if (!sheet) throw new Error('Missing sheet: Bank_ladger. Run setupAccountPortal.');
  const rowIndex = Number(request.rowIndex);
  if (!Number.isInteger(rowIndex) || rowIndex < 2 || rowIndex > sheet.getLastRow()) {
    throw new Error('Invalid ledger row.');
  }
  const headers = getHeaders_(sheet);
  const current = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const changed = (key, normalize) =>
    normalize(request[key]) !== normalize(current[key]);
  const text = (value) => String(value ?? '').trim();
  const money = (value) =>
    value === '' || value === null || value === undefined
      ? ''
      : Number(value) || 0;
  const needsEdit = [
    'date',
    'byWhom',
    'remarks',
    'payMode',
    'entryBy',
  ].some((key) =>
    changed(key, key === 'date' ? (value) => formatDate_(value) : text),
  );
  const needsUpdate = ['deposit', 'withdrawal', 'balance'].some((key) =>
    changed(key, money),
  );
  requirePermission_(request.token, needsEdit || !needsUpdate ? 'ledger_edit' : 'ledger_update');
  if (needsEdit && needsUpdate) {
    requirePermission_(request.token, 'ledger_update');
  }
}

function deleteAmount_(request) {
  const sheet = getSpreadsheet_().getSheetByName('Bank_ladger');
  if (!sheet) throw new Error('Missing sheet: Bank_ladger. Run setupAccountPortal.');
  const headers = getHeaders_(sheet);
  const balanceColumn = headers.indexOf('balance') + 1;
  if (balanceColumn < 1) throw new Error('The bank ledger is missing its balance column.');
  const rowIndex = Number(request.rowIndex);
  if (
    !Number.isInteger(rowIndex) ||
    rowIndex < 2 ||
    rowIndex > sheet.getLastRow()
  ) {
    throw new Error('Invalid ledger row.');
  }
  const lastRow = sheet.getLastRow();
  const deleted = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const openingBalance =
    rowIndex > 2
      ? Number(sheet.getRange(rowIndex - 1, balanceColumn).getValue()) || 0
      : (Number(deleted.balance) || 0) -
        (Number(deleted.deposit) || 0) +
        (Number(deleted.withdrawal) || 0);
  let runningBalance = openingBalance;
  const remainingBalances =
    rowIndex < lastRow
      ? sheet
          .getRange(rowIndex + 1, 1, lastRow - rowIndex, headers.length)
          .getValues()
          .map((values) => {
            const record = rowToObject_(headers, values);
            runningBalance = roundCurrency_(
              runningBalance +
                (Number(record.deposit) || 0) -
                (Number(record.withdrawal) || 0),
            );
            if (runningBalance < 0) {
              throw new Error('This deletion would make a later running balance negative.');
            }
            return [runningBalance];
          })
      : [];
  sheet.deleteRow(rowIndex);
  if (remainingBalances.length > 0) {
    sheet
      .getRange(rowIndex, balanceColumn, remainingBalances.length, 1)
      .setValues(remainingBalances);
  }
  return { status: 'success' };
}

function parseDateField_(value, label) {
  const dateText = requiredText_(value, label);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateText)) {
    throw new Error(`${label} must use YYYY-MM-DD format.`);
  }
  const date = new Date(`${dateText}T00:00:00Z`);
  if (
    Number.isNaN(date.getTime()) ||
    Utilities.formatDate(date, 'UTC', 'yyyy-MM-dd') !== dateText
  ) {
    throw new Error(`Enter a valid ${label.toLowerCase()}.`);
  }
  return dateText;
}

function readAmount_() {
  return readRecords_('Bank_ladger').map((record) => ({
    ...record,
    date: formatDate_(record.date),
  }));
}

function ensureDefaultLoanSchemes_(spreadsheet) {
  const sheet =
    spreadsheet.getSheetByName('Loan_Schemes') ||
    spreadsheet.insertSheet('Loan_Schemes');
  ensureHeaders_(sheet, SHEETS.Loan_Schemes);
  sheet.setFrozenRows(1);
  const schemes = readRecords_('Loan_Schemes');
  const defaults = [
    {
      schemeId: 'personal-loan-standard',
      schemeName: 'Personal Loan Standard',
      loanType: 'personal',
    },
    {
      schemeId: 'gold-loan-standard',
      schemeName: 'Gold Loan Standard',
      loanType: 'gold',
    },
  ];
  defaults.forEach((scheme) => {
    const existing = schemes.find(
      (record) => String(record.schemeId || '') === scheme.schemeId,
    );
    const headers = getHeaders_(sheet);
    const defaultFields = {
      ...scheme,
      minAnnualRate: 18,
      maxAnnualRate: 37,
      minAmount: 1,
      maxAmount: 1000000000,
      minTenureYears: 1,
      maxTenureYears: 7,
      fileChargePercent: 0,
      processingFeePercent: 0,
      calculationMethod: 'flat',
      active: true,
    };
    if (!existing) {
      appendRecord_(sheet, headers, defaultFields);
      return;
    }
    Object.entries(defaultFields).forEach(([field, value]) => {
      if (
        existing[field] === '' ||
        existing[field] === null ||
        existing[field] === undefined
      ) {
        setField_(sheet, existing.__rowIndex, headers, field, value);
      }
    });
  });
}

function migrateLoanSchemeLinks_(spreadsheet) {
  const schemes = readRecords_('Loan_Schemes');
  ['Loan_Master', 'Approved_Loans'].forEach((sheetName) => {
    const loansSheet = spreadsheet.getSheetByName(sheetName);
    if (!loansSheet || loansSheet.getLastRow() < 2) return;
    const headers = getHeaders_(loansSheet);
    readRecords_(sheetName).forEach((record) => {
      const currentSchemeId = String(record.schemeId || '').trim();
      const loanType = String(record.loanType || '').trim().toLowerCase();
      const scheme =
        (currentSchemeId
          ? schemes.find(
              (candidate) =>
                String(candidate.schemeId || '') === currentSchemeId &&
                String(candidate.loanType || '').trim().toLowerCase() ===
                    loanType,
            )
          : null) ||
        schemes.find(
          (candidate) =>
            String(candidate.loanType || '').trim().toLowerCase() ===
              loanType &&
            isActive_(candidate.active),
        );
      if (
        currentSchemeId &&
        String(record.schemeName || '').trim() &&
        scheme
      ) {
        return;
      }
      if (!scheme) {
        throw new Error(
          `Loan ${record.id || record.__rowIndex} has no active ${loanType} loan scheme.`,
        );
      }
      setField_(
        loansSheet,
        record.__rowIndex,
        headers,
        'schemeId',
        scheme.schemeId,
      );
      setField_(
        loansSheet,
        record.__rowIndex,
        headers,
        'schemeName',
        scheme.schemeName,
      );
    });
  });
}

function migrateLoanApprovalStatuses_(spreadsheet) {
  ['Loan_Master', 'Approved_Loans'].forEach((sheetName) => {
    const sheet = spreadsheet.getSheetByName(sheetName);
    if (!sheet || sheet.getLastRow() < 2) return;
    const headers = getHeaders_(sheet);
    readRecords_(sheetName).forEach((record) => {
      if (!String(record.approvalStatus || '').trim()) {
        setField_(
          sheet,
          record.__rowIndex,
          headers,
          'approvalStatus',
          'Approved',
        );
      }
    });
  });
}

function migrateLoanDisbursementAmounts_(spreadsheet) {
  const schemes = readRecords_('Loan_Schemes');
  ['Loan_Master', 'Approved_Loans'].forEach((sheetName) => {
    const sheet = spreadsheet.getSheetByName(sheetName);
    if (!sheet || sheet.getLastRow() < 2) return;
    const headers = getHeaders_(sheet);
    readRecords_(sheetName).forEach((record) => {
      const scheme = schemes.find(
        (candidate) =>
          String(candidate.schemeId || '') === String(record.schemeId || ''),
      );
      if (!scheme) {
        throw new Error(
          `Loan ${record.id || record.__rowIndex} has no matching scheme for disbursement fees.`,
        );
      }
      const principal = Number(record.principal) || 0;
      const fileChargePercent = Number(scheme.fileChargePercent) || 0;
      const processingFeePercent = Number(scheme.processingFeePercent) || 0;
      const loanFileChargePercent = isBlankLoanValue_(record.fileChargePercent)
        ? fileChargePercent
        : Number(record.fileChargePercent) || 0;
      const loanProcessingFeePercent =
        isBlankLoanValue_(record.processingFeePercent)
          ? processingFeePercent
          : Number(record.processingFeePercent) || 0;
      if (
        loanFileChargePercent < 0 ||
        loanProcessingFeePercent < 0 ||
        loanFileChargePercent + loanProcessingFeePercent > 100
      ) {
        throw new Error(
          `Loan ${record.id || record.__rowIndex} has invalid disbursement fee percentages.`,
        );
      }
      const fileCharge =
        roundCurrency_(principal * loanFileChargePercent / 100);
      const processingFee =
        roundCurrency_(principal * loanProcessingFeePercent / 100);
      const values = {
        fileChargePercent: loanFileChargePercent,
        processingFeePercent: loanProcessingFeePercent,
        fileCharge,
        processingFee,
        disbursedAmount: roundCurrency_(principal - fileCharge - processingFee),
      };
      sheet.getRange(record.__rowIndex, 1, 1, headers.length).setValues([
        headers.map((header) =>
          Object.prototype.hasOwnProperty.call(values, header)
            ? safeCellValue_(values[header])
            : safeCellValue_(record[header]),
        ),
      ]);
    });
  });
}

function ensureApprovedLoansSheet_(spreadsheet) {
  const sheet =
    spreadsheet.getSheetByName('Approved_Loans') ||
    spreadsheet.insertSheet('Approved_Loans');
  ensureHeaders_(sheet, SHEETS.Loan_Master);
  sheet.setFrozenRows(1);
  return sheet;
}

function writeLoanRecord_(sheet, record) {
  const headers = getHeaders_(sheet);
  const values = headers.map((header) =>
    safeCellValue_(
      Object.prototype.hasOwnProperty.call(record, header) ? record[header] : '',
    ),
  );
  const rowIndex = loanRow_(record.id, sheet);
  if (rowIndex) {
    sheet.getRange(rowIndex, 1, 1, headers.length).setValues([values]);
    return rowIndex;
  }
  appendRecord_(sheet, headers, record);
  return sheet.getLastRow();
}

function loanSheetForId_(id) {
  const spreadsheet = getSpreadsheet_();
  const master = spreadsheet.getSheetByName('Loan_Master');
  const applications = spreadsheet.getSheetByName('Approved_Loans');
  if (!master) throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
  if (!applications) {
    throw new Error('Missing sheet: Approved_Loans. Run setupAccountPortal.');
  }
  const masterRow = loanRow_(id, master);
  const applicationRow = loanRow_(id, applications);
  if (masterRow && applicationRow) {
    throw new Error(`Loan ${id} exists in both loan sheets. Run setupAccountPortal.`);
  }
  if (applicationRow) return { sheet: applications, rowIndex: applicationRow };
  if (masterRow) return { sheet: master, rowIndex: masterRow };
  throw new Error('Loan not found.');
}

function allLoanRecords_() {
  const spreadsheet = getSpreadsheet_();
  const master = spreadsheet.getSheetByName('Loan_Master');
  const applications = spreadsheet.getSheetByName('Approved_Loans');
  if (!master) throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
  if (!applications) {
    throw new Error('Missing sheet: Approved_Loans. Run setupAccountPortal.');
  }
  const recordsById = new Map();
  [...readRecords_('Loan_Master'), ...readRecords_('Approved_Loans')].forEach(
    (record) => {
      const id = String(record.id || '').trim();
      if (id && !recordsById.has(id)) recordsById.set(id, record);
    },
  );
  return [...recordsById.values()];
}

function loanNumbersInUse_() {
  return new Set(
    allLoanRecords_()
      .map((record) => String(record.loanNumber || '').trim())
      .filter(Boolean),
  );
}

function generateLoanNumber_(usedNumbers) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const year = new Date().getFullYear();
    const suffix = String(Math.floor(Math.random() * 1000000)).padStart(6, '0');
    const loanNumber = `LN-${year}-${suffix}`;
    if (!usedNumbers.has(loanNumber)) {
      usedNumbers.add(loanNumber);
      return loanNumber;
    }
  }
  throw new Error('Could not generate a unique loan number. Please retry.');
}

function syncApprovedLoans_() {
  const spreadsheet = getSpreadsheet_();
  const master = spreadsheet.getSheetByName('Loan_Master');
  if (!master) throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
  ensureHeaders_(master, SHEETS.Loan_Master);
  const applications = ensureApprovedLoansSheet_(spreadsheet);
  const usedNumbers = loanNumbersInUse_();

  readRecords_('Approved_Loans')
    .sort((first, second) => second.__rowIndex - first.__rowIndex)
    .forEach((record) => {
      const status = String(record.approvalStatus || 'Pending')
        .trim()
        .toLowerCase();
      const masterRow = loanRow_(record.id, master);
      if (status === 'approved') {
        if (!String(record.loanNumber || '').trim()) {
          record.loanNumber = generateLoanNumber_(usedNumbers);
        }
        writeLoanRecord_(master, record);
        applications.deleteRow(record.__rowIndex);
      } else if (masterRow) {
        const masterRecord = rowToObject_(
          getHeaders_(master),
          master
            .getRange(masterRow, 1, 1, getHeaders_(master).length)
            .getValues()[0],
        );
        if (
          String(masterRecord.approvalStatus || 'Approved')
            .trim()
            .toLowerCase() === 'approved'
        ) {
          applications.deleteRow(record.__rowIndex);
        }
      }
    });

  readRecords_('Loan_Master')
    .sort((first, second) => second.__rowIndex - first.__rowIndex)
    .forEach((record) => {
      if (
        String(record.approvalStatus || 'Approved').trim().toLowerCase() ===
        'approved'
      ) {
        if (!String(record.loanNumber || '').trim()) {
          record.loanNumber = generateLoanNumber_(usedNumbers);
          writeLoanRecord_(master, record);
        }
        return;
      }
      writeLoanRecord_(applications, record);
      master.deleteRow(record.__rowIndex);
    });
}

function loanSchemeInput_(request) {
  const schemeName = requiredText_(request.schemeName, 'Loan scheme name');
  const loanType = String(request.loanType || '').trim().toLowerCase();
  if (!['personal', 'gold'].includes(loanType)) {
    throw new Error('Select Personal Loan or Gold Loan.');
  }
  const minAnnualRate = parseNonNegativeNumber_(
    request.minAnnualRate,
    'Minimum annual interest rate',
  );
  const maxAnnualRate = parseNonNegativeNumber_(
    request.maxAnnualRate,
    'Maximum annual interest rate',
  );
  const minAmount = parseNonNegativeNumber_(request.minAmount, 'Minimum amount');
  const maxAmount = parseNonNegativeNumber_(request.maxAmount, 'Maximum amount');
  const minTenureYears = Number(request.minTenureYears);
  const maxTenureYears = Number(request.maxTenureYears);
  const fileChargePercent = parseNonNegativeNumber_(
    request.fileChargePercent ?? 0,
    'File charge percentage',
  );
  const processingFeePercent = parseNonNegativeNumber_(
    request.processingFeePercent ?? 0,
    'Processing fee percentage',
  );
  const requestedCalculationMethod = String(
    request.calculationMethod || 'flat',
  )
    .trim()
    .toLowerCase();
  const calculationMethod =
    requestedCalculationMethod === 'flat'
      ? 'fixed_emi'
      : requestedCalculationMethod;
  if (
    minAnnualRate < 18 ||
    maxAnnualRate > 37 ||
    minAnnualRate > maxAnnualRate ||
    minAmount < 1 ||
    maxAmount > 1000000000 ||
    minAmount > maxAmount ||
    !Number.isInteger(minTenureYears) ||
    !Number.isInteger(maxTenureYears) ||
    minTenureYears < 1 ||
    maxTenureYears > 7 ||
    minTenureYears > maxTenureYears ||
    fileChargePercent > 100 ||
    processingFeePercent > 100 ||
    !['fixed_emi', 'interest_only'].includes(calculationMethod) ||
    (loanType === 'personal' && calculationMethod !== 'fixed_emi') ||
    fileChargePercent + processingFeePercent > 100
  ) {
    throw new Error('The loan scheme limits are invalid.');
  }
  return {
    schemeName,
    loanType,
    minAnnualRate,
    maxAnnualRate,
    minAmount,
    maxAmount,
    minTenureYears,
    maxTenureYears,
    fileChargePercent,
    processingFeePercent,
    calculationMethod,
    active: request.active !== false,
  };
}

function addLoanScheme_(request) {
  const sheet = getSpreadsheet_().getSheetByName('Loan_Schemes');
  if (!sheet) throw new Error('Missing sheet: Loan_Schemes. Run setupAccountPortal.');
  const scheme = loanSchemeInput_(request);
  const duplicateName = readRecords_('Loan_Schemes').some(
    (record) =>
      String(record.schemeName || '').trim().toLowerCase() ===
        scheme.schemeName.toLowerCase() &&
      String(record.loanType || '').trim().toLowerCase() === scheme.loanType,
  );
  if (duplicateName) {
    throw new Error('A scheme with this name already exists for that loan type.');
  }
  appendRecord_(sheet, getHeaders_(sheet), {
    schemeId: Utilities.getUuid(),
    ...scheme,
  });
  return { status: 'success' };
}

function editLoanScheme_(request) {
  const schemeId = requiredText_(request.schemeId, 'Loan scheme ID');
  const sheet = getSpreadsheet_().getSheetByName('Loan_Schemes');
  if (!sheet) throw new Error('Missing sheet: Loan_Schemes. Run setupAccountPortal.');
  const records = readRecords_('Loan_Schemes');
  const matches = records.filter(
    (record) => String(record.schemeId || '') === schemeId,
  );
  if (matches.length !== 1) throw new Error('Loan scheme not found or duplicated.');
  const scheme = loanSchemeInput_(request);
  const linkedLoans = allLoanRecords_().filter(
    (loan) => String(loan.schemeId || '') === schemeId,
  );
  if (
    linkedLoans.length &&
    String(matches[0].loanType || '').trim().toLowerCase() !== scheme.loanType
  ) {
    throw new Error('The loan type cannot change while loans use this scheme.');
  }
  const duplicateName = records.some(
    (record) =>
      String(record.schemeId || '') !== schemeId &&
      String(record.schemeName || '').trim().toLowerCase() ===
        scheme.schemeName.toLowerCase() &&
      String(record.loanType || '').trim().toLowerCase() === scheme.loanType,
  );
  if (duplicateName) {
    throw new Error('A scheme with this name already exists for that loan type.');
  }
  const headers = getHeaders_(sheet);
  sheet.getRange(matches[0].__rowIndex, 1, 1, headers.length).setValues([
    headers.map((header) => {
      if (header === 'schemeId') return safeCellValue_(schemeId);
      if (Object.prototype.hasOwnProperty.call(scheme, header)) {
        return safeCellValue_(scheme[header]);
      }
      return safeCellValue_(matches[0][header]);
    }),
  ]);
  return { status: 'success' };
}

function deleteLoanScheme_(request) {
  const schemeId = requiredText_(request.schemeId, 'Loan scheme ID');
  const sheet = getSpreadsheet_().getSheetByName('Loan_Schemes');
  if (!sheet) throw new Error('Missing sheet: Loan_Schemes. Run setupAccountPortal.');
  const matches = readRecords_('Loan_Schemes').filter(
    (record) => String(record.schemeId || '') === schemeId,
  );
  if (matches.length !== 1) throw new Error('Loan scheme not found or duplicated.');
  if (
    allLoanRecords_().some(
      (loan) => String(loan.schemeId || '') === schemeId,
    )
  ) {
    throw new Error('This scheme is used by existing loans and cannot be deleted.');
  }
  sheet.deleteRow(matches[0].__rowIndex);
  return { status: 'success' };
}

function readLoanSchemes_(loanTypeValue, user, includeInactive) {
  const loanType = String(loanTypeValue || '').trim().toLowerCase();
  if (loanType && !['personal', 'gold'].includes(loanType)) {
    throw new Error('Select a valid loan type.');
  }
  const permissions = permissionsForUser_(user);
  if (
    user.role === 'Member' &&
    !permissions.loan_view &&
    !permissions.loan_add
  ) {
    return [];
  }
  return readRecords_('Loan_Schemes')
    .filter(
      (record) =>
        ((includeInactive && user.role === 'Admin') || isActive_(record.active)) &&
        (!loanType ||
          String(record.loanType || '').trim().toLowerCase() === loanType),
    )
    .map((record) => {
      return {
        schemeId: String(record.schemeId || ''),
        schemeName: String(record.schemeName || ''),
        loanType: String(record.loanType || '').trim().toLowerCase(),
        minAnnualRate: Number(record.minAnnualRate) || 0,
        maxAnnualRate: Number(record.maxAnnualRate) || 0,
        minAmount: Number(record.minAmount) || 0,
        maxAmount: Number(record.maxAmount) || 0,
        minTenureYears: Number(record.minTenureYears) || 0,
        maxTenureYears: Number(record.maxTenureYears) || 0,
        fileChargePercent: Number(record.fileChargePercent) || 0,
        processingFeePercent: Number(record.processingFeePercent) || 0,
        calculationMethod: String(record.calculationMethod || '').toLowerCase(),
        active: isActive_(record.active),
      };
    });
}

function loanSchemeById_(schemeId) {
  const matchingSchemes = readRecords_('Loan_Schemes').filter(
    (record) =>
      String(record.schemeId || '') === schemeId && isActive_(record.active),
  );
  if (matchingSchemes.length !== 1) {
    throw new Error('Select a unique active loan scheme.');
  }
  const scheme = matchingSchemes[0];
  const loanType = String(scheme.loanType || '').trim().toLowerCase();
  const minAnnualRate = Number(scheme.minAnnualRate);
  const maxAnnualRate = Number(scheme.maxAnnualRate);
  const minAmount = Number(scheme.minAmount);
  const maxAmount = Number(scheme.maxAmount);
  const minTenureYears = Number(scheme.minTenureYears);
  const maxTenureYears = Number(scheme.maxTenureYears);
  const fileChargePercent = Number(scheme.fileChargePercent || 0);
  const processingFeePercent = Number(scheme.processingFeePercent || 0);
  const configuredCalculationMethod = String(
    scheme.calculationMethod || 'flat',
  )
    .trim()
    .toLowerCase();
  const calculationMethod =
    configuredCalculationMethod === 'flat'
      ? 'fixed_emi'
      : configuredCalculationMethod;
  if (
    !['personal', 'gold'].includes(loanType) ||
    !Number.isFinite(minAnnualRate) ||
    !Number.isFinite(maxAnnualRate) ||
    minAnnualRate < 18 ||
    maxAnnualRate > 37 ||
    minAnnualRate > maxAnnualRate ||
    !Number.isFinite(minAmount) ||
    !Number.isFinite(maxAmount) ||
    minAmount < 1 ||
    maxAmount > 1000000000 ||
    minAmount > maxAmount ||
    !Number.isInteger(minTenureYears) ||
    !Number.isInteger(maxTenureYears) ||
    minTenureYears < 1 ||
    maxTenureYears > 7 ||
    minTenureYears > maxTenureYears ||
    !Number.isFinite(fileChargePercent) ||
    !Number.isFinite(processingFeePercent) ||
    fileChargePercent < 0 ||
    processingFeePercent < 0 ||
    fileChargePercent + processingFeePercent > 100 ||
    !['fixed_emi', 'interest_only'].includes(calculationMethod) ||
    (loanType === 'personal' && calculationMethod !== 'fixed_emi')
  ) {
    throw new Error(`Loan scheme ${scheme.schemeName} has invalid settings.`);
  }
  return {
    schemeId,
    schemeName: requiredText_(scheme.schemeName, 'Loan scheme name'),
    loanType,
    minAnnualRate,
    maxAnnualRate,
    minAmount,
    maxAmount,
    minTenureYears,
    maxTenureYears,
    calculationMethod,
    fileChargePercent,
    processingFeePercent,
  };
}

function loanInput_(request) {
  const loanType = String(request.loanType || '').trim().toLowerCase();
  if (!['personal', 'gold'].includes(loanType)) {
    throw new Error('Select Personal Loan or Gold Loan.');
  }
  const scheme = loanSchemeById_(
    requiredText_(request.schemeId, 'Loan scheme'),
  );
  if (scheme.loanType !== loanType) {
    throw new Error('The selected scheme does not match the loan type.');
  }
  const memberName = cleanText_(request.memberName, CONFIG.maxNameLength);
  if (!memberName) throw new Error('Borrower name is required.');
  const startDate = parseDateField_(request.startDate, 'Loan date');
  const principal = parseNonNegativeNumber_(request.principal, 'Loan amount');
  if (principal < scheme.minAmount || principal > scheme.maxAmount) {
    throw new Error(
      `Loan amount for this scheme must be between ${scheme.minAmount} and ${scheme.maxAmount}.`,
    );
  }
  const annualRate = parseNonNegativeNumber_(
    request.annualRate,
    'Annual interest rate',
  );
  if (
    annualRate < scheme.minAnnualRate ||
    annualRate > scheme.maxAnnualRate
  ) {
    throw new Error(
      `Annual interest rate for this scheme must be between ${scheme.minAnnualRate}% and ${scheme.maxAnnualRate}%.`,
    );
  }
  const tenureYears = Number(request.tenureYears);
  if (
    !Number.isInteger(tenureYears) ||
    tenureYears < scheme.minTenureYears ||
    tenureYears > scheme.maxTenureYears
  ) {
    throw new Error(
      `Loan period for this scheme must be between ${scheme.minTenureYears} and ${scheme.maxTenureYears} years.`,
    );
  }
  const totalInterest = roundCurrency_(
    principal * (annualRate / 100) * tenureYears,
  );
  const totalPayable = roundCurrency_(principal + totalInterest);
  const monthlyInstallment = roundCurrency_(
    (scheme.calculationMethod === 'interest_only' ? totalInterest : totalPayable) /
      (tenureYears * 12),
  );
  const fileCharge = roundCurrency_(
    principal * scheme.fileChargePercent / 100,
  );
  const processingFee = roundCurrency_(
    principal * scheme.processingFeePercent / 100,
  );
  const disbursedAmount = roundCurrency_(
    principal - fileCharge - processingFee,
  );
  return {
    memberName,
    schemeId: scheme.schemeId,
    schemeName: scheme.schemeName,
    loanType,
    startDate,
    principal,
    annualRate,
    tenureYears,
    repaymentMethod: scheme.calculationMethod,
    paymentSchedule: '',
    totalInterest,
    totalPayable,
    monthlyInstallment,
    fileChargePercent: scheme.fileChargePercent,
    processingFeePercent: scheme.processingFeePercent,
    fileCharge,
    processingFee,
    disbursedAmount,
  };
}

function loanDueDate_(startDate, monthOffset) {
  const start = new Date(`${formatDate_(startDate)}T00:00:00Z`);
  if (Number.isNaN(start.getTime())) {
    throw new Error('The loan start date is invalid for its payment schedule.');
  }
  const monthIndex = start.getUTCMonth() + monthOffset;
  const year = start.getUTCFullYear() + Math.floor(monthIndex / 12);
  const month = monthIndex % 12;
  const day = Math.min(
    start.getUTCDate(),
    new Date(Date.UTC(year, month + 1, 0)).getUTCDate(),
  );
  return Utilities.formatDate(
    new Date(Date.UTC(year, month, day)),
    'UTC',
    'yyyy-MM-dd',
  );
}

function generateLoanPaymentSchedule_(loan) {
  const monthCount = Number(loan.tenureYears) * 12;
  if (!Number.isInteger(monthCount) || monthCount < 1 || monthCount > 84) {
    throw new Error('The loan term is invalid for its payment schedule.');
  }
  const principal = Number(loan.principal);
  const configuredInterest = isBlankLoanValue_(loan.totalInterest)
    ? Number.NaN
    : Number(loan.totalInterest);
  const annualRate = Number(loan.annualRate);
  const totalInterest =
    Number.isFinite(configuredInterest) && configuredInterest >= 0
      ? configuredInterest
      : roundCurrency_(principal * annualRate / 100 * (monthCount / 12));
  if (
    !Number.isFinite(principal) ||
    principal <= 0 ||
    !Number.isFinite(totalInterest) ||
    totalInterest < 0
  ) {
    throw new Error('The loan amounts are invalid for its payment schedule.');
  }
  const method =
    String(loan.repaymentMethod || 'fixed_emi').trim().toLowerCase() ===
    'interest_only'
      ? 'interest_only'
      : 'fixed_emi';
  const monthlyInterest = roundCurrency_(totalInterest / monthCount);
  const configuredInstallment = isBlankLoanValue_(loan.monthlyInstallment)
    ? Number.NaN
    : Number(loan.monthlyInstallment);
  const monthlyInstallment =
    Number.isFinite(configuredInstallment) && configuredInstallment >= 0
      ? configuredInstallment
      : roundCurrency_(
          (method === 'interest_only'
            ? totalInterest
            : principal + totalInterest) / monthCount,
        );
  let interestPaid = 0;
  let installmentPaid = 0;
  return Array.from({ length: monthCount }, (_, index) => {
    const finalPeriod = index === monthCount - 1;
    const interestAmount = finalPeriod
      ? roundCurrency_(totalInterest - interestPaid)
      : monthlyInterest;
    const principalAmount =
      method === 'interest_only'
        ? finalPeriod
          ? principal
          : 0
        : finalPeriod
          ? roundCurrency_(principal - installmentPaid)
          : roundCurrency_(monthlyInstallment - monthlyInterest);
    const installmentAmount = roundCurrency_(principalAmount + interestAmount);
    interestPaid = roundCurrency_(interestPaid + interestAmount);
    if (method !== 'interest_only') {
      installmentPaid = roundCurrency_(installmentPaid + principalAmount);
    }
    return {
      periodIndex: index + 1,
      dueDate: loanDueDate_(loan.startDate, index + 1),
      installmentAmount,
      principalAmount,
      interestAmount,
      paid: false,
      status: 'Unpaid',
      paidAt: '',
      updatedAt: '',
      updatedBy: '',
    };
  });
}

function loanPaymentScheduleFromRecord_(record) {
  const rawSchedule = record.paymentSchedule;
  if (!rawSchedule) return null;
  let schedule;
  try {
    schedule = typeof rawSchedule === 'string'
      ? JSON.parse(rawSchedule)
      : rawSchedule;
  } catch (error) {
    throw new Error('The stored loan payment schedule is invalid JSON.');
  }
  const expectedCount = Number(record.tenureYears) * 12;
  if (
    !Array.isArray(schedule) ||
    schedule.length !== expectedCount ||
    schedule.some(
      (payment, index) =>
        !payment ||
        Number(payment.periodIndex) !== index + 1 ||
        typeof payment.dueDate !== 'string' ||
        typeof payment.paid !== 'boolean' ||
        !Number.isFinite(Number(payment.installmentAmount)),
    )
  ) {
    throw new Error('The stored loan payment schedule is invalid.');
  }
  return schedule;
}

function migrateLoanPaymentSchedules_(spreadsheet) {
  ['Loan_Master', 'Approved_Loans'].forEach((sheetName) => {
    const sheet = spreadsheet.getSheetByName(sheetName);
    if (!sheet || sheet.getLastRow() < 2) return;
    const headers = getHeaders_(sheet);
    const scheduleColumn = headers.indexOf('paymentSchedule') + 1;
    if (scheduleColumn < 1) {
      throw new Error(`${sheetName} is missing its paymentSchedule column.`);
    }
    readRecords_(sheetName).forEach((loan) => {
      if (
        String(loan.approvalStatus || 'Approved').trim().toLowerCase() !==
          'approved' ||
        loan.paymentSchedule
      ) {
        return;
      }
      const schedule = generateLoanPaymentSchedule_(loan);
      sheet
        .getRange(loan.__rowIndex, scheduleColumn)
        .setValue(JSON.stringify(schedule));
    });
  });
}

function readLoanPaymentSchedule_(loanIdValue, user) {
  const loanId = requiredText_(loanIdValue, 'Loan ID');
  const visibleLoan = readLoans_(null, user, false).find(
    (loan) => loan.id === loanId,
  );
  if (!visibleLoan) throw new Error('Loan not found or not available to you.');
  if (visibleLoan.approvalStatus !== 'Approved') {
    throw new Error('A payment schedule is available only after loan approval.');
  }
  const sheet = getSpreadsheet_().getSheetByName('Loan_Master');
  if (!sheet) throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
  const rowIndex = loanRow_(loanId, sheet);
  if (!rowIndex) throw new Error('Loan not found.');
  const headers = getHeaders_(sheet);
  const loan = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  let schedule = loanPaymentScheduleFromRecord_(loan);
  if (!schedule) {
    schedule = generateLoanPaymentSchedule_(loan);
    setField_(
      sheet,
      rowIndex,
      headers,
      'paymentSchedule',
      JSON.stringify(schedule),
    );
    syncApprovedLoans_();
  }
  const normalizedMemberName = normalizeMemberName_(loan.memberName);
  const scheduleMember = readRecords_('Users').find(
    (member) =>
      member.role === 'Member' &&
      isActive_(member.active) &&
      normalizeMemberName_(member.name) === normalizedMemberName,
  );
  const permissions = permissionsForUser_(user);
  const canCreateMemberPayment =
    user.role === 'Member' ||
    permissions.shared_data_read ||
    permissions.user_view;
  return {
    loanId,
    memberName: String(loan.memberName || ''),
    memberId:
      canCreateMemberPayment && scheduleMember
        ? String(scheduleMember.id || '')
        : '',
    memberPhoneNumber:
      canCreateMemberPayment && scheduleMember
      ? String(scheduleMember.phoneNumber || '')
      : '',
    repaymentMethod: String(loan.repaymentMethod || 'fixed_emi'),
    principal: Number(loan.principal) || 0,
    totalPayable:
      Number(loan.totalPayable) ||
      roundCurrency_(
        schedule.reduce(
          (total, payment) =>
            total + Number(payment.installmentAmount || 0),
          0,
        ),
      ),
    payments: schedule,
  };
}

function toggleLoanPayment_(request, user) {
  const loanId = requiredText_(request.id, 'Loan ID');
  const sheet = getSpreadsheet_().getSheetByName('Loan_Master');
  if (!sheet) throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
  const rowIndex = loanRow_(loanId, sheet);
  if (!rowIndex) throw new Error('Loan not found.');
  const headers = getHeaders_(sheet);
  const loan = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  if (
    String(loan.approvalStatus || '').trim().toLowerCase() !== 'approved'
  ) {
    throw new Error('Only approved loans can have payments recorded.');
  }
  const schedule = loanPaymentScheduleFromRecord_(loan);
  if (!schedule) throw new Error('The approved loan has no payment schedule.');
  const periodIndex = Number(request.periodIndex);
  if (
    !Number.isInteger(periodIndex) ||
    periodIndex < 1 ||
    periodIndex > schedule.length
  ) {
    throw new Error('Invalid loan payment period.');
  }
  const payment = schedule[periodIndex - 1];
  payment.paid = !payment.paid;
  payment.status = payment.paid ? 'Paid' : 'Unpaid';
  payment.paidAt = payment.paid ? new Date().toISOString() : '';
  payment.updatedAt = new Date().toISOString();
  payment.updatedBy = String(user.name || user.id || 'Administrator');
  setField_(
    sheet,
    rowIndex,
    headers,
    'paymentSchedule',
    JSON.stringify(schedule),
  );
  syncApprovedLoans_();
  return { status: 'success', periodIndex, paid: payment.paid };
}

function addLoan_(request, user) {
  const spreadsheet = getSpreadsheet_();
  if (!spreadsheet.getSheetByName('Loan_Master')) {
    throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
  }
  const sheet = ensureApprovedLoansSheet_(spreadsheet);
  const loanRequest =
    user.role === 'Member'
      ? { ...request, memberName: requiredText_(user.name, 'Member name') }
      : request;
  const loan = loanInput_(loanRequest);
  appendRecord_(sheet, getHeaders_(sheet), {
    id: Utilities.getUuid(),
    ...loan,
    approvalStatus: 'Pending',
    reviewedAt: '',
    reviewedBy: '',
    createdAt: new Date(),
    createdBy: user.id,
  });
  syncApprovedLoans_();
  return { status: 'success' };
}

function editLoan_(request) {
  const id = requiredText_(request.id, 'Loan ID');
  const { sheet, rowIndex } = loanSheetForId_(id);
  const headers = getHeaders_(sheet);
  const existing = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const loan = loanInput_(request);
  sheet.getRange(rowIndex, 1, 1, headers.length).setValues([
    headers.map((header) => {
      if (header === 'approvalStatus') return 'Pending';
      if (header === 'reviewedAt' || header === 'reviewedBy') return '';
      return Object.prototype.hasOwnProperty.call(loan, header)
        ? safeCellValue_(loan[header])
        : safeCellValue_(existing[header]);
    }),
  ]);
  syncApprovedLoans_();
  return { status: 'success' };
}

function deleteLoan_(request) {
  const { sheet, rowIndex } = loanSheetForId_(
    requiredText_(request.id, 'Loan ID'),
  );
  sheet.deleteRow(rowIndex);
  syncApprovedLoans_();
  return { status: 'success' };
}

function approveLoan_(request, user) {
  const status = String(request.approvalStatus || '').trim();
  if (!['Approved', 'Rejected'].includes(status)) {
    throw new Error('Choose Approved or Rejected for the loan.');
  }
  const id = requiredText_(request.id, 'Loan ID');
  const { sheet, rowIndex } = loanSheetForId_(id);
  const headers = getHeaders_(sheet);
  const current = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const currentStatus = String(current.approvalStatus || 'Approved').trim();
  if (currentStatus !== 'Pending') {
    throw new Error('Only pending loans can be approved or rejected.');
  }
  const values = headers.map((header) => {
    if (header === 'approvalStatus') return status;
    if (header === 'reviewedAt') return new Date();
    if (header === 'reviewedBy') return user.id;
    if (header === 'repaymentMethod') {
      return String(current.repaymentMethod || 'fixed_emi');
    }
    if (header === 'paymentSchedule') {
      return status === 'Approved'
        ? JSON.stringify(
            generateLoanPaymentSchedule_({
              ...current,
              repaymentMethod: current.repaymentMethod || 'fixed_emi',
            }),
          )
        : '';
    }
    return safeCellValue_(current[header]);
  });
  if (status === 'Approved' && sheet.getName() === 'Approved_Loans') {
    const approvedRecord = rowToObject_(headers, values);
    const master = getSpreadsheet_().getSheetByName('Loan_Master');
    if (!master) {
      throw new Error('Missing sheet: Loan_Master. Run setupAccountPortal.');
    }
    writeLoanRecord_(master, approvedRecord);
    sheet.deleteRow(rowIndex);
  } else {
    sheet.getRange(rowIndex, 1, 1, headers.length).setValues([values]);
  }
  syncApprovedLoans_();
  return { status: 'success' };
}

function readLoans_(loanTypeValue, user, approvedOnly, selectedMember) {
  const loanType = String(loanTypeValue || '').trim().toLowerCase();
  if (loanType && !['personal', 'gold'].includes(loanType)) {
    throw new Error('Select a valid loan type.');
  }
  const permissions = permissionsForUser_(user);
  if (
    user.role !== 'Admin' &&
    user.role !== 'Member' &&
    !permissions.loan_view &&
    !permissions.loan_edit &&
    !permissions.loan_delete &&
    !permissions.loan_update
  ) {
    return [];
  }
  return allLoanRecords_()
    .filter(
      (record) =>
        (!loanType ||
          String(record.loanType || '').trim().toLowerCase() === loanType) &&
        (!approvedOnly ||
          String(record.approvalStatus || '').trim().toLowerCase() ===
              'approved') &&
        (user.role === 'Admin' ||
          user.role === 'Member' ||
          permissions.loan_edit ||
          permissions.loan_delete ||
          permissions.loan_update ||
          String(record.approvalStatus || 'Approved').trim() === 'Approved') &&
        (user.role !== 'Member' ||
          normalizeMemberName_(record.memberName) ===
              normalizeMemberName_(user.name)) &&
        (!selectedMember ||
          normalizeMemberName_(record.memberName) ===
            normalizeMemberName_(selectedMember.name)),
    )
    .map((record) => ({
      id: String(record.id || ''),
      loanNumber: String(record.loanNumber || ''),
      memberName: String(record.memberName || ''),
      schemeId: String(record.schemeId || ''),
      schemeName: String(record.schemeName || ''),
      loanType: String(record.loanType || '').trim().toLowerCase(),
      startDate: formatDate_(record.startDate),
      principal: Number(record.principal) || 0,
      annualRate: Number(record.annualRate) || 0,
      tenureYears: Number(record.tenureYears) || 0,
      totalInterest: Number(record.totalInterest) || 0,
      totalPayable: Number(record.totalPayable) || 0,
      monthlyInstallment: Number(record.monthlyInstallment) || 0,
      repaymentMethod: String(record.repaymentMethod || 'fixed_emi')
        .trim()
        .toLowerCase(),
      fileChargePercent: Number(record.fileChargePercent) || 0,
      processingFeePercent: Number(record.processingFeePercent) || 0,
      fileCharge: Number(record.fileCharge) || 0,
      processingFee: Number(record.processingFee) || 0,
      disbursedAmount: Number(record.disbursedAmount) || 0,
      approvalStatus: String(record.approvalStatus || 'Approved').trim(),
      reviewedAt: formatDate_(record.reviewedAt),
      reviewedBy: String(record.reviewedBy || ''),
      createdAt: formatDate_(record.createdAt),
      createdBy: String(record.createdBy || ''),
    }));
}

function loanRow_(id, sheet) {
  const headers = getHeaders_(sheet);
  const idColumn = headers.indexOf('id') + 1;
  if (idColumn < 1 || sheet.getLastRow() < 2) return 0;
  const values = sheet
    .getRange(2, idColumn, sheet.getLastRow() - 1, 1)
    .getValues();
  const index = values.findIndex((row) => String(row[0]) === String(id));
  return index < 0 ? 0 : index + 2;
}

const DEPOSIT_CADENCES = Object.freeze({
  FD: ['monthly'],
  RD: ['weekly', 'monthly'],
  DRD: ['daily', 'weekly', 'monthly'],
});
const MAX_DEPOSIT_TENURE_MONTHS = 120;

function validDepositProduct_(value) {
  const product = String(value || '').toUpperCase();
  if (!Object.prototype.hasOwnProperty.call(DEPOSIT_CADENCES, product)) {
    throw new Error('Select a valid deposit product.');
  }
  return product;
}

function validDepositCadence_(value) {
  const cadence = String(value || '').toLowerCase();
  if (!['daily', 'weekly', 'monthly'].includes(cadence)) {
    throw new Error('Select a valid deposit frequency.');
  }
  return cadence;
}

function validateDepositProductCadence_(productValue, cadenceValue) {
  const product = validDepositProduct_(productValue);
  const cadence = validDepositCadence_(cadenceValue);
  if (!DEPOSIT_CADENCES[product].includes(cadence)) {
    throw new Error(`${product} is not available with ${cadence} payments.`);
  }
  return { product, cadence };
}

function depositMaturityDate_(startDate, tenureMonths) {
  const [year, month, day] = startDate.split('-').map(Number);
  const targetMonth = month - 1 + tenureMonths;
  const targetYear = year + Math.floor(targetMonth / 12);
  const targetMonthIndex = targetMonth % 12;
  const lastDay = new Date(Date.UTC(targetYear, targetMonthIndex + 1, 0)).getUTCDate();
  const maturity = new Date(
    Date.UTC(targetYear, targetMonthIndex, Math.min(day, lastDay)),
  );
  return Utilities.formatDate(maturity, 'UTC', 'yyyy-MM-dd');
}

function depositPeriodDates_(startDate, maturityDate, cadence) {
  const start = new Date(`${startDate}T00:00:00Z`);
  const maturity = new Date(`${maturityDate}T00:00:00Z`);
  const dates = [];
  if (cadence === 'monthly') {
    const startDay = start.getUTCDate();
    for (let period = 1; period <= MAX_DEPOSIT_TENURE_MONTHS; period++) {
      const targetMonth = start.getUTCMonth() + period;
      const targetYear = start.getUTCFullYear() + Math.floor(targetMonth / 12);
      const targetMonthIndex = targetMonth % 12;
      const lastDay = new Date(
        Date.UTC(targetYear, targetMonthIndex + 1, 0),
      ).getUTCDate();
      const dueDate = new Date(
        Date.UTC(targetYear, targetMonthIndex, Math.min(startDay, lastDay)),
      );
      if (dueDate > maturity) break;
      dates.push(Utilities.formatDate(dueDate, 'UTC', 'yyyy-MM-dd'));
    }
    return dates;
  }

  const daysPerPeriod = cadence === 'weekly' ? 7 : 1;
  for (
    let dueDate = new Date(start.getTime() + daysPerPeriod * 86400000);
    dueDate <= maturity;
    dueDate = new Date(dueDate.getTime() + daysPerPeriod * 86400000)
  ) {
    dates.push(Utilities.formatDate(dueDate, 'UTC', 'yyyy-MM-dd'));
  }
  return dates;
}

function calculateDepositMaturity_(
  product,
  cadence,
  amount,
  annualRate,
  tenureMonths,
  periodCount,
) {
  const rate = annualRate / 100;
  if (product === 'FD') {
    return roundCurrency_(amount * Math.pow(1 + rate / 12, tenureMonths));
  }
  if (product === 'DRD' && cadence === 'daily') {
    const contributions = amount * periodCount;
    const maturity = contributions * (1 + rate * tenureMonths / 12);
    return roundCurrency_(maturity);
  }
  const periodsPerYear =
    cadence === 'daily' ? 365 : cadence === 'weekly' ? 52 : 12;
  const periodRate = rate / periodsPerYear;
  const maturity =
    periodRate === 0
      ? amount * periodCount
      : amount * (Math.pow(1 + periodRate, periodCount) - 1) / periodRate;
  return roundCurrency_(maturity);
}

function roundCurrency_(value) {
  if (!Number.isFinite(value)) throw new Error('Maturity amount is too large.');
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function isBlankLoanValue_(value) {
  return value === '' || value === null || value === undefined;
}

function depositAccountInput_(request) {
  const { product, cadence } = validateDepositProductCadence_(
    request.product,
    request.cadence,
  );
  const memberName = cleanText_(request.memberName, CONFIG.maxNameLength);
  if (!memberName) throw new Error('Member name is required.');
  const startDate = parseDateField_(request.startDate, 'Start date');
  const amount = parseNonNegativeNumber_(
    request.amount,
    product === 'FD' ? 'Principal amount' : 'Installment amount',
  );
  if (amount <= 0) throw new Error('Amount must be greater than zero.');
  const annualRate = parseNonNegativeNumber_(
    request.annualRate,
    'Annual interest rate',
  );
  if (annualRate > 100) {
    throw new Error('Annual interest rate cannot exceed 100%.');
  }
  const tenureMonths = Number(request.tenureMonths);
  if (
    !Number.isInteger(tenureMonths) ||
    tenureMonths < 1 ||
    tenureMonths > MAX_DEPOSIT_TENURE_MONTHS
  ) {
    throw new Error(
      `Tenure must be between 1 and ${MAX_DEPOSIT_TENURE_MONTHS} months.`,
    );
  }
  const maturityDate = depositMaturityDate_(startDate, tenureMonths);
  const periodDates =
    product === 'FD'
      ? []
      : depositPeriodDates_(startDate, maturityDate, cadence);
  const payments = periodDates.map(() => false);
  const maturityAmount = calculateDepositMaturity_(
    product,
    cadence,
    amount,
    annualRate,
    tenureMonths,
    periodDates.length,
  );
  return {
    memberName,
    product,
    cadence,
    startDate,
    amount,
    annualRate,
    tenureMonths,
    maturityDate,
    maturityAmount,
    payments,
    periodDates,
  };
}

function addDepositAccount_(request, user) {
  const input = depositAccountInput_(request);
  const spreadsheet = getSpreadsheet_();
  const sheet = spreadsheet.getSheetByName('Deposit_Accounts');
  if (!sheet) {
    throw new Error('Deposit_Accounts sheet is missing. Run setupAccountPortal.');
  }
  ensureDepositPaymentColumns_(sheet, input.payments.length);
  const id = Utilities.getUuid();
  appendRecord_(sheet, getHeaders_(sheet), {
    id,
    ...input,
    payment_count: input.payments.length,
    paid_count: 0,
    ...depositPaymentFields_(input.payments),
    createdAt: new Date(),
    createdBy: user.id,
  });
  syncDepositPaymentSchedule_(
    id,
    input.periodDates,
    input.payments,
  );
  return { status: 'success' };
}

function editDepositAccount_(request) {
  const id = requiredText_(request.id, 'Deposit account ID');
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  if (!sheet) {
    throw new Error('Deposit_Accounts sheet is missing. Run setupAccountPortal.');
  }
  const rowIndex = depositAccountRow_(id, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');

  let headers = getHeaders_(sheet);
  const existing = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const input = depositAccountInput_(request);
  if (
    existing.product !== input.product ||
    existing.cadence !== input.cadence
  ) {
    throw new Error('A deposit account product and cadence cannot be changed.');
  }

  const oldStartDate = formatDate_(existing.startDate);
  const oldMaturityDate = formatDate_(existing.maturityDate);
  const oldDates =
    input.product === 'FD'
      ? []
      : depositPeriodDates_(oldStartDate, oldMaturityDate, input.cadence);
  const oldPayments = depositPaymentsFromRecord_(existing, oldDates.length);
  const newDates =
    input.product === 'FD'
      ? []
      : depositPeriodDates_(input.startDate, input.maturityDate, input.cadence);
  const payments = preserveDepositPayments_(oldPayments, oldDates, newDates);
  ensureDepositPaymentColumns_(sheet, newDates.length);
  headers = getHeaders_(sheet);
  const updated = Object.assign({}, existing, input, {
    id,
    payment_count: payments.length,
    paid_count: payments.filter((paid) => paid).length,
    ...depositPaymentFields_(payments),
  });
  sheet
    .getRange(rowIndex, 1, 1, headers.length)
    .setValues([
      headers.map((header) =>
        Object.prototype.hasOwnProperty.call(updated, header)
          ? safeCellValue_(updated[header])
          : '',
      ),
    ]);
  syncDepositPaymentSchedule_(
    id,
    newDates,
    payments,
  );
  return { status: 'success' };
}

function preserveDepositPayments_(payments, oldDates, newDates) {
  if (
    !Array.isArray(payments) ||
    payments.length !== oldDates.length ||
    payments.some((paid) => typeof paid !== 'boolean')
  ) {
    throw new Error('The deposit payment schedule is invalid.');
  }
  const paidDates = new Set(
    oldDates.filter((date, index) => payments[index]),
  );
  const newDateSet = new Set(newDates);
  if ([...paidDates].some((date) => !newDateSet.has(date))) {
    throw new Error(
      'This edit would remove a paid installment date. Keep the existing paid dates in the schedule.',
    );
  }
  const paymentsByDate = new Map(
    oldDates.map((date, index) => [date, payments[index]]),
  );
  return newDates.map((date) => paymentsByDate.get(date) === true);
}

function migrateLegacyDepositPayments_(spreadsheet) {
  const accountsSheet = spreadsheet.getSheetByName('Deposit_Accounts');
  if (!accountsSheet) throw new Error('Deposit_Accounts sheet is missing.');
  let accountHeaders = getHeaders_(accountsSheet);
  const legacySheet = spreadsheet.getSheetByName('Deposit_Payments');
  const legacyRows = legacySheet ? readRecords_('Deposit_Payments') : [];
  const legacyByDeposit = new Map();
  legacyRows.forEach((payment) => {
    const depositId = String(payment.depositId || '');
    const periodIndex = Number(payment.periodIndex);
    if (!depositId || !Number.isInteger(periodIndex) || periodIndex < 1) {
      throw new Error('A Deposit_Payments row has an invalid account or period.');
    }
    if (!legacyByDeposit.has(depositId)) {
      legacyByDeposit.set(depositId, new Map());
    }
    const byPeriod = legacyByDeposit.get(depositId);
    if (byPeriod.has(periodIndex)) {
      throw new Error(`Duplicate deposit payment row ${depositId}:${periodIndex}.`);
    }
    byPeriod.set(periodIndex, payment);
  });

  let accounts = readRecords_('Deposit_Accounts');
  const schedules = accounts.map((account) => {
    const product = String(account.product || '').toUpperCase();
    return product === 'FD'
      ? []
      : depositPeriodDates_(
          formatDate_(account.startDate),
          formatDate_(account.maturityDate),
          String(account.cadence || '').toLowerCase(),
        );
  });
  ensureDepositPaymentColumns_(
    accountsSheet,
    schedules.reduce((maximum, dates) => Math.max(maximum, dates.length), 0),
  );
  accountHeaders = getHeaders_(accountsSheet);
  accounts = readRecords_('Deposit_Accounts');
  const accountIds = new Set(accounts.map((account) => String(account.id || '')));
  accounts.forEach((account, accountIndex) => {
    const id = String(account.id || '');
    if (!id) return;
    const dates = schedules[accountIndex];
    const payments = depositPaymentsFromRecord_(account, dates.length);
    let storedRows;
    try {
      storedRows = String(account.paymentRows || '').trim()
        ? JSON.parse(String(account.paymentRows))
        : [];
    } catch (error) {
      console.error(`Invalid payment rows for deposit ${id}.`, error);
      throw new Error(`Deposit ${id} has invalid payment rows.`);
    }
    if (!Array.isArray(storedRows)) {
      throw new Error(`Deposit ${id} has invalid payment rows.`);
    }
    const storedByPeriod = new Map();
    storedRows.forEach((payment) => {
      if (!payment || typeof payment !== 'object') {
        throw new Error(`Deposit ${id} has an invalid stored payment row.`);
      }
      const periodIndex = Number(payment.periodIndex);
      if (
        !Number.isInteger(periodIndex) ||
        periodIndex < 1 ||
        periodIndex > dates.length ||
        storedByPeriod.has(periodIndex)
      ) {
        throw new Error(`Deposit ${id} has invalid or duplicate payment rows.`);
      }
      storedByPeriod.set(periodIndex, payment);
    });
    const legacyByPeriod = legacyByDeposit.get(id) || new Map();
    legacyByPeriod.forEach((_, periodIndex) => {
      if (periodIndex > dates.length) {
        throw new Error(
          `Deposit ${id} has a legacy payment row outside its current schedule.`,
        );
      }
    });
    dates.forEach((_, index) => {
      const oldRow = legacyByPeriod.get(index + 1);
      if (typeof account[depositPaymentColumn_(index + 1)] === 'boolean') {
        return;
      }
      const source = oldRow || storedByPeriod.get(index + 1);
      if (!source) return;
      payments[index] = normalizeDepositPaid_(
        Object.prototype.hasOwnProperty.call(source, 'paid') &&
            source.paid !== ''
          ? source.paid
          : source.status,
      );
    });
    writeDepositPaymentColumns_(
      accountsSheet,
      account.__rowIndex,
      accountHeaders,
      payments,
    );
    writeDepositPaymentCounts_(
      accountsSheet,
      account.__rowIndex,
      accountHeaders,
      payments,
    );
  });

  legacyByDeposit.forEach((_, depositId) => {
    if (!accountIds.has(depositId)) {
      throw new Error(
        `Deposit_Payments contains rows for unknown deposit ${depositId}.`,
      );
    }
  });
  if (legacySheet) spreadsheet.deleteSheet(legacySheet);
  accountHeaders
    .map((header, index) =>
      header === 'paymentRows' ||
      header === 'payments' ||
      /^payment_\d+_paid$/.test(header)
        ? index + 1
        : 0,
    )
    .filter((column) => column > 0)
    .sort((left, right) => right - left)
    .forEach((column) => accountsSheet.deleteColumn(column));
}

function normalizeDepositPaid_(value) {
  if (typeof value === 'boolean') return value;
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'true' || normalized === 'paid') return true;
  if (normalized === 'false' || normalized === 'unpaid' || !normalized) {
    return false;
  }
  throw new Error(`Invalid deposit payment status: ${value}.`);
}

function depositPaymentColumn_(periodIndex) {
  return `P${periodIndex}`;
}

function depositPaymentFields_(payments) {
  return payments.reduce(
    (fields, paid, index) => ({
      ...fields,
      [depositPaymentColumn_(index + 1)]: paid,
    }),
    {},
  );
}

function ensureDepositPaymentColumns_(sheet, periodCount) {
  if (!Number.isInteger(periodCount) || periodCount < 0) {
    throw new Error('Invalid deposit payment period count.');
  }
  ensureHeaders_(
    sheet,
    Array.from({ length: periodCount }, (_, index) =>
      depositPaymentColumn_(index + 1),
    ),
  );
}

function depositPaymentsFromRecord_(record, periodCount) {
  const columnPayments = Array.from({ length: periodCount }, (_, index) => {
    const periodIndex = index + 1;
    const columnValue = record[depositPaymentColumn_(periodIndex)];
    if (typeof columnValue === 'boolean') return columnValue;
    const legacyColumnValue = record[`payment_${periodIndex}_paid`];
    if (typeof legacyColumnValue === 'boolean') return legacyColumnValue;
    return null;
  });
  if (columnPayments.every((paid) => typeof paid === 'boolean')) {
    return columnPayments;
  }

  let legacyPayments = [];
  if (Object.prototype.hasOwnProperty.call(record, 'payments')) {
    try {
      legacyPayments = JSON.parse(String(record.payments || '[]'));
    } catch (error) {
      console.error(`Invalid payment schedule for deposit ${record.id}.`, error);
      throw new Error('A deposit payment schedule is invalid. Contact an administrator.');
    }
    if (
      !Array.isArray(legacyPayments) ||
      legacyPayments.length !== periodCount ||
      legacyPayments.some((paid) => typeof paid !== 'boolean')
    ) {
      throw new Error('A deposit payment schedule is invalid. Contact an administrator.');
    }
  }
  return columnPayments.map((paid, index) =>
    typeof paid === 'boolean' ? paid : legacyPayments[index] === true,
  );
}

function writeDepositPaymentColumns_(sheet, rowIndex, headers, payments) {
  const paymentColumns = headers
    .map((header, index) => ({
      column: index + 1,
      periodIndex: /^P(\d+)$/.test(header)
        ? Number(header.match(/^P(\d+)$/)[1])
        : 0,
    }))
    .filter((entry) => entry.periodIndex > 0);
  paymentColumns.sort((left, right) => left.column - right.column);
  let first = 0;
  while (first < paymentColumns.length) {
    let end = first + 1;
    while (
      end < paymentColumns.length &&
      paymentColumns[end].column === paymentColumns[end - 1].column + 1
    ) {
      end += 1;
    }
    const columns = paymentColumns.slice(first, end);
    sheet
      .getRange(rowIndex, columns[0].column, 1, columns.length)
      .setValues([
        columns.map(({ periodIndex }) =>
          periodIndex <= payments.length ? payments[periodIndex - 1] : '',
        ),
      ]);
    first = end;
  }
}

function writeDepositPaymentCounts_(sheet, rowIndex, headers, payments) {
  setField_(sheet, rowIndex, headers, 'payment_count', payments.length);
  setField_(
    sheet,
    rowIndex,
    headers,
    'paid_count',
    payments.filter((paid) => paid).length,
  );
}

function syncDepositPaymentSchedule_(
  depositId,
  dueDates,
  payments,
) {
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  const rowIndex = depositAccountRow_(depositId, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');
  let headers = getHeaders_(sheet);
  if (
    payments.length !== dueDates.length ||
    payments.some((paid) => typeof paid !== 'boolean')
  ) {
    throw new Error(`Deposit ${depositId} has an invalid payment schedule.`);
  }
  ensureDepositPaymentColumns_(sheet, payments.length);
  ensureHeaders_(sheet, ['payment_count', 'paid_count']);
  headers = getHeaders_(sheet);
  writeDepositPaymentColumns_(sheet, rowIndex, headers, payments);
  writeDepositPaymentCounts_(sheet, rowIndex, headers, payments);
}

function upsertDepositPaymentRow_(record) {
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  const rowIndex = depositAccountRow_(record.depositId, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');
  const headers = getHeaders_(sheet);
  const account = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  const product = validDepositProduct_(account.product);
  const cadence = validDepositCadence_(account.cadence);
  const dates = depositPeriodDates_(
    formatDate_(account.startDate),
    formatDate_(account.maturityDate),
    cadence,
  );
  const payments = depositPaymentsFromRecord_(account, dates.length);
  const periodIndex = Number(record.periodIndex);
  if (
    !Array.isArray(payments) ||
    !Number.isInteger(periodIndex) ||
    periodIndex < 1 ||
    periodIndex > payments.length
  ) {
    throw new Error('The deposit payment schedule is invalid.');
  }
  payments[periodIndex - 1] = normalizeDepositPaid_(
    Object.prototype.hasOwnProperty.call(record, 'paid')
      ? record.paid
      : record.status,
  );
  syncDepositPaymentSchedule_(record.depositId, dates, payments);
}

function readDepositAccounts_(productValue, cadence, user, selectedMemberId) {
  const { product, cadence: validCadence } = validateDepositProductCadence_(
    productValue,
    cadence,
  );
  const memberName = normalizeMemberName_(user.name);
  const selectedMember = selectedMemberId
    ? findUserById_(selectedMemberId)
    : null;
  if (
    selectedMemberId &&
    (!selectedMember ||
      selectedMember.role !== 'Member' ||
      !isActive_(selectedMember.active))
  ) {
    throw new Error('Select an active Member account.');
  }
  const targetMemberName = normalizeMemberName_(
    selectedMember ? selectedMember.name : user.name,
  );
  const membersByName = new Map(
    readRecords_('Users')
      .filter((member) => isActive_(member.active) && member.role === 'Member')
      .map((member) => [normalizeMemberName_(member.name), member]),
  );
  const profileImagesByName = new Map();
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  ensureDepositPaymentColumns_(
    sheet,
    readRecords_('Deposit_Accounts').reduce((maximum, account) => {
      const dates =
        String(account.product || '').trim().toUpperCase() === 'FD'
          ? []
          : depositPeriodDates_(
              formatDate_(account.startDate),
              formatDate_(account.maturityDate),
              String(account.cadence || '').trim().toLowerCase(),
            );
      return Math.max(maximum, dates.length);
    }, 0),
  );
  return readRecords_('Deposit_Accounts')
    .filter(
      (record) =>
        String(record.product || '').trim().toUpperCase() === product &&
        String(record.cadence || '').trim().toLowerCase() === validCadence &&
        (user.role !== 'Member' ||
          normalizeMemberName_(record.memberName) === memberName) &&
        (!selectedMemberId ||
          normalizeMemberName_(record.memberName) === targetMemberName),
    )
    .map((record) => {
      const normalizedName = normalizeMemberName_(record.memberName);
      const member = membersByName.get(normalizedName);
      if (member && !profileImagesByName.has(normalizedName)) {
        profileImagesByName.set(
          normalizedName,
          profileImageDataUrl_(member),
        );
      }
      const startDate = formatDate_(record.startDate);
      const maturityDate = formatDate_(record.maturityDate);
      const periodDates =
        product === 'FD'
          ? []
          : depositPeriodDates_(startDate, maturityDate, validCadence);
      const payments = depositPaymentsFromRecord_(record, periodDates.length);
      const mergedPaymentRows = periodDates.map((dueDate, index) => {
        const periodIndex = index + 1;
        const paid = payments[index];
        return {
          periodIndex,
          dueDate,
          installmentAmount: Number(record.amount) || 0,
          paid,
          status: paid ? 'Paid' : 'Unpaid',
        };
      });
      const amount = Number(record.amount) || 0;
      const annualRate = Number(record.annualRate) || 0;
      const tenureMonths = Number(record.tenureMonths) || 0;
      return {
        id: String(record.id || ''),
        memberName: String(record.memberName || ''),
        memberId: member ? String(member.id || '') : '',
        memberPhoneNumber: member
          ? String(member.phoneNumber || '')
          : '',
        profileImageUrl: profileImagesByName.get(normalizedName) || '',
        product,
        cadence: validCadence,
        startDate,
        amount,
        annualRate,
        tenureMonths,
        maturityDate,
        maturityAmount: calculateDepositMaturity_(
          product,
          validCadence,
          amount,
          annualRate,
          tenureMonths,
          periodDates.length,
        ),
        payments,
        periodDates,
        paymentRows: mergedPaymentRows,
        paymentRowCount: mergedPaymentRows.length,
        paymentCount: payments.length,
        paidCount: payments.filter((paid) => paid).length,
      };
    });
}

function depositAccountRow_(id, sheet) {
  const headers = getHeaders_(sheet);
  const idColumn = headers.indexOf('id') + 1;
  if (idColumn < 1 || sheet.getLastRow() < 2) return 0;
  const values = sheet
    .getRange(2, idColumn, sheet.getLastRow() - 1, 1)
    .getValues();
  const index = values.findIndex((row) => String(row[0]) === String(id));
  return index < 0 ? 0 : index + 2;
}

function toggleDepositPayment_(request, user) {
  const id = requiredText_(request.id, 'Deposit account ID');
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  const rowIndex = depositAccountRow_(id, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');
  const headers = getHeaders_(sheet);
  const row = rowToObject_(
    headers,
    sheet.getRange(rowIndex, 1, 1, headers.length).getValues()[0],
  );
  if (row.product === 'FD') {
    throw new Error('Fixed deposits do not have recurring payment periods.');
  }
  const { product, cadence } = validateDepositProductCadence_(
    row.product,
    row.cadence,
  );
  const periodIndex = Number(request.periodIndex);
  const periodDates = depositPeriodDates_(
    formatDate_(row.startDate),
    formatDate_(row.maturityDate),
    cadence,
  );
  if (
    !Number.isInteger(periodIndex) ||
    periodIndex < 1 ||
    periodIndex > periodDates.length
  ) {
    throw new Error('Invalid deposit payment period.');
  }
  const payments = depositPaymentsFromRecord_(row, periodDates.length);
  if (
    !Array.isArray(payments) ||
    payments.length !== periodDates.length ||
    payments.some((paid) => typeof paid !== 'boolean')
  ) {
    throw new Error('The deposit payment schedule is invalid.');
  }
  const currentPaid = payments[periodIndex - 1];
  payments[periodIndex - 1] = !currentPaid;
  const now = new Date();
  upsertDepositPaymentRow_({
    depositId: id,
    periodIndex,
    dueDate: periodDates[periodIndex - 1],
    installmentAmount: Number(row.amount) || 0,
    paid: payments[periodIndex - 1],
    status: payments[periodIndex - 1] ? 'Paid' : 'Unpaid',
    paidAt: payments[periodIndex - 1] ? now : '',
    paymentMethod: payments[periodIndex - 1] ? 'Manual' : '',
    transactionId: '',
    updatedAt: now,
    updatedBy: String(user.name || user.id || 'Administrator'),
  });
  return { status: 'success', product, cadence };
}

function deleteDepositAccount_(request) {
  const id = requiredText_(request.id, 'Deposit account ID');
  const sheet = getSpreadsheet_().getSheetByName('Deposit_Accounts');
  const rowIndex = depositAccountRow_(id, sheet);
  if (!rowIndex) throw new Error('Deposit account not found.');
  sheet.deleteRow(rowIndex);
  return { status: 'success' };
}

function createUser_(user) {
  const sheet = getSpreadsheet_().getSheetByName('Users');
  if (!sheet) throw new Error('Users sheet is missing. Run setupAccountPortal.');
  const headers = getHeaders_(sheet);
  const salt = Utilities.getUuid();
  const id = Utilities.getUuid();
  const accountNo = nextAccountNumber_(user.role);
  const profileImageFileId = user.profileImageData
    ? saveProfileImage_(
        user.profileImageData,
        user.profileImageMimeType,
        id,
      )
    : '';
  try {
    appendRecord_(sheet, headers, {
      id,
      accountNo,
      name: user.name,
      profileImageUrl: '',
      profileImageFileId,
      email: user.email,
      phoneNumber: normalizePhoneNumber_(user.phoneNumber),
      role: user.role,
      passwordSalt: salt,
      passwordHash: passwordHash_(user.password, salt, getPasswordPepper_()),
      active: true,
      dailyAccess: user.dailyAccess !== false,
      weeklyAccess: user.weeklyAccess !== false,
      monthlyAccess: user.monthlyAccess !== false,
      createdAt: new Date(),
    });
  } catch (error) {
    if (profileImageFileId) trashProfileImage_(profileImageFileId);
    throw error;
  }
  return id;
}

function getOrCreateProfileImagesFolder_() {
  const properties = PropertiesService.getScriptProperties();
  const folderId = properties.getProperty('PROFILE_IMAGES_FOLDER_ID');
  if (folderId) return DriveApp.getFolderById(folderId);
  const folder = DriveApp.createFolder('NTCCSL Portal Profile Images');
  properties.setProperty('PROFILE_IMAGES_FOLDER_ID', folder.getId());
  return folder;
}

function saveProfileImage_(encodedImage, mimeType, userId) {
  if (typeof encodedImage !== 'string' || !encodedImage) {
    throw new Error('Select a profile image to upload.');
  }
  if (
    mimeType !== 'image/jpeg' &&
    mimeType !== 'image/png' &&
    mimeType !== 'image/webp'
  ) {
    throw new Error('Profile images must be JPEG, PNG, or WebP.');
  }
  const maximumEncodedLength =
    Math.ceil(CONFIG.maxProfileImageBytes / 3) * 4;
  if (encodedImage.length > maximumEncodedLength) {
    throw new Error('Profile image is too large. Choose an image under 300 KB.');
  }
  let bytes;
  try {
    bytes = Utilities.base64Decode(encodedImage);
  } catch (error) {
    throw new Error('Profile image data is invalid.');
  }
  if (bytes.length === 0 || bytes.length > CONFIG.maxProfileImageBytes) {
    throw new Error('Profile image must be between 1 byte and 300 KB.');
  }
  validateProfileImageSignature_(bytes, mimeType);
  const extension = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  }[mimeType];
  const blob = Utilities.newBlob(bytes, mimeType, `profile-${userId}.${extension}`);
  return getOrCreateProfileImagesFolder_().createFile(blob).getId();
}

function validateProfileImageSignature_(bytes, mimeType) {
  const byteAt = (index) => bytes[index] & 0xff;
  let valid = false;
  if (mimeType === 'image/jpeg') {
    valid =
      bytes.length >= 3 &&
      byteAt(0) === 0xff &&
      byteAt(1) === 0xd8 &&
      byteAt(2) === 0xff;
  } else if (mimeType === 'image/png') {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    valid =
      bytes.length >= signature.length &&
      signature.every((value, index) => byteAt(index) === value);
  } else if (mimeType === 'image/webp') {
    valid =
      bytes.length >= 12 &&
      byteAt(0) === 0x52 &&
      byteAt(1) === 0x49 &&
      byteAt(2) === 0x46 &&
      byteAt(3) === 0x46 &&
      byteAt(8) === 0x57 &&
      byteAt(9) === 0x45 &&
      byteAt(10) === 0x42 &&
      byteAt(11) === 0x50;
  }
  if (!valid) {
    throw new Error('Profile image data does not match its image type.');
  }
}

function trashProfileImage_(fileId) {
  DriveApp.getFileById(String(fileId)).setTrashed(true);
}

function profileImageDataUrl_(user) {
  const fileId = String(user.profileImageFileId || '');
  if (!fileId) return String(user.profileImageUrl || '');
  const blob = DriveApp.getFileById(fileId).getBlob();
  const mimeType = blob.getContentType();
  if (
    mimeType !== 'image/jpeg' &&
    mimeType !== 'image/png' &&
    mimeType !== 'image/webp'
  ) {
    throw new Error('Stored profile image has an unsupported file type.');
  }
  return `data:${mimeType};base64,${Utilities.base64Encode(blob.getBytes())}`;
}

function nextAccountNumber_(role) {
  const prefix = accountNumberPrefix_(role);
  if (role === 'Admin') {
    const existingNumbers = new Set(
      readRecords_('Users').map((user) => String(user.accountNo || '')),
    );
    let accountNo;
    do {
      accountNo = `ADM${Math.floor(100000000 + Math.random() * 900000000)}`;
    } while (existingNumbers.has(accountNo));
    return accountNo;
  }

  const highest = readRecords_('Users').reduce((max, user) => {
    const match = String(user.accountNo || '').match(
      new RegExp(`^${prefix}(\\d{9})$`),
    );
    const value = match ? Number(match[1]) : 0;
    return Number.isSafeInteger(value) && value > max ? value : max;
  }, 0);
  if (highest >= 999999999) {
    throw new Error(`No ${role} account numbers remain.`);
  }
  return `${prefix}${String(highest + 1).padStart(9, '0')}`;
}

function accountNumberPrefix_(role) {
  if (role === 'Member') return 'DRD';
  if (role === 'Collector') return 'EMP';
  if (role === 'Admin') return 'ADM';
  throw new Error(`Cannot create an account number for role ${role}.`);
}

function backfillAccountNumbers_() {
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const accountNoColumn = headers.indexOf('accountNo') + 1;
  if (accountNoColumn < 1 || sheet.getLastRow() < 2) return;

  const users = readRecords_('Users');
  const validAccountNumber = (user) => {
    const prefix = accountNumberPrefix_(String(user.role || ''));
    return new RegExp(`^${prefix}\\d{9}$`).test(
      String(user.accountNo || ''),
    );
  };
  users.forEach((user) => {
    if (!validAccountNumber(user)) {
      setField_(
        sheet,
        user.__rowIndex,
        headers,
        'accountNo',
        nextAccountNumber_(String(user.role || '')),
      );
    }
  });
}

function requireRole_(token, allowedRoles) {
  const session = CacheService.getScriptCache().get(
    `session:${sha256Hex_(String(token || ''))}`,
  );
  if (!session) throw new Error('Your session expired. Sign in again.');
  const stored = JSON.parse(session);
  const user = findUserById_(stored.userId);
  if (!user || !isActive_(user.active)) {
    throw new Error('This account is inactive. Contact an administrator.');
  }
  if (!allowedRoles.includes(user.role)) {
    throw new Error('You do not have permission to perform this action.');
  }
  return user;
}

function requirePermission_(token, permission) {
  const user = requireRole_(token, PORTAL_ROLES);
  if (
    user.role !== 'Admin' &&
    !permissionsForUser_(user)[permission]
  ) {
    throw new Error('You do not have permission to perform this action.');
  }
  return user;
}

function requireAnyPermission_(token, permissions) {
  const user = requireRole_(token, PORTAL_ROLES);
  if (
    user.role !== 'Admin' &&
    !permissions.some((permission) => permissionsForUser_(user)[permission])
  ) {
    throw new Error('You do not have permission to view this data.');
  }
  return user;
}

function requireDepositRead_(token, cadence) {
  const user = requireRole_(token, PORTAL_ROLES);
  requireMemberDepositCadence_(user, cadence);
  const permissions = permissionsForUser_(user);
  if (
    user.role !== 'Admin' &&
    !permissions.deposit_view &&
    !permissions.deposit_add &&
    !permissions.deposit_edit &&
    !permissions.deposit_delete &&
    !permissions.deposit_update
  ) {
    throw new Error('You do not have permission to view deposit accounts.');
  }
  return user;
}

function requireMemberDepositCadence_(user, cadence) {
  const reportAccessField = `${cadence}Access`;
  if (
    user.role === 'Member' &&
    !isReportAccessEnabled_(user[reportAccessField])
  ) {
    throw new Error('This report is inactive for your account.');
  }
}

function requireLoanRead_(token) {
  const user = requireRole_(token, PORTAL_ROLES);
  const permissions = permissionsForUser_(user);
  if (
    user.role !== 'Admin' &&
    !permissions.loan_view &&
    !(user.role === 'Member' && permissions.loan_add) &&
    ![
      'loan_add',
      'loan_edit',
      'loan_delete',
      'loan_update',
    ].some((permission) => permissions[permission])
  ) {
    throw new Error('You do not have permission to view loans.');
  }
  return user;
}

function findUserByEmail_(email) {
  return readRecords_('Users').find(
    (user) => normalizeEmail_(user.email) === email,
  );
}

function findUserByAccountNumber_(accountNumber) {
  return readRecords_('Users').find(
    (user) => String(user.accountNo || '').trim().toUpperCase() === accountNumber,
  );
}

function findUserById_(id) {
  return readRecords_('Users').find((user) => String(user.id) === String(id));
}

function findUserRowById_(id) {
  const sheet = getSpreadsheet_().getSheetByName('Users');
  const headers = getHeaders_(sheet);
  const idColumn = headers.indexOf('id') + 1;
  if (idColumn < 1 || sheet.getLastRow() < 2) return 0;
  const found = sheet
    .getRange(2, idColumn, sheet.getLastRow() - 1, 1)
    .createTextFinder(String(id))
    .matchEntireCell(true)
    .findNext();
  return found ? found.getRow() : 0;
}

function assertAnotherActiveAdmin_(exceptId) {
  const admins = readRecords_('Users').filter(
    (user) =>
      String(user.id) !== String(exceptId) &&
      user.role === 'Admin' &&
      isActive_(user.active),
  );
  if (admins.length === 0) {
    throw new Error('The last active admin cannot be deleted or demoted.');
  }
}

function readRecords_(sheetName) {
  const sheet = getSpreadsheet_().getSheetByName(sheetName);
  if (!sheet) {
    throw new Error(`Missing sheet: ${sheetName}. Run setupAccountPortal.`);
  }
  const headers = getHeaders_(sheet);
  if (sheet.getLastRow() < 2) return [];
  return sheet
    .getRange(2, 1, sheet.getLastRow() - 1, headers.length)
    .getValues()
    .map((row, index) => ({
      ...rowToObject_(headers, row),
      __rowIndex: index + 2,
    }))
    .filter((record) =>
      Object.keys(record).some(
        (key) => key !== '__rowIndex' && record[key] !== '',
      ),
    );
}

function appendRecord_(sheet, headers, record) {
  sheet.appendRow(
    headers.map((header) =>
      Object.prototype.hasOwnProperty.call(record, header)
        ? safeCellValue_(record[header])
        : '',
    ),
  );
}

function rowToObject_(headers, row) {
  const record = {};
  headers.forEach((header, index) => {
    record[header] = row[index];
  });
  return record;
}

function ensureHeaders_(sheet, requiredHeaders) {
  const lastColumn = sheet.getLastColumn();
  if (sheet.getLastRow() === 0 || lastColumn === 0) {
    sheet.getRange(1, 1, 1, requiredHeaders.length).setValues([requiredHeaders]);
    return;
  }
  const existing = sheet
    .getRange(1, 1, 1, lastColumn)
    .getValues()[0]
    .map((value) => String(value));
  const missing = requiredHeaders.filter((header) => !existing.includes(header));
  if (missing.length > 0) {
    sheet
      .getRange(1, lastColumn + 1, 1, missing.length)
      .setValues([missing]);
  }
}

function getHeaders_(sheet) {
  if (!sheet || sheet.getLastColumn() < 1) {
    throw new Error('Sheet is not configured. Run setupAccountPortal.');
  }
  return sheet
    .getRange(1, 1, 1, sheet.getLastColumn())
    .getValues()[0]
    .map((value) => String(value));
}

function setField_(sheet, row, headers, field, value) {
  const column = headers.indexOf(field) + 1;
  if (column < 1) throw new Error(`Missing sheet column: ${field}`);
  sheet.getRange(row, column).setValue(safeCellValue_(value));
}

function getSpreadsheet_() {
  const id =
    PropertiesService.getScriptProperties().getProperty('SPREADSHEET_ID');
  if (!id) {
    throw new Error('Spreadsheet is not configured. Run setupAccountPortal.');
  }
  return SpreadsheetApp.openById(id);
}

function getPasswordPepper_() {
  const pepper =
    PropertiesService.getScriptProperties().getProperty('PASSWORD_PEPPER');
  if (!pepper) {
    throw new Error('Password secret is missing. Run setupAccountPortal.');
  }
  return pepper;
}

function passwordHash_(password, salt, pepper) {
  return bytesToHex_(
    Utilities.computeHmacSha256Signature(
      `${salt}:${password}`,
      pepper,
      Utilities.Charset.UTF_8,
    ),
  );
}

function sha256Hex_(value) {
  return bytesToHex_(
    Utilities.computeDigest(
      Utilities.DigestAlgorithm.SHA_256,
      String(value),
      Utilities.Charset.UTF_8,
    ),
  );
}

function bytesToHex_(bytes) {
  return bytes.map((byte) => (byte + 256).toString(16).slice(-2)).join('');
}

function constantTimeEquals_(left, right) {
  const a = String(left || '');
  const b = String(right || '');
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index++) {
    difference |= (a.charCodeAt(index) || 0) ^ (b.charCodeAt(index) || 0);
  }
  return difference === 0;
}

function validateRegistration_(name, email, password, minimumPasswordLength) {
  validateNameAndEmail_(name, email);
  validatePassword_(password, minimumPasswordLength);
}

function validateNameAndEmail_(name, email) {
  if (!name || name.length > CONFIG.maxNameLength) {
    throw new Error('Enter a valid name.');
  }
  if (
    !email ||
    email.length > CONFIG.maxEmailLength ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new Error('Enter a valid email address.');
  }
}

function assertUniqueMemberName_(name, exceptUserId) {
  const normalizedName = normalizeMemberName_(name);
  const duplicate = readRecords_('Users').some(
    (user) =>
      isActive_(user.active) &&
      user.role === 'Member' &&
      String(user.id) !== String(exceptUserId || '') &&
      normalizeMemberName_(user.name) === normalizedName,
  );
  if (duplicate) {
    throw new Error(
      'An active Member account already uses this name. Member names must be unique.',
    );
  }
}

function validatePassword_(password, minimumLength) {
  if (
    password.length < minimumLength ||
    password.length > CONFIG.maxPasswordLength
  ) {
    throw new Error(
      `Password must be between ${minimumLength} and ${CONFIG.maxPasswordLength} characters.`,
    );
  }
}

function normalizePhoneNumber_(value) {
  const rawPhoneNumber = String(value || '').trim();
  if (!rawPhoneNumber) return '';
  const phoneNumber = rawPhoneNumber.replace(/[\s()+-]/g, '');
  if (!/^\d+$/.test(phoneNumber)) {
    throw new Error('Enter a valid 10-digit phone number.');
  }
  const normalized =
    phoneNumber.length === 12 && phoneNumber.startsWith('91')
      ? phoneNumber.slice(2)
      : phoneNumber;
  if (!/^\d{10}$/.test(normalized)) {
    throw new Error('Enter a valid 10-digit phone number.');
  }
  return normalized;
}

function normalizeEmail_(value) {
  return String(value || '').trim().toLowerCase();
}

function normalizeMemberName_(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

function normalizeRole_(value) {
  const role = String(value || '').trim();
  if (!['Admin', 'Collector', 'Member'].includes(role)) {
    throw new Error('Role must be Admin, Collector, or Member.');
  }
  return role;
}

function cleanText_(value, maxLength) {
  const text = String(value || '').trim();
  if (text.length > maxLength) throw new Error('A text field is too long.');
  return text;
}

function requiredText_(value, label) {
  const text = String(value || '').trim();
  if (!text) throw new Error(`${label} is required.`);
  return text;
}

function parseNonNegativeNumber_(value, label) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    throw new Error(`${label} must be a non-negative number.`);
  }
  return number;
}

function isActive_(value) {
  return value === true || String(value).toLowerCase() === 'true';
}

function isPaid_(value) {
  return value === true || value === 1 || String(value).toLowerCase() === 'true';
}

function publicUser_(user) {
  return {
    id: String(user.id),
    accountNo: String(user.accountNo || ''),
    name: String(user.name || ''),
    profileImageUrl: profileImageDataUrl_(user),
    email: String(user.email || ''),
    phoneNumber: String(user.phoneNumber || ''),
    role: String(user.role || 'Member'),
    dailyAccess: isReportAccessEnabled_(user.dailyAccess),
    weeklyAccess: isReportAccessEnabled_(user.weeklyAccess),
    monthlyAccess: isReportAccessEnabled_(user.monthlyAccess),
  };
}

function formatDate_(value) {
  if (value instanceof Date) {
    const spreadsheet = getSpreadsheet_();
    const timeZone =
      spreadsheet.getSpreadsheetTimeZone() || Session.getScriptTimeZone();
    return Utilities.formatDate(value, timeZone, 'yyyy-MM-dd');
  }
  const text = String(value || '').trim();
  if (!text) return '';
  const isoDate = text.match(/^(\d{4}-\d{2}-\d{2})(?:$|T)/);
  return isoDate ? isoDate[1] : text;
}

function formatOptionalDateTime_(value) {
  if (!value) return '';
  if (value instanceof Date) {
    const spreadsheet = getSpreadsheet_();
    const timeZone =
      spreadsheet.getSpreadsheetTimeZone() || Session.getScriptTimeZone();
    return Utilities.formatDate(value, timeZone, 'yyyy-MM-dd HH:mm:ss');
  }
  return String(value).trim();
}

function safeCellValue_(value) {
  if (typeof value !== 'string') return value;
  return /^[=+\-@]/.test(value) ? `'${value}` : value;
}

function withScriptLock_(callback) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) {
    throw new Error('The service is busy. Please try again.');
  }
  try {
    return callback();
  } finally {
    lock.releaseLock();
  }
}

function jsonOutput_(data) {
  return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(
    ContentService.MimeType.JSON,
  );
}

function safeErrorMessage_(error) {
  const message = error && error.message ? String(error.message) : '';
  return message || 'The request could not be completed.';
}