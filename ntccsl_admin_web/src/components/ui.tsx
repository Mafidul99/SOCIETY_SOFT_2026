import { useEffect, useState, type CSSProperties, type FormEvent, type ReactNode } from 'react';
import { dateToday, text, type Field } from '../utils';
import type { RecordRow } from '../types';

export function Modal({
  title,
  children,
  onClose,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
}) {
  useEffect(() => {
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => window.removeEventListener('keydown', closeOnEscape);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <section className="modal" role="dialog" aria-modal="true" aria-label={title}>
        <header className="modal-heading">
          <h2>{title}</h2>
          <button type="button" className="icon-button" onClick={onClose} aria-label="Close dialog">×</button>
        </header>
        {children}
      </section>
    </div>
  );
}

export function PaymentSuccessOverlay({
  message,
  onComplete,
}: {
  message: string;
  onComplete: () => void;
}) {
  const [secondsRemaining, setSecondsRemaining] = useState(10);

  useEffect(() => {
    let remaining = 10;
    const timer = window.setInterval(() => {
      remaining -= 1;
      setSecondsRemaining(remaining);
      if (remaining <= 0) {
        window.clearInterval(timer);
        onComplete();
      }
    }, 1000);
    return () => window.clearInterval(timer);
  }, [onComplete]);

  return (
    <div className="payment-success-backdrop">
      <section className="payment-success-modal" role="alertdialog" aria-modal="true" aria-labelledby="payment-success-title" aria-describedby="payment-success-message">
        <div className="payment-success-icon" aria-hidden="true">✓</div>
        <h2 id="payment-success-title">Payment successful</h2>
        <p id="payment-success-message">{message}</p>
        <div className="payment-success-countdown" role="status">
          Returning to Make a Payment in <strong>{secondsRemaining}</strong> seconds…
        </div>
      </section>
    </div>
  );
}

export function RecordForm({
  title,
  fields,
  initial = {},
  busy,
  openingBalance,
  onClose,
  onSubmit,
}: {
  title: string;
  fields: Field[];
  initial?: Record<string, unknown>;
  busy?: boolean;
  openingBalance?: number;
  onClose: () => void;
  onSubmit: (values: Record<string, string | boolean>) => Promise<void>;
}) {
  const [values, setValues] = useState<Record<string, string | boolean>>(() =>
    Object.fromEntries(fields.map((field) => [
      field.name,
      field.type === 'checkbox'
        ? initial[field.name] === undefined
          ? ['dailyAccess', 'weeklyAccess', 'monthlyAccess'].includes(field.name)
          : initial[field.name] === true || text(initial[field.name]).toLowerCase() === 'true'
        : text(initial[field.name] ?? (field.name === 'date' || field.name === 'startDate' ? dateToday() : '')),
    ])),
  );
  const [error, setError] = useState('');
  const updateField = (name: string, value: string | boolean) => {
    const next = { ...values, [name]: value };
    if (openingBalance !== undefined && (name === 'deposit' || name === 'withdrawal')) {
      next.balance = (
        openingBalance + (Number(next.deposit) || 0) - (Number(next.withdrawal) || 0)
      ).toFixed(2);
    }
    setValues(next);
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError('');
    try {
      await onSubmit(values);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'The request could not be completed.');
    }
  };

  return (
    <Modal title={title} onClose={onClose}>
      <form className="record-form" onSubmit={submit}>
        <div className="form-grid">
          {fields.map((field) => (
            <label className={`field ${field.type === 'checkbox' ? 'field-checkbox' : ''}`} key={field.name}>
              {field.type === 'checkbox' ? (
                <>
                  <input
                    type="checkbox"
                    checked={Boolean(values[field.name])}
                    onChange={(event) => updateField(field.name, event.target.checked)}
                  />
                  <span>{field.label}</span>
                </>
              ) : (
                <>
                  <span>{field.label}{field.required ? ' *' : ''}</span>
                  {field.type === 'select' ? (
                    <select
                      required={field.required}
                      value={text(values[field.name])}
                      onChange={(event) => updateField(field.name, event.target.value)}
                    >
                      <option value="">Choose…</option>
                      {(field.options ?? []).map((option) => (
                        <option value={option.value} key={option.value}>{option.label}</option>
                      ))}
                    </select>
                  ) : (
                    <input
                      type={field.type ?? 'text'}
                      required={field.required}
                      readOnly={field.readOnly}
                      min={field.min}
                      max={field.max}
                      step={field.step}
                      placeholder={field.placeholder}
                      value={text(values[field.name])}
                      onChange={(event) => setValues({ ...values, [field.name]: event.target.value })}
                    />
                  )}
                </>
              )}
            </label>
          ))}
        </div>
        {error && <p className="form-error" role="alert">{error}</p>}
        <footer className="modal-actions">
          <button type="button" className="button button-quiet" onClick={onClose}>Cancel</button>
          <button className="button button-primary" disabled={busy}>{busy && <PortalLoader label="Saving" inline size={16} />}{busy ? 'Saving…' : 'Save changes'}</button>
        </footer>
      </form>
    </Modal>
  );
}

export function PageHeading({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return (
    <div className="page-heading">
      <div><p className="eyebrow">NTCCSL FINANCE SYSTEM</p><h1>{title}</h1>{subtitle && <p className="muted">{subtitle}</p>}</div>
      {action}
    </div>
  );
}

export function PortalLoader({
  label = 'Loading',
  detail,
  size = 112,
  inline = false,
}: {
  label?: string;
  detail?: string;
  size?: number;
  inline?: boolean;
}) {
  const scale = size / 112;
  const dotCount = 28;
  const dots = Array.from({ length: dotCount }, (_, index) => {
    const angle = (index / dotCount) * Math.PI * 2 - Math.PI / 2;
    const distance = Math.min(index, dotCount - index);
    const intensity = Math.max(0.12, 1 - distance / 10);
    return {
      x: 56 + Math.cos(angle) * 48.16 * 0.64,
      y: 56 + Math.sin(angle) * 48.16 * 0.64,
      intensity,
      radius: (2.2 + intensity * 1.25) * scale,
      glow: intensity > 0.78,
    };
  });

  return (
    <span
      className={`portal-loader ${inline ? 'portal-loader-inline' : ''}`}
      style={{ '--loader-size': `${size}px`, '--loader-scale': scale } as CSSProperties}
      role="status"
      aria-live="polite"
      aria-label={label}
    >
      <span className="portal-loader-orbit" aria-hidden="true">
        <svg viewBox="0 0 112 112" focusable="false">
          <circle className="portal-loader-track" cx="56" cy="56" r="48.16" />
          <circle className="portal-loader-arc" cx="56" cy="56" r="48.16" />
          <g className="portal-loader-dots">
            {dots.map((dot, index) => (
              <g key={index}>
                {dot.glow && <circle className="portal-loader-dot-glow" cx={dot.x} cy={dot.y} r={5.2 * scale} />}
                <circle
                  className="portal-loader-dot"
                  cx={dot.x}
                  cy={dot.y}
                  r={dot.radius}
                  fill={`color-mix(in srgb, var(--loader-accent) ${dot.intensity * 100}%, var(--loader-track))`}
                  opacity={inline ? dot.intensity : 1}
                />
              </g>
            ))}
          </g>
          <circle className="portal-loader-center-glow" cx="56" cy="56" r={48.16 * 0.31} />
          <circle className="portal-loader-center-dot" cx="56" cy="56" r={3 * scale} />
        </svg>
      </span>
      <span className="portal-loader-copy">
        <strong>{label}</strong>
        {detail !== undefined && <small>{detail}</small>}
      </span>
    </span>
  );
}

export type ToastType = 'success' | 'info' | 'warning' | 'error';

export function Toast({
  message,
  type,
  onDismiss,
}: {
  message: string;
  type: ToastType;
  onDismiss: () => void;
}) {
  const icons: Record<ToastType, ReactNode> = {
    success: <path d="m5 12 4 4L19 6" />,
    info: <><circle cx="12" cy="12" r="9" /><path d="M12 11v5m0-8h.01" /></>,
    warning: <><path d="M12 3 2.8 19h18.4L12 3Z" /><path d="M12 9v4m0 3h.01" /></>,
    error: <><circle cx="12" cy="12" r="9" /><path d="m9 9 6 6m0-6-6 6" /></>,
  };

  return (
    <div className={`toast toast-${type}`} role={type === 'error' ? 'alert' : 'status'} aria-live={type === 'error' ? 'assertive' : 'polite'} aria-atomic="true">
      <span className="toast-icon" aria-hidden="true"><svg viewBox="0 0 24 24">{icons[type]}</svg></span>
      <span className="toast-copy"><strong>{type === 'success' ? 'Success' : type === 'warning' ? 'Check this' : type === 'error' ? 'Something went wrong' : 'Notice'}</strong><span>{message}</span></span>
      <button type="button" className="toast-close" onClick={onDismiss} aria-label="Dismiss notification">×</button>
      <span className="toast-progress" aria-hidden="true" />
    </div>
  );
}

export function StatCard({ label, value, tone = 'blue' }: { label: string; value: string; tone?: string }) {
  return <article className={`stat-card tone-${tone}`}><span>{label}</span><strong>{value}</strong></article>;
}

export function Table({
  columns,
  rows,
  empty = 'No records found.',
}: {
  columns: { key: string; label: string; render?: (row: RecordRow) => ReactNode }[];
  rows: RecordRow[];
  empty?: string;
}) {
  if (!rows.length) return <div className="empty-state"><strong>Nothing here yet</strong><span>{empty}</span></div>;
  return (
    <div className="table-scroll">
      <table>
        <thead><tr>{columns.map((column) => <th key={column.key}>{column.label}</th>)}</tr></thead>
        <tbody>{rows.map((row, index) => (
          <tr key={`${text(row.id || row.__rowIndex || row.rowIndex || row.orderId || 'record')}-${index}`}>
            {columns.map((column) => <td key={column.key}>{column.render ? column.render(row) : text(row[column.key]) || '—'}</td>)}
          </tr>
        ))}</tbody>
      </table>
    </div>
  );
}

export function StatePanel({
  loading,
  error,
  retry,
  children,
}: {
  loading: boolean;
  error: string;
  retry: () => void;
  children: ReactNode;
}) {
  if (loading) return <div className="state-panel state-loading"><PortalLoader label="Loading portal data…" detail="SECURE FINANCE PORTAL" size={64} /></div>;
  if (error) return <div className="state-panel state-error"><strong>Could not load this page</strong><span>{error}</span><button className="button button-secondary" onClick={retry}>Try again</button></div>;
  return <>{children}</>;
}

export function RowActions({
  edit,
  remove,
  editDisabled = false,
  removeDisabled = false,
  removeBusyLabel,
}: {
  edit?: () => void;
  remove?: () => void;
  editDisabled?: boolean;
  removeDisabled?: boolean;
  removeBusyLabel?: string;
}) {
  if (!edit && !remove) return <span className="muted">—</span>;
  return <div className="row-actions">
    {edit && <button type="button" className="row-action-button row-action-edit" aria-label="Edit" title="Edit" disabled={editDisabled} onClick={edit}>
      <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M12 20h9" /><path d="m16.5 3.5 4 4L8 20l-5 1 1-5Z" /></svg>
    </button>}
    {remove && <button type="button" className="row-action-button row-action-delete" aria-label="Delete" title="Delete" disabled={removeDisabled} onClick={remove}>
      {removeBusyLabel && removeDisabled
        ? <PortalLoader label={removeBusyLabel} inline size={16} />
        : <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M4 7h16M10 11v6m4-6v6M5.5 7l1 14h11l1-14M9 7V4h6v3" /></svg>}
    </button>}
  </div>;
}
