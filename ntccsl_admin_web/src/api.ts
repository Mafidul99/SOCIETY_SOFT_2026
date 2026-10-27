import type { RecordRow, Session } from './types';

type ApiEnvelope<T> = { status: 'success'; data: T } | { status: 'error'; message: string };

declare global {
  interface Window {
    google?: {
      script?: {
        run: {
          withSuccessHandler(callback: (value: ApiEnvelope<unknown>) => void): {
            withFailureHandler(callback: (error: Error) => void): {
              adminApi(request: Record<string, unknown>): void;
            };
          };
        };
      };
    };
    Cashfree?: (options: { mode: 'sandbox' | 'production' }) => {
      checkout(options: { paymentSessionId: string; redirectTarget: '_modal' }): Promise<unknown>;
    };
  }
}

export class ApiError extends Error {}

type CashfreeSdk = NonNullable<Window['Cashfree']>;

let cashfreeSdkPromise: Promise<CashfreeSdk> | undefined;

export function loadCashfree(): Promise<CashfreeSdk> {
  if (window.Cashfree) return Promise.resolve(window.Cashfree);
  if (!cashfreeSdkPromise) {
    cashfreeSdkPromise = new Promise<CashfreeSdk>((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://sdk.cashfree.com/js/v3/cashfree.js';
      script.async = true;
      script.onload = () => {
        if (window.Cashfree) resolve(window.Cashfree);
        else reject(new ApiError('Cashfree checkout did not initialize.'));
      };
      script.onerror = () => {
        script.remove();
        reject(new ApiError('Could not load Cashfree checkout. Check your network and retry.'));
      };
      document.head.appendChild(script);
    }).catch((cause: unknown) => {
      cashfreeSdkPromise = undefined;
      throw cause;
    });
  }
  return cashfreeSdkPromise;
}

export function request<T>(
  action: string,
  payload: Record<string, unknown> = {},
  session?: Session,
): Promise<T> {
  const runner = window.google?.script?.run;
  if (!runner) {
    return requestThroughLocalProxy<T>(action, payload, session);
  }

  return new Promise<T>((resolve, reject) => {
    runner
      .withSuccessHandler((response) => {
        if (!response || response.status !== 'success') {
          reject(new ApiError(response?.message || 'The server returned an invalid response.'));
          return;
        }
        resolve(response.data as T);
      })
      .withFailureHandler((error) => {
        reject(new ApiError(error?.message || 'The request could not reach Apps Script.'));
      })
      .adminApi({
        action,
        ...payload,
        ...(session ? { token: session.token } : {}),
      });
  });
}

async function requestThroughLocalProxy<T>(
  action: string,
  payload: Record<string, unknown>,
  session?: Session,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch('/api', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action,
        ...payload,
        ...(session ? { token: session.token } : {}),
      }),
      signal: AbortSignal.timeout(35_000),
    });
  } catch {
    throw new ApiError('Could not connect to the local Apps Script proxy. Restart the Vite dev server and try again.');
  }

  let result: unknown;
  try {
    result = await response.json();
  } catch {
    throw new ApiError('Apps Script returned an invalid response. Confirm the deployment URL and that doPost is deployed.');
  }
  if (!response.ok) {
    const message =
      result && typeof result === 'object' && 'message' in result
        ? String(result.message)
        : `The Apps Script proxy returned status ${response.status}.`;
    throw new ApiError(message);
  }
  if (!result || typeof result !== 'object') {
    throw new ApiError('Apps Script returned an invalid response.');
  }
  const record = result as Record<string, unknown>;
  if (record.status === 'error') {
    throw new ApiError(String(record.message || 'The request failed.'));
  }
  if (record.status === 'success' && 'data' in record) {
    return record.data as T;
  }
  return result as T;
}

export async function login(identifier: string, password: string, loginType: 'staff' | 'member') {
  const result = await request<{
    status: string;
    token: string;
    user: Session['user'];
    permissions: Record<string, boolean>;
    reportAccess: Record<string, boolean>;
  }>('login', { identifier, email: identifier, password, loginType });
  if (result.status !== 'success' || !result.token || !result.user?.id) {
    throw new ApiError('The server returned an incomplete login response.');
  }
  return result as Session;
}

export async function getRows(action: string, session: Session, params: Record<string, unknown> = {}) {
  const rows = await request<unknown>(action, params, session);
  if (!Array.isArray(rows) || rows.some((row) => !row || typeof row !== 'object')) {
    throw new ApiError(`The server returned invalid ${action} data.`);
  }
  return rows as RecordRow[];
}

export async function mutate(
  action: string,
  session: Session,
  payload: Record<string, unknown> = {},
) {
  const result = await request<unknown>(action, payload, session);
  if (result && typeof result === 'object' && 'status' in result && result.status === 'error') {
    throw new ApiError('The requested change was not saved.');
  }
  return result;
}
