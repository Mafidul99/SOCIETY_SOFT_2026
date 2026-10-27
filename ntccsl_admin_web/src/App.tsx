import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { DEPOSIT_ROUTES, type Session } from './types';
import { allows, hasDepositAccess, hasLedgerAccess, hasLoanAccess, hasUserAccess } from './utils';
import { LoginScreen } from './pages/AuthPage';
import { Dashboard } from './pages/DashboardPage';
import { LedgerPage } from './pages/LedgerPage';
import { DepositPage } from './pages/DepositPage';
import { UsersPage } from './pages/UsersPage';
import { RolesPage } from './pages/RolesPage';
import { LoanPage } from './pages/LoansPage';
import { ProfilePage } from './pages/ProfilePage';
import { PaymentsPage } from './pages/PaymentsPage';
import { SupportPage } from './pages/SupportPage';
import { PaymentSuccessOverlay, Toast, type ToastType } from './components/ui';

const routeNames: Record<string, string> = {
  dashboard: 'Dashboard',
  ledger: 'Bank ledger',
  users: 'Users',
  roles: 'Roles & permissions',
  'loan-master': 'Loan master',
  'personal-loan': 'Personal loans',
  'gold-loan': 'Gold loans',
  'approved-loans': 'Approved loans',
  payments: 'Payments',
  profile: 'My profile',
  support: 'Help & support',
};

type NavigationIconName =
  | 'dashboard'
  | 'ledger'
  | 'fd-monthly'
  | 'rd-weekly'
  | 'rd-monthly'
  | 'drd-daily'
  | 'drd-weekly'
  | 'drd-monthly'
  | 'loan-master'
  | 'personal-loan'
  | 'gold-loan'
  | 'approved-loans'
  | 'users'
  | 'roles'
  | 'payments'
  | 'profile'
  | 'support';

type ToastNotice = { id: number; message: string; type: ToastType };

function noticeType(message: string): ToastType {
  if (/\b(enter a valid|choose .+ first|select .+ first|you cannot)\b/i.test(message)) return 'warning';
  if (/\b(could not|cannot|can't|failed|failure|error|invalid|unable to|not allowed|not authorized|not found|already exists|must be|expired|incorrect|denied)\b/i.test(message)) return 'error';
  if (/\b(success|updated|saved|created|added|deleted|removed|submitted|changed|approved|rejected|deactivated|signed in|registration)\b/i.test(message)) return 'success';
  return 'info';
}

function NavigationIcon({ name }: { name: NavigationIconName }) {
  const common = { fill: 'none', stroke: 'currentColor', strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const, strokeWidth: 1.8 };
  const paths: Record<NavigationIconName, ReactNode> = {
    dashboard: <><rect x="3.5" y="3.5" width="7" height="7" rx="1.5" /><rect x="13.5" y="3.5" width="7" height="4.5" rx="1.5" /><rect x="13.5" y="11" width="7" height="9.5" rx="1.5" /><rect x="3.5" y="13" width="7" height="7.5" rx="1.5" /></>,
    ledger: <><path d="M4 5.5h16M4 10.5h16M4 15.5h16M7 3.5v14M17 5.5v15" /><path d="M4 20.5h16" /></>,
    'fd-monthly': <><path d="M12 3.5v17M16.5 7.5c-.7-1.1-2-1.8-4.1-1.8-2.4 0-4 1.1-4 2.8 0 4.4 8.1 1.8 8.1 6.3 0 1.8-1.7 3.1-4.4 3.1-2.1 0-3.7-.7-4.6-2" /><circle cx="12" cy="12" r="9.5" /></>,
    'rd-weekly': <><rect x="4" y="5.5" width="16" height="15" rx="2" /><path d="M8 3.5v4M16 3.5v4M4 10h16M8 14h2M14 14h2M8 17h2" /></>,
    'rd-monthly': <><path d="M5 4.5h14v16H5zM8 2.5v4M16 2.5v4M5 9h14" /><path d="M8 13h2M14 13h2M8 16.5h2M14 16.5h2" /></>,
    'drd-daily': <><circle cx="12" cy="12" r="9.5" /><path d="M12 7v5l3.5 2M5.5 4.5l-2 2M18.5 4.5l2 2" /></>,
    'drd-weekly': <><path d="M4 7.5h16M6 4.5h12M6 10.5h12M8 13.5h8M10 16.5h4" /><circle cx="12" cy="12" r="9.5" /></>,
    'drd-monthly': <><rect x="3.5" y="4.5" width="17" height="16" rx="2" /><path d="M7.5 2.5v4M16.5 2.5v4M3.5 9h17M8 13h2M14 13h2M8 16.5h2M14 16.5h2" /></>,
    'loan-master': <><path d="M4 8.5h16v11H4zM3 8.5l2-5h14l2 5M8 13h8M8 16.5h5" /><path d="M8 3.5v5M16 3.5v5" /></>,
    'personal-loan': <><circle cx="9" cy="8" r="3.5" /><path d="M3 20c.5-3.5 2.5-5.5 6-5.5s5.5 2 6 5.5M17 8h4M19 6v4M17 15.5c2.2.4 3.5 1.9 4 4.5" /></>,
    'gold-loan': <><path d="M12 3.5 20 8v8l-8 4.5L4 16V8z" /><path d="m4.5 8.3 7.5 4.4 7.5-4.4M12 12.7v7.5M8.2 5.7l7.6 4.4" /></>,
    'approved-loans': <><circle cx="12" cy="12" r="9.5" /><path d="m7.5 12 3 3 6-6" /></>,
    users: <><circle cx="9" cy="8" r="3.2" /><path d="M3 20c.4-3.7 2.4-5.7 6-5.7s5.6 2 6 5.7M16 5.2a3.2 3.2 0 0 1 0 6.1M17 14.5c2.4.7 3.7 2.5 4 5.5" /></>,
    roles: <><path d="M12 3.5 20 7v5c0 4.2-2.6 7.2-8 9-5.4-1.8-8-4.8-8-9V7z" /><path d="m8.5 12 2.3 2.3 4.8-4.8" /></>,
    payments: <><rect x="3" y="5" width="18" height="14" rx="2.5" /><path d="M3.5 9h17M7 14.5h4" /><circle cx="17" cy="14.5" r="1" /></>,
    profile: <><circle cx="12" cy="8" r="3.5" /><path d="M4 20c.6-4.2 3.2-6.3 8-6.3s7.4 2.1 8 6.3" /></>,
    support: <><circle cx="12" cy="12" r="9.5" /><path d="M9.2 9a2.9 2.9 0 1 1 4.9 2.1c-1.3 1.2-2.1 1.6-2.1 3.4M12 17.5v.1" /></>,
  };
  return <svg aria-hidden="true" viewBox="0 0 24 24" {...common}>{paths[name]}</svg>;
}

function accountInitial(name: string) {
  return name.trim().slice(0, 1).toUpperCase() || '?';
}

export function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [page, setPage] = useState('dashboard');
  const [toast, setToast] = useState<ToastNotice | null>(null);
  const [paymentSuccess, setPaymentSuccess] = useState('');
  const toastId = useRef(0);
  const [theme, setTheme] = useState<'system' | 'light' | 'dark'>(() => {
    const saved = window.localStorage.getItem('ntccsl-theme');
    return saved === 'light' || saved === 'dark' ? saved : 'system';
  });
  const [themeMenuOpen, setThemeMenuOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(() => window.localStorage.getItem('ntccsl-sidebar-collapsed') === 'true');
  const [accountMenuOpen, setAccountMenuOpen] = useState(false);
  const [isMobile, setIsMobile] = useState(() => window.matchMedia('(max-width: 760px)').matches);
  const accountMenuRef = useRef<HTMLDivElement>(null);
  const notice = useCallback((message: string) => {
    toastId.current += 1;
    setToast({ id: toastId.current, message, type: noticeType(message) });
  }, []);
  const finishPaymentSuccess = useCallback(() => {
    setPaymentSuccess('');
    setPage('payments');
  }, []);
  useEffect(() => {
    if (!toast) return;
    const timeout = window.setTimeout(() => setToast((current) => current?.id === toast.id ? null : current), 4500);
    return () => window.clearTimeout(timeout);
  }, [toast]);
  useEffect(() => {
    if (theme === 'system') delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = theme;
    window.localStorage.setItem('ntccsl-theme', theme);
  }, [theme]);
  useEffect(() => {
    window.localStorage.setItem('ntccsl-sidebar-collapsed', String(sidebarCollapsed));
  }, [sidebarCollapsed]);
  useEffect(() => {
    const mobileQuery = window.matchMedia('(max-width: 760px)');
    const updateViewport = (event: MediaQueryListEvent) => setIsMobile(event.matches);
    setIsMobile(mobileQuery.matches);
    mobileQuery.addEventListener('change', updateViewport);
    return () => mobileQuery.removeEventListener('change', updateViewport);
  }, []);
  useEffect(() => {
    if (!isMobile) setMenuOpen(false);
  }, [isMobile]);
  useEffect(() => {
    if (!accountMenuOpen) return;
    const closeOnOutsideClick = (event: PointerEvent) => {
      if (event.target instanceof Node && !accountMenuRef.current?.contains(event.target)) setAccountMenuOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setAccountMenuOpen(false);
    };
    document.addEventListener('pointerdown', closeOnOutsideClick);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('pointerdown', closeOnOutsideClick);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [accountMenuOpen]);

  const navigation = useMemo(() => {
    if (!session) return [];
    const items: { id: string; label: string; group: string }[] = [{ id: 'dashboard', label: 'Overview', group: 'Workspace' }];
    if (hasLedgerAccess(session)) items.push({ id: 'ledger', label: 'Bank ledger', group: 'Workspace' });
    if (hasDepositAccess(session)) {
      for (const route of DEPOSIT_ROUTES) {
        if (session.user.role === 'Member' && session.reportAccess[route.cadence] === false) continue;
        items.push({ id: route.page, label: route.title, group: 'Deposit accounts' });
      }
    }
    if (hasLoanAccess(session)) {
      if (session.user.role === 'Admin') items.push({ id: 'loan-master', label: 'Loan master', group: 'Loans' });
      if (session.user.role !== 'Collector' || allows(session, 'loan_view') || allows(session, 'loan_add') || allows(session, 'loan_edit') || allows(session, 'loan_delete') || allows(session, 'loan_update')) {
        items.push({ id: 'personal-loan', label: 'Personal loans', group: 'Loans' }, { id: 'gold-loan', label: 'Gold loans', group: 'Loans' });
      }
      if (session.user.role === 'Admin' || session.user.role === 'Member' || allows(session, 'loan_view') || allows(session, 'loan_edit') || allows(session, 'loan_delete') || allows(session, 'loan_update')) {
        items.push({ id: 'approved-loans', label: 'Approved loans', group: 'Loans' });
      }
    }
    if (hasUserAccess(session)) items.push({ id: 'users', label: 'Users', group: 'Administration' });
    if (session.user.role === 'Admin') items.push({ id: 'roles', label: 'Roles & permissions', group: 'Administration' });
    const canMakePayment =
      session.user.role === 'Admin' ||
      session.user.role === 'Member' ||
      (session.user.role === 'Collector' &&
        (allows(session, 'shared_data_read') || allows(session, 'user_view')) &&
        (allows(session, 'deposit_view') ||
          allows(session, 'loan_view') ||
          allows(session, 'loan_edit') ||
          allows(session, 'loan_delete') ||
          allows(session, 'loan_update')));
    if (canMakePayment) items.push({ id: 'payments', label: 'Make a payment', group: 'Member services' });
    items.push({ id: 'profile', label: 'My profile', group: 'Account' }, { id: 'support', label: 'Help & support', group: 'Account' });
    return items;
  }, [session]);

  const selectPage = (id: string) => { setPage(id); setMenuOpen(false); setAccountMenuOpen(false); };
  const signOut = () => {
    setSession(null);
    setPage('dashboard');
    setMenuOpen(false);
    setAccountMenuOpen(false);
  };
  if (!session) return <LoginScreen onLoggedIn={setSession} onNotice={notice} />;
  const allowedPage = navigation.some((item) => item.id === page);
  const currentPage = allowedPage ? page : 'dashboard';
  const route = DEPOSIT_ROUTES.find((item) => item.page === currentPage);
  let content: ReactNode;
  if (currentPage === 'dashboard') content = <Dashboard session={session} />;
  else if (currentPage === 'ledger') content = <LedgerPage session={session} onNotice={notice} />;
  else if (route) content = <DepositPage session={session} route={route} onNotice={notice} onPaymentSuccess={setPaymentSuccess} />;
  else if (currentPage === 'users') content = <UsersPage session={session} onNotice={notice} />;
  else if (currentPage === 'roles') content = <RolesPage session={session} onNotice={notice} />;
  else if (['loan-master', 'personal-loan', 'gold-loan', 'approved-loans'].includes(currentPage)) content = <LoanPage session={session} page={currentPage} onNotice={notice} onPaymentSuccess={setPaymentSuccess} />;
  else if (currentPage === 'payments') content = <PaymentsPage session={session} onNotice={notice} onPaymentSuccess={setPaymentSuccess} />;
  else if (currentPage === 'profile') content = <ProfilePage session={session} onSessionUpdated={setSession} onNotice={notice} />;
  else content = <SupportPage />;
  const sections = [...new Set(navigation.map((item) => item.group))];

  return <div className={`app-shell ${menuOpen ? 'menu-open' : ''} ${sidebarCollapsed ? 'sidebar-collapsed' : ''}`}>
    {menuOpen && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setMenuOpen(false)} />}
    <aside className="sidebar">
      <div className="sidebar-brand"><div className="brand-mark brand-mark-small">N</div><div><strong>NTCCSL</strong><span>Finance System</span></div></div>
      <div className="sidebar-user"><div className="avatar">{session.user.name.slice(0, 1).toUpperCase()}</div><div><strong>{session.user.name}</strong><span>{session.user.role}</span></div></div>
      <nav className="side-navigation">
        {sections.map((group) => <div className="nav-group" key={group}><span className="nav-label">{group}</span>
          {navigation.filter((item) => item.group === group).map((item, index) => <button key={item.id} title={sidebarCollapsed ? item.label : undefined} aria-label={sidebarCollapsed ? item.label : undefined} aria-current={currentPage === item.id ? 'page' : undefined} className={`nav-item ${currentPage === item.id ? 'nav-active' : ''}`} onClick={() => selectPage(item.id)}>
            <span className={`nav-icon nav-icon-tone-${(index + sections.indexOf(group)) % 7}`}><NavigationIcon name={item.id as NavigationIconName} /></span><span className="nav-item-label">{item.label}</span>
          </button>)}
        </div>)}
      </nav>
      <div className="sidebar-bottom">
        <div className="appearance-control">
          <button
            className={`nav-item ${themeMenuOpen ? 'nav-active' : ''}`}
            aria-expanded={themeMenuOpen}
            aria-controls="appearance-menu"
            onClick={() => setThemeMenuOpen((open) => !open)}
          >
            <span className="nav-dot">{theme === 'dark' ? '☾' : theme === 'light' ? '☼' : '◐'}</span>
            <span>Appearance: {theme === 'system' ? 'System' : theme === 'light' ? 'Light' : 'Dark'}</span>
            <span className="appearance-chevron">{themeMenuOpen ? '⌃' : '⌄'}</span>
          </button>
          {themeMenuOpen && (
            <div id="appearance-menu" className="appearance-menu" role="radiogroup" aria-label="Color theme">
              {([
                ['system', 'System', '◐'],
                ['light', 'Light', '☼'],
                ['dark', 'Dark', '☾'],
              ] as const).map(([value, label, icon]) => (
                <button
                  key={value}
                  type="button"
                  role="radio"
                  aria-checked={theme === value}
                  className={`appearance-option ${theme === value ? 'appearance-selected' : ''}`}
                  onClick={() => {
                    setTheme(value);
                    setThemeMenuOpen(false);
                  }}
                >
                  <span aria-hidden="true">{icon}</span>
                  {label}
                  {theme === value && <span className="appearance-check" aria-hidden="true">✓</span>}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    </aside>
    <main className="main-area">
      <header className="topbar"><button className="menu-toggle" aria-label={isMobile ? (menuOpen ? 'Close navigation' : 'Open navigation') : (sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar')} aria-expanded={isMobile ? menuOpen : !sidebarCollapsed} onClick={() => {
        if (isMobile) setMenuOpen((open) => !open);
        else setSidebarCollapsed((collapsed) => !collapsed);
      }}><span className="menu-toggle-bars" aria-hidden="true">{menuOpen ? '×' : '☰'}</span></button>
        <div className="breadcrumbs"><span>NTCCSL</span><b>/</b><strong>{route?.title || routeNames[currentPage] || 'NTCCSL'}</strong></div>
        <div className="topbar-user" ref={accountMenuRef}>
          <button className="account-trigger" aria-haspopup="menu" aria-expanded={accountMenuOpen} aria-label={`Account menu for ${session.user.name}`} onClick={() => setAccountMenuOpen((open) => !open)}>
            <span className="avatar avatar-button">{session.user.profileImageUrl ? <img src={session.user.profileImageUrl} alt="" /> : accountInitial(session.user.name)}</span>
            <span className="account-trigger-copy"><strong>{session.user.name}</strong><span>{session.user.role}</span></span>
            <svg className={`account-chevron ${accountMenuOpen ? 'account-chevron-open' : ''}`} aria-hidden="true" viewBox="0 0 20 20"><path d="m5 7.5 5 5 5-5" /></svg>
          </button>
          {accountMenuOpen && <div className="account-menu" role="menu" aria-label="Account">
            <div className="account-menu-heading"><strong>{session.user.name}</strong><span>{session.user.email || session.user.role}</span></div>
            <button type="button" role="menuitem" onClick={() => selectPage('profile')}><NavigationIcon name="profile" /><span>My profile</span></button>
            <button type="button" role="menuitem" className="account-signout" onClick={signOut}><svg aria-hidden="true" viewBox="0 0 24 24"><path d="M10 4H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h5M16 16l5-4-5-4M21 12H9" /></svg><span>Sign out</span></button>
          </div>}
        </div>
      </header>
      <div className="page-content" key={currentPage}>{content}</div>
      <footer className="app-footer">NTCCSL Finance System <span>•</span> Secure member NTCCSL</footer>
    </main>
    {toast && <Toast key={toast.id} message={toast.message} type={toast.type} onDismiss={() => setToast(null)} />}
    {paymentSuccess && <PaymentSuccessOverlay key={paymentSuccess} message={paymentSuccess} onComplete={finishPaymentSuccess} />}
  </div>;
}
