import { useState, type FormEvent } from 'react';
import { login, request } from '../api';
import type { Session } from '../types';
import { PortalLoader, RecordForm } from '../components/ui';

export function LoginScreen({ onLoggedIn, onNotice }: { onLoggedIn: (session: Session) => void; onNotice: (message: string) => void }) {
  const [loginType, setLoginType] = useState<'staff' | 'member'>('staff');
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [registrationBusy, setRegistrationBusy] = useState(false);
  const [registering, setRegistering] = useState(false);

  const submitLogin = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      onLoggedIn(await login(identifier, password, loginType));
      onNotice('Signed in successfully.');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Sign in failed.');
    } finally {
      setBusy(false);
    }
  };

  const submitRegistration = async (values: Record<string, string | boolean>) => {
    setRegistrationBusy(true);
    try {
      await request('register', {
        name: values.name,
        email: values.email,
        password: values.password,
      });
      setRegistering(false);
      setLoginType('member');
      onNotice('Registration successful. You can now sign in.');
    } finally {
      setRegistrationBusy(false);
    }
  };

  return (
    <main className="login-layout">
      <section className="login-brand">
        <div className="brand-mark">N</div>
        <p className="eyebrow">NORTH TRIPURA CO-OPERATIVE</p>
        <h1>NTCCSL<br />Finance System</h1>
        <p>Secure access to your accounts, deposits, loans, and member services.</p>
        <div className="brand-footnote">A trusted financial and secure portal.</div>
      </section>
      <section className="login-panel">
        <div className="login-card">
          <p className="eyebrow">WELCOME BACK</p>
          <h2>Sign in to your account</h2>
          <p className="muted">Choose the account type that applies to you.</p>
          <div className="segmented">
            <button type="button" className={loginType === 'staff' ? 'selected' : ''} onClick={() => setLoginType('staff')}>Admin / Collector</button>
            <button type="button" className={loginType === 'member' ? 'selected' : ''} onClick={() => setLoginType('member')}>Member</button>
          </div>
          <form className="login-form" onSubmit={submitLogin}>
            <label className="field"><span>{loginType === 'member' ? 'Email or account number' : 'Email address'}</span>
              <input required autoComplete="username" value={identifier} onChange={(event) => setIdentifier(event.target.value)} />
            </label>
            <label className="field"><span>Password</span>
              <input required type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} />
            </label>
            {error && <p className="form-error" role="alert">{error}</p>}
            <button className="button button-primary button-full" disabled={busy}>{busy && <PortalLoader label="Signing in" inline size={18} />}{busy ? 'Signing in…' : 'Sign in'}</button>
          </form>
          <button className="text-button" onClick={() => setError('Contact your portal administrator to reset your password.')}>Forgot password?</button>
          <div className="login-divider"><span>New member?</span></div>
          <button className="button button-secondary button-full" onClick={() => setRegistering(true)}>Create a member account</button>
          <p className="login-privacy">Your account role and access permissions are verified by the portal.</p>
        </div>
      </section>
      {registering && <RecordForm title="Create member account" fields={[
        { name: 'name', label: 'Full name', required: true },
        { name: 'email', label: 'Email address', type: 'email', required: true },
        { name: 'password', label: 'Password (8+ characters)', type: 'password', required: true },
      ]} busy={registrationBusy} onClose={() => setRegistering(false)} onSubmit={submitRegistration} />}
    </main>
  );
}
