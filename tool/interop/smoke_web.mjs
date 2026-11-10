// drives the built web app in a headless browser: loads every route, reads
// the accessible labels, encrypts a message, and opens one from the age CLI.
//
//     node tool/interop/smoke_web.mjs build/web
//     WEB_CRYPT_BROWSER=firefox node tool/interop/smoke_web.mjs build/web
//     WEB_CRYPT_ORIGIN=http://127.0.0.1:8080 node tool/interop/smoke_web.mjs
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import puppeteer from 'puppeteer';

const ROOT = process.argv[2] ?? 'build/web';
const PORT = Number(process.env.PORT ?? 8138);
const SERVED = process.env.WEB_CRYPT_ORIGIN;
const ORIGIN = SERVED ?? `http://127.0.0.1:${PORT}`;
const SECRET = 'meet me at the usual place';
const PASSPHRASE = 'correct horse battery staple';
const DROP_HINT = 'Paste an encrypted message, or drop a file anywhere here';

// made by the real age CLI, so the browser's scrypt is checked against it
const AGE_CLI_MESSAGE = `-----BEGIN AGE ENCRYPTED FILE-----
YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IHNjcnlwdCBzc0ppV3d4d0d1MjVuRWpX
dTZJZnh3IDE4CitSOGFxajNvK1dzK1JFYlN5c3JCem9HalljMFMwSjd6SEcxWEsr
TS96SUkKLS0tIE1QNlllbDZaVUR1VU1pY1h2dUhuVUh2MW0zdDllOXlRaUh3ZUU2
NTN4akEK6LqZhrm2czH056tVyIOjfSdn6OpsihDyfSUgWBAorSWZMUiC2CqpD+Ne
Hc/WzGBQbUdk
-----END AGE ENCRYPTED FILE-----`;

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
};

// only routes fall back to index.html, a missing file 404s, as nginx does
const server = createServer(async (req, res) => {
  const url = new URL(req.url, ORIGIN);
  let path = join(ROOT, normalize(decodeURIComponent(url.pathname)));
  try {
    const info = await stat(path);
    if (info.isDirectory()) path = join(path, 'index.html');
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

const pass = (m) => console.log(`\x1b[32mPASS\x1b[0m  ${m}`);
const fail = (m) => {
  console.error(`\x1b[31mFAIL\x1b[0m  ${m}`);
  process.exitCode = 1;
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// the splash goes on the first painted frame, so its absence means the app is
// up rather than merely downloaded
async function ready(page) {
  await page.waitForSelector('flutter-view, flt-glass-pane', {
    timeout: 90_000,
  });
  await page.waitForFunction(() => !document.getElementById('boot'), {
    timeout: 90_000,
  });
  await sleep(2500);
}

async function enableSemantics(page) {
  await page.evaluate(() => {
    const placeholder = document.querySelector(
      'flt-semantics-placeholder, flutter-view flt-semantics-placeholder',
    );
    if (placeholder) placeholder.click();
  });
  await sleep(1500);
}

// labels live in `aria-label` or the leaf's text. only leaves count, since an
// ancestor's text is everything beneath it joined together
async function labelsOf(page) {
  return page.evaluate(() => {
    const labels = new Set();
    for (const node of document.querySelectorAll('flt-semantics')) {
      const aria = node.getAttribute('aria-label');
      if (aria) labels.add(aria.trim());
      if (node.querySelector('flt-semantics')) continue;
      const text = (node.textContent ?? '').trim();
      if (text) labels.add(text);
    }
    for (const field of document.querySelectorAll('input, textarea')) {
      for (const value of [
        field.getAttribute('aria-label'),
        field.getAttribute('placeholder'),
      ]) {
        if (value) labels.add(value.trim());
      }
    }
    return [...labels];
  });
}

// semantics buttons are ordinary DOM nodes, so a click reaches the framework
async function pressButton(page, name) {
  await page.evaluate((wanted) => {
    const buttons = document.querySelectorAll('flt-semantics[role=button]');
    [...buttons].find((n) => (n.textContent ?? '').trim() === wanted)?.click();
  }, name);
}

async function fill(page, selector, text) {
  await page.click(selector);
  await page.keyboard.type(text);
}

// sent as text, like a paste, since typing armor trips Flutter's key handling
async function paste(page, selector, text) {
  await page.click(selector);
  for (const char of text) await page.keyboard.sendCharacter(char);
}

// the longest gap between ticks, which is how long the page stopped painting
async function watchStalls(page) {
  await page.evaluate(() => {
    let last = performance.now();
    window.longestStall = 0;
    setInterval(() => {
      const now = performance.now();
      window.longestStall = Math.max(window.longestStall, now - last);
      last = now;
    }, 20);
  });
}

async function findLabel(page, predicate, timeoutMs = 20000) {
  const deadline = Date.now() + timeoutMs;
  let seen = [];
  while (Date.now() < deadline) {
    seen = await labelsOf(page);
    const hit = seen.find(predicate);
    if (hit) return hit;
    await sleep(500);
  }
  console.error(`    saw: ${seen.slice(0, 12).join(' | ')}`);
  return null;
}

if (!SERVED) {
  await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve));
}

// not BROWSER, which on Linux already means the preferred desktop browser
const BROWSER = process.env.WEB_CRYPT_BROWSER ?? 'chrome';

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

// a browser per route, since headless Firefox will not restart its engine
async function onRoute(route, body) {
  const browser = await launch();
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 900 });
    const errors = [];
    page.on('pageerror', (error) => errors.push(String(error)));
    await page.goto(`${ORIGIN}${route}`, {
      waitUntil: 'domcontentloaded',
      timeout: 90_000,
    });
    await ready(page);
    await body(page, errors);
    return errors;
  } finally {
    await browser.close();
  }
}

const allErrors = [];

allErrors.push(
  ...(await onRoute('/', async (page) => {
    pass(`the built app loads and paints in ${BROWSER}`);
    await enableSemantics(page);

    const heading = await findLabel(page, (label) => label === 'Encrypt');
    if (heading) {
      pass('the encrypt screen is announced to assistive technology');
    } else {
      fail('no accessible node named "Encrypt"');
    }

    const message = await findLabel(page, (label) =>
      label.includes('Type or paste your message'),
    );
    if (message) {
      pass('the message field carries its label');
    } else {
      fail('the message field has no accessible label');
    }

    const passphrase = await findLabel(page, (label) => label === 'Passphrase');
    if (passphrase) {
      pass('the passphrase field carries its label');
    } else {
      fail('the passphrase field has no accessible label');
    }

    // the form only gives way to the result panel once there is ciphertext
    const messageField = 'textarea[aria-label="Type or paste your message"]';
    await fill(page, messageField, SECRET);
    await fill(page, 'input[aria-label="Passphrase"]', PASSPHRASE);
    await fill(page, 'input[aria-label="Passphrase again"]', PASSPHRASE);
    await watchStalls(page);
    await pressButton(page, 'Encrypt');

    const result = await findLabel(page, (label) =>
      label.startsWith('Send this whole block'),
    );
    if (result) {
      pass('the shipped bundle encrypts a message');
    } else {
      fail('encrypting in the browser produced no output');
    }

    const stall = Math.round(await page.evaluate(() => window.longestStall));
    if (stall < 2000) {
      pass(`the page kept painting while it encrypted, at most ${stall} ms`);
    } else {
      fail(`the page froze for ${stall} ms while it encrypted`);
    }
  })),
);

allErrors.push(
  ...(await onRoute('/decrypt', async (page) => {
    await enableSemantics(page);
    await paste(page, `textarea[aria-label="${DROP_HINT}"]`, AGE_CLI_MESSAGE);
    await fill(page, 'input[aria-label="Passphrase"]', PASSPHRASE);
    await pressButton(page, 'Decrypt');

    if (await findLabel(page, (label) => label === 'Decrypted')) {
      pass('a message from the age CLI decrypts in the browser');
    } else {
      fail('the age CLI message did not decrypt in the browser');
    }
  })),
);

// matched on something only that screen says, since the heading merges into
// its parent semantics node along with the subtitle
for (const [route, marker] of [
  ['/decrypt', DROP_HINT],
  ['/keys', 'No keys yet'],
  ['/settings', 'Appearance'],
]) {
  allErrors.push(
    ...(await onRoute(route, async (page) => {
      await enableSemantics(page);
      const found = await findLabel(page, (label) => label === marker);
      if (found) {
        pass(`${route} deep links straight to that screen`);
      } else {
        fail(`${route} did not render its own screen`);
      }
    })),
  );
}

if (allErrors.length === 0) {
  pass('no uncaught errors on any route');
} else {
  fail(`uncaught errors: ${[...new Set(allErrors)].slice(0, 3).join(' | ')}`);
}

if (!SERVED) server.close();
