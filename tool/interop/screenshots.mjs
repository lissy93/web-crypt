// takes the screenshots the readme uses. serves the built web app, fills it
// with a made-up keyring and messages, then captures each screen. needs gpg
// and age-keygen on PATH for the keys
//
//     flutter build web --release --no-web-resources-cdn
//     node tool/interop/screenshots.mjs .github/screenshots
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join, normalize } from 'node:path';
import puppeteer from 'puppeteer';

const ROOT = process.env.WEB_ROOT ?? 'build/web';
const OUT = process.argv[2] ?? '.github/screenshots';
const PORT = Number(process.env.PORT ?? 8155);
const ORIGIN = `http://127.0.0.1:${PORT}`;

const WEB = { width: 1180, height: 820, deviceScaleFactor: 2 };
const MOBILE = { width: 390, height: 844, deviceScaleFactor: 3 };

const MASTER_PASSWORD = 'hunter2 but longer, much longer';
const PASSPHRASE = 'never trust dave with dairy';

const MESSAGE = `Dave,

I know it was you who ate my yoghurt from the office fridge. It had my name on it. In Sharpie. Twice.

This is your one warning.`;

const REPLY = `It was already open when I found it, so legally it was abandoned property.

Also it went out of date in March. You're welcome.

Dave`;

const ESCALATION = `Gran,

The yoghurt situation has escalated. I've brought in a specialist.

Say nothing to Dave.`;

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

// a throwaway cast, made fresh each run so no private key lives in the repo
async function makeCast() {
  const home = await mkdtemp(join(tmpdir(), 'web-crypt-shots-'));
  const gpg = (args, input) =>
    execFileSync(
      'gpg',
      [
        '--homedir', home,
        '--batch', '--yes', '--quiet',
        '--pinentry-mode', 'loopback', '--passphrase', '',
        ...args,
      ],
      { input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] },
    );
  const ageKey = () => {
    const out = execFileSync('age-keygen', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return {
      public: out.match(/public key: (age1\S+)/)[1],
      secret: out.match(/AGE-SECRET-KEY-1\S+/)[0],
    };
  };

  try {
    const me = 'Sam (rightful yoghurt owner) <sam@example.com>';
    const dave = 'Dave from Accounts <dave@example.com>';
    const gran = 'Gran (knows more PGP than you) <gran@example.com>';
    const spy = 'Definitely Not A Spy <not.a.spy@example.com>';
    for (const uid of [me, dave, gran, spy]) {
      gpg(['--quick-gen-key', uid, 'future-default', 'default', 'never']);
    }

    const reply = gpg(
      [
        '--armor', '--trust-model', 'always',
        '--local-user', 'dave@example.com',
        '--recipient', 'sam@example.com',
        // gpg compresses by default, and signatures inside a compressed
        // packet are not read
        '--compress-algo', 'none',
        '--sign', '--encrypt',
      ],
      REPLY,
    );

    return {
      keys: [
        { label: 'Me, on the good laptop', material: ageKey().secret },
        { label: 'Sir Pounce (the cat)', material: ageKey().public },
        { label: "Nan's new iPad", material: ageKey().public },
        { material: gpg(['--armor', '--export-secret-keys', 'sam@example.com']) },
        { material: gpg(['--armor', '--export', 'dave@example.com']) },
        { material: gpg(['--armor', '--export', 'gran@example.com']) },
        { material: gpg(['--armor', '--export', 'not.a.spy@example.com']) },
      ],
      reply,
    };
  } finally {
    await rm(home, { recursive: true, force: true });
  }
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, ORIGIN);
  let path = join(ROOT, normalize(decodeURIComponent(url.pathname)));
  try {
    if ((await stat(path)).isDirectory()) path = join(path, 'index.html');
  } catch {
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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// everything below goes through the semantics tree, since flutter paints the
// rest to a canvas
async function enableSemantics(page) {
  await page.evaluate(() =>
    document.querySelector('flt-semantics-placeholder')?.click(),
  );
  await sleep(1500);
}

async function waitFor(page, check, what, timeout = 30_000) {
  try {
    await page.waitForFunction(check, { timeout, polling: 250 });
  } catch {
    throw new Error(`gave up waiting for ${what}`);
  }
}

const hasText = (page, text) =>
  waitFor(
    page,
    `[...document.querySelectorAll('flt-semantics')].some((n) =>
      (n.getAttribute('aria-label') ?? n.textContent ?? '').includes(${JSON.stringify(text)}))`,
    `"${text}"`,
  );

// the last match, so a button in a sheet or dialog wins over the one behind
// it. widest picks a full-width action over a nav item of the same name
async function press(page, name, { widest = false } = {}) {
  const selector = 'flt-semantics[role=button], flt-semantics[role=radio]';
  await waitFor(
    page,
    `[...document.querySelectorAll(${JSON.stringify(selector)})].some((n) =>
      [n.getAttribute('aria-label'), n.textContent].some((t) => (t ?? '').trim() === ${JSON.stringify(name)}))`,
    `a "${name}" button`,
  );
  await page.evaluate(
    (selector, name, widest) => {
      const hits = [...document.querySelectorAll(selector)].filter((n) =>
        [n.getAttribute('aria-label'), n.textContent].some(
          (t) => (t ?? '').trim() === name,
        ),
      );
      if (widest) {
        const width = (n) => n.getBoundingClientRect().width;
        hits.sort((a, b) => width(a) - width(b));
      }
      hits.at(-1).click();
    },
    selector,
    name,
    widest,
  );
  await sleep(600);
}

// a field's label is its hint until it has text, so the message boxes go by
// tag, there being one textarea per screen
const labelled = (label) =>
  `input[aria-label="${label}"], textarea[aria-label="${label}"]`;

// insertText rather than typing, since a pasted key is a thousand characters
async function fill(page, selector, text) {
  await page.waitForSelector(selector, { timeout: 30_000 });
  const fields = await page.$$(selector);
  await fields.at(-1).click();
  await sleep(200);
  await page.keyboard.down('Control');
  await page.keyboard.press('a');
  await page.keyboard.up('Control');
  await page.keyboard.sendCharacter(text);
  await sleep(300);
}

// in-app navigation without a reload, so the unlocked keyring survives. the
// rail has no semantics nodes to press
async function go(page, path) {
  await page.evaluate((path) => {
    history.pushState(null, '', path);
    dispatchEvent(new PopStateEvent('popstate', { state: null }));
  }, path);
  await sleep(1500);
}

async function setTheme(page, dark) {
  await page.emulateMediaFeatures([
    { name: 'prefers-color-scheme', value: dark ? 'dark' : 'light' },
  ]);
  await sleep(800);
}

// off the last field clicked, which would otherwise keep its hover tint
async function shoot(page, name) {
  await page.evaluate(() => document.activeElement?.blur());
  await page.mouse.move(1, 1);
  await sleep(1200);
  await page.screenshot({ path: join(OUT, `${name}.png`) });
  console.log(name);
}

async function importKeys(page, keys) {
  await go(page, '/keys');
  let vaultReady = false;
  for (const key of keys) {
    await press(page, 'Import');
    await fill(page, labelled('Or paste it here'), key.material);
    if (key.label) await fill(page, labelled('Label'), key.label);
    await press(page, 'Import');
    const isPrivate =
      key.material.includes('PRIVATE') || key.material.startsWith('AGE-SECRET');
    if (!vaultReady && isPrivate) {
      await fill(page, labelled('Master password'), MASTER_PASSWORD);
      await fill(page, labelled('Master password again'), MASTER_PASSWORD);
      await press(page, 'Continue');
      vaultReady = true;
    }
    // a successful import opens that key's details
    await hasText(page, 'Export public');
    await page.keyboard.press('Escape');
    await sleep(800);
  }
}

async function fillEncrypt(page, { passphrase = true } = {}) {
  await go(page, '/encrypt');
  // the last result outlives a layout change
  const done = await page.evaluate(() =>
    [...document.querySelectorAll('flt-semantics')].some((n) =>
      (n.textContent ?? '').includes('Send this whole block'),
    ),
  );
  if (done) await press(page, 'Start over');
  await press(page, 'age');
  await press(page, 'Passphrase');
  await fill(page, 'textarea', MESSAGE);
  // below the fold on a phone, where a click on them lands on something else
  if (!passphrase) return;
  await fill(page, labelled('Passphrase'), PASSPHRASE);
  await fill(page, labelled('Passphrase again'), PASSPHRASE);
}

async function pickRecipient(page, name) {
  await press(page, 'From keyring');
  const item = `[...document.querySelectorAll('flt-semantics[role]')]
    .findLast((n) => (n.textContent ?? '').includes(${JSON.stringify(name)}))`;
  await waitFor(page, `!!${item}`, `"${name}" in the keyring menu`);
  await page.evaluate(`${item}.click()`);
  await sleep(600);
}

async function fillRecipients(page) {
  await go(page, '/encrypt');
  await press(page, 'PGP');
  await press(page, 'Recipients');
  await fill(page, 'textarea', ESCALATION);
  await pickRecipient(page, 'Gran');
  await pickRecipient(page, 'Definitely Not A Spy');
}

async function decryptReply(page, reply) {
  await go(page, '/decrypt');
  await fill(page, 'textarea', reply);
  await press(page, 'Decrypt', { widest: true });
  await hasText(page, 'Signature checks out');
}

const cast = await makeCast();
await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve));
await mkdir(OUT, { recursive: true });

const browser = await puppeteer.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});

const page = await browser.newPage();
try {
  await page.setViewport(WEB);
  await setTheme(page, false);
  await page.goto(`${ORIGIN}/encrypt`, {
    waitUntil: 'networkidle0',
    timeout: 60_000,
  });
  await page.waitForFunction(() => !document.getElementById('boot'), {
    timeout: 60_000,
  });
  await sleep(2000);
  await enableSemantics(page);

  await importKeys(page, cast.keys);

  await fillEncrypt(page);
  await shoot(page, 'encrypt-light');

  await fillRecipients(page);
  await shoot(page, 'recipients-light');

  await press(page, 'Encrypt', { widest: true });
  await hasText(page, 'Send this whole block');
  await setTheme(page, true);
  await shoot(page, 'encrypted-dark');

  await decryptReply(page, cast.reply);
  await shoot(page, 'decrypt-dark');

  await go(page, '/keys');
  await setTheme(page, false);
  await shoot(page, 'keys-light');

  await page.setViewport(MOBILE);
  await sleep(1500);
  await fillEncrypt(page, { passphrase: false });
  await shoot(page, 'mobile-encrypt-light');

  await decryptReply(page, cast.reply);
  await setTheme(page, true);
  await shoot(page, 'mobile-decrypt-dark');
} catch (error) {
  await page.screenshot({ path: join(OUT, 'failed.png') });
  throw error;
} finally {
  await browser.close();
  server.close();
}
