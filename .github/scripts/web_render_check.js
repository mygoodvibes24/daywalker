// CI regression guard for the web build: load the exported game in headless Chromium
// (SwiftShader WebGL2), skip straight into a Hunt (?autohunt, main_menu.gd), and fail if the
// centre of the screen is near-uniform. That is the "HUD over plain sky, no city" failure:
// in Godot 4.3's single-threaded web build, a scene over 1000 instances used to cull to
// nothing (see threaded_cull_minimum_instances.web in game/project.godot).
//
// It then also guards the sound: the browser's autoplay policy is left on (like a real player's),
// so the page starts with a suspended AudioContext. One click must unlock it, and the Web Audio
// output (an AnalyserNode tapped onto the destination) must then be non-silent, with no cycle in
// the bus graph. Godot 4.3's web "Sample" playback once wired Master into a child bus and back
// (buses added at runtime with AudioServer.add_bus()), and the browser silences such a cycle: no
// sound at all on the web. See settings.gd ensure_buses() and default_bus_layout.tres.
//
// Last, the walkable lair (?lair, scenes/lair.tscn: where Start and a Hunt's results land) must load
// (LAIR_READY in the console) and draw the room, not a black or uniform screen.
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
const MIN_RMS = 0.002;
const LAIR_MIN_STDDEV = 8; // the lair is a dark crypt: a drawn room measures well above this, black ~0 // the Hunt after a click (music, rain, a sword swing) measures about 0.05-0.15; broken 0

// Injected before the page loads: tap every AudioContext's destination with an analyser and
// record the audio graph's edges, so the check can measure the output and find a cycle.
function audioProbe() {
  const Base = window.AudioContext || window.webkitAudioContext;
  if (!Base) return;
  const A = { ctxs: [], taps: [], edges: new Map(), peak: 0, peakSince: 0 };
  window.__dwProbe = A;
  function Probed(...args) {
    const c = new Base(...args);
    const an = c.createAnalyser();
    an.fftSize = 2048;
    an.__tap = true;
    A.ctxs.push(c);
    A.taps.push(an);
    return c;
  }
  Probed.prototype = Base.prototype;
  window.AudioContext = Probed;
  if (window.webkitAudioContext) window.webkitAudioContext = Probed;
  const connect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dst, ...rest) {
    if (dst instanceof AudioNode && !this.__tap) {
      if (!A.edges.has(this)) A.edges.set(this, new Set());
      A.edges.get(this).add(dst);
      if (dst === this.context.destination) {
        const tap = A.taps[A.ctxs.indexOf(this.context)];
        if (tap) connect.call(this, tap);
      }
    }
    return connect.call(this, dst, ...rest);
  };
  const disconnect = AudioNode.prototype.disconnect;
  AudioNode.prototype.disconnect = function (dst, ...rest) {
    const e = A.edges.get(this);
    if (e) { if (dst instanceof AudioNode) e.delete(dst); else e.clear(); }
    return disconnect.call(this, dst, ...rest);
  };
  const buf = new Float32Array(2048);
  setInterval(() => {
    for (const t of A.taps) {
      t.getFloatTimeDomainData(buf);
      let s = 0;
      for (const v of buf) s += v * v;
      A.peak = Math.max(A.peak, Math.sqrt(s / buf.length));
    }
  }, 100);
  A.reset = () => { A.peak = 0; };
  A.cycle = () => {
    const state = new Map();
    let found = false;
    const dfs = (n) => {
      state.set(n, 1);
      for (const d of (A.edges.get(n) || [])) {
        if (found) return;
        if (state.get(d) === 1) { found = true; return; }
        if (!state.has(d)) dfs(d);
      }
      state.set(n, 2);
    };
    for (const n of A.edges.keys()) if (!found && !state.has(n)) dfs(n);
    return found;
  };
  A.report = () => ({ states: A.ctxs.map((c) => c.state), peak: A.peak, cycle: A.cycle() });
}

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
    // keep Chromium's autoplay policy (Playwright turns it off by default): audio must wait for a click
    ignoreDefaultArgs: ['--autoplay-policy=no-user-gesture-required'],
  });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  await page.addInitScript(audioProbe);
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

  // Sound. Nothing has clicked yet, so the page must still be silent; one click (an attack in
  // the Hunt) must unlock the AudioContext, and music, rain and the sword must then be audible.
  // (page.evaluate counts as a user gesture, so read the probe only after the click.)
  const vp = page.viewportSize();
  await page.mouse.click(vp.width * 0.5, vp.height * 0.55);
  await page.evaluate(() => window.__dwProbe && window.__dwProbe.reset());
  await page.waitForTimeout(2500);
  await page.mouse.click(vp.width * 0.5, vp.height * 0.55); // a second swing
  await page.waitForTimeout(6000);
  const aud = await page.evaluate(() => (window.__dwProbe ? window.__dwProbe.report() : null));
  console.log('audio after a click:', JSON.stringify(aud), `(need running, no cycle, peak RMS >= ${MIN_RMS})`);
  let audioOk = true;
  if (!aud || !aud.states.length) {
    console.error('::error::web build never created an AudioContext');
    audioOk = false;
  } else if (aud.cycle) {
    console.error('::error::the Web Audio bus graph has a cycle, which the browser silences (no sound at all): see settings.gd ensure_buses()');
    audioOk = false;
  } else if (!aud.states.includes('running')) {
    console.error('::error::a click did not unlock the AudioContext (still ' + aud.states.join(',') + ')');
    audioOk = false;
  } else if (aud.peak < MIN_RMS) {
    console.error('::error::web build is silent after a click in the Hunt (peak RMS ' + aud.peak.toFixed(4) + ')');
    audioOk = false;
  }

  // the lair: Start / results land here (?lair goes straight in)
  const lp = await browser.newPage({ viewport: { width: 960, height: 540 } });
  let lairReady = false;
  lp.on('console', (m) => {
    log.push('lair ' + m.type() + ': ' + m.text());
    if (m.text().includes('LAIR_READY')) lairReady = true;
  });
  lp.on('pageerror', (e) => log.push('lair PAGEERROR: ' + e.message));
  await lp.goto(url + sep + 'lair', { timeout: 120000 });
  const t1 = Date.now();
  while (!lairReady && Date.now() - t1 < READY_TIMEOUT_MS) await lp.waitForTimeout(2000);
  let lairSd = 0;
  if (lairReady) {
    await lp.waitForTimeout(SETTLE_MS);
    const png = await lp.screenshot({ path: path.join(outDir, 'lair.png'), timeout: 120000 });
    lairSd = await centreStddev(browser, png);
    console.log(`lair: centre luminance stddev ${lairSd.toFixed(1)} (need >= ${LAIR_MIN_STDDEV})`);
  }

  fs.writeFileSync(path.join(outDir, 'console.txt'), log.join('\n'));
  await browser.close();
  if (!lairReady) {
    console.error('::error::the lair did not load (no LAIR_READY in the console)');
    process.exit(1);
  }
  if (lairSd < LAIR_MIN_STDDEV) {
    console.error('::error::the lair renders as a near-uniform screen: see web-render-check/lair.png');
    process.exit(1);
  }
  if (best < MIN_STDDEV) {
    console.error('::error::web build renders the Hunt as a near-uniform screen (no city / Sol): see the web-render-check screenshots');
    process.exit(1);
  }
  if (!audioOk) process.exit(1);
  console.log('web render + audio check: PASS');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
