# NTCCSL React admin portal

This Vite + React application can be served by the existing Google Apps Script web app or hosted as a static frontend on Hostinger Shared Hosting. Both options use the existing Apps Script backend and Google Sheets data.

## Development

```sh
npm install
npm run dev
```

For local sign-in and live spreadsheet data, create `.env.local` in this folder:

```ini
VITE_GAS_EXEC_URL=https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec
```

Use your deployed Apps Script `/exec` URL without `?panel=1`, then restart Vite. The development server proxies API calls to `doPost`, avoiding browser cross-origin restrictions. Never put passwords, Cashfree keys, or other credentials in this file. Without this setting, API calls only work inside the deployed Apps Script HTML-service page.

## Build and deploy

```sh
npm run typecheck
npm run build
```

The build creates two deployment targets:

- `Admin.html` in this directory is the self-contained Google Apps Script portal. Keep it beside `Code.gs` in the bound Apps Script project, deploy a new web-app version, and open the deployment URL with `?panel=1`.
- `dist/` is a Hostinger-ready website containing `index.html`, the built frontend assets, and a PHP API relay.

### Hostinger Shared Hosting

1. Deploy the Apps Script project as a web app that executes as the owner, then copy its `/exec` URL. Its access setting must allow unauthenticated server-to-server requests (usually **Anyone**, if permitted by your Google account); the app itself still requires login and checks permissions for protected actions.
2. After `npm run build`, open `dist/api.php` and replace `REPLACE_WITH_YOUR_DEPLOYMENT_ID` in `APPS_SCRIPT_EXEC_URL` with the deployment ID from the `/exec` URL.
3. In Hostinger hPanel, point your domain to its website directory (usually `public_html`). Upload the **contents** of `dist/` into that directory, including `.htaccess` and `api.php`. Do not upload `node_modules` or the project source.
4. Select PHP 8.1 or newer in hPanel, enable SSL for the domain, and open the domain over HTTPS. The PHP cURL extension and Apache rewrite support must be enabled by the hosting plan.
5. Test sign-in and data loading. If requests fail, check that the Apps Script URL ends in `/exec`, the web app deployment is accessible, and PHP cURL is enabled.

The browser calls the same-origin `/api` route; `api.php` forwards requests to the fixed Apps Script URL, avoiding browser cross-origin restrictions. The API relay accepts POST only and caps request bodies at 500 KB. Keep the Apps Script backend authoritative for authentication, roles, validation, and payment verification. Never put passwords, Cashfree keys, or other credentials in frontend code.

The Apps Script project must include the current `Code.gs`, its existing Sheets/Drive setup, and the appropriate Cashfree Script Properties when enabling payments. The server remains authoritative for login, roles, permissions, validation, loan calculations, and payment verification.

Members can start Cashfree checkout for the next unpaid deposit or loan installment from its schedule popup. Admins and Collectors with `shared_data_read` or `user_view` permission can start checkout for the member attached to an account. The app verifies the order with Cashfree on the server before marking an installment paid; pending or closed checkouts can be resumed or verified from the popup. Configure `CASHFREE_APP_ID`, `CASHFREE_SECRET_KEY`, and `CASHFREE_ENVIRONMENT` in Apps Script Script Properties. The server adds a 2% service charge to Cashfree orders.

## Included portal pages

Sign in and member registration, dashboard, bank ledger, FD/RD/DRD schedules, users, role permissions, loan master and scheme management, personal loans, gold loans, approved loans and schedules, member installment payments, profile/password updates, and support.

Each screen lives in its own component under [`src/pages`](./src/pages), shared form/table components live in [`src/components/ui.tsx`](./src/components/ui.tsx), and `src/App.tsx` handles role-aware navigation and page selection.

The dashboard summarizes ledger, deposit, and loan data with responsive overview cards and recent activity tables. Use **Refresh** to reload the latest dashboard data.

Data-backed screens show a shared, accessible portal loader while requests are pending and retain retry/error states when they fail. Form submissions, payment steps, permission updates, and repayment schedule actions also show progress while in flight.

App notifications use accessible success, information, warning, and error toasts. They can be dismissed manually and close automatically after 4.5 seconds.

On **My profile**, use **Change photo** to preview and save a JPG, PNG, or WebP profile photo, or choose **Remove** to clear it. Images larger than the 300 KB server limit are resized in the browser before upload; the Apps Script backend stores the saved photo in Drive. Saved profile photos also appear in the **Users** table, with an initial shown if a photo is missing or cannot be loaded.

## Navigation

Use the top-left menu button to collapse or expand the sidebar on desktop. On mobile, it opens and closes the navigation drawer; choosing a page closes the drawer. The desktop sidebar choice is remembered in local storage. Use the account menu in the top-right corner to open your profile or sign out.

## Appearance

Use **Appearance** at the bottom of the navigation to choose **System**, **Light**, or **Dark**. System follows the browser/device color-scheme preference, including changes while the app is open. The selection is saved in local storage for the next visit.

The portal uses a shared blue-and-indigo color palette across pages, with separate semantic colors for success, warnings, and errors.
