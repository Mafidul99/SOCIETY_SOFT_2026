import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, loadEnv, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

const projectDirectory = dirname(fileURLToPath(import.meta.url));

function appsScriptDevProxy(scriptUrl: string | undefined): Plugin {
  return {
    name: 'ntccsl-apps-script-dev-proxy',
    configureServer(server) {
      server.middlewares.use('/api', async (request, response) => {
        if (request.method !== 'POST') {
          response.writeHead(405, { Allow: 'POST' }).end();
          return;
        }
        if (!scriptUrl) {
          response.writeHead(503, { 'Content-Type': 'application/json' }).end(
            JSON.stringify({ status: 'error', message: 'Set VITE_GAS_EXEC_URL in .env.local and restart the dev server.' }),
          );
          return;
        }

        try {
          const chunks: Buffer[] = [];
          let size = 0;
          for await (const chunk of request) {
            const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
            size += buffer.length;
            if (size > 500_000) {
              response.writeHead(413, { 'Content-Type': 'application/json' }).end(
                JSON.stringify({ status: 'error', message: 'Request is too large.' }),
              );
              return;
            }
            chunks.push(buffer);
          }

          const upstream = await fetch(scriptUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: Buffer.concat(chunks),
            redirect: 'follow',
            signal: AbortSignal.timeout(30_000),
          });
          const body = await upstream.text();
          response.writeHead(upstream.status, {
            'Content-Type': upstream.headers.get('content-type') || 'application/json',
          }).end(body);
        } catch (error) {
          console.error('Apps Script development proxy failed:', error);
          response.writeHead(502, { 'Content-Type': 'application/json' }).end(
            JSON.stringify({ status: 'error', message: 'Could not reach the Apps Script deployment. Check the URL and network, then retry.' }),
          );
        }
      });
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, projectDirectory, '');
  const scriptUrl = env.VITE_GAS_EXEC_URL;

  return {
    plugins: [react(), appsScriptDevProxy(scriptUrl)],
    define: {
      'process.env.NODE_ENV': JSON.stringify('production'),
    },
    build: {
      outDir: 'dist',
      emptyOutDir: true,
      lib: {
        entry: resolve(projectDirectory, 'src/main.tsx'),
        name: 'NtccslPortal',
        formats: ['iife'],
        fileName: () => 'portal.js',
        cssFileName: 'portal',
      },
      cssCodeSplit: false,
      rollupOptions: {
        output: {
          inlineDynamicImports: true,
        },
      },
    },
  };
});
