import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { getRows } from '../api';
import { DEPOSIT_ROUTES, type RecordRow, type Session } from '../types';
import { hasDepositAccess, hasLedgerAccess, hasLoanAccess, hasUserAccess, money, normalize, text } from '../utils';
import { PageHeading, PortalLoader, StatePanel, Table } from '../components/ui';

type DashboardIconName = 'ledger' | 'deposits' | 'loans' | 'pending';

function DashboardIcon({ name }: { name: DashboardIconName }) {
  const icons: Record<DashboardIconName, ReactNode> = {
    ledger: <><path d="M4 5h16v14H4z" /><path d="M4 9h16M8 5v14M7 12h-1m5 0h6m-6 3h4" /></>,
    deposits: <><path d="M4 20V10m5 10V4m6 16v-7m5 7V7" /><path d="M2 20h20" /></>,
    loans: <><path d="M4 8h16v11H4zM3 8l2-4h14l2 4" /><path d="M8 12h8m-8 3h5" /></>,
    pending: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
  };
  return <svg aria-hidden="true" viewBox="0 0 24 24">{icons[name]}</svg>;
}

function DashboardMetric({ label, value, tone, icon }: { label: string; value: string; tone: 'blue' | 'green' | 'violet' | 'orange'; icon: DashboardIconName }) {
  return (
    <article className={`dashboard-metric dashboard-metric-${tone}`}>
      <span className="dashboard-metric-icon"><DashboardIcon name={icon} /></span>
      <span className="dashboard-metric-label">{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

export function Dashboard({ session }: { session: Session }) {
  const [state, setState] = useState({ loading: true, errors: [] as string[], rows: {} as Record<string, RecordRow[]> });
  const load = useCallback(async () => {
    setState({ loading: true, errors: [], rows: {} });
    const requests: [string, Promise<RecordRow[]>][] = [];
    if (hasLedgerAccess(session)) requests.push(['ledger', getRows('getAmount', session)]);
    if (hasUserAccess(session)) requests.push(['users', getRows('getUsers', session)]);
    if (hasLoanAccess(session)) requests.push(['loans', getRows('getLoans', session)]);
    if (hasDepositAccess(session)) {
      for (const route of DEPOSIT_ROUTES.filter((item) => session.user.role !== 'Member' || session.reportAccess[item.cadence] !== false)) {
        requests.push([route.page, getRows('getDepositAccounts', session, { product: route.product, cadence: route.cadence })]);
      }
    }
    const responses = await Promise.all(requests.map(async ([key, promise]) => {
      try { return { key, rows: await promise }; }
      catch (cause) { return { key, error: `${key}: ${cause instanceof Error ? cause.message : 'Unavailable'}` }; }
    }));
    setState({
      loading: false,
      errors: responses.flatMap((response) => response.error ? [response.error] : []),
      rows: Object.fromEntries(responses.flatMap((response) => response.rows ? [[response.key, response.rows]] : [])),
    });
  }, [session]);

  useEffect(() => { void load(); }, [load]);

  const ledger = state.rows.ledger ?? [];
  const deposits = Object.entries(state.rows).filter(([key]) => key.startsWith('fd-') || key.startsWith('rd-') || key.startsWith('drd-')).flatMap(([, rows]) => rows);
  const loans = state.rows.loans ?? [];
  const balance = ledger.length ? Number(ledger[ledger.length - 1].balance) || 0 : 0;
  const pendingLoans = loans.filter((loan) => normalize(loan.approvalStatus) === 'pending');
  const hasDepositData = Object.keys(state.rows).some((key) => key.startsWith('fd-') || key.startsWith('rd-') || key.startsWith('drd-'));

  return (
    <div className="dashboard-page">
      <PageHeading
        title={`Good day, ${session.user.name.split(' ')[0] || 'there'}`}
        subtitle="Your finances and account activity at a glance."
        action={<button className="button button-secondary dashboard-refresh" disabled={state.loading} onClick={() => void load()}>
          {state.loading ? <PortalLoader label="Refreshing dashboard" inline size={15} /> : <svg aria-hidden="true" viewBox="0 0 24 24"><path d="M20 7v5h-5M4 17v-5h5" /><path d="M5.6 9a7 7 0 0 1 11.8-2L20 12M4 12l2.6 5a7 7 0 0 0 11.8-2" /></svg>}
          <span>{state.loading ? 'Refreshing…' : 'Refresh'}</span>
        </button>}
      />
      <StatePanel loading={state.loading} error="" retry={() => void load()}>
        {state.errors.length > 0 && <div className="partial-warning" role="status"><strong>Some overview data is unavailable.</strong><span>{state.errors.join(' · ')}</span></div>}
        <section className="dashboard-metrics" aria-label="Finance overview">
          <DashboardMetric label="Ledger balance" value={state.rows.ledger ? money(balance) : '—'} tone="blue" icon="ledger" />
          <DashboardMetric label="Deposit accounts" value={hasDepositData ? String(deposits.length) : '—'} tone="green" icon="deposits" />
          <DashboardMetric label="Loan applications" value={state.rows.loans ? String(loans.length) : '—'} tone="violet" icon="loans" />
          <DashboardMetric label="Pending review" value={state.rows.loans ? String(pendingLoans.length) : '—'} tone="orange" icon="pending" />
        </section>
        <div className="dashboard-grid">
          <section className="panel dashboard-panel">
            <div className="panel-heading dashboard-panel-heading">
              <span className="dashboard-section-icon dashboard-section-loans"><DashboardIcon name="loans" /></span>
              <div className="dashboard-section-copy"><h2>Recent loan activity</h2><p>Latest applications and their review status</p></div>
              <span className="badge">{loans.length} total</span>
            </div>
            <Table rows={[...loans].slice(-6).reverse()} columns={[
              { key: 'memberName', label: 'Member' }, { key: 'loanType', label: 'Type' },
              { key: 'principal', label: 'Principal', render: (row) => money(row.principal) },
              { key: 'approvalStatus', label: 'Status', render: (row) => <span className={`status status-${normalize(row.approvalStatus)}`}>{text(row.approvalStatus || 'Approved')}</span> },
            ]} empty="Loan activity will appear here when available." />
          </section>
          <section className="panel dashboard-panel">
            <div className="panel-heading dashboard-panel-heading">
              <span className="dashboard-section-icon dashboard-section-deposits"><DashboardIcon name="deposits" /></span>
              <div className="dashboard-section-copy"><h2>Deposit overview</h2><p>Member deposit plans and contributions</p></div>
              <span className="badge">{deposits.length} accounts</span>
            </div>
            <Table rows={deposits.slice(0, 6)} columns={[
              { key: 'memberName', label: 'Member' }, { key: 'product', label: 'Plan' },
              { key: 'amount', label: 'Contribution', render: (row) => money(row.amount) },
              { key: 'maturityAmount', label: 'Est. maturity', render: (row) => money(row.maturityAmount) },
            ]} empty="Deposit accounts will appear here when available." />
          </section>
        </div>
      </StatePanel>
    </div>
  );
}
