// CI regression guard for the web build: load the exported game in headless Chromium
// (SwiftShader WebGL2), skip straight into a Hunt (?autohunt, main_menu.gd), and fail if the
// centre of the screen is near-uniform. That is the "HUD over plain sky, no city" failure:
// in Godot 4.3's single-threaded web build, a scene over 1000 instances used to cull to
// nothing (see threaded_cull_minimum_instances.web in game/project.godot).
//
// usage (run from a directory where playwright is installed):
//   node web_render_check.js http://localhost:8060/index.html <screenshot dir>
const path = require('path');
const fs = require('fs');
const { chromium } = require(require.resolve('playwright', { paths: [process.cwd()] }));

const url = process.argv[2];
const outDir = process.argv[3] || 'web-render-check';
const READY_TIMEOUT_MS = 240000; // SwiftShader on CI runners is slow (about 1 fps)
const SETTLE_MS = 15000; // the Hunt's fade-in and first frames after HUNT_READY
const MIN_STDDEV = 12; // broken (sky only) measures about 5.5; a drawn city 25-85

async function centreStddev(browser, png) {
  // decode the screenshot in a blank page's canvas (no image libraries needed)
  const page = await browser.newPage();
  const v = await page.evaluate(async (b64) => {
    const img = new Image();
    img.src = 'data:image/png;base64,' + b64;
    await img.decode();
    const c = document.createElement('canvas');
    c.width = img.width; c.height = img.height;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0);
    const x0 = Math.floor(img.width * 0.25), x1 = Math.floor(img.width * 0.75);
    const y0 = Math.floor(img.height * 0.45), y1 = Math.floor(img.height * 0.8);
    const d = g.getImageData(x0, y0, x1 - x0, y1 - y0).data;
    let s = 0, s2 = 0, n = 0;
    for (let i = 0; i < d.length; i += 4) {
      const l = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      s += l; s2 += l * l; n++;
    }
    const m = s / n;
    return Math.sqrt(Math.max(0, s2 / n - m * m));
  }, png.toString('base64'));
  await page.close();
  return v;
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch({
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  const log = [];
  let ready = false;
  page.on('console', (m) => {
    log.push(m.type() + ': ' + m.text());
    if (m.text().includes('HUNT_READY')) ready = true;
  });
  page.on('pageerror', (e) => log.push('PAGEERROR: ' + e.message));
  const sep = url.includes('?') ? '&' : '?';
  await page.goto(url + sep + 'autohunt', { timeout: 120000 });

  const t0 = Date.now();
  while (!ready && Date.now() - t0 < READY_TIMEOUT_MS) await page.waitForTimeout(2000);
  if (!ready) {
    await page.screenshot({ path: path.join(outDir, 'timeout.png'), timeout: 120000 }).catch(() => {});
    fs.writeFileSync(path.join(outDir, 'console.txt'), log.join('\n'));
    console.error(`::error::the Hunt did not start within ${READY_TIMEOUT_MS / 1000}s (no HUNT_READY in the console)`);
    await browser.close();
    process.exit(1);
  }
  console.log(`Hunt ready after ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  await page.waitForTimeout(SETTLE_MS);

  // a few samples: pass as soon as one shows real geometry in the centre
  let best = 0;
  for (let i = 0; i < 3; i++) {
    const png = await page.screenshot({ path: path.join(outDir, `hunt_${i}.png`), timeout: 120000 });
    const sd = await centreStddev(browser, png);
    console.log(`sample ${i}: centre luminance stddev ${sd.toFixed(1)} (need >= ${MIN_STDDEV})`);
    best = Math.max(best, sd);
    if (best >= MIN_STDDEV) break;
    await page.waitForTimeout(10000);
  }
  fs.writeFileSync(path.join(outDir, 'console.txt'), log.join('\n'));
  await browser.close();
  if (best < MIN_STDDEV) {
    console.error('::error::web build renders the Hunt as a near-uniform screen (no city / Sol): see the web-render-check screenshots');
    process.exit(1);
  }
  console.log('web render check: PASS');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
