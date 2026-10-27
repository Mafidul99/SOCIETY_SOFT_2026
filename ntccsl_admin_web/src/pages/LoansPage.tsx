import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { getRows, loadCashfree, mutate, request } from '../api';
import type { LoanPayment, RecordRow, Session } from '../types';
import { allows, dateToday, money, normalize, text } from '../utils';
import { Modal, PageHeading, PortalLoader, RowActions, StatePanel, Table } from '../components/ui';

export function LoanForm({
  session,
  row,
  defaultType,
  schemes,
  onClose,
  onSave,
}: {
  session: Session;
  row?: RecordRow;
  defaultType?: 'personal' | 'gold';
  schemes: RecordRow[];
  onClose: () => void;
  onSave: (payload: Record<string, unknown>) => Promise<void>;
}) {
  const loanTypes = (['personal', 'gold'] as const);
  const [loanType, setLoanType] = useState<'personal' | 'gold'>(
    defaultType ?? (normalize(row?.loanType) === 'gold' ? 'gold' : 'personal'),
  );
  const [schemeId, setSchemeId] = useState(text(row?.schemeId));
  const [memberName, setMemberName] = useState(session.user.role === 'Member' ? session.user.name : text(row?.memberName));
  const [startDate, setStartDate] = useState(text(row?.startDate) || dateToday());
  const [principal, setPrincipal] = useState(text(row?.principal));
  const [annualRate, setAnnualRate] = useState(text(row?.annualRate));
  const [tenureYears, setTenureYears] = useState(text(row?.tenureYears || 1));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const options = schemes.filter((scheme) => normalize(scheme.loanType) === loanType && (scheme.active === true || scheme.active === 'TRUE' || scheme.active === undefined || row?.schemeId === scheme.schemeId));
  const currentScheme = options.find((scheme) => text(scheme.schemeId) === schemeId);

  useEffect(() => {
    if (!options.some((scheme) => text(scheme.schemeId) === schemeId)) {
      setSchemeId(text(options[0]?.schemeId));
    }
  }, [options, schemeId]);

  const submit = async (event: FormEvent) => {
    event.preventDefault(); setBusy(true); setError('');
    try {
      await onSave({
        ...(row ? { id: row.id } : {}),
        schemeId, loanType, memberName, startDate,
        principal: Number(principal), annualRate: Number(annualRate), tenureYears: Number(tenureYears),
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The loan could not be saved.');
    } finally { setBusy(false); }
  };

  return <Modal title={row ? 'Edit loan' : 'New loan application'} onClose={onClose}>
    <form className="record-form" onSubmit={submit}>
      <div className="form-grid">
        {session.user.role !== 'Member' && !defaultType && <label className="field"><span>Loan category *</span>
          <select value={loanType} onChange={(event) => setLoanType(event.target.value as 'personal' | 'gold')}>
            {loanTypes.map((type) => <option value={type} key={type}>{type === 'personal' ? 'Personal loan' : 'Gold loan'}</option>)}
          </select>
        </label>}
        {session.user.role !== 'Member' && <label className="field"><span>Member name *</span><input required value={memberName} onChange={(event) => setMemberName(event.target.value)} /></label>}
        <label className="field"><span>Loan scheme *</span><select required value={schemeId} onChange={(event) => setSchemeId(event.target.value)}>
          <option value="">Choose a scheme…</option>{options.map((scheme) => <option key={text(scheme.schemeId)} value={text(scheme.schemeId)}>{text(scheme.schemeName)}</option>)}
        </select></label>
        <label className="field"><span>Application date *</span><input required type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} /></label>
        <label className="field"><span>Principal amount (₹) *</span><input required type="number" min={currentScheme?.minAmount === undefined ? 1 : Number(currentScheme.minAmount)} max={currentScheme?.maxAmount === undefined ? 1000000000 : Number(currentScheme.maxAmount)} step="0.01" value={principal} onChange={(event) => setPrincipal(event.target.value)} /></label>
        <label className="field"><span>Annual rate (%) *</span><input required type="number" min={currentScheme?.minAnnualRate === undefined ? 18 : Number(currentScheme.minAnnualRate)} max={currentScheme?.maxAnnualRate === undefined ? 37 : Number(currentScheme.maxAnnualRate)} step="0.01" value={annualRate} onChange={(event) => setAnnualRate(event.target.value)} /></label>
        <label className="field"><span>Tenure (years) *</span><input required type="number" min={currentScheme?.minTenureYears === undefined ? 1 : Number(currentScheme.minTenureYears)} max={currentScheme?.maxTenureYears === undefined ? 7 : Number(currentScheme.maxTenureYears)} step="1" value={tenureYears} onChange={(event) => setTenureYears(event.target.value)} /></label>
      </div>
      {currentScheme && <p className="form-hint">Repayment method: {normalize(currentScheme.calculationMethod) === 'interest_only' ? 'Interest EMI' : 'Fixed EMI'}. The server calculates repayment and fees from the selected scheme.</p>}
      {error && <p className="form-error" role="alert">{error}</p>}
      <footer className="modal-actions"><button type="button" className="button button-quiet" onClick={onClose}>Cancel</button><button className="button button-primary" disabled={busy || options.length === 0}>{busy && <PortalLoader label="Saving loan" inline size={16} />}{busy ? 'Saving…' : row ? 'Save loan' : 'Submit application'}</button></footer>
    </form>
  </Modal>;
}

export function SchemeForm({
  row,
  onClose,
  onSave,
}: {
  row?: RecordRow;
  onClose: () => void;
  onSave: (payload: Record<string, unknown>) => Promise<void>;
}) {
  const [name, setName] = useState(text(row?.schemeName));
  const [loanType, setLoanType] = useState(text(row?.loanType) || 'personal');
  const [minAmount, setMinAmount] = useState(text(row?.minAmount || 1));
  const [maxAmount, setMaxAmount] = useState(text(row?.maxAmount || 1000000000));
  const [minRate, setMinRate] = useState(text(row?.minAnnualRate || 18));
  const [maxRate, setMaxRate] = useState(text(row?.maxAnnualRate || 37));
  const [minYears, setMinYears] = useState(text(row?.minTenureYears || 1));
  const [maxYears, setMaxYears] = useState(text(row?.maxTenureYears || 7));
  const [fileFee, setFileFee] = useState(text(row?.fileChargePercent || 0));
  const [processingFee, setProcessingFee] = useState(text(row?.processingFeePercent || 0));
  const [calculationMethod, setCalculationMethod] = useState(text(row?.calculationMethod || 'fixed_emi'));
  const [active, setActive] = useState(row ? row.active === true || text(row.active).toLowerCase() === 'true' : true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const submit = async (event: FormEvent) => {
    event.preventDefault(); setBusy(true); setError('');
    try {
      await onSave({
        ...(row ? { schemeId: row.schemeId } : {}),
        schemeName: name, loanType, minAmount: Number(minAmount), maxAmount: Number(maxAmount),
        minAnnualRate: Number(minRate), maxAnnualRate: Number(maxRate),
        minTenureYears: Number(minYears), maxTenureYears: Number(maxYears),
        fileChargePercent: Number(fileFee), processingFeePercent: Number(processingFee),
        calculationMethod: loanType === 'gold' ? calculationMethod : 'fixed_emi', active,
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The scheme could not be saved.');
    } finally { setBusy(false); }
  };
  const numberField = (label: string, value: string, onChange: (value: string) => void, min = 0, max?: number, step = '0.01') => (
    <label className="field" key={label}><span>{label}</span><input type="number" required min={min} max={max} step={step} value={value} onChange={(event) => onChange(event.target.value)} /></label>
  );
  return <Modal title={row ? 'Edit loan scheme' : 'Add loan scheme'} onClose={onClose}>
    <form className="record-form" onSubmit={submit}>
      <div className="form-grid">
        <label className="field"><span>Scheme name *</span><input required value={name} onChange={(event) => setName(event.target.value)} /></label>
        <label className="field"><span>Loan type *</span><select value={loanType} onChange={(event) => setLoanType(event.target.value)}><option value="personal">Personal</option><option value="gold">Gold</option></select></label>
        {numberField('Minimum amount (₹)', minAmount, setMinAmount, 1, 1000000000)}
        {numberField('Maximum amount (₹)', maxAmount, setMaxAmount, 1, 1000000000)}
        {numberField('Minimum annual rate (%)', minRate, setMinRate, 18, 37)}
        {numberField('Maximum annual rate (%)', maxRate, setMaxRate, 18, 37)}
        {numberField('Minimum term (years)', minYears, setMinYears, 1, 7, '1')}
        {numberField('Maximum term (years)', maxYears, setMaxYears, 1, 7, '1')}
        {numberField('File charge (%)', fileFee, setFileFee, 0, 100)}
        {numberField('Processing fee (%)', processingFee, setProcessingFee, 0, 100)}
        {loanType === 'gold' && <label className="field"><span>Repayment method</span><select value={calculationMethod} onChange={(event) => setCalculationMethod(event.target.value)}><option value="fixed_emi">Fixed EMI</option><option value="interest_only">Interest EMI</option></select></label>}
        <label className="field field-checkbox"><input type="checkbox" checked={active} onChange={(event) => setActive(event.target.checked)} /><span>Scheme is active</span></label>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
      <footer className="modal-actions"><button type="button" className="button button-quiet" onClick={onClose}>Cancel</button><button className="button button-primary" disabled={busy}>{busy && <PortalLoader label="Saving scheme" inline size={16} />}{busy ? 'Saving…' : 'Save scheme'}</button></footer>
    </form>
  </Modal>;
}

export function LoanPage({
  session,
  page,
  onNotice,
  onPaymentSuccess,
}: {
  session: Session;
  page: string;
  onNotice: (message: string) => void;
  onPaymentSuccess: (message: string) => void;
}) {
  const master = page === 'loan-master';
  const approvedOnly = page === 'approved-loans';
  const loanType = page === 'personal-loan' ? 'personal' : page === 'gold-loan' ? 'gold' : undefined;
  const [loans, setLoans] = useState<RecordRow[]>([]);
  const [schemes, setSchemes] = useState<RecordRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [formRow, setFormRow] = useState<RecordRow | undefined>();
  const [creating, setCreating] = useState(false);
  const [schemeRow, setSchemeRow] = useState<RecordRow | null | undefined>(undefined);
  const [schedules, setSchedules] = useState<Record<string, LoanPayment[]>>({});
  const [scheduleMembers, setScheduleMembers] = useState<
    Record<string, { memberId: string; memberPhoneNumber: string }>
  >({});
  const [loadingSchedules, setLoadingSchedules] = useState<Set<string>>(() => new Set());
  const [scheduleErrors, setScheduleErrors] = useState<Record<string, string>>({});
  const [pendingLoanActions, setPendingLoanActions] = useState<Set<string>>(() => new Set());
  const [expandedId, setExpandedId] = useState('');
  const [paymentPhone, setPaymentPhone] = useState(session.user.phoneNumber);
  const [paymentBusy, setPaymentBusy] = useState(false);
  const [paymentMessage, setPaymentMessage] = useState('');
  const [cashfreeOrder, setCashfreeOrder] = useState<{
    orderId: string;
    paymentSessionId: string;
    environment: 'sandbox' | 'production';
    loanId: string;
    periodIndex: number;
  } | null>(null);
  const [paymentNeedsReconciliation, setPaymentNeedsReconciliation] =
    useState(false);
  const canAdd = allows(session, 'loan_add');
  const canEdit = allows(session, 'loan_edit');
  const canDelete = allows(session, 'loan_delete');
  const canReview = allows(session, 'loan_update');
  const canPayOnline =
    session.user.role === 'Member' ||
    allows(session, 'shared_data_read') ||
    allows(session, 'user_view');
  const isAdmin = session.user.role === 'Admin';
  const load = useCallback(async () => {
    setLoading(true); setError('');
    try {
      const [loanRows, schemeRows] = await Promise.all([
        getRows('getLoans', session, { ...(loanType ? { loanType } : {}), ...(approvedOnly ? { approvedOnly: true } : {}) }),
        isAdmin || canAdd ? getRows('getLoanSchemes', session, { ...(loanType ? { loanType } : {}), ...(isAdmin && master ? { includeInactive: true } : {}) }) : Promise.resolve([]),
      ]);
      setLoans(loanRows); setSchemes(schemeRows);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Loan data is unavailable.');
    } finally { setLoading(false); }
  }, [approvedOnly, canAdd, isAdmin, loanType, master, session]);
  useEffect(() => { void load(); }, [load]);

  const saveLoan = async (payload: Record<string, unknown>) => {
    await mutate(payload.id ? 'editLoan' : 'addLoan', session, payload);
    setFormRow(undefined); setCreating(false); onNotice(payload.id ? 'Loan updated. It is pending review.' : 'Loan application submitted.'); await load();
  };
  const saveScheme = async (payload: Record<string, unknown>) => {
    await mutate(payload.schemeId ? 'editLoanScheme' : 'addLoanScheme', session, payload);
    setSchemeRow(undefined); onNotice('Loan scheme saved.'); await load();
  };
  const removeLoan = async (row: RecordRow) => {
    if (!window.confirm('Delete this loan record?')) return;
    const actionKey = `delete:${text(row.id)}`;
    setPendingLoanActions((current) => new Set(current).add(actionKey));
    try { await mutate('deleteLoan', session, { id: row.id }); onNotice('Loan record deleted.'); await load(); }
    catch (cause) { onNotice(cause instanceof Error ? cause.message : 'Could not delete loan.'); }
    finally {
      setPendingLoanActions((current) => {
        const next = new Set(current);
        next.delete(actionKey);
        return next;
      });
    }
  };
  const reviewLoan = async (row: RecordRow, approvalStatus: 'Approved' | 'Rejected') => {
    const actionKey = `review:${text(row.id)}`;
    setPendingLoanActions((current) => new Set(current).add(actionKey));
    try {
      await mutate('approveLoan', session, { id: row.id, approvalStatus });
      onNotice(`Loan ${approvalStatus.toLowerCase()}.`);
      await load();
    } catch (cause) { onNotice(cause instanceof Error ? cause.message : 'Could not update approval status.'); }
    finally {
      setPendingLoanActions((current) => {
        const next = new Set(current);
        next.delete(actionKey);
        return next;
      });
    }
  };
  const removeScheme = async (row: RecordRow) => {
    if (!window.confirm(`Delete scheme "${text(row.schemeName)}"?`)) return;
    try { await mutate('deleteLoanScheme', session, { schemeId: row.schemeId }); onNotice('Loan scheme deleted.'); await load(); }
    catch (cause) { onNotice(cause instanceof Error ? cause.message : 'Could not delete scheme.'); }
  };
  const togglePayment = async (loanId: string, periodIndex: number) => {
    const actionKey = `payment:${loanId}:${periodIndex}`;
    setPendingLoanActions((current) => new Set(current).add(actionKey));
    try {
      await mutate('toggleLoanPayment', session, { id: loanId, periodIndex });
      const schedule = await request<{ payments: LoanPayment[] }>('getLoanPaymentSchedule', { id: loanId }, session);
      setSchedules((current) => ({ ...current, [loanId]: schedule.payments }));
      onNotice('Loan payment updated.');
    }
    catch (cause) { onNotice(cause instanceof Error ? cause.message : 'Could not update payment.'); }
    finally {
      setPendingLoanActions((current) => {
        const next = new Set(current);
        next.delete(actionKey);
        return next;
      });
    }
  };
  const toggleSchedule = async (loanId: string) => {
    setExpandedId(loanId);
    setPaymentMessage('');
    setPaymentPhone(
      text(scheduleMembers[loanId]?.memberPhoneNumber) ||
        session.user.phoneNumber,
    );
    if (!schedules[loanId]) {
      setLoadingSchedules((current) => new Set(current).add(loanId));
      setScheduleErrors((current) => ({ ...current, [loanId]: '' }));
      try {
        const schedule = await request<{
          payments: LoanPayment[];
          memberId?: string;
          memberPhoneNumber?: string;
        }>('getLoanPaymentSchedule', { id: loanId }, session);
        setSchedules((current) => ({ ...current, [loanId]: schedule.payments }));
        setScheduleMembers((current) => ({
          ...current,
          [loanId]: {
            memberId: text(schedule.memberId),
            memberPhoneNumber: text(schedule.memberPhoneNumber),
          },
        }));
        setPaymentPhone(
          text(schedule.memberPhoneNumber) || session.user.phoneNumber,
        );
      } catch (cause) {
        const message = cause instanceof Error ? cause.message : 'Could not load payment schedule.';
        setScheduleErrors((current) => ({ ...current, [loanId]: message }));
        onNotice(message);
      } finally {
        setLoadingSchedules((current) => {
          const next = new Set(current);
          next.delete(loanId);
          return next;
        });
      }
    }
  };

  const selectedLoan = loans.find((loan) => text(loan.id) === expandedId);
  const selectedSchedule = schedules[expandedId] || [];
  const nextUnpaidIndex = selectedSchedule.findIndex((payment) => !payment.paid);
  const selectedScheduleMember = scheduleMembers[expandedId];
  const cashfreeOrderMatchesLoan =
    Boolean(selectedLoan) && cashfreeOrder?.loanId === expandedId;
  const cashfreeOrderIsNextPayment =
    cashfreeOrderMatchesLoan &&
    nextUnpaidIndex >= 0 &&
    cashfreeOrder?.periodIndex === selectedSchedule[nextUnpaidIndex]?.periodIndex;
  const cashfreeOrderPaymentMarked =
    cashfreeOrderMatchesLoan &&
    Boolean(
      selectedSchedule.find(
        (payment) => payment.periodIndex === cashfreeOrder?.periodIndex,
      )?.paid,
    );

  const payNextLoanInstallment = async () => {
    if (!selectedLoan || nextUnpaidIndex < 0 || !selectedScheduleMember) return;
    if (cashfreeOrder) {
      if (cashfreeOrder.loanId === expandedId && cashfreeOrderIsNextPayment) {
        await openLoanCashfreeCheckout(cashfreeOrder);
      }
      return;
    }
    const phone = paymentPhone.replace(/\D/g, '');
    if (!/^\d{10}$/.test(phone)) {
      onNotice('Enter a valid 10-digit mobile number.');
      return;
    }
    const payment = selectedSchedule[nextUnpaidIndex];
    setPaymentBusy(true);
    setPaymentMessage('');
    try {
      const order = await request<{
        orderId: string;
        paymentSessionId: string;
        environment: 'sandbox' | 'production';
      }>('createCashfreeOrder', {
        baseAmount: payment.installmentAmount.toFixed(2),
        customerPhone: phone,
        ...(session.user.role !== 'Member'
          ? { memberId: selectedScheduleMember.memberId }
          : {}),
        scheduleTarget: {
          kind: 'loan',
          id: expandedId,
          periodIndex: payment.periodIndex,
        },
      }, session);
      if (
        !order.orderId ||
        !order.paymentSessionId ||
        !['sandbox', 'production'].includes(order.environment)
      ) {
        throw new Error('The server returned invalid Cashfree payment details.');
      }
      const activeOrder = {
        ...order,
        loanId: expandedId,
        periodIndex: payment.periodIndex,
      };
      setCashfreeOrder(activeOrder);
      setPaymentNeedsReconciliation(false);
      setPaymentMessage(`Cashfree order ${order.orderId} is ready.`);
      await openLoanCashfreeCheckout(activeOrder);
    } catch (cause) {
      onNotice(cause instanceof Error ? cause.message : 'Could not start secure Cashfree payment.');
    } finally {
      setPaymentBusy(false);
    }
  };

  const openLoanCashfreeCheckout = async (order: {
    orderId: string;
    paymentSessionId: string;
    environment: 'sandbox' | 'production';
    loanId: string;
    periodIndex: number;
  }) => {
    setPaymentBusy(true);
    try {
      const sdk = await loadCashfree();
      await sdk({ mode: order.environment }).checkout({
        paymentSessionId: order.paymentSessionId,
        redirectTarget: '_modal',
      });
      setPaymentMessage(`Checkout closed for order ${order.orderId}. Checking payment status…`);
      await verifyLoanCashfreePayment(order);
    } catch (cause) {
      setPaymentMessage(`Checkout did not complete for order ${order.orderId}. Resume checkout or verify payment.`);
      onNotice(cause instanceof Error ? cause.message : 'Could not open Cashfree checkout.');
    } finally {
      setPaymentBusy(false);
    }
  };

  const verifyLoanCashfreePayment = async (
    orderToVerify: { orderId: string; loanId: string } | null = cashfreeOrder,
  ) => {
    if (!orderToVerify) return;
    setPaymentBusy(true);
    try {
      const result = await request<{
        orderId: string;
        paid: boolean;
        paymentStatus: string;
        scheduleApplied?: boolean;
        scheduleDescription?: string;
      }>('verifyCashfreePayment', { orderId: orderToVerify.orderId }, session);
      if (result.paid && result.scheduleApplied === true) {
        setPaymentMessage(`Payment verified. ${result.scheduleDescription || 'The loan installment is updated.'}`);
        setCashfreeOrder((current) => current?.orderId === orderToVerify.orderId ? null : current);
        setPaymentNeedsReconciliation(false);
        onNotice('Cashfree payment verified and loan installment updated.');
        onPaymentSuccess(
          result.scheduleDescription || 'Your loan installment payment has been received and applied.',
        );
        const schedule = await request<{ payments: LoanPayment[] }>(
          'getLoanPaymentSchedule',
          { id: orderToVerify.loanId },
          session,
        );
        setSchedules((current) => ({
          ...current,
          [orderToVerify.loanId]: schedule.payments,
        }));
      } else if (result.paid) {
        setPaymentNeedsReconciliation(true);
        setPaymentMessage(`Cashfree received the payment, but the loan schedule was not updated. ${result.scheduleDescription || 'Contact an administrator to reconcile this payment.'}`);
        onNotice('Cashfree received the payment, but the loan schedule needs administrator reconciliation.');
      } else {
        const status = result.paymentStatus || 'PENDING';
        setPaymentMessage(`Payment status: ${status}. The installment is not marked paid.`);
        if (['FAILED', 'EXPIRED', 'TERMINATED', 'CANCELLED'].includes(status)) {
          setCashfreeOrder((current) => current?.orderId === orderToVerify.orderId ? null : current);
        }
      }
    } catch (cause) {
      onNotice(cause instanceof Error ? cause.message : 'Could not verify the Cashfree payment.');
    } finally {
      setPaymentBusy(false);
    }
  };

  const filteredLoans = loans.filter((loan) => !approvedOnly || normalize(loan.approvalStatus || 'Approved') === 'approved');
  const title = master ? 'Loan master' : approvedOnly ? 'Approved loans' : `${loanType === 'gold' ? 'Gold' : 'Personal'} loans`;
  const subtitle = master ? 'Review applications and maintain loan products and terms.' : approvedOnly ? 'Approved accounts and repayment progress.' : 'Review loans, repayment schedules, and applications.';
  const loanColumns = [
    { key: 'loanNumber', label: 'Loan no.' },
    { key: 'memberName', label: 'Member' },
    { key: 'schemeName', label: 'Scheme' },
    { key: 'principal', label: 'Principal', render: (row: RecordRow) => money(row.principal) },
    { key: 'monthlyInstallment', label: 'Installment', render: (row: RecordRow) => money(row.monthlyInstallment) },
    { key: 'approvalStatus', label: 'Status', render: (row: RecordRow) => <span className={`status status-${normalize(row.approvalStatus || 'approved')}`}>{text(row.approvalStatus || 'Approved')}</span> },
    { key: 'actions', label: 'Actions', render: (row: RecordRow) => <div className="row-actions">
      {normalize(row.approvalStatus) === 'pending' && canReview && <><button className="text-button" disabled={pendingLoanActions.has(`review:${text(row.id)}`)} onClick={() => void reviewLoan(row, 'Approved')}>{pendingLoanActions.has(`review:${text(row.id)}`) && <PortalLoader label="Updating loan" inline size={15} />}Approve</button><button className="text-button danger-text" disabled={pendingLoanActions.has(`review:${text(row.id)}`)} onClick={() => void reviewLoan(row, 'Rejected')}>Reject</button></>}
      <RowActions
        edit={canEdit ? () => setFormRow(row) : undefined}
        remove={canDelete ? () => void removeLoan(row) : undefined}
        removeDisabled={pendingLoanActions.has(`delete:${text(row.id)}`)}
        removeBusyLabel="Deleting loan"
      />
      {normalize(row.approvalStatus || 'approved') === 'approved' && <button type="button" className="button button-secondary loan-schedule-button" onClick={() => void toggleSchedule(text(row.id))}>View schedule</button>}
    </div> },
  ];
  return <>
    <PageHeading title={title} subtitle={subtitle} action={canAdd && !master && <button className="button button-primary" onClick={() => setCreating(true)}>＋ New loan</button>} />
    {master && isAdmin && <section className="panel scheme-panel">
      <div className="panel-heading"><div><h2>Loan schemes</h2><p className="muted">Rates, limits, terms, and disbursement charges</p></div><button className="button button-secondary" onClick={() => setSchemeRow(null)}>＋ Add scheme</button></div>
      <StatePanel loading={loading} error={error} retry={() => void load()}><Table rows={schemes} columns={[
        { key: 'schemeName', label: 'Scheme' }, { key: 'loanType', label: 'Type' },
        { key: 'minAmount', label: 'Amount range', render: (row) => `${money(row.minAmount)} – ${money(row.maxAmount)}` },
        { key: 'minAnnualRate', label: 'Rate range', render: (row) => `${text(row.minAnnualRate)}% – ${text(row.maxAnnualRate)}%` },
        { key: 'calculationMethod', label: 'Method', render: (row) => normalize(row.calculationMethod) === 'interest_only' ? 'Interest EMI' : 'Fixed EMI' },
        { key: 'active', label: 'Status', render: (row) => <span className={`status ${row.active === false || text(row.active).toLowerCase() === 'false' ? 'status-rejected' : 'status-approved'}`}>{row.active === false || text(row.active).toLowerCase() === 'false' ? 'Inactive' : 'Active'}</span> },
        { key: 'actions', label: 'Actions', render: (row) => <RowActions edit={() => setSchemeRow(row)} remove={() => void removeScheme(row)} /> },
      ]} empty="No schemes configured." /></StatePanel>
    </section>}
    <section className="panel loan-panel">
      <div className="panel-heading"><h2>{master ? 'Application queue' : `${title} records`}</h2><span className="badge">{filteredLoans.length} records</span></div>
      <StatePanel loading={loading} error={error} retry={() => void load()}>
        <Table rows={filteredLoans} columns={loanColumns} empty={canAdd ? 'Submit a loan application to get started.' : 'There are no loan records to show.'} />
      </StatePanel>
    </section>
    {selectedLoan && <Modal
      title={`Repayment schedule · ${text(selectedLoan.loanNumber || selectedLoan.memberName)}`}
      onClose={() => setExpandedId('')}
    >
      <div className="schedule-popup-summary">
        <div><span>Loan type</span><strong>{text(selectedLoan.loanType)}</strong></div>
        <div><span>Principal</span><strong>{money(selectedLoan.principal)}</strong></div>
        <div><span>Repayment method</span><strong>{normalize(selectedLoan.repaymentMethod) === 'interest_only' ? 'Interest EMI' : 'Fixed EMI'}</strong></div>
      </div>
      {loadingSchedules.has(expandedId) ? (
        <div className="state-panel state-loading"><PortalLoader label="Loading repayment schedule…" size={48} /></div>
      ) : scheduleErrors[expandedId] ? (
        <div className="state-panel state-error">
          <span>{scheduleErrors[expandedId]}</span>
          <button type="button" className="button button-secondary" onClick={() => void toggleSchedule(expandedId)}>Try again</button>
        </div>
      ) : (
        <>
          {(canReview || canPayOnline) && selectedSchedule.length > 0 && (
            <section className="schedule-popup-next schedule-popup-next-online">
              <span>
                {paymentNeedsReconciliation
                  ? `Cashfree confirmed order ${cashfreeOrder?.orderId || ''}, but the installment was not updated. Do not pay again; contact an administrator.`
                  : cashfreeOrder && !cashfreeOrderMatchesLoan
                    ? `Cashfree order ${cashfreeOrder.orderId} is pending for another loan. Verify it from that loan schedule before starting a new payment.`
                    : cashfreeOrderPaymentMarked
                      ? `Installment ${cashfreeOrder?.periodIndex} is marked paid. Verify Cashfree order ${cashfreeOrder?.orderId} before making another payment.`
                      : nextUnpaidIndex >= 0
                        ? `Next due: installment ${selectedSchedule[nextUnpaidIndex].periodIndex} · ${money(selectedSchedule[nextUnpaidIndex].installmentAmount)}`
                        : 'All loan installments are paid.'}
              </span>
              {canPayOnline && (
                <div className="cashfree-payment-actions">
                  <label className="field">
                    <span>Payment mobile number</span>
                    <input type="tel" inputMode="numeric" maxLength={10} value={paymentPhone} disabled={Boolean(cashfreeOrder)} onChange={(event) => setPaymentPhone(event.target.value)} />
                  </label>
                  <p className="payment-note">A 2% service charge is added by the server. Review the total in Cashfree checkout.</p>
                  <div className="cashfree-payment-buttons">
                    <button
                      type="button"
                      className="button button-primary pay-next-installment-button"
                      disabled={nextUnpaidIndex < 0 || paymentBusy || paymentNeedsReconciliation || (Boolean(cashfreeOrder) && !cashfreeOrderIsNextPayment)}
                      onClick={() => void payNextLoanInstallment()}
                    >
                      {paymentBusy && <PortalLoader label="Preparing Cashfree checkout" inline size={15} />}
                      {cashfreeOrder
                        ? paymentNeedsReconciliation
                          ? 'Payment needs reconciliation'
                          : cashfreeOrderIsNextPayment
                            ? `Resume Cashfree checkout · ${money(selectedSchedule[nextUnpaidIndex].installmentAmount)}`
                            : 'Pending payment must be verified'
                        : `Pay next Cashfree · ${nextUnpaidIndex >= 0 ? money(selectedSchedule[nextUnpaidIndex].installmentAmount) : money(0)}`}
                    </button>
                    {cashfreeOrder && cashfreeOrderMatchesLoan && (
                      <button type="button" className="button button-secondary" disabled={paymentBusy || paymentNeedsReconciliation} onClick={() => void verifyLoanCashfreePayment()}>
                        Verify payment
                      </button>
                    )}
                  </div>
                  {paymentMessage && (!cashfreeOrder || cashfreeOrderMatchesLoan || paymentNeedsReconciliation) && <div className="payment-result" role="status">{paymentMessage}</div>}
                </div>
              )}
              {!canPayOnline && canReview && nextUnpaidIndex >= 0 && (
                <button
                  type="button"
                  className="button button-primary pay-next-installment-button"
                  disabled={pendingLoanActions.has(`payment:${expandedId}:${selectedSchedule[nextUnpaidIndex].periodIndex}`)}
                  onClick={() => void togglePayment(expandedId, selectedSchedule[nextUnpaidIndex].periodIndex)}
                >
                  Mark next installment paid
                </button>
              )}
            </section>
          )}
          {selectedSchedule.length === 0 ? (
            <div className="empty-state"><strong>No repayment schedule</strong><span>There are no installments in this loan schedule.</span></div>
          ) : (
            <div className="table-scroll schedule-popup-table">
              <table>
                <thead><tr><th>#</th><th>Due date</th><th>Principal</th><th>Interest</th><th>Installment</th><th>Status</th></tr></thead>
                <tbody>{selectedSchedule.map((payment) => {
                  const actionKey = `payment:${expandedId}:${payment.periodIndex}`;
                  return <tr key={payment.periodIndex}>
                    <td>{payment.periodIndex}</td><td>{payment.dueDate}</td>
                    <td>{money(payment.principalAmount)}</td><td>{money(payment.interestAmount)}</td><td>{money(payment.installmentAmount)}</td>
                    <td>{canReview ? <button type="button" className={`status status-button ${payment.paid ? 'status-paid' : 'status-neutral'}`} disabled={pendingLoanActions.has(actionKey)} onClick={() => void togglePayment(expandedId, payment.periodIndex)}>{pendingLoanActions.has(actionKey) && <PortalLoader label="Updating installment" inline size={14} />}{payment.paid ? 'Paid · mark unpaid' : 'Unpaid · mark paid'}</button> : <span className={`status ${payment.paid ? 'status-paid' : 'status-neutral'}`}>{text(payment.status || (payment.paid ? 'Paid' : 'Due'))}</span>}</td>
                  </tr>;
                })}</tbody>
              </table>
            </div>
          )}
        </>
      )}
    </Modal>}
    {(creating || formRow) && <LoanForm session={session} row={formRow} defaultType={loanType} schemes={schemes}
      onClose={() => { setCreating(false); setFormRow(undefined); }} onSave={saveLoan} />}
    {schemeRow !== undefined && <SchemeForm row={schemeRow ?? undefined} onClose={() => setSchemeRow(undefined)} onSave={saveScheme} />}
  </>;
}
