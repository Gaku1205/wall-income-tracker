#!/usr/bin/env node
// 画面を本物のブラウザで開いて、決まった幅で撮る（工場のデザイン部門の試作と、実装AIの「撮って見て直す」で使う）。
// 依存なし：taste-skill の Chrome の操作（.claude/skills/taste-skill/scripts/lib/cdp.mjs）を使う。Node 22 以上と Chrome が要る。
//
//   node .github/scripts/shot.mjs [--serve] [--out DIR] [--widths 390,1440,1920] [--full] [--reduced] [--steps FILE] 対象...
//
//   対象：--serve のときはパス（/ や /settings）。そうでなければ URL か HTML のファイル（例：factory-proto/01-empty.html）
//   --serve：ビルド済みのアプリを npm run start で立ち上げてから撮り、撮り終わったら止める（先に npm run build が要る）
//   --steps：操作してから撮る場面を JSON で書いたファイル。対象の代わりに使う（両方書いてもよい）
//     [{ "name": "after-record", "path": "/", "steps": [
//        { "storage": { "キー": "値" } },      ← localStorage に入れて読み込み直す（データが入った状態を作る）
//        { "click": "記録する" },              ← 見えている文字（ボタン・リンク）か CSS セレクタ（# . [ で始まる物など）を押す
//        { "fill": ["金額", "1200"] },         ← 入力欄に打ち込む（ラベル・placeholder の文字か CSS セレクタで探す）
//        { "press": "Enter" }, { "wait": 500 }, { "scroll": 800 } ] }]
//   --full：画面の下まで全部撮る（無ければ最初の1画面だけ）
//   --reduced：prefers-reduced-motion を有効にして撮る
// 出力：DIR/<名前>-<幅>.png（DIR の既定は .shots）。撮った画像の一覧と、ページで起きたエラーを表示する
// 終了コード：撮れた → 0、撮れなかった物がある → 1、使い方の間違い → 2
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, statSync, createReadStream } from 'node:fs';
import { createServer } from 'node:http';
import { basename, dirname, extname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const cdpPath = resolve(here, '../../.claude/skills/taste-skill/scripts/lib/cdp.mjs');
if (!existsSync(cdpPath)) {
  console.error('taste-skill の cdp.mjs が見つかりません：' + cdpPath);
  process.exit(2);
}
const { Browser, sleep } = await import(pathToFileURL(cdpPath).href);

const args = process.argv.slice(2);
const flag = (name, def) => {
  const i = args.indexOf('--' + name);
  if (i === -1) return def;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
};
const has = (name) => {
  const i = args.indexOf('--' + name);
  if (i === -1) return false;
  args.splice(i, 1);
  return true;
};
const outDir = resolve(flag('out', '.shots'));
const widths = String(flag('widths', '390,1440,1920')).split(',').map(Number).filter((n) => n >= 200 && n <= 3000);
const stepsFile = flag('steps', '');
const serve = has('serve');
const full = has('full');
const reduced = has('reduced');
const HEIGHT = { 360: 780, 375: 812, 390: 844, 768: 1024, 1024: 768, 1280: 800, 1440: 900, 1920: 1080, 2560: 1440 };

if (args.some((a) => a.startsWith('--')) || (!args.length && !stepsFile) || !widths.length) {
  console.error('使い方：node .github/scripts/shot.mjs [--serve] [--out DIR] [--widths 390,1440,1920] [--full] [--reduced] [--steps FILE] 対象...');
  process.exit(2);
}

// 撮る場面：{ name, target, steps }
const safeName = (s) => String(s).replace(/^\/+|\/+$/g, '').replace(/[^A-Za-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || 'top';
const scenes = args.map((t) => ({
  name: /^https?:\/\//.test(t) ? safeName(new URL(t).pathname) : serve ? safeName(t) : safeName(basename(t, extname(t))),
  target: t,
  steps: [],
}));
if (stepsFile) {
  let list;
  try {
    list = JSON.parse(readFileSync(stepsFile, 'utf8'));
  } catch (e) {
    console.error('--steps のファイルを読めません：' + e.message);
    process.exit(2);
  }
  if (!Array.isArray(list)) {
    console.error('--steps のファイルは、場面の配列にしてください');
    process.exit(2);
  }
  for (const s of list) {
    if (!s || typeof s !== 'object' || typeof (s.path ?? s.target) !== 'string') {
      console.error('--steps の場面には path（または target）が要ります：' + JSON.stringify(s));
      process.exit(2);
    }
    scenes.push({ name: safeName(s.name || s.path || s.target), target: s.path ?? s.target, steps: Array.isArray(s.steps) ? s.steps : [] });
  }
}

// HTML のファイルは、使い捨てのサーバーで返す（相対パスの画像や CSS が、公開したときと同じに読める）
let fileServer = null;
let fileRoot = '';
async function fileUrl(target) {
  const file = resolve(target);
  if (!existsSync(file)) throw new Error('ファイルがありません：' + target);
  if (!fileServer) {
    fileRoot = resolve('.');
    fileServer = createServer((req, res) => {
      try {
        let f = resolve(join(fileRoot, decodeURIComponent(new URL(req.url, 'http://x').pathname)));
        if (f !== fileRoot && !f.startsWith(fileRoot + sep)) {
          res.writeHead(403);
          return res.end();
        }
        if (statSync(f).isDirectory()) f = join(f, 'index.html');
        const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.woff2': 'font/woff2', '.json': 'application/json' };
        res.writeHead(200, { 'content-type': types[extname(f).toLowerCase()] || 'application/octet-stream', 'cache-control': 'no-store' });
        createReadStream(f).pipe(res);
      } catch {
        res.writeHead(404);
        res.end('not found');
      }
    });
    await new Promise((r) => fileServer.listen(0, '127.0.0.1', r));
  }
  if (!file.startsWith(fileRoot + sep)) throw new Error('今いるフォルダの外のファイルは撮れません：' + target);
  return `http://127.0.0.1:${fileServer.address().port}/${relative(fileRoot, file).split(sep).map(encodeURIComponent).join('/')}`;
}

// --serve：ビルド済みのアプリを立ち上げる
let app = null;
let base = '';
async function startApp() {
  if (!existsSync('package.json')) throw new Error('package.json が無いので、アプリを立ち上げられません');
  if (!existsSync('.next') && !existsSync('dist') && !existsSync('build')) {
    throw new Error('ビルドした物がありません。先に npm run build をしてください');
  }
  const port = 3400 + Math.floor(Math.random() * 500);
  base = `http://127.0.0.1:${port}`;
  app = spawn('npm', ['run', 'start', '--', '-p', String(port)], {
    env: { ...process.env, PORT: String(port), NODE_ENV: 'production' },
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: true,
  });
  let log = '';
  app.stdout.on('data', (d) => (log += d));
  app.stderr.on('data', (d) => (log += d));
  const until = Date.now() + 90000;
  while (Date.now() < until) {
    if (app.exitCode !== null) throw new Error('アプリが立ち上がる前に止まりました\n' + log.slice(-1500));
    try {
      await fetch(base + '/', { signal: AbortSignal.timeout(3000) });
      return;
    } catch {
      await sleep(500);
    }
  }
  throw new Error('90秒たってもアプリが立ち上がりませんでした\n' + log.slice(-1500));
}
function stopApp() {
  if (!app || app.exitCode !== null) return;
  try {
    process.kill(-app.pid, 'SIGTERM');
  } catch {
    try {
      app.kill('SIGTERM');
    } catch {}
  }
}
process.once('exit', stopApp);

async function urlOf(target) {
  if (/^https?:\/\//.test(target)) return target;
  if (serve) return base + (target.startsWith('/') ? target : '/' + target);
  return fileUrl(target);
}

// 見えている文字か CSS セレクタで、押す物の真ん中の位置を探す
const FIND = `(q, field) => {
  const visible = (el) => { const r = el.getBoundingClientRect(); const cs = getComputedStyle(el); return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none'; };
  let el = null;
  if (/^[#.\\[]/.test(q) || /^[a-z]+[#.\\[:]/.test(q)) { try { el = [...document.querySelectorAll(q)].find(visible) || null; } catch {} }
  if (!el) {
    const sel = field
      ? 'label, input, textarea, select, [contenteditable=true]'
      : 'button, a, label, summary, [role=button], [role=tab], [role=menuitem], input[type=submit], input[type=button]';
    const all = [...document.querySelectorAll(sel)].filter(visible);
    const text = (e) => (e.innerText || e.getAttribute('aria-label') || e.getAttribute('placeholder') || (field ? '' : e.value) || '').replace(/\\s+/g, ' ').trim();
    el = all.find((e) => text(e) === q) || all.find((e) => text(e).includes(q)) || null;
  }
  if (el && field && el.tagName === 'LABEL') el = el.control;
  if (!el) return null;
  el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
  const r = el.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
}`;
const KEYS = { Enter: 13, Tab: 9, Escape: 27, Backspace: 8, ArrowDown: 40, ArrowUp: 38, ArrowLeft: 37, ArrowRight: 39, Space: 32 };

async function runStep(page, url, step) {
  if (step.storage && typeof step.storage === 'object') {
    await page.eval((items) => {
      for (const [k, v] of Object.entries(items)) localStorage.setItem(k, typeof v === 'string' ? v : JSON.stringify(v));
      return true;
    }, step.storage);
    await page.goto(url, { timeoutMs: 30000, settleMs: 800 });
  } else if (typeof step.click === 'string') {
    const at = await page.eval(`(${FIND})(${JSON.stringify(step.click)}, false)`);
    if (!at) throw new Error('押す物が見つかりません：' + step.click);
    await sleep(150);
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
      await page.send('Input.dispatchMouseEvent', { type, x: at.x, y: at.y, button: 'left', clickCount: 1 });
    }
    await sleep(400);
  } else if (Array.isArray(step.fill) && step.fill.length === 2) {
    const at = await page.eval(`(${FIND})(${JSON.stringify(step.fill[0])}, true)`);
    if (!at) throw new Error('入力欄が見つかりません：' + step.fill[0]);
    for (const type of ['mousePressed', 'mouseReleased']) {
      await page.send('Input.dispatchMouseEvent', { type, x: at.x, y: at.y, button: 'left', clickCount: 1 });
    }
    await page.eval('document.activeElement && document.activeElement.select ? (document.activeElement.select(), true) : true');
    await page.send('Input.insertText', { text: String(step.fill[1]) });
    await sleep(200);
  } else if (typeof step.press === 'string') {
    const code = KEYS[step.press] || 0;
    const key = step.press === 'Space' ? ' ' : step.press;
    await page.send('Input.dispatchKeyEvent', { type: 'keyDown', key, windowsVirtualKeyCode: code, text: key === 'Enter' ? '\r' : key.length === 1 ? key : undefined });
    await page.send('Input.dispatchKeyEvent', { type: 'keyUp', key, windowsVirtualKeyCode: code });
    await sleep(300);
  } else if (typeof step.wait === 'number') {
    await sleep(Math.min(Math.max(step.wait, 0), 20000));
  } else if (typeof step.scroll === 'number') {
    await page.eval(`window.scrollTo({ top: ${step.scroll}, behavior: 'instant' })`);
    await sleep(400);
  } else {
    throw new Error('分からない操作です：' + JSON.stringify(step));
  }
}

let failed = 0;
const written = [];
mkdirSync(outDir, { recursive: true });
let browser = null;
try {
  if (serve) await startApp();
  browser = await Browser.launch();
  for (const scene of scenes) {
    let url;
    try {
      url = await urlOf(scene.target);
    } catch (e) {
      console.error(`× ${scene.name}：${e.message}`);
      failed++;
      continue;
    }
    for (const w of widths) {
      const h = HEIGHT[w] || Math.round(w * 0.625);
      const page = await browser.newPage({ width: w, height: h, dsf: 1, mobile: w < 600, reducedMotion: reduced });
      try {
        await page.goto(url, { timeoutMs: 30000, settleMs: 800 });
        for (const step of scene.steps) await runStep(page, url, step);
        await page.eval('document.fonts.ready.then(() => true)').catch(() => {});
        await sleep(500);
        const path = join(outDir, `${scene.name}-${w}.png`);
        await page.screenshot({ path, format: 'png', fullPage: full });
        written.push(path);
        if (page.consoleErrors.length) console.log(`  ! ${scene.name}-${w}：ページのエラー：${page.consoleErrors.slice(0, 3).join(' / ')}`);
      } catch (e) {
        console.error(`× ${scene.name}-${w}：${e.message}`);
        failed++;
      } finally {
        await page.close();
      }
    }
  }
} catch (e) {
  console.error('× ' + e.message);
  failed++;
} finally {
  if (browser) await browser.close();
  if (fileServer) fileServer.close();
  stopApp();
}
if (written.length) {
  console.log('撮った画像（全部 Read で見てください）：');
  for (const p of written) {
    const r = relative(process.cwd(), p);
    console.log('  ' + (r.startsWith('..') ? p : r));
  }
}
process.exit(failed ? 1 : 0);
