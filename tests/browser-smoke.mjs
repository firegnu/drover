// 看板本机服务的浏览器冒烟测试：不装任何 npm 包，用 Node 自带的 WebSocket 走 Chrome DevTools 协议驱动无头 Chrome。
// 用法：node tests/browser-smoke.mjs <服务地址> <服务 pid>   —— 由 tests/drover-board.sh 在它搭好的样例项目上调用。
// 页面上每个按钮都点到「提交」为止，同时监听页面里所有未捕获的脚本错误：任何一个报错都算失败（只打开再取消测不出提交那段的错）。
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
setTimeout(() => fail("timed out after 150s"), 150000).unref();

// ---- 连上 Chrome：它把 DevTools 地址打到 stderr
const wsUrl = await new Promise((resolve, reject) => {
  let buf = "";
  chrome.stderr.on("data", (d) => { buf += d; const m = buf.match(/DevTools listening on (ws:\/\/\S+)/); if (m) resolve(m[1]); });
  chrome.on("exit", () => reject(new Error("chrome exited: " + buf.slice(-400))));
}).catch((e) => fail("start Chrome", String(e)));
const ws = new WebSocket(wsUrl);
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let seq = 0; const waiting = new Map(); const pageErrors = [];
ws.onmessage = (m) => {
  const msg = JSON.parse(m.data);
  if (msg.id && waiting.has(msg.id)) { waiting.get(msg.id)(msg); waiting.delete(msg.id); return; }
  if (msg.method === "Runtime.exceptionThrown") {                  // 页面里任何未捕获的脚本错误
    const d = msg.params.exceptionDetails;
    pageErrors.push((d.exception && d.exception.description) || d.text);
  }
};
const send = (method, params = {}, sessionId) => new Promise((resolve) => {
  const id = ++seq; waiting.set(id, resolve); ws.send(JSON.stringify({ id, method, params, sessionId }));
});
const { result: { targetId } } = await send("Target.createTarget", { url: "about:blank" });
const { result: { sessionId } } = await send("Target.attachToTarget", { targetId, flatten: true });
await send("Page.enable", {}, sessionId);
await send("Runtime.enable", {}, sessionId);

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
const noErrors = async (step) => { if (pageErrors.length) await fail(`${step}: the page threw`, pageErrors); };
async function until(step, body, ms = 8000) {
  const t0 = Date.now(); let last;
  while (Date.now() - t0 < ms) { last = await ev(body, 3); if (last === true) return noErrors(step); await sleep(250); }
  await fail(step, last);
}
// 做一次会改东西的操作：只点一次（点了就算，结果由后面的检查判断），页面随后刷新
async function act(step, body) {
  const r = await ev(body, 3);
  if (r !== true) await fail(step, r);
  await noErrors(step);
  await sleep(1500);
  await until(`${step}: page back after refresh`, `return document.body&&document.body.classList.contains('live')`);
}
const panel = (p) => `document.querySelector('.proj[data-p="${p}"]').click();await new Promise(r=>setTimeout(r,80));const P=document.querySelector('.panel.sel');`;
const eta = panel("eta/repo");
const titles = `[...P.querySelectorAll('ol.q li .t')].map(x=>x.textContent.replace(/^T\\d+/,''))`;
// 确认框：点按钮 → 可选填原因 → 点「确认」→ 等结果；成功就点「完成」（页面随后刷新）
const confirm = (sel, reason = "") => `const b=P.querySelector('${sel}');if(!b)return 'missing ${sel}';b.click();await new Promise(r=>setTimeout(r,80));
  const d=document.querySelector('dialog.rbd');if(!d.open)return 'dialog did not open';${reason ? `d.querySelector('.rbd-r').value=${JSON.stringify(reason)};` : ""}
  d.querySelector('.rbd-ok').click();for(let i=0;i<40&&d.querySelector('.rbd-out').hidden;i++)await new Promise(r=>setTimeout(r,100));
  const out=d.querySelector('.rbd-out');if(!/ok/.test(out.className))return out.textContent||'no result';d.querySelector('.rbd-no').click();return true`;
// 编辑框：填好后点保存，等结果，成功就点「完成」
const editorSave = (title, body) => `const ed=document.querySelector('dialog.rbe');if(!ed.open)return 'editor did not open';
  ed.querySelector('.rbe-title').value=${JSON.stringify(title)};const b=ed.querySelector('.rbe-body');b.value=${JSON.stringify(body)};b.dispatchEvent(new Event('input'));
  ed.querySelector('.rbe-ok').click();const o=ed.querySelector('.rbe-out');for(let i=0;i<40&&o.hidden;i++)await new Promise(r=>setTimeout(r,100));
  if(!/ok/.test(o.className))return o.textContent||'no result';ed.querySelector('.rbe-no').click();return true`;
const order = (step, want) => until(step, `${eta}const t=${titles};return JSON.stringify(t)===${JSON.stringify(JSON.stringify(want))}||t`, 10000);

await send("Page.navigate", { url }, sessionId);
await until("page loads in live mode", `return document.body&&document.body.classList.contains('live')`);
await until("health pill is not red", `const h=document.querySelector('.hp');return !!h&&/\\b(ok|warn)\\b/.test(h.className)`);
await order("starting queue", ["普通任务", "导出支持按月分文件"]);

// ---- 抽屉：任务全文、服务健康、查看全部（筛选、详情、返回）
await until("task drawer opens", `${eta}P.querySelector('[data-td]').click();await new Promise(r=>setTimeout(r,80));
  const d=document.querySelector('.drawer');return !d.hidden&&!!d.querySelector('.dtt')`);
await until("Esc closes the drawer", `document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));return document.querySelector('.drawer').hidden`);
await until("health drawer lists the checks", `document.querySelector('.hp').click();for(let i=0;i<30&&!document.querySelector('.drawer .hrow');i++)await new Promise(r=>setTimeout(r,100));
  const n=document.querySelectorAll('.drawer .hrow').length;document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));return n===5||n`);
await until("history drawer lists, filters, opens and goes back", `${eta}P.querySelector('[data-act="history"]').click();
  for(let i=0;i<30&&!document.querySelector('.drawer .hlist2 .drow');i++)await new Promise(r=>setTimeout(r,100));
  const all=document.querySelectorAll('.drawer .hlist2 .drow').length;
  [...document.querySelectorAll('.drawer .hf')].find(x=>x.textContent==='放弃').click();
  const rows=[...document.querySelectorAll('.drawer .hlist2 .drow')];const onlyDropped=rows.length>0&&rows.every(r=>r.classList.contains('dropped'));
  rows[0].click();const back=document.querySelector('.drawer .hback');if(!back)return 'no detail';back.click();
  const listBack=!!document.querySelector('.drawer .hlist2');document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));
  return all>rows.length&&onlyDropped&&listBack`);

// ---- 加任务、编辑任务：保存到底
await until("editor preview renders headings and warns about ##", `${eta}P.querySelector('[data-act="add"]').click();await new Promise(r=>setTimeout(r,80));
  const ed=document.querySelector('dialog.rbe');ed.querySelector('.rbe-title').value='冒烟';const b=ed.querySelector('.rbe-body');
  b.value='### 范围\\n- 一条\\n## 错的';b.dispatchEvent(new Event('input'));
  const ok=ed.open&&!!ed.querySelector('.rbe-pv .dh4')&&!!ed.querySelector('.rbe-pv .dli')&&!!ed.querySelector('.rbe-pv .dp.bad');
  ed.close();try{localStorage.clear()}catch(e){};return ok`);
await act("add a task from the editor", `${eta}P.querySelector('[data-act="add"]').click();await new Promise(r=>setTimeout(r,80));${editorSave("冒烟新增", "### 范围\\n- 只是冒烟")}`);
await order("the added task is in the queue", ["普通任务", "导出支持按月分文件", "冒烟新增"]);
await act("edit a task from the editor", `${eta}P.querySelector('ol.q li[data-pos="3"] [data-act="edit"]').click();await new Promise(r=>setTimeout(r,80));${editorSave("冒烟新增（改）", "改过的正文")}`);
await order("the edited title is in the queue", ["普通任务", "导出支持按月分文件", "冒烟新增（改）"]);

// ---- 调整顺序：↑、拖动；队列被别人改过时弹出失败框
await act("move up", `${eta}P.querySelector('ol.q li[data-pos="3"] [data-act="up"]').click();return true`);
await order("moved up", ["普通任务", "冒烟新增（改）", "导出支持按月分文件"]);
await act("drag to reorder", `${eta}const lis=P.querySelectorAll('ol.q li[draggable]');const dt=new DataTransfer();
  lis[0].dispatchEvent(new DragEvent('dragstart',{bubbles:true,dataTransfer:dt}));
  lis[2].dispatchEvent(new DragEvent('dragover',{bubbles:true,cancelable:true,dataTransfer:dt}));
  lis[2].dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:dt}));
  lis[0].dispatchEvent(new DragEvent('dragend',{bubbles:true,dataTransfer:dt}));return true`);
await order("dragged", ["冒烟新增（改）", "导出支持按月分文件", "普通任务"]);
await until("a stale queue fingerprint shows the failure box", `${eta}P.querySelector('section.tasks').dataset.qv='000000000000';
  P.querySelector('ol.q li[data-pos="1"] [data-act="down"]').click();const d=document.querySelector('dialog.rbd');
  for(let i=0;i<40&&!(d.open&&!d.querySelector('.rbd-out').hidden);i++)await new Promise(r=>setTimeout(r,100));
  const ok=d.open&&/CONFLICT/.test(d.querySelector('.rbd-out').textContent);d.querySelector('.rbd-no').click();return ok`);
await order("a refused move changes nothing", ["冒烟新增（改）", "导出支持按月分文件", "普通任务"]);

// ---- 循环开关、做完停、暂停 / 恢复、放弃：确认框都点到「确认」
await act("turn the loop on", `${eta}${confirm('[data-act="loop"]')}`);
await until("the loop chip shows", `${eta}return !!P.querySelector('.mode.loop')`);
await act("hold a pending task", `${eta}P.querySelector('ol.q li[data-pos="1"] [data-act="hold"]').click();return true`);
await until("the hold chip shows", `${eta}return !!P.querySelector('ol.q li[data-pos="1"] .sub .hold-tag')`);
await act("unhold", `${eta}P.querySelector('ol.q li[data-pos="1"] [data-act="hold"]').click();return true`);
await until("the hold chip is gone", `${eta}return !P.querySelector('ol.q li[data-pos="1"] .sub .hold-tag')`);
await act("turn the loop off", `${eta}${confirm('[data-act="loop"]')}`);
await until("the loop chip is gone", `${eta}return !P.querySelector('.mode.loop')`);
await act("confirming pause really pauses", `${eta}${confirm('[data-act="pause"]')}`);
await until("paused", `${eta}return !!P.querySelector('[data-act="resume"]')`);
await act("confirming resume really resumes", `${eta}${confirm('[data-act="resume"]')}`);
await until("resumed", `${eta}return !!P.querySelector('[data-act="pause"]')`);
await act("drop a pending task with a reason", `${eta}${confirm('ol.q li[data-pos="1"] [data-act="drop"]', "冒烟不要了")}`);
await order("the dropped task left the queue", ["导出支持按月分文件", "普通任务"]);
await act("move down", `${eta}P.querySelector('ol.q li[data-pos="1"] [data-act="down"]').click();return true`);
await order("moved down", ["普通任务", "导出支持按月分文件"]);

// ---- 放行：theta 有一个做完等放行的任务
await act("release a finished task", `${panel("theta/repo")}${confirm('[data-act="go"]')}`);
await until("nothing waits for release any more", `${panel("theta/repo")}return !P.querySelector('[data-act="go"]')`);

// ---- 停掉服务：圆点变红、按钮变灰
process.kill(Number(servePid));
await until("pill turns red and buttons disable when the service stops", `const h=document.querySelector('.hp');
  const b=document.querySelector('.panel.sel [data-act]');return /\\bbad\\b/.test(h.className)&&document.body.classList.contains('offline')&&(!b||getComputedStyle(b).pointerEvents==='none')`, 12000);
await noErrors("the whole run");

console.log("PASS browser smoke: every page action submitted with no script errors (drawers, add, edit, move, drag, conflict, loop, hold, pause, resume, drop, release, offline)");
ws.close(); await finish(0);
