import { useCallback, useEffect, useRef, useState } from 'react';
import { getRows, loadCashfree, request } from '../api';
import type { RecordRow, Session } from '../types';
import { money, text } from '../utils';
import { Modal, PageHeading, PortalLoader } from '../components/ui';

type PaymentMember = {
  id: string;
  name: string;
  accountNo: string;
  email: string;
  phoneNumber: string;
};

type PaymentOption = {
  key: string;
  label: string;
  amount: number;
  dueDate: string;
  memberPhoneNumber: string;
  target: { kind: 'deposit' | 'loan'; id: string; periodIndex: number };
};

type PaymentSources = { deposits: boolean; loans: boolean };
type PaymentStage = 'creating' | 'checkout' | 'verifying' | null;
const PAYMENT_DATA_TIMEOUT_MS = 25_000;
const PAYMENT_VERIFICATION_TIMEOUT_MS = 35_000;

function withTimeout<T>(
  requestPromise: Promise<T>,
  message: string,
  timeoutMs = PAYMENT_DATA_TIMEOUT_MS,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timeout = window.setTimeout(() => {
      reject(new Error(message));
    }, timeoutMs);
    requestPromise.then(
      (data) => {
        window.clearTimeout(timeout);
        resolve(data);
      },
      (cause: unknown) => {
        window.clearTimeout(timeout);
        reject(cause);
      },
    );
  });
}

function phoneDigits(value: string): string {
  const digits = value.replace(/\D/g, '');
  return digits.length === 12 && digits.startsWith('91')
    ? digits.slice(2)
    : digits;
}

function paymentMemberFromRow(row: RecordRow): PaymentMember {
  return {
    id: text(row.id),
    name: text(row.name),
    accountNo: text(row.accountNo),
    email: text(row.email),
    phoneNumber: text(row.phoneNumber),
  };
}

export function PaymentsPage({
  session,
  onNotice,
  onPaymentSuccess,
}: {
  session: Session;
  onNotice: (message: string) => void;
  onPaymentSuccess: (message: string) => void;
}) {
  const isStaff = session.user.role !== 'Member';
  const [members, setMembers] = useState<PaymentMember[]>([]);
  const [memberSearch, setMemberSearch] = useState('');
  const [selectedMember, setSelectedMember] = useState<PaymentMember | null>(
    isStaff
      ? null
      : {
          id: session.user.id,
          name: session.user.name,
          accountNo: session.user.accountNo,
          email: session.user.email,
          phoneNumber: session.user.phoneNumber,
        },
  );
  const [options, setOptions] = useState<PaymentOption[]>([]);
  const [paymentSources, setPaymentSources] = useState<PaymentSources>({
    deposits: false,
    loans: false,
  });
  const [phone, setPhone] = useState(isStaff ? '' : session.user.phoneNumber);
  const [membersLoading, setMembersLoading] = useState(isStaff);
  const [loadingSchedules, setLoadingSchedules] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [paymentStage, setPaymentStage] = useState<PaymentStage>(null);
  const [orderId, setOrderId] = useState('');
  const [paymentMessage, setPaymentMessage] = useState('');
  const [selectedPayment, setSelectedPayment] = useState('');
  const [scheduleNeedsReconciliation, setScheduleNeedsReconciliation] = useState(false);
  const requestSequence = useRef(0);

  const loadMemberSchedules = useCallback(async (member: PaymentMember) => {
    const sequence = ++requestSequence.current;
    setSelectedMember(member);
    setOptions([]);
    setSelectedPayment('');
    setPhone(phoneDigits(member.phoneNumber));
    setError('');
    setPaymentMessage('');
    setScheduleNeedsReconciliation(false);
    setLoadingSchedules(true);
    try {
      const data = await withTimeout(
        request<{
          member: PaymentMember;
          payments: Array<{
            label: string;
            amount: number;
            dueDate: string;
            target: { kind: 'deposit' | 'loan'; id: string; periodIndex: number };
          }>;
          sources: PaymentSources;
        }>('getMemberPaymentData', { memberId: member.id }, session),
        'Payment data is taking too long to load. Check that the latest Apps Script is deployed, then retry.',
      );
      if (
        !data.member ||
        data.member.id !== member.id ||
        !Array.isArray(data.payments) ||
        typeof data.sources?.deposits !== 'boolean' ||
        typeof data.sources?.loans !== 'boolean'
      ) {
        throw new Error('The server returned invalid member payment data.');
      }
      const nextOptions = data.payments.map((payment): PaymentOption => {
        const amount = Number(payment.amount);
        const target = payment.target;
        if (
          !Number.isFinite(amount) ||
          amount <= 0 ||
          !target ||
          !['deposit', 'loan'].includes(target.kind) ||
          !target.id ||
          !Number.isInteger(target.periodIndex) ||
          target.periodIndex < 1
        ) {
          throw new Error('The server returned an invalid unpaid installment.');
        }
        return {
          key: `${target.kind}:${target.id}:${target.periodIndex}`,
          label: text(payment.label),
          amount,
          dueDate: text(payment.dueDate),
          memberPhoneNumber: phoneDigits(data.member.phoneNumber || member.phoneNumber),
          target,
        };
      });
      if (requestSequence.current === sequence) {
        nextOptions.sort((left, right) => left.dueDate.localeCompare(right.dueDate));
        setSelectedMember(data.member);
        setPhone(phoneDigits(data.member.phoneNumber));
        setOptions(nextOptions);
        setPaymentSources(data.sources);
        setError('');
      }
    } catch (cause) {
      if (requestSequence.current === sequence) {
        setError(
          cause instanceof Error
            ? cause.message
            : 'Could not load this member’s payment schedules.',
        );
      }
    } finally {
      if (requestSequence.current === sequence) setLoadingSchedules(false);
    }
  }, [session]);

  const loadMembers = useCallback(async () => {
    setMembersLoading(true);
    setError('');
    try {
      const rows = await withTimeout(
        getRows('getPaymentMembers', session),
        'The member list is taking too long to load. Check that the latest Apps Script is deployed, then retry.',
      );
      setMembers(
        rows
          .filter((row) => text(row.role) === 'Member')
          .map(paymentMemberFromRow)
          .filter((member) => member.id && member.name)
          .sort((left, right) => left.name.localeCompare(right.name)),
      );
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load members.');
    } finally {
      setMembersLoading(false);
    }
  }, [session]);

  useEffect(() => {
    if (!isStaff) {
      void loadMemberSchedules({
        id: session.user.id,
        name: session.user.name,
        accountNo: session.user.accountNo,
        email: session.user.email,
        phoneNumber: session.user.phoneNumber,
      });
      return;
    }
    void loadMembers();
  }, [isStaff, loadMemberSchedules, loadMembers, session]);

  const startPayment = async () => {
    const option = options.find((item) => item.key === selectedPayment);
    if (!option || !selectedMember) {
      onNotice('Choose a member and an unpaid installment first.');
      return;
    }
    const customerPhone = phoneDigits(phone);
    if (!/^\d{10}$/.test(customerPhone)) {
      onNotice('Enter a valid 10-digit mobile number.');
      return;
    }
    setBusy(true);
    setPaymentStage('creating');
    setPaymentMessage('');
    let createdOrderId = '';
    try {
      const order = await request<{
        status: string;
        orderId: string;
        paymentSessionId: string;
        environment: 'sandbox' | 'production';
      }>(
        'createCashfreeOrder',
        {
          baseAmount: option.amount.toFixed(2),
          customerPhone,
          ...(isStaff ? { memberId: selectedMember.id } : {}),
          scheduleTarget: option.target,
        },
        session,
      );
      if (
        !order.orderId ||
        !order.paymentSessionId ||
        !['sandbox', 'production'].includes(order.environment)
      ) {
        throw new Error('The server returned invalid payment details.');
      }
      createdOrderId = order.orderId;
      setOrderId(order.orderId);
      setPaymentStage('checkout');
      const sdk = await loadCashfree();
      await sdk({ mode: order.environment }).checkout({
        paymentSessionId: order.paymentSessionId,
        redirectTarget: '_modal',
      });
      setPaymentMessage(`Checkout closed for order ${order.orderId}. Checking payment status…`);
      await verifyPayment(order.orderId);
    } catch (cause) {
      if (createdOrderId) {
        setPaymentMessage(
          `Checkout could not finish for order ${createdOrderId}. Verify its status before trying another payment.`,
        );
        setPaymentStage('verifying');
      }
      onNotice(cause instanceof Error ? cause.message : 'Could not start secure payment.');
    } finally {
      setBusy(false);
      setPaymentStage(null);
    }
  };

  const verifyPayment = async (orderIdToVerify = orderId) => {
    if (!orderIdToVerify) return;
    setBusy(true);
    setPaymentStage('verifying');
    setPaymentMessage('Verifying payment with Cashfree…');
    try {
      const result = await withTimeout(
        request<{
          orderId: string;
          paid: boolean;
          paymentStatus: string;
          scheduleApplied?: boolean;
          scheduleDescription?: string;
        }>('verifyCashfreePayment', { orderId: orderIdToVerify }, session),
        'Payment verification is taking longer than expected. Do not start another payment; retry verification.',
        PAYMENT_VERIFICATION_TIMEOUT_MS,
      );
      if (result.paid && result.scheduleApplied === true) {
        setOrderId('');
        setSelectedPayment('');
        setScheduleNeedsReconciliation(false);
        onPaymentSuccess(
          result.scheduleDescription || 'Your installment payment has been received and applied.',
        );
        if (selectedMember) void loadMemberSchedules(selectedMember);
      } else if (result.paid) {
        setScheduleNeedsReconciliation(true);
        setPaymentMessage(`Cashfree confirmed the payment, but the installment was not updated. ${result.scheduleDescription || 'Contact an administrator to reconcile the payment.'}`);
        onNotice('Cashfree received the payment, but the installment needs administrator reconciliation.');
      } else {
        const status = result.paymentStatus || 'PENDING';
        setPaymentMessage(`Payment status: ${status}. The installment is not marked paid.`);
        if (['FAILED', 'EXPIRED', 'TERMINATED', 'CANCELLED'].includes(status)) {
          setOrderId('');
          setScheduleNeedsReconciliation(false);
          setPaymentMessage(`Payment status: ${status}. Select an installment to retry.`);
        }
      }
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : 'Could not verify the payment.';
      setPaymentMessage(message);
      onNotice(message);
    } finally {
      setBusy(false);
      setPaymentStage(null);
    }
  };

  const visibleMembers = members.filter((member) =>
    `${member.name} ${member.accountNo} ${member.phoneNumber}`
      .toLowerCase()
      .includes(memberSearch.trim().toLowerCase()),
  );
  const activeOption = options.find((option) => option.key === selectedPayment);

  return (
    <>
      <PageHeading
        title="Make a payment"
        subtitle={
          isStaff
            ? 'Select a member to load their unpaid deposits and loans.'
            : 'Choose one of your unpaid deposit or loan installments.'
        }
      />
      <section className={`panel payment-panel payment-workspace ${isStaff ? '' : 'payment-workspace-member'}`}>
        {isStaff && (
          <section className="payment-member-picker">
            <div className="payment-section-heading">
              <div>
                <span className="eyebrow">MEMBER</span>
                <h2>Select a member</h2>
              </div>
              {selectedMember && (
                <span className="payment-selected-count">
                  {options.length} due {options.length === 1 ? 'payment' : 'payments'}
                </span>
              )}
            </div>
            <label className="field">
              <span>Search by name, account number, or mobile</span>
              <input
                type="search"
                value={memberSearch}
                placeholder="Type a member name…"
                onChange={(event) => setMemberSearch(event.target.value)}
              />
            </label>
            {membersLoading ? (
              <div className="payment-member-loading"><PortalLoader label="Loading members" size={30} /></div>
            ) : error && members.length === 0 ? (
              <div className="payment-load-error" role="alert">
                <span>{error}</span>
                <button type="button" className="button button-secondary" onClick={() => void loadMembers()}>
                  Retry loading members
                </button>
              </div>
            ) : visibleMembers.length === 0 ? (
              <div className="payment-member-empty">
                {memberSearch.trim()
                  ? 'No members match this search.'
                  : 'No active member accounts are available.'}
              </div>
            ) : (
              <div className="payment-member-list" role="listbox" aria-label="Members">
                {visibleMembers.slice(0, 100).map((member) => (
                  <button
                    key={member.id}
                    type="button"
                    role="option"
                    disabled={busy || loadingSchedules || Boolean(orderId)}
                    aria-selected={selectedMember?.id === member.id}
                    className={`payment-member-option ${selectedMember?.id === member.id ? 'payment-member-option-active' : ''}`}
                    onClick={() => void loadMemberSchedules(member)}
                  >
                    <span className="payment-member-avatar" aria-hidden="true">
                      {member.name.trim().slice(0, 1).toUpperCase()}
                    </span>
                    <span className="payment-member-copy">
                      <strong>{member.name}</strong>
                      <small>{member.accountNo || 'Account number not available'}</small>
                      <small>{member.phoneNumber || member.email || 'Contact not provided'}</small>
                    </span>
                    {selectedMember?.id === member.id && <span className="payment-member-check" aria-hidden="true">✓</span>}
                  </button>
                ))}
                {visibleMembers.length > 100 && (
                  <p className="payment-member-limit">Showing the first 100 matches. Refine your search.</p>
                )}
              </div>
            )}
          </section>
        )}

        <section className="payment-installment-panel">
          {!selectedMember ? (
            <div className="payment-prompt">
              <span className="payment-prompt-icon" aria-hidden="true">↖</span>
              <strong>Choose a member to begin</strong>
              <span>Their available deposit and loan installments will load here.</span>
            </div>
          ) : (
            <>
              <div className="payment-section-heading payment-installment-heading">
                <div>
                  <span className="eyebrow">{selectedMember.accountNo || 'MEMBER ACCOUNT'}</span>
                  <h2>{selectedMember.name}</h2>
                </div>
                {selectedMember.phoneNumber && <span className="payment-member-phone">{selectedMember.phoneNumber}</span>}
              </div>
              <div className="payment-member-details">
                <div><span>Account number</span><strong>{selectedMember.accountNo || 'Not available'}</strong></div>
                <div><span>Mobile</span><strong>{selectedMember.phoneNumber || 'Not provided'}</strong></div>
                <div><span>Email</span><strong>{selectedMember.email || 'Not provided'}</strong></div>
              </div>
              {loadingSchedules ? (
                <div className="payment-schedules-loading">
                  <PortalLoader label="Loading deposit and loan installments" size={34} />
                  <span>Finding this member’s due payments…</span>
                </div>
              ) : error && options.length === 0 ? (
                <div className="payment-load-error" role="alert">
                  <span>{error}</span>
                  <button type="button" className="button button-secondary" disabled={busy || Boolean(orderId)} onClick={() => void loadMemberSchedules(selectedMember)}>
                    Retry loading
                  </button>
                </div>
              ) : options.length === 0 ? (
                <div className="payment-member-empty">
                  {paymentSources.deposits || paymentSources.loans
                    ? 'No unpaid installments were found in the deposit and loan accounts available to this member.'
                    : 'No deposit or loan payment access is enabled for this account.'}
                </div>
              ) : (
                <>
                  <div className="payment-options-heading">
                    <strong>Choose a deposit or loan installment</strong>
                    <span>{options.length} available</span>
                  </div>
                  <div className="payment-options-list" role="group" aria-label="Unpaid installments">
                    {options.map((option) => (
                      <button
                        key={option.key}
                        type="button"
                        className={`payment-option ${selectedPayment === option.key ? 'payment-option-selected' : ''}`}
                        aria-pressed={selectedPayment === option.key}
                        disabled={busy || Boolean(orderId)}
                        onClick={() => {
                          setSelectedPayment(option.key);
                          setPhone(phoneDigits(option.memberPhoneNumber || selectedMember.phoneNumber));
                          setPaymentMessage('');
                        }}
                      >
                        <span className="payment-option-copy">
                          <strong>{option.label}</strong>
                          <small>Due {option.dueDate || 'date not available'}</small>
                        </span>
                        <span className="payment-option-action">
                          <strong>{money(option.amount)}</strong>
                          <small>{selectedPayment === option.key ? 'Selected · View' : 'View & pay'}</small>
                        </span>
                      </button>
                    ))}
                  </div>
                </>
              )}
            </>
          )}
        </section>
      </section>
      {activeOption && selectedMember && (
        <Modal
          title="Review installment payment"
          onClose={() => {
            if (!busy && !orderId) setSelectedPayment('');
          }}
        >
          <div className="payment-modal-content">
            <div className="payment-modal-kind">
              <span aria-hidden="true">{activeOption.target.kind === 'deposit' ? '◉' : '↗'}</span>
              <div>
                <strong>{activeOption.target.kind === 'deposit' ? 'Deposit installment' : 'Loan installment'}</strong>
                <small>{activeOption.dueDate ? `Due ${activeOption.dueDate}` : 'Due date not available'}</small>
              </div>
            </div>
            <div className="payment-modal-details">
              <div><span>Member</span><strong>{selectedMember.name}</strong></div>
              <div><span>Account number</span><strong>{selectedMember.accountNo || 'Not available'}</strong></div>
              <div><span>Installment</span><strong>{activeOption.label}</strong></div>
              <div className="payment-modal-amount"><span>Amount</span><strong>{money(activeOption.amount)}</strong></div>
            </div>
            <label className="field">
              <span>Payment mobile number</span>
              <input
                type="tel"
                inputMode="numeric"
                maxLength={14}
                value={phone}
                disabled={busy || Boolean(orderId)}
                onChange={(event) => setPhone(event.target.value)}
              />
            </label>
            <p className="payment-modal-note">
              A 2% service charge is added by the server. Review the final total in Cashfree checkout.
            </p>
            <button
              type="button"
              className="button button-primary payment-submit-button"
              disabled={busy || scheduleNeedsReconciliation}
              onClick={() => void (orderId ? verifyPayment() : startPayment())}
            >
              {busy && (
                <PortalLoader
                  label={
                    paymentStage === 'verifying'
                      ? 'Verifying payment with Cashfree'
                      : paymentStage === 'checkout'
                        ? 'Opening Cashfree checkout'
                        : 'Preparing secure checkout'
                  }
                  inline
                  size={16}
                />
              )}
              {scheduleNeedsReconciliation
                ? 'Payment needs reconciliation'
                : busy
                  ? paymentStage === 'verifying'
                    ? 'Verifying payment…'
                    : paymentStage === 'checkout'
                      ? 'Opening secure checkout…'
                      : 'Preparing secure checkout…'
                  : orderId
                    ? 'Verify payment status'
                    : `Pay now · ${money(activeOption.amount)}`}
            </button>
            {paymentMessage && (
              <div className="payment-result" role="status">
                <span>{paymentMessage}</span>
                {orderId && (
                  <button type="button" className="button button-secondary" disabled={busy} onClick={() => void verifyPayment()}>
                    {busy && <PortalLoader label="Verifying payment with Cashfree" inline size={16} />}
                    {busy ? 'Verifying payment…' : 'Verify payment'}
                  </button>
                )}
              </div>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}
