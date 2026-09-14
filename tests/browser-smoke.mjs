// 看板本机服务的浏览器冒烟测试：不装任何 npm 包，用 Node 自带的 WebSocket 走 Chrome DevTools 协议驱动无头 Chrome。
// 用法：node tests/browser-smoke.mjs <服务地址> <服务 pid>   —— 由 tests/review-board.sh 在它搭好的样例项目上调用。
// 最后一步会停掉那个服务，检查页面变成「服务已断开」。没有 Chrome 时退出码 77（调用方当作跳过）。
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, servePid] = process.argv.slice(2);
const chromeBin = process.env.CHROME_BIN || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
if (!existsSync(chromeBin)) { console.log("SKIP browser smoke: no Chrome at " + chromeBin); process.exit(77); }

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const profile = mkdtempSync(join(tmpdir(), "rb-smoke-"));
const chrome = spawn(chromeBin, ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--no-first-run", "--no-default-browser-check", "--window-size=1440,1000", "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
// 收尾：等 Chrome 真退出了再删临时配置目录（杀掉后它还会往里写一会儿，立刻删会留下残目录）
async function finish(code) {
  const exited = chrome.exitCode !== null ? Promise.resolve() : new Promise((r) => chrome.once("exit", r));
  try { chrome.kill("SIGKILL"); } catch {}
  await Promise.race([exited, sleep(5000)]);
  for (let i = 0; i < 5; i++) { try { rmSync(profile, { recursive: true, force: true }); break; } catch { await sleep(200); } }
  process.exit(code);
}
const fail = (step, detail) => { console.error(`FAIL browser smoke: ${step}${detail ? " — " + JSON.stringify(detail) : ""}`); return finish(1); };
setTimeout(() => fail("timed out after 90s"), 90000).unref();

// ---- 连上 Chrome：它把 DevTools 地址打到 stderr
const wsUrl = await new Promise((resolve, reject) => {
  let buf = "";
  chrome.stderr.on("data", (d) => { buf += d; const m = buf.match(/DevTools listening on (ws:\/\/\S+)/); if (m) resolve(m[1]); });
  chrome.on("exit", () => reject(new Error("chrome exited: " + buf.slice(-400))));
}).catch((e) => fail("start Chrome", String(e)));
const ws = new WebSocket(wsUrl);
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let seq = 0; const waiting = new Map();
ws.onmessage = (m) => { const msg = JSON.parse(m.data); if (msg.id && waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); } };
const send = (method, params = {}, sessionId) => new Promise((resolve) => {
  const id = ++seq; waiting.set(id, resolve); ws.send(JSON.stringify({ id, method, params, sessionId }));
});
const { result: { targetId } } = await send("Target.createTarget", { url: "about:blank" });
const { result: { sessionId } } = await send("Target.attachToTarget", { targetId, flatten: true });
await send("Page.enable", {}, sessionId);

// 在页面里跑一段 async 代码拿回 JSON；页面正在跳转（刷新）时重试
async function ev(body, tries = 20) {
  for (let i = 0; i < tries; i++) {
    const r = await send("Runtime.evaluate", { expression: `(async()=>{${body}})()`, awaitPromise: true, returnByValue: true }, sessionId);
    if (!r.error && !r.result?.exceptionDetails) return r.result.result.value;
    await sleep(300);
  }
  const r = await send("Runtime.evaluate", { expression: `(async()=>{${body}})()`, awaitPromise: true, returnByValue: true }, sessionId);
  return { __error: r.error || r.result?.exceptionDetails?.exception?.description };
}
async function until(step, body, ms = 8000) {
  const t0 = Date.now(); let last;
  while (Date.now() - t0 < ms) { last = await ev(body, 3); if (last === true) return; await sleep(250); }
  await fail(step, last);
}
const eta = `document.querySelector('.proj[data-p="eta/repo"]').click();await new Promise(r=>setTimeout(r,80));const P=document.querySelector('.panel.sel');`;

await send("Page.navigate", { url }, sessionId);
await until("page loads in live mode", `return document.body&&document.body.classList.contains('live')`);
await until("health pill is not red", `const h=document.querySelector('.hp');return !!h&&/\\b(ok|warn)\\b/.test(h.className)`);

// 点任务 → 右侧抽屉显示全文；Esc 关闭
await until("task drawer opens", `${eta}P.querySelector('[data-td]').click();await new Promise(r=>setTimeout(r,80));
  const d=document.querySelector('.drawer');return !d.hidden&&!!d.querySelector('.dtt')`);
await until("Esc closes the drawer", `document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));return document.querySelector('.drawer').hidden`);

// 加任务：预览按抽屉排版，顶格 ## 标红；不保存
await until("editor preview renders headings and warns about ##", `${eta}P.querySelector('[data-act="add"]').click();await new Promise(r=>setTimeout(r,80));
  const ed=document.querySelector('dialog.rbe');ed.querySelector('.rbe-title').value='冒烟';const b=ed.querySelector('.rbe-body');
  b.value='### 范围\\n- 一条\\n## 错的';b.dispatchEvent(new Event('input'));
  const ok=ed.open&&!!ed.querySelector('.rbe-pv .dh4')&&!!ed.querySelector('.rbe-pv .dli')&&!!ed.querySelector('.rbe-pv .dp.bad');
  ed.close();try{localStorage.clear()}catch(e){};return ok`);

// 放弃：确认框打开，取消后什么都不做
await until("drop confirmation opens and cancels", `${eta}const b=P.querySelector('ol.q li [data-act="drop"]');b.click();await new Promise(r=>setTimeout(r,80));
  const d=document.querySelector('dialog.rbd');const ok=d.open&&d.querySelector('.rbd-t').textContent.indexOf('放弃')===0&&!d.querySelector('.rbd-r').hidden;
  d.querySelector('.rbd-no').click();await new Promise(r=>setTimeout(r,80));return ok&&!d.open`);

// 确认框点「确认」真的生效（放行 / 放弃 / 暂停 / 恢复 / 开关循环共用同一段提交代码）：暂停再恢复
await until("confirming pause really pauses", `${eta}const b=P.querySelector('[data-act="pause"]');if(!b)return 'no pause button';b.click();
  await new Promise(r=>setTimeout(r,80));const d=document.querySelector('dialog.rbd');d.querySelector('.rbd-ok').click();
  for(let i=0;i<30&&d.querySelector('.rbd-out').hidden;i++)await new Promise(r=>setTimeout(r,100));
  const ok=/rbd-out ok/.test(d.querySelector('.rbd-out').className);if(ok)d.querySelector('.rbd-no').click();return ok`);
await sleep(1500);
await until("confirming resume really resumes", `${eta}const b=P.querySelector('[data-act="resume"]');if(!b)return 'no resume button';b.click();
  await new Promise(r=>setTimeout(r,80));const d=document.querySelector('dialog.rbd');d.querySelector('.rbd-ok').click();
  for(let i=0;i<30&&d.querySelector('.rbd-out').hidden;i++)await new Promise(r=>setTimeout(r,100));
  const ok=/rbd-out ok/.test(d.querySelector('.rbd-out').className);if(ok)d.querySelector('.rbd-no').click();return ok`);
await sleep(1500);

// 查看全部：列表、筛「放弃」、点一行看详情
await until("history drawer lists, filters and opens a task", `${eta}P.querySelector('[data-act="history"]').click();
  for(let i=0;i<30&&!document.querySelector('.drawer .hlist2 .drow');i++)await new Promise(r=>setTimeout(r,100));
  const all=document.querySelectorAll('.drawer .hlist2 .drow').length;
  [...document.querySelectorAll('.drawer .hf')].find(x=>x.textContent==='放弃').click();
  const rows=[...document.querySelectorAll('.drawer .hlist2 .drow')];const onlyDropped=rows.length>0&&rows.every(r=>r.classList.contains('dropped'));
  rows[0].click();const detail=!!document.querySelector('.drawer .hback');
  document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));return all>rows.length&&onlyDropped&&detail`);

// ↓ 调整顺序：页面刷新后第一个任务换了
const before = await ev(`${eta}return [...P.querySelectorAll('ol.q li .t')].map(x=>x.textContent)`);
if (!Array.isArray(before) || before.length < 2) await fail("need two pending tasks to move", before);
await ev(`${eta}P.querySelector('ol.q li[data-pos="1"] [data-act="down"]').click();return true`);
await sleep(1500);
await until("move down reorders the queue", `${eta}const t=[...P.querySelectorAll('ol.q li .t')].map(x=>x.textContent);
  return t[0]===${JSON.stringify(before[1])}&&t[1]===${JSON.stringify(before[0])}`, 10000);

// 停掉服务：圆点变红、按钮变灰
process.kill(Number(servePid));
await until("pill turns red and buttons disable when the service stops", `const h=document.querySelector('.hp');
  const b=document.querySelector('.panel.sel [data-act]');return /\\bbad\\b/.test(h.className)&&document.body.classList.contains('offline')&&(!b||getComputedStyle(b).pointerEvents==='none')`, 12000);

console.log("PASS browser smoke: live mode, health pill, task drawer, editor preview, drop dialog, confirm (pause/resume), history, move, offline");
ws.close(); await finish(0);
