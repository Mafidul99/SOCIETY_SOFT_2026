import { readFile, writeFile } from 'node:fs/promises';

const [javascript, stylesheet, proxy, rewriteRules] = await Promise.all([
  readFile(new URL('../dist/portal.js', import.meta.url), 'utf8'),
  readFile(new URL('../dist/portal.css', import.meta.url), 'utf8'),
  readFile(new URL('../api.php', import.meta.url), 'utf8'),
  readFile(new URL('../.htaccess', import.meta.url), 'utf8'),
]);

const html = `<!doctype html>
<html lang="en">
  <head>
    <base target="_top">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/svg+xml" href="ntccsl_logo.png" />
    <meta name="theme-color" content="#102d58">
    <title>NTCCSL Finance System</title>
    <style>${stylesheet}</style>
  </head>
  <body>
    <div id="root"></div>
    <script>${javascript}</script>
  </body>
</html>
`;

const hostingerHtml = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/svg+xml" href="ntccsl_logo.png" />
    <meta name="theme-color" content="#102d58">
    <title>NTCCSL Finance System</title>
    <link rel="stylesheet" href="./portal.css">
  </head>
  <body>
    <div id="root"></div>
    <script src="./portal.js"></script>
  </body>
</html>
`;

await Promise.all([
  writeFile(new URL('../Admin.html', import.meta.url), html),
  writeFile(new URL('../dist/index.html', import.meta.url), hostingerHtml),
  writeFile(new URL('../dist/api.php', import.meta.url), proxy),
  writeFile(new URL('../dist/.htaccess', import.meta.url), rewriteRules),
]);
console.log('Built Admin.html for Apps Script and a Hostinger-ready site in dist/.');
