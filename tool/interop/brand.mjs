// draws every app icon, the link preview banner and the install screenshots
// from the one logo below, then writes them over the copies in the repo
//
//     node tool/interop/brand.mjs
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import puppeteer from 'puppeteer';

const LIGHT = { tile: '#1e5f74', ink: '#ffffff' };
const DARK = { tile: '#6fb3c6', ink: '#10221e' };

// a shield with a keyhole, on the 24 unit grid the Material icons use. the
// app's AppLogo and the splash in web/index.html draw the same shapes
const SHIELD =
  'M12 2.6 19 5.3v5.6c0 4.6-2.9 8.6-7 10.5-4.1-1.9-7-5.9-7-10.5V5.3z';
const KEYHOLE =
  '<circle cx="12" cy="10.3" r="2.15"/><path d="M11.25 11.4h1.5l.75 4.3h-3z"/>';

const colors = ({ tile, ink }) =>
  `.tile{fill:${tile}}.ink{fill:${ink};stroke:${ink}}`;
const SHADOW =
  '<filter id="s"><feDropShadow dx="0" dy=".24" stdDeviation=".3" ' +
  'flood-opacity=".3"/></filter>';

// inset and rx shape the tile, scale sizes the shield on it
function logo({ inset = 0, rx = 5.3, scale = 0.72, shadow = false, dark }) {
  const size = 24 - 2 * inset;
  const glyph = +((scale * size) / 24).toFixed(3);
  const css = dark ? `@media (prefers-color-scheme:dark){${colors(DARK)}}` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<style>${colors(LIGHT)}${css}</style>${shadow ? SHADOW : ''}
<rect class="tile" x="${inset}" y="${inset}" width="${size}" height="${size}"
  rx="${rx}"${shadow ? ' filter="url(#s)"' : ''}/>
<g transform="translate(12 12) scale(${glyph}) translate(-12 -12)">
<path class="ink" d="${SHIELD}" stroke-width="1.2" stroke-linejoin="round"/>
<g class="tile">${KEYHOLE}</g>
</g>
</svg>
`;
}

const ROUNDED = logo({});
// iOS rounds the corners itself, and fills transparent ones with black
const SQUARE = logo({ rx: 0 });
// Android crops these to its own shape, so the shield stays well inside
const MASKABLE = logo({ rx: 0, scale: 0.6 });
// Apple's grid, an 824 tile with a soft shadow on a 1024 canvas
const MAC = logo({ inset: 2.34, rx: 4.35, shadow: true });

const browser = await puppeteer.launch({ headless: true });
const page = await browser.newPage();

async function shoot(html, width, height, type = 'png') {
  await page.setViewport({ width, height, deviceScaleFactor: 1 });
  await page.setContent(`<style>body{margin:0}</style>${html}`);
  await page.evaluate(() => document.fonts.ready);
  const options = { type, omitBackground: true };
  if (type === 'webp') options.quality = 90;
  return Buffer.from(await page.screenshot(options));
}

const png = (svg, size) =>
  shoot(svg.replace('<svg ', '<svg width="100%" height="100%" '), size, size);

// png entries in an ico work everywhere from Windows Vista on
async function ico(svg, sizes) {
  const images = [];
  for (const size of sizes) images.push([size, await png(svg, size)]);
  const head = Buffer.alloc(6 + 16 * images.length);
  head.writeUInt16LE(1, 2);
  head.writeUInt16LE(images.length, 4);
  let offset = head.length;
  images.forEach(([size, data], i) => {
    const at = 6 + 16 * i;
    // 256 is written as 0
    head.writeUInt8(size % 256, at);
    head.writeUInt8(size % 256, at + 1);
    head.writeUInt16LE(1, at + 4);
    head.writeUInt16LE(32, at + 6);
    head.writeUInt32LE(data.length, at + 8);
    head.writeUInt32LE(offset, at + 12);
    offset += data.length;
  });
  return Buffer.concat([head, ...images.map(([, data]) => data)]);
}

const dataUrl = async (path, type) =>
  `data:${type};base64,${(await readFile(path)).toString('base64')}`;

const font = async (weight, file) =>
  `@font-face{font-family:Inter;font-weight:${weight};src:url(${await dataUrl(
    `assets/fonts/${file}`,
    'font/ttf',
  )})}`;

// what a shared link shows, the name and pitch beside the app itself
async function banner() {
  const shot = await dataUrl(
    '.github/screenshots/encrypt-light.png',
    'image/png',
  );
  return shoot(
    `<style>
${await font(400, 'Inter-Regular.ttf')}
${await font(500, 'Inter-Medium.ttf')}
${await font(600, 'Inter-SemiBold.ttf')}
body{width:1200px;height:630px;overflow:hidden;position:relative;
  background:#fbfbfa;color:#1a1a18;font-family:Inter}
.copy{position:absolute;left:80px;top:0;bottom:0;width:470px;
  display:flex;flex-direction:column;justify-content:center}
.copy svg{width:84px;height:84px}
h1{font-size:68px;font-weight:600;letter-spacing:-1.5px;margin:32px 0 14px}
p{font-size:28px;line-height:1.4;color:#56564f;margin:0}
.tags{display:flex;gap:10px;margin-top:34px}
.tags span{font-size:19px;font-weight:500;color:#1e5f74;background:#e8f0f3;
  padding:7px 14px;border-radius:7px}
img{position:absolute;left:620px;top:96px;width:760px;
  border:1px solid #e2e2de;border-radius:14px}
</style>
<div class="copy">
  ${ROUNDED}
  <h1>web-crypt</h1>
  <p>Encrypt and decrypt messages and files, all on your own device</p>
  <div class="tags"><span>age</span><span>OpenPGP</span>
    <span>Offline</span><span>Open source</span></div>
</div>
<img src="${shot}">`,
    1200,
    630,
  );
}

// for the install dialog, scaled down from the readme screenshots
async function screenshot(file, width, height) {
  const src = await dataUrl(`.github/screenshots/${file}`, 'image/png');
  return shoot(
    `<img src="${src}" style="display:block;width:100vw;height:100vh">`,
    width,
    height,
    'webp',
  );
}

const outputs = {
  'web/favicon.svg': logo({ dark: true }),
  'web/favicon.ico': () => ico(ROUNDED, [16, 32, 48]),
  'web/icons/apple-touch-icon.png': () => png(SQUARE, 180),
  'web/icons/Icon-192.png': () => png(ROUNDED, 192),
  'web/icons/Icon-512.png': () => png(ROUNDED, 512),
  'web/icons/Icon-maskable-192.png': () => png(MASKABLE, 192),
  'web/icons/Icon-maskable-512.png': () => png(MASKABLE, 512),
  'web/banner.png': banner,
  'web/screenshots/wide.webp': () => screenshot('encrypt-light.png', 1180, 820),
  'web/screenshots/narrow.webp': () =>
    screenshot('mobile-encrypt-light.png', 585, 1266),
  'windows/runner/resources/app_icon.ico': () =>
    ico(ROUNDED, [16, 20, 24, 32, 40, 48, 64, 256]),
  'linux/runner/resources/app_icon.png': () => png(ROUNDED, 256),
};
const MAC_ICONS = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
for (const size of [16, 32, 64, 128, 256, 512, 1024]) {
  outputs[`${MAC_ICONS}/app_icon_${size}.png`] = () => png(MAC, size);
}

try {
  for (const [path, make] of Object.entries(outputs)) {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, typeof make === 'function' ? await make() : make);
    console.log(path);
  }
} finally {
  await browser.close();
}
