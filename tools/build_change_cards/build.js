"use strict";

const fs = require("fs"), path = require("path"), crypto = require("crypto");
const { execFileSync } = require("child_process");
const { presets, block, row } = require("./content.js");
const root = path.resolve(__dirname, "../..");
const reports = path.join(root, "release/acbcm-changes-0803-1013-verified");
const deepDir = path.join(root, "release/acbcm-deep-research-0803-1013");
const roster = JSON.parse(fs.readFileSync(path.join(root, "data/SF6CC/fighters.json"))).fighters;
const escape = value => String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
const json = file => JSON.parse(fs.readFileSync(file, "utf8"));
const psQuote = value => `'${String(value).replaceAll("'", "''")}'`;
function windowsRequest(command) {
    return execFileSync("pwsh", ["-NoLogo", "-NoProfile", "-Command",
        `$ErrorActionPreference='Stop';[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();${command}`],
    { encoding: "utf8", maxBuffer: 16 * 1024 * 1024, windowsHide: true });
}

async function download(url, file) {
    if (fs.existsSync(file)) return;
    if (process.platform === "win32") {
        windowsRequest(`$r=Invoke-WebRequest -Uri ${psQuote(url)} -OutFile ${psQuote(file)} -PassThru -TimeoutSec 30;if(($r.Headers['Content-Type'] -join '') -notmatch 'image'){throw 'Not an image'}`);
        return;
    }
    const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`${response.status}: ${url}`);
    if (!response.headers.get("content-type")?.includes("image")) throw new Error(`Not an image: ${url}`);
    fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
}

async function locale(output) {
    const file = path.join(output, "official-names.json");
    if (fs.existsSync(file)) return json(file);
    const url = "https://www.streetfighter.com/6/zh-hans/character/mai/frame";
    let html;
    if (process.platform === "win32") html = windowsRequest(`(Invoke-WebRequest -Uri ${psQuote(url)} -TimeoutSec 30).Content`);
    else {
        const response = await fetch(url, { signal: AbortSignal.timeout(30000) });
        if (!response.ok) throw new Error(`Official names: ${response.status}`);
        html = await response.text();
    }
    const match = html.match(/<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/);
    if (!match) throw new Error("Official locale payload missing");
    const namespaces = JSON.parse(match[1]).props.pageProps.__namespaces;
    const names = {};
    for (const fighter of roster) {
        names[fighter.key] = namespaces[`character/frame/${fighter.official_slug}`] || {};
    }
    const result = { source: url, language: "zh-hans", policy: "Use official locale value; English fallback is permitted. No invented move translations.", names };
    fs.writeFileSync(file, JSON.stringify(result, null, 2));
    return result;
}

function displayName(fighter, raw, names) {
    if (["翼旋脚", "弱 天昇脚", "中 天昇脚", "行雲流水", "OD 龍炎舞", "[強化版]OD 龍炎舞", "OD 風破刃"].includes(raw)) {
        return raw.replace("[強化版]", "强化版 ").replace(/^弱 /, "轻").replace(/^中 /, "中");
    }
    const translated = names.names[fighter.key]?.[`[t]${raw}`];
    if (translated && !translated.startsWith("[t]")) return translated;
    const familyRaw = raw.startsWith("SA1 ") ? raw.replace(/^SA1 /, "SA1 弱 ") : `弱 ${raw}`;
    const family = names.names[fighter.key]?.[`[t]${familyRaw}`];
    if (family && !family.startsWith("[t]")) return family.replace(/^(SA1 )?L /, (_, superArt) => superArt || "");
    return raw;
}

function inputIcons(command, prefix) {
    const match = command.match(/(?:\[[2468]\][2468]+|[1-9]{2,6})\+(?:LP|MP|HP|LK|MK|HK|PP|KK|P|K)\b/);
    if (!match) return "";
    const icons = [], token = match[0];
    for (let i = 0; i < token.length;) {
        const hold = token.slice(i).match(/^\[([2468])\]/);
        const button = token.slice(i).match(/^(LP|MP|HP|LK|MK|HK|PP|KK|P|K)/);
        if (hold) { icons.push(`${hold[1]}_HOLD.png`); i += hold[0].length; }
        else if (button) {
            if (["PP", "KK"].includes(button[0])) icons.push(`${button[0][0]}.png`, `${button[0][0]}.png`);
            else icons.push(`${button[0].length === 1 ? button[0] : button[0].toLowerCase()}.png`);
            i += button[0].length;
        } else { icons.push(token[i] === "+" ? "PLUS.png" : `${token[i]}.png`); i++; }
    }
    return `<span class="input-icons" aria-hidden="true">${icons.map(icon => `<img src="${prefix}assets/inputs/${icon}" alt="">`).join("")}</span>`;
}

function blocksFor(fighter, report) {
    if (report.new_character) return [block("新增角色资料", "0803无对应角色基线", "新增", [
        row("官网招式资料", "无对应资料", `${report.current_moves.length}行招式`),
        row("指令动作资料", "无对应资料", `${report.current_action_count}项动作`)
    ], "这是新增角色的当前资料，不存在旧版帧数或伤害变化幅度。全部招式资料在页面下方深度资料中。")];
    return presets[fighter.key] || [];
}

function renderBlock(fighter, item, names, prefix) {
    const title = displayName(fighter, item.title, names);
    return `<section class="change"><div class="block-head"><h3>${escape(title)}</h3><span class="tag" data-kind="${escape(item.kind)}">${escape(item.kind)}</span></div>
<div class="command"><span class="prefix">指令</span>${escape(item.command)}${inputIcons(item.command, prefix)}</div>
${item.rows.map(r => `<div class="delta"><div class="label">${escape(r.label)}</div><div class="values"><span class="old">${escape(r.before)}</span><span class="delta-arrow">→</span><span class="new">${escape(r.after)}</span></div></div>`).join("")}
${item.note ? `<p class="note">${escape(item.note)}</p>` : ""}</section>`;
}

function poster(fighter, index, report, deep, names, media, prefix) {
    const blocks = blocksFor(fighter, report), isNew = report.new_character;
    const changed = blocks.length > 0;
    if (!changed && deep.contexts?.length) throw new Error(`Presentation omitted changed fighter: ${fighter.key}`);
    const headline = isNew ? "新增角色 · 无旧版基线" : changed ? "逐项改动 · 数值与行为分开核对" : "可比资料未发现差异";
    const commands = blocks.filter(item => !/内部动作|个动作位置|涉及内部/.test(item.command));
    const commandTable = commands.length ? `<section class="commands"><h2>涉及招式与指令</h2><table class="cmd-table"><tbody>${commands.map(item => `<tr><td>${escape(displayName(fighter, item.title, names))}</td><td>${escape(item.command)}</td></tr>`).join("")}</tbody></table><p class="command-key">P／K＝拳／脚　PP／KK＝两个拳键／脚键　[4]／[2]＝蓄力　OD＝强化版<br>中文名称未核实时保留官网原名；英文招式名均可通过右侧指令对应。</p></section>` : "";
    const noChange = `<div class="empty-message"><div class="zero">NO DELTA</div><h3>当前证据中，没有发现可比改动。</h3><p>已核对两版动作与输入资料、可比嵌套节点，以及官网帧数、伤害、斗气和备注。<br><br>这不是“游戏内所有参数完全不变”的保证；旧版未采集的字段不能参与判断。</p></div>
<section class="scope"><div><b>帧数／斗气</b><span>官网可比字段<br>未发现变化</span></div><div><b>伤害</b><span>官网资料未变<br>完整伤害表未导出</span></div><div><b>输入条件</b><span>原始输入路线<br>未发现可比变化</span></div><div><b>动作连接</b><span>可比动作节点<br>未发现变化</span></div></section>`;
    return `<article class="poster" data-fighter="${fighter.key}"><header class="cover">
${media ? `<img class="cover-art${media.endsWith(".jpg") ? " sns" : ""}" src="${prefix}assets/characters/${media}" alt="${escape(fighter.name_zh)}官方角色立绘">` : ""}
<div class="cover-copy"><div class="series">街霸6 <b>角色资料对比</b></div><p class="role-en">${escape(fighter.name_en)}</p><h1>${escape(fighter.name_zh)}</h1><div class="version"><span>08.03</span><span class="arrow">→</span><span>10.13</span></div><div class="cover-caption">2026 · AC／BCM 与官网资料核对</div></div><div class="issue">${String(index + 1).padStart(2, "0")} / 32</div></header>
<section class="intro"><h2>${headline}</h2><span class="pill">${isNew ? "新增资料" : changed ? `${blocks.length}组观察` : "未发现差异"}</span></section>
${changed ? `<div class="content">${blocks.map(item => renderBlock(fighter, item, names, prefix)).join("")}</div>${commandTable}` : noChange}
<footer class="footer"><div class="footer-top"><span>SF6CC · 角色改动观察</span><span>0803 → 1013</span></div><div class="legend"><span><i></i>旧版值</span><span><i class="green"></i>新版值</span><span><i class="yellow"></i>变化≠加强／削弱</span></div><p>来源：原始动作／输入采集、CAPCOM 官网资料与角色图片。不是官方补丁公告。<br>旧版缺完整取消组与部分帧窗口；导出不含完整伤害表。待验证项不作为已确认实战调整。</p></footer></article>`;
}

function researchHtml(fighter, report, deep, names, prefix) {
    const contexts = deep.contexts || [];
    const entries = contexts.map(c => {
        const change = deep.ac.changes.find(v => v.locator === c.locator);
        const commands = c.input_contexts.map(v => v.command).filter((v, i, all) => all.indexOf(v) === i);
        return `<details class="entry"><summary>动作 ${c.action_id} · ${escape(commands.join("／") || "尚未确认输入归属")}</summary><p>当前动作长度：${c.frame ?? "未知"}F。以下帧窗口属于1013当前采集，不能自动当作新增窗口。</p><pre>${escape(JSON.stringify({ difference: change, current_context: c }, null, 2))}</pre></details>`;
    }).join("");
    const newMoves = report.new_character ? `<table class="cmd-table"><tbody>${report.current_moves.map(m => `<tr><td>${escape(displayName(fighter, m.name, names))}</td><td>${escape(report.current_web.actions[m.command.action_id]?.classic?.display || m.command.fallback?.classic?.display || "尚未解析")}</td><td>${escape(m.frames.startup.raw ?? "—")}F / ${escape(m.damage.raw ?? "—")}</td></tr>`).join("")}</tbody></table>` : "";
    return `<section class="research"><h2>深度资料 · ${escape(fighter.name_zh)}</h2><p>以下保留原始值、当前输入引用链与时间窗口，供进一步核对；同编号不代表跨版本同一招式。普通分支、飞行道具生成引用和LockKey参数引用分开标注。</p><p><a href="${prefix}research/${fighter.key}.json">完整研究资料 JSON</a> · <a href="${prefix}research/说明.md">研究边界与补查结论</a></p>${newMoves}${entries || "<p>可比资料未发现动作差异。</p>"}</section>`;
}

function page(fighter, index, report, deep, names, media, prefix, home = false) {
    const previous = roster[(index + roster.length - 1) % roster.length], next = roster[(index + 1) % roster.length];
    const href = f => `${prefix}pages/${f.key}.html`;
    const options = roster.map(f => `<option value="${href(f)}"${f.key === fighter.key ? " selected" : ""}>${escape(f.name_zh)} · ${escape(f.name_en)}</option>`).join("");
    return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(fighter.name_zh)} · 0803对比1013</title><link rel="stylesheet" href="${prefix}style.css"></head><body>
<nav class="toolbar" aria-label="角色预览"><span class="brand">SF6CC · 0803 → 1013</span><a class="tool" title="上一个角色" aria-label="上一个角色" href="${href(previous)}"><img src="${prefix}assets/chevron_left.png" alt=""></a><select id="fighter" aria-label="角色">${options}</select><a class="tool" title="下一个角色" aria-label="下一个角色" href="${href(next)}"><img src="${prefix}assets/chevron_right.png" alt=""></a><a class="tool download" title="下载本角色图片" href="${prefix}可发图片/${fighter.name_zh}_${fighter.key}.png" download>PNG</a><button id="clean" class="tool" title="纯净预览，Esc返回">纯净预览</button><a class="tool" href="#deep">深度资料</a></nav>
<main class="stage">${poster(fighter, index, report, deep, names, media, prefix)}</main><div id="deep">${researchHtml(fighter, report, deep, names, prefix)}</div><script src="${prefix}app.js"></script></body></html>`;
}

async function run(output) {
    output = path.resolve(output);
    for (const dir of ["pages", "research", "assets/characters", "assets/inputs", "可发图片"])
        fs.mkdirSync(path.join(output, dir), { recursive: true });
    for (const file of ["style.css", "app.js"]) fs.copyFileSync(path.join(__dirname, file), path.join(output, file));
    fs.copyFileSync(path.join(root, "fonts/SF6_college.ttf"), path.join(output, "assets/college.ttf"));
    fs.copyFileSync(path.join(root, "images/ui_icons/chevron_left_ios.png"), path.join(output, "assets/chevron_left.png"));
    fs.copyFileSync(path.join(root, "images/ui_icons/chevron_right_ios.png"), path.join(output, "assets/chevron_right.png"));
    for (const file of fs.readdirSync(path.join(root, "images/buttonsAndArrows")))
        if (file.endsWith(".png")) fs.copyFileSync(path.join(root, "images/buttonsAndArrows", file), path.join(output, "assets/inputs", file));
    const names = await locale(output), manifest = { old: "2026-08-03", new: "2026-10-13", images: [], characters: [] };
    for (let i = 0; i < roster.length; i++) {
        const f = roster[i], report = json(path.join(reports, `${f.key}.json`)), deep = json(path.join(deepDir, `${f.key}.json`));
        const base = `https://www.streetfighter.com/6/assets/images/character/${f.official_slug}`;
        let media = `${f.key}.png`, source = `${base}/${f.official_slug}.png`;
        try { await download(source, path.join(output, "assets/characters", media)); }
        catch (error) {
            console.warn(error.message); media = `${f.key}.jpg`; source = `${base}/sns.jpg`;
            try { await download(source, path.join(output, "assets/characters", media)); }
            catch (fallback) { throw new Error(`No official character artwork: ${f.key}: ${fallback.message}`); }
        }
        manifest.images.push({ fighter: f.key, source, local: `assets/characters/${media}`,
            sha256: crypto.createHash("sha256").update(fs.readFileSync(path.join(output, "assets/characters", media))).digest("hex") });
        const html = page(f, i, report, deep, names, media, "../");
        fs.writeFileSync(path.join(output, "pages", `${f.key}.html`), html);
        fs.writeFileSync(path.join(output, "research", `${f.key}.json`), JSON.stringify({
            sources: report.sources, official_changes: report.web?.moves || [], bcm: deep.bcm || [],
            ac: deep.ac || report.current_ac, contexts: deep.contexts || [],
            new_character_moves: report.current_moves || undefined
        }, null, 2));
        if (f.key === "ChunLi") fs.writeFileSync(path.join(output, "index.html"), page(f, i, report, deep, names, media, "", true));
        manifest.characters.push({ key: f.key, name: f.name_zh, page: `pages/${f.key}.html`, image: `可发图片/${f.name_zh}_${f.key}.png` });
        console.log(`Built ${f.name_zh}: ${blocksFor(f, report).length} sections`);
    }
    fs.copyFileSync(path.join(__dirname, "研究说明.md"), path.join(output, "research/说明.md"));
    fs.writeFileSync(path.join(output, "manifest.json"), JSON.stringify(manifest, null, 2));
    fs.writeFileSync(path.join(output, "打开说明.txt"), "打开 index.html 浏览逐角色页面。\r\n可发图片 文件夹包含32张完整PNG，可直接发送动态。\r\n每个角色也有独立HTML页面，全部资源本地保存，不需要启动服务。\r\n红色是旧值，绿色是新值，不表示加强或削弱。\r\n资料变化、采集差异、待验证项不能当作已确认实战调整。\r\n角色图片版权归CAPCOM及相关权利方。\r\n");
    console.log(`Complete: ${output}`);
}
if (require.main === module) run(process.argv[2]).catch(error => { console.error(error); process.exitCode = 1; });
module.exports = { displayName, inputIcons, blocksFor, page };
