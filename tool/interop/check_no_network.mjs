// loads the built web app in a headless browser and asserts it asks the
// network for nothing outside the origin it was served from.
//
//     node tool/interop/check_no_network.mjs build/web
//     WEB_CRYPT_BROWSER=firefox node tool/interop/check_no_network.mjs build/web
//     WEB_CRYPT_ORIGIN=http://127.0.0.1:8080 node tool/interop/check_no_network.mjs
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import puppeteer from 'puppeteer';

const ROOT = process.argv[2] ?? 'build/web';
const PORT = Number(process.env.PORT ?? 8137);
const SERVED = process.env.WEB_CRYPT_ORIGIN;
const ORIGIN = SERVED ?? `http://127.0.0.1:${PORT}`;
const ROUTES = ['/', '/encrypt', '/decrypt', '/keys', '/settings'];

// not BROWSER, which on Linux already means the preferred desktop browser
const BROWSER = process.env.WEB_CRYPT_BROWSER ?? 'chrome';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.symbols': 'application/octet-stream',
  '.bin': 'application/octet-stream',
};

// only routes fall back to index.html, a missing file 404s, as nginx does
const server = createServer(async (req, res) => {
  const url = new URL(req.url, ORIGIN);
  let path = join(ROOT, normalize(decodeURIComponent(url.pathname)));
  try {
    if ((await stat(path)).isDirectory()) path = join(path, 'index.html');
  } catch {
    if (extname(path)) {
      res.writeHead(404).end('not found');
      return;
    }
    path = join(ROOT, 'index.html');
  }
  try {
    const body = await readFile(path);
    res.writeHead(200, {
      'Content-Type': MIME[extname(path)] ?? 'application/octet-stream',
    });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});

const pass = (message) => console.log(`\x1b[32mPASS\x1b[0m  ${message}`);
const fail = (message) => {
  console.error(`\x1b[31mFAIL\x1b[0m  ${message}`);
  process.exitCode = 1;
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const launch = () =>
  puppeteer.launch({
    headless: true,
    ...(BROWSER === 'firefox'
      ? {
          browser: 'firefox',
          // there is no GPU to talk to on a CI box
          extraPrefsFirefox: {
            'gfx.webrender.software': true,
            'webgl.force-enabled': true,
          },
        }
      : {
          protocol: 'cdp',
          args: ['--no-sandbox', '--disable-dev-shm-usage'],
        }),
  });

if (!SERVED) {
  await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve));
}

const external = [];
const consoleErrors = [];
let titleSeen = null;

try {
  // a browser per route, since headless Firefox will not restart its engine
  for (const route of ROUTES) {
    const browser = await launch();
    try {
      const page = await browser.newPage();
      page.on('request', (request) => {
        const url = request.url();
        if (url.startsWith('data:') || url.startsWith('blob:')) return;
        if (!url.startsWith(ORIGIN)) {
          external.push(`${request.method()} ${url}`);
        }
      });
      page.on('console', (message) => {
        if (message.type() === 'error') consoleErrors.push(message.text());
      });
      page.on('pageerror', (error) => consoleErrors.push(String(error)));

      await page.goto(`${ORIGIN}${route}`, {
        waitUntil: 'domcontentloaded',
        timeout: 90_000,
      });
      await page.waitForSelector('flutter-view, flt-glass-pane', {
        timeout: 90_000,
      });
      // the splash goes on the first painted frame, so its absence means up
      await page.waitForFunction(() => !document.getElementById('boot'), {
        timeout: 90_000,
      });
      // glyphs the bundled faces lack are what send the engine looking
      if (route === '/encrypt') {
        await page.keyboard.type('\u4f60\u597d \u0645\u0631\u062d\u0628\u0627 \u0448\u0438\u0444\u0440 \ud83d\udd10\ud83e\uddea');
        await sleep(1500);
      }
      await sleep(2500);
      titleSeen ??= await page.title();
    } finally {
      await browser.close();
    }
  }

  if (external.length === 0) {
    pass(`${BROWSER} made no requests outside its own origin`);
  } else {
    fail(`external requests: ${[...new Set(external)].join(', ')}`);
  }

  if (consoleErrors.length === 0) {
    pass('no console errors on any route');
  } else {
    fail(
      `console errors: ${[...new Set(consoleErrors)].slice(0, 5).join(' | ')}`,
    );
  }

  if (titleSeen === 'web-crypt') {
    pass('page title is set');
  } else {
    fail(`unexpected title "${titleSeen}"`);
  }
} finally {
  if (!SERVED) server.close();
}
