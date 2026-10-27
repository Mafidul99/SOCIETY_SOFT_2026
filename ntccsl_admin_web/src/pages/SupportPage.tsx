import { useEffect, useRef, useState, type FormEvent } from 'react';
import { PageHeading } from '../components/ui';

type SupportMessage = { text: string; fromUser: boolean };

const suggestedQuestions = [
  'How do I log in?',
  'How do I apply for a loan?',
  'How do I view my deposits?',
  'How can I contact support?',
];

const contacts = [
  {
    icon: '☎',
    label: 'Call our office',
    value: '+91 9282956845',
    href: 'tel:+919282956845',
    accent: 'green',
  },
  {
    icon: '✉',
    label: 'Email support',
    value: 'support@ntccsl.in',
    href: 'mailto:support@ntccsl.in?subject=NTCCSL%20account%20support&body=Hello%20NTCCSL%20Support%2C%0A%0AI%20need%20help%20with%20my%20account.',
    accent: 'blue',
  },
  {
    icon: '↗',
    label: 'Visit our website',
    value: 'ntccsl.in',
    href: 'https://ntccsl.in',
    accent: 'violet',
    external: true,
  },
];

function supportAnswer(question: string) {
  const normalized = question.trim().toLowerCase();

  if (
    normalized.includes('login') ||
    normalized.includes('log in') ||
    normalized.includes('sign in') ||
    normalized.includes('password') ||
    normalized.includes('account access')
  ) {
    return 'Sign in with your registered email, or use your Member ID (account number) and password. If you cannot access your account or forgot your password, contact the office at +91 9282956845 or support@ntccsl.in.';
  }
  if (
    normalized.includes('loan') ||
    normalized.includes('borrow') ||
    normalized.includes('application')
  ) {
    return 'You can apply from the Personal Loan or Gold Loan page. Applications stay Pending until reviewed. After approval, check your approved loan details in the portal. For account-specific help, contact the office at +91 9282956845.';
  }
  if (
    normalized.includes('deposit') ||
    normalized.includes('fd') ||
    normalized.includes('rd') ||
    normalized.includes('drd')
  ) {
    return 'Open the Deposit section to view the FD, RD, or DRD accounts available to your account. If an expected account is missing, contact the office at +91 9282956845 or support@ntccsl.in.';
  }
  if (
    normalized.includes('contact') ||
    normalized.includes('phone') ||
    normalized.includes('email') ||
    normalized.includes('website') ||
    normalized.includes('whatsapp') ||
    normalized.includes('support')
  ) {
    return 'You can call +91 9282956845, email support@ntccsl.in, visit ntccsl.in, or use the WhatsApp button on this Support page.';
  }
  return 'I can help with account access, loans, deposits, and support contacts. Try one of those topics, or contact our office at +91 9282956845 for more help.';
}

export function SupportPage() {
  const [chatOpen, setChatOpen] = useState(false);
  const [draft, setDraft] = useState('');
  const [messages, setMessages] = useState<SupportMessage[]>([
    {
      text: 'Hi! I can help with general questions about account access, loans, deposits, and support contacts.',
      fromUser: false,
    },
  ]);
  const chatDialogRef = useRef<HTMLElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const messageListRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!chatOpen) return;
    const previouslyFocused = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
    inputRef.current?.focus();
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setChatOpen(false);
        return;
      }
      if (event.key !== 'Tab') return;

      const focusable = chatDialogRef.current?.querySelectorAll<HTMLElement>(
        'button:not(:disabled), input:not(:disabled)',
      );
      if (!focusable?.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => {
      window.removeEventListener('keydown', closeOnEscape);
      previouslyFocused?.focus();
    };
  }, [chatOpen]);

  useEffect(() => {
    messageListRef.current?.scrollTo({
      top: messageListRef.current.scrollHeight,
      behavior: 'smooth',
    });
  }, [messages]);

  function sendMessage(question = draft) {
    const text = question.trim();
    if (!text) return;
    setMessages((current) => [
      ...current,
      { text, fromUser: true },
      { text: supportAnswer(text), fromUser: false },
    ]);
    setDraft('');
  }

  function submitMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    sendMessage();
  }

  return (
    <div className="support-page">
      <PageHeading title="Help & support" subtitle="Get help using the NTCCSL Finance System." />

      <section className="support-hero" aria-labelledby="support-hero-title">
        <div className="support-hero-heading">
          <span className="support-hero-icon" aria-hidden="true">?</span>
          <div>
            <p>We are here to help with your account.</p>
            <h2 id="support-hero-title">SUPPORT</h2>
          </div>
          <span className="support-verified" aria-hidden="true">✓</span>
        </div>
        <h3>Personal assistance, when you need it.</h3>
        <p>Contact our head office for account questions, member assistance, and portal access support.</p>
      </section>

      <section className="support-contacts" aria-labelledby="support-contact-title">
        <div className="support-section-heading">
          <h2 id="support-contact-title">Get in touch</h2>
          <p>Choose the contact option that works best for you.</p>
        </div>
        <div className="support-contact-grid">
          {contacts.map((contact) => (
            <a
              className={`support-contact-card support-contact-${contact.accent}`}
              href={contact.href}
              key={contact.label}
              {...('external' in contact && contact.external
                ? { target: '_blank', rel: 'noreferrer' }
                : {})}
            >
              <span className="support-contact-icon" aria-hidden="true">{contact.icon}</span>
              <span className="support-contact-copy">
                <span>{contact.label}</span>
                <strong>{contact.value}</strong>
              </span>
              <span className="support-contact-open" aria-hidden="true">↗</span>
            </a>
          ))}
        </div>
      </section>

      <button
        type="button"
        className="button support-chat-open"
        onClick={() => setChatOpen(true)}
      >
        <span aria-hidden="true">✦</span> Ask AI Support Assistant
      </button>

      <aside className="support-note">
        <span className="support-note-icon" aria-hidden="true">i</span>
        <div>
          <h2>How can we help?</h2>
          <p>For account updates, portal access, or member assistance, contact the head office using the details above.</p>
        </div>
      </aside>

      <a
        className="support-whatsapp"
        href="https://wa.me/919282956845?text=Hello%2C%20I%20need%20help%20with%20my%20NTCCSL%20account."
        target="_blank"
        rel="noreferrer"
        aria-label="Message us on WhatsApp"
        title="Message us on WhatsApp"
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="M20.5 11.8a8.4 8.4 0 0 1-12.4 7.4L3 20.5l1.3-4.9a8.4 8.4 0 1 1 16.2-3.8Z" />
          <path d="M8.4 7.7c.2-.4.4-.4.7-.4h.5c.2 0 .4 0 .5.4l.8 1.8c.1.3.1.5-.1.7l-.6.7c-.2.2-.2.4 0 .6.4.7 1 1.3 1.7 1.7.2.1.4.1.6-.1l.8-.9c.2-.2.4-.2.7-.1l1.7.8c.3.1.4.3.4.5 0 .2-.1 1-.6 1.4-.4.5-1 .7-1.7.7-.6 0-1.4-.2-2.4-.7-1.1-.6-2-1.4-2.8-2.3-.7-.8-1.2-1.8-1.3-2.6-.2-.8 0-1.6.4-2.2Z" />
        </svg>
      </a>

      {chatOpen && (
        <div
          className="support-chat-backdrop"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setChatOpen(false);
          }}
        >
          <section
            className="support-chat-dialog"
            ref={chatDialogRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby="support-chat-title"
          >
            <header className="support-chat-header">
              <span className="support-chat-sparkle" aria-hidden="true">✦</span>
              <div>
                <h2 id="support-chat-title">AI Support Assistant</h2>
                <p>Quick answers from support FAQs</p>
              </div>
              <button
                type="button"
                className="support-chat-close"
                onClick={() => setChatOpen(false)}
                aria-label="Close support assistant"
              >
                ×
              </button>
            </header>
            <div className="support-chat-messages" ref={messageListRef} aria-live="polite">
              {messages.map((message, index) => (
                <article
                  className={`support-chat-message ${message.fromUser ? 'support-chat-user' : 'support-chat-assistant'}`}
                  key={`${index}-${message.fromUser ? 'user' : 'assistant'}`}
                >
                  <span>{message.fromUser ? 'You' : 'Support assistant'}</span>
                  <p>{message.text}</p>
                </article>
              ))}
              {messages.length === 1 && (
                <div className="support-chat-suggestions" aria-label="Suggested questions">
                  {suggestedQuestions.map((question) => (
                    <button type="button" key={question} onClick={() => sendMessage(question)}>
                      {question}
                    </button>
                  ))}
                </div>
              )}
            </div>
            <form className="support-chat-form" onSubmit={submitMessage}>
              <label className="sr-only" htmlFor="support-chat-input">Ask a support question</label>
              <input
                id="support-chat-input"
                ref={inputRef}
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
                placeholder="Ask a support question…"
                autoComplete="off"
              />
              <button type="submit" disabled={!draft.trim()} aria-label="Send message" title="Send message">
                <svg viewBox="0 0 24 24" aria-hidden="true">
                  <path d="m21 3-7.2 18-3.6-7.2L3 10.2 21 3Z" />
                  <path d="M10.2 13.8 21 3" />
                </svg>
              </button>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}
