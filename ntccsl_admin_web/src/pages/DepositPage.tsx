import { useCallback, useEffect, useState } from "react";
import { getRows, loadCashfree, mutate, request } from "../api";
import type { DepositRoute, RecordRow, Session } from "../types";
import { allows, money, normalize, text, dateToday } from "../utils";
import {
  PageHeading,
  Modal,
  PortalLoader,
  RecordForm,
  RowActions,
  StatePanel,
  StatCard,
} from "../components/ui";

function DepositAvatar({ name, imageUrl }: { name: string; imageUrl: string }) {
  const [imageFailed, setImageFailed] = useState(false);
  useEffect(() => setImageFailed(false), [imageUrl]);
  const initial = name.trim().slice(0, 1).toUpperCase() || "M";

  return (
    <span className="avatar deposit-avatar">
      {imageUrl && !imageFailed ? (
        <img
          src={imageUrl}
          alt=""
          loading="lazy"
          decoding="async"
          onError={() => setImageFailed(true)}
        />
      ) : (
        initial
      )}
    </span>
  );
}

export function DepositPage({
  session,
  route,
  onNotice,
  onPaymentSuccess,
}: {
  session: Session;
  route: DepositRoute;
  onNotice: (message: string) => void;
  onPaymentSuccess: (message: string) => void;
}) {
  const [rows, setRows] = useState<RecordRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [formRow, setFormRow] = useState<RecordRow | null | undefined>(
    undefined,
  );
  const [busy, setBusy] = useState(false);
  const [pendingInstallment, setPendingInstallment] = useState("");
  const [selectedScheduleId, setSelectedScheduleId] = useState("");
  const [paymentPhone, setPaymentPhone] = useState(session.user.phoneNumber);
  const [paymentBusy, setPaymentBusy] = useState(false);
  const [cashfreeOrder, setCashfreeOrder] = useState<{
    orderId: string;
    paymentSessionId: string;
    environment: "sandbox" | "production";
    depositId: string;
    periodIndex: number;
  } | null>(null);
  const [cashfreeNeedsReconciliation, setCashfreeNeedsReconciliation] =
    useState(false);
  const [paymentMessage, setPaymentMessage] = useState("");
  const [query, setQuery] = useState("");
  const canWrite = session.user.role !== "Member";
  const canView = allows(session, "deposit_view");
  const canAdd = canWrite && allows(session, "deposit_add");
  const canEdit = canWrite && allows(session, "deposit_edit");
  const canDelete = canWrite && allows(session, "deposit_delete");
  const canUpdate = canWrite && allows(session, "deposit_update");
  const canPayOnline =
    session.user.role === "Member" ||
    allows(session, "shared_data_read") ||
    allows(session, "user_view");
  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      setRows(
        await getRows("getDepositAccounts", session, {
          product: route.product,
          cadence: route.cadence,
        }),
      );
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Deposit accounts are unavailable.",
      );
    } finally {
      setLoading(false);
    }
  }, [route.cadence, route.product, session]);
  useEffect(() => {
    void load();
  }, [load]);

  const save = async (values: Record<string, string | boolean>) => {
    setBusy(true);
    try {
      const editing = Boolean(formRow);
      await mutate(
        editing ? "editDepositAccount" : "addDepositAccount",
        session,
        {
          ...(editing ? { id: formRow?.id } : {}),
          memberName: values.memberName,
          product: route.product,
          cadence: route.cadence,
          startDate: values.startDate,
          amount: values.amount,
          annualRate: values.annualRate,
          tenureMonths: values.tenureMonths,
        },
      );
      setFormRow(undefined);
      onNotice(
        editing ? "Deposit account updated." : "Deposit account created.",
      );
      await load();
    } finally {
      setBusy(false);
    }
  };
  const remove = async (row: RecordRow) => {
    if (
      !window.confirm(
        `Delete the ${route.product} account for ${text(row.memberName)}? This also deletes its payment history.`,
      )
    )
      return;
    try {
      await mutate("deleteDepositAccount", session, { id: row.id });
      onNotice("Deposit account deleted.");
      await load();
    } catch (cause) {
      onNotice(
        cause instanceof Error
          ? cause.message
          : "Could not delete this account.",
      );
    }
  };
  const togglePayment = async (row: RecordRow, periodIndex: number) => {
    const actionKey = `${text(row.id)}:${periodIndex}`;
    setPendingInstallment(actionKey);
    try {
      await mutate("toggleDepositPayment", session, {
        id: row.id,
        periodIndex,
      });
      onNotice(`Installment ${periodIndex} updated.`);
      await load();
    } catch (cause) {
      onNotice(
        cause instanceof Error
          ? cause.message
          : "Could not update installment.",
      );
    } finally {
      setPendingInstallment("");
    }
  };
  const payNextInstallment = async () => {
    if (!selectedSchedule || nextUnpaidIndex < 0) return;
    if (cashfreeOrder) {
      if (
        cashfreeOrder.depositId === text(selectedSchedule.id) &&
        cashfreeOrder.periodIndex === nextUnpaidIndex + 1
      ) {
        await openCashfreeCheckout(cashfreeOrder);
      }
      return;
    }

    const phone = paymentPhone.replace(/\D/g, "");
    if (!/^\d{10}$/.test(phone)) {
      onNotice("Enter a valid 10-digit mobile number.");
      return;
    }

    setPaymentBusy(true);
    setPaymentMessage("");
    try {
      const order = await request<{
        status: string;
        orderId: string;
        paymentSessionId: string;
        environment: "sandbox" | "production";
      }>(
        "createCashfreeOrder",
        {
          baseAmount: (Number(selectedSchedule.amount) || 0).toFixed(2),
          customerPhone: phone,
          ...(session.user.role !== "Member"
            ? { memberId: text(selectedSchedule.memberId) }
            : {}),
          scheduleTarget: {
            kind: "deposit",
            id: text(selectedSchedule.id),
            periodIndex: nextUnpaidIndex + 1,
          },
        },
        session,
      );
      if (
        !order.orderId ||
        !order.paymentSessionId ||
        !["sandbox", "production"].includes(order.environment)
      ) {
        throw new Error("The server returned invalid Cashfree payment details.");
      }
      const activeOrder = {
        ...order,
        depositId: text(selectedSchedule.id),
        periodIndex: nextUnpaidIndex + 1,
      };
      setCashfreeOrder(activeOrder);
      setCashfreeNeedsReconciliation(false);
      setPaymentMessage(
        `Cashfree order ${order.orderId} is ready. Complete checkout, then verify the payment status.`,
      );
      await openCashfreeCheckout(activeOrder);
    } catch (cause) {
      onNotice(
        cause instanceof Error
          ? cause.message
          : "Could not start secure Cashfree payment.",
      );
    } finally {
      setPaymentBusy(false);
    }
  };
  const openCashfreeCheckout = async (order: {
    orderId: string;
    paymentSessionId: string;
    environment: "sandbox" | "production";
  }) => {
    setPaymentBusy(true);
    try {
      const sdk = await loadCashfree();
      await sdk({ mode: order.environment }).checkout({
        paymentSessionId: order.paymentSessionId,
        redirectTarget: "_modal",
      });
      setPaymentMessage(
        `Checkout closed for order ${order.orderId}. Checking payment status…`,
      );
      await verifyCashfreePayment(order);
    } catch (cause) {
      setPaymentMessage(
        `Checkout did not complete for order ${order.orderId}. You can resume checkout or verify its status.`,
      );
      onNotice(
        cause instanceof Error
          ? cause.message
          : "Could not open Cashfree checkout.",
      );
    } finally {
      setPaymentBusy(false);
    }
  };
  const verifyCashfreePayment = async (
    orderToVerify: { orderId: string } | null = cashfreeOrder,
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
      }>("verifyCashfreePayment", { orderId: orderToVerify.orderId }, session);
      if (result.paid) {
        if (result.scheduleApplied === true) {
          setPaymentMessage(
            `Payment verified. ${result.scheduleDescription || "The installment has been updated."}`,
          );
          setCashfreeOrder((current) =>
            current?.orderId === orderToVerify.orderId ? null : current,
          );
          setCashfreeNeedsReconciliation(false);
          onNotice("Cashfree payment verified and installment updated.");
          onPaymentSuccess(
            result.scheduleDescription || "Your installment payment has been received and applied.",
          );
          await load();
        } else {
          setCashfreeNeedsReconciliation(true);
          setPaymentMessage(
            `Cashfree confirmed this payment, but the installment was not updated. ${result.scheduleDescription || "Contact an administrator to reconcile the payment."}`,
          );
          onNotice(
            "Cashfree received the payment, but the installment needs administrator reconciliation.",
          );
        }
      } else {
        const status = result.paymentStatus || "PENDING";
        setPaymentMessage(
          `Payment status: ${status}. The installment is not marked paid.`,
        );
        if (["FAILED", "EXPIRED", "TERMINATED", "CANCELLED"].includes(status)) {
          setCashfreeOrder((current) =>
            current?.orderId === orderToVerify.orderId ? null : current,
          );
          setPaymentMessage(
            `Payment status: ${status}. Start a new checkout to pay this installment.`,
          );
        }
      }
    } catch (cause) {
      onNotice(
        cause instanceof Error
          ? cause.message
          : "Could not verify the Cashfree payment.",
      );
    } finally {
      setPaymentBusy(false);
    }
  };

  const filtered = rows.filter(
    (row) =>
      !query ||
      normalize(row.memberName).includes(normalize(query)),
  );
  const paid = rows.reduce(
    (sum, row) =>
      sum +
      (Array.isArray(row.payments)
        ? row.payments.filter(Boolean).length
        : Number(row.paid_count) || 0),
    0,
  );
  const scheduled = rows.reduce(
    (sum, row) =>
      sum +
      (Array.isArray(row.payments)
        ? row.payments.length
        : Number(row.payment_count) || 0),
    0,
  );
  const selectedSchedule = rows.find(
    (row) => text(row.id) === selectedScheduleId,
  );
  const selectedPayments = Array.isArray(selectedSchedule?.payments)
    ? selectedSchedule.payments
    : [];
  const selectedDates = Array.isArray(selectedSchedule?.periodDates)
    ? selectedSchedule.periodDates
    : [];
  const selectedPaid = selectedPayments.filter(Boolean).length;
  const nextUnpaidIndex = selectedPayments.findIndex((isPaid) => !isPaid);
  const cashfreeOrderMatchesSchedule =
    Boolean(selectedSchedule) &&
    cashfreeOrder?.depositId === text(selectedSchedule?.id);
  const cashfreeOrderIsNextInstallment =
    cashfreeOrderMatchesSchedule &&
    cashfreeOrder?.periodIndex === nextUnpaidIndex + 1 &&
    nextUnpaidIndex >= 0;
  const cashfreeOrderInstallmentPaid =
    cashfreeOrderMatchesSchedule &&
    Boolean(selectedPayments[cashfreeOrder?.periodIndex
      ? cashfreeOrder.periodIndex - 1
      : -1]);
  const nextInstallmentPending =
    nextUnpaidIndex >= 0 &&
    pendingInstallment === `${selectedScheduleId}:${nextUnpaidIndex + 1}`;

  return (
    <>
      <PageHeading
        title={route.title}
        subtitle={`${route.product === "FD" ? "Fixed deposit" : route.product === "RD" ? "Recurring deposit" : "Daily recurring deposit"} · Track contributions and estimated maturity.`}
        action={
          canAdd && (
            <button
              className="button button-primary"
              onClick={() => setFormRow(null)}
            >
              ＋ New account
            </button>
          )
        }
      />
      {canView && (
        <div className="stats-grid stats-grid-small">
          <StatCard label="Accounts" value={String(rows.length)} />
          <StatCard
            label="Installments paid"
            value={`${paid} / ${scheduled}`}
            tone="green"
          />
          <StatCard
            label="Estimated maturity"
            value={money(
              rows.reduce(
                (sum, row) => sum + (Number(row.maturityAmount) || 0),
                0,
              ),
            )}
            tone="violet"
          />
        </div>
      )}
      <section className="panel">
        {canView && (
          <div className="panel-toolbar">
            <label className="search-field">
              <span>⌕</span>
              <input
                placeholder="Search member"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
              />
            </label>
          </div>
        )}
        <StatePanel loading={loading} error={error} retry={() => void load()}>
          {canView ? (
            <div className="account-list">
            {filtered.map((row, index) => {
              const payments = Array.isArray(row.payments) ? row.payments : [];
              const currentPaid = payments.filter(Boolean).length;
              return (
                <article className="account-card" key={text(row.id)}>
                  <div className="account-card-main">
                    <DepositAvatar
                      name={text(row.memberName)}
                      imageUrl={text(row.profileImageUrl)}
                    />
                    <div className="account-title">
                      <strong>{text(row.memberName) || "Member"}</strong>
                      <span>
                        SL No. {index + 1} · {route.product} {route.cadence}
                      </span>
                    </div>
                    <span className="status status-neutral">
                      {currentPaid}/
                      {payments.length || Number(row.payment_count) || 0} paid
                    </span>
                    <RowActions
                      edit={canEdit ? () => setFormRow(row) : undefined}
                      remove={canDelete ? () => void remove(row) : undefined}
                    />
                  </div>
                  <div className="account-metrics">
                    <div>
                      <span>
                        {route.product === "FD" ? "Principal" : "Installment"}
                      </span>
                      <strong>{money(row.amount)}</strong>
                    </div>
                    <div>
                      <span>Rate / tenure</span>
                      <strong>
                        {text(row.annualRate)}% · {text(row.tenureMonths)}{" "}
                        months
                      </strong>
                    </div>
                    <div>
                      <span>Maturity date</span>
                      <strong>{text(row.maturityDate) || "—"}</strong>
                    </div>
                    <div>
                      <span>Estimated maturity</span>
                      <strong>{money(row.maturityAmount)}</strong>
                    </div>
                  </div>
                  {payments.length > 0 && (
                    <div className="schedule-details">
                      <div className="schedule-toggle-row">
                        <button
                          type="button"
                          className="button button-primary schedule-toggle"
                          onClick={() => {
                            setSelectedScheduleId(text(row.id));
                            setPaymentPhone(
                              text(row.memberPhoneNumber) ||
                                session.user.phoneNumber,
                            );
                          }}
                        >
                          <span className="schedule-toggle-label">
                            <svg aria-hidden="true" viewBox="0 0 24 24">
                              <rect
                                x="4"
                                y="5"
                                width="16"
                                height="15"
                                rx="2"
                              />
                              <path d="M8 3v4m8-4v4M4 10h16M8 14h3m-3 3h7" />
                            </svg>
                            View installment schedule
                          </span>
                        </button>
                        <span className="schedule-toggle-count">
                          <span className="schedule-count-paid">
                            {currentPaid} paid
                          </span>
                          <span aria-hidden="true">·</span>
                          <span className="schedule-count-due">
                            {payments.length - currentPaid} due
                          </span>
                        </span>
                      </div>
                    </div>
                  )}
                </article>
              );
            })}
            {!filtered.length && (
              <div className="empty-state">
                <strong>No accounts found</strong>
                <span>
                  {query
                    ? "Try a different search."
                    : "Create an account to start tracking deposits."}
                </span>
              </div>
            )}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Deposit accounts are not visible</strong>
              <span>
                Your assigned permissions allow deposit actions, but viewing
                existing accounts requires Deposit view permission.
              </span>
            </div>
          )}
        </StatePanel>
      </section>
      {selectedSchedule && selectedPayments.length > 0 && (
        <Modal
          title={`Installment schedule · ${text(selectedSchedule.memberName) || "Member"}`}
          onClose={() => setSelectedScheduleId("")}
        >
          <div className="schedule-popup-summary">
            <div>
              <span>Product</span>
              <strong>
                {route.product} · {route.cadence}
              </strong>
            </div>
            <div>
              <span>Installment amount</span>
              <strong>{money(selectedSchedule.amount)}</strong>
            </div>
            <div>
              <span>Progress</span>
              <strong>
                {selectedPaid} of {selectedPayments.length} paid
              </strong>
            </div>
          </div>
          {(canUpdate || canPayOnline) && (
            <div
              className={`schedule-popup-next ${canPayOnline ? "schedule-popup-next-online" : ""}`}
            >
              <span>
                {cashfreeNeedsReconciliation
                  ? `Cashfree received order ${cashfreeOrder?.orderId || ""}, but the schedule needs administrator reconciliation. Do not pay this installment again.`
                  : cashfreeOrder && !cashfreeOrderMatchesSchedule
                  ? `A Cashfree order is pending for installment ${cashfreeOrder.periodIndex}. Reopen that account's schedule to resume or verify payment.`
                  : cashfreeOrderInstallmentPaid
                    ? `Installment ${cashfreeOrder.periodIndex} is marked paid. Verify Cashfree order ${cashfreeOrder.orderId} before making another payment.`
                    : nextUnpaidIndex >= 0
                      ? `Next due: installment ${nextUnpaidIndex + 1} · ${money(selectedSchedule.amount)}`
                      : "All installments are paid."}
              </span>
              {canPayOnline ? (
                <div className="cashfree-payment-actions">
                  <label className="field">
                    <span>Payment mobile number</span>
                    <input
                      type="tel"
                      inputMode="numeric"
                      maxLength={10}
                      value={paymentPhone}
                      disabled={Boolean(cashfreeOrder)}
                      onChange={(event) => setPaymentPhone(event.target.value)}
                    />
                  </label>
                  <p className="payment-note">
                    A 2% service charge is added by the server. Review the
                    total in Cashfree checkout.
                  </p>
                  <div className="cashfree-payment-buttons">
                    <button
                      type="button"
                      className="button button-primary pay-next-installment-button"
                      disabled={
                        nextUnpaidIndex < 0 ||
                        paymentBusy ||
                        Boolean(pendingInstallment) ||
                        cashfreeNeedsReconciliation ||
                        (Boolean(cashfreeOrder) &&
                          !cashfreeOrderIsNextInstallment)
                      }
                      onClick={() => void payNextInstallment()}
                    >
                      {paymentBusy && (
                        <PortalLoader
                          label={cashfreeOrder ? "Opening checkout" : "Preparing payment"}
                          inline
                          size={15}
                        />
                      )}
                      {cashfreeOrder
                        ? cashfreeNeedsReconciliation
                          ? "Payment needs reconciliation"
                          : cashfreeOrderIsNextInstallment
                          ? `Resume Cashfree checkout · ${money(selectedSchedule.amount)}`
                          : "Pending payment must be verified"
                        : `Pay next Cashfree · ${money(selectedSchedule.amount)}`}
                    </button>
                    {cashfreeOrder && cashfreeOrderMatchesSchedule && (
                      <button
                        type="button"
                        className="button button-secondary"
                        disabled={paymentBusy || cashfreeNeedsReconciliation}
                        onClick={() => void verifyCashfreePayment()}
                      >
                        Verify payment
                      </button>
                    )}
                  </div>
                  {paymentMessage &&
                    (!cashfreeOrder ||
                      cashfreeOrderMatchesSchedule ||
                      cashfreeNeedsReconciliation) && (
                      <div className="payment-result" role="status">
                        {paymentMessage}
                      </div>
                    )}
                </div>
              ) : (
                <button
                  type="button"
                  className="button button-primary"
                  disabled={
                    nextUnpaidIndex < 0 ||
                    Boolean(pendingInstallment) ||
                    paymentBusy
                  }
                  onClick={() => {
                    if (nextUnpaidIndex >= 0) {
                      void togglePayment(selectedSchedule, nextUnpaidIndex + 1);
                    }
                  }}
                >
                  {nextInstallmentPending && (
                    <PortalLoader
                      label="Updating next installment"
                      inline
                      size={15}
                    />
                  )}
                  Mark next installment paid
                </button>
              )}
            </div>
          )}
          <div className="table-scroll schedule-popup-table">
            <table>
              <thead>
                <tr>
                  <th>SL No.</th>
                  <th>Due date</th>
                  <th>Amount</th>
                  <th>Status</th>
                  {canUpdate && <th>Action</th>}
                </tr>
              </thead>
              <tbody>
                {selectedPayments.map((isPaid, periodIndex) => {
                  const periodIndexOneBased = periodIndex + 1;
                  const actionKey = `${selectedScheduleId}:${periodIndexOneBased}`;
                  const isPending = pendingInstallment === actionKey;
                  return (
                    <tr key={periodIndexOneBased}>
                      <td>{periodIndexOneBased}</td>
                      <td>
                        {text(selectedDates[periodIndex]) ||
                          `Period ${periodIndexOneBased}`}
                      </td>
                      <td>{money(selectedSchedule.amount)}</td>
                      <td>
                        <span
                          className={`status ${isPaid ? "status-paid" : "status-neutral"}`}
                        >
                          {isPaid ? "Paid" : "Due"}
                        </span>
                      </td>
                      {canUpdate && (
                        <td>
                          <button
                            type="button"
                            className={`button ${isPaid ? "button-secondary" : "button-primary"} installment-action`}
                            disabled={isPending}
                            onClick={() =>
                              void togglePayment(
                                selectedSchedule,
                                periodIndexOneBased,
                              )
                            }
                          >
                            {isPending && (
                              <PortalLoader
                                label="Updating installment"
                                inline
                                size={15}
                              />
                            )}
                            {isPaid ? "Mark unpaid" : "Mark paid"}
                          </button>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Modal>
      )}
      {formRow !== undefined && (
        <RecordForm
          title={formRow ? "Edit deposit account" : "Create deposit account"}
          busy={busy}
          initial={
            formRow ?? {
              startDate: dateToday(),
              tenureMonths: 12,
              annualRate: 0,
            }
          }
          onClose={() => setFormRow(undefined)}
          onSubmit={save}
          fields={[
            { name: "memberName", label: "Member name", required: true },
            {
              name: "startDate",
              label: "Start date",
              type: "date",
              required: true,
            },
            {
              name: "amount",
              label:
                route.product === "FD"
                  ? "Principal amount"
                  : "Installment amount",
              type: "number",
              min: 1,
              step: "0.01",
              required: true,
            },
            {
              name: "annualRate",
              label: "Annual rate (%)",
              type: "number",
              min: 0,
              max: 100,
              step: "0.01",
              required: true,
            },
            {
              name: "tenureMonths",
              label: "Tenure (months)",
              type: "number",
              min: 1,
              max: 120,
              step: "1",
              required: true,
            },
          ]}
        />
      )}
    </>
  );
}
