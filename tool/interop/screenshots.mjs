// takes the screenshots the readme uses, serving the built web app locally
// and capturing each screen in both themes and at both layouts.
//
//     flutter build web --release --no-web-resources-cdn
//     node tool/interop/screenshots.mjs .github/screenshots
import { createServer } from 'node:http';
import { mkdir, readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import puppeteer from 'puppeteer';

const ROOT = process.env.WEB_ROOT ?? 'build/web';
const OUT = process.argv[2] ?? '.github/screenshots';
const PORT = Number(process.env.PORT ?? 8155);
const ORIGIN = `http://127.0.0.1:${PORT}`;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
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

const SHOTS = [
  { name: 'encrypt-light', route: '/encrypt', width: 1180, height: 820 },
  { name: 'decrypt-light', route: '/decrypt', width: 1180, height: 820 },
  { name: 'keys-dark', route: '/keys', width: 1180, height: 820, dark: true },
  { name: 'settings-light', route: '/settings', width: 1180, height: 900 },
  { name: 'encrypt-narrow', route: '/encrypt', width: 420, height: 860 },
];

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

await new Promise((resolve) => server.listen(PORT, '127.0.0.1', resolve));
await mkdir(OUT, { recursive: true });

const browser = await puppeteer.launch({
  headless: 'new',
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});

try {
  for (const shot of SHOTS) {
    const page = await browser.newPage();
    await page.setViewport({
      width: shot.width,
      height: shot.height,
      deviceScaleFactor: 2,
    });
    await page.emulateMediaFeatures([
      { name: 'prefers-color-scheme', value: shot.dark ? 'dark' : 'light' },
    ]);
    await page.goto(`${ORIGIN}${shot.route}`, {
      waitUntil: 'networkidle0',
      timeout: 60_000,
    });
    await sleep(3500);
    await page.screenshot({ path: join(OUT, `${shot.name}.png`) });
    await page.close();
    console.log(shot.name);
  }
} finally {
  await browser.close();
  server.close();
}
