"use strict";
const fs = require("fs"), path = require("path"), { pathToFileURL } = require("url");
const { chromium } = require("playwright");
const sharp = require("sharp");

async function run(output) {
    output = path.resolve(output);
    const manifest = JSON.parse(fs.readFileSync(path.join(output, "manifest.json")));
    if (manifest.characters.length !== 32) throw new Error("Expected 32 character pages");
    const browser = await chromium.launch({ headless: true });
    try {
        const page = await browser.newPage({ viewport: { width: 1120, height: 1600 }, deviceScaleFactor: 1 });
        const errors = [];
        page.on("pageerror", error => errors.push(error.message));
        const qa = [];
        for (const fighter of manifest.characters) {
            await page.goto(`${pathToFileURL(path.join(output, fighter.page)).href}?export=1`);
            await page.evaluate(() => document.fonts.ready);
            const check = await page.evaluate(() => {
                const poster = document.querySelector(".poster"), bounds = poster.getBoundingClientRect();
                const broken = [...poster.querySelectorAll("img")].filter(img => !img.complete || img.naturalWidth === 0).map(img => img.src);
                const overflow = [...poster.querySelectorAll("h1,h2,h3,p,.delta,.values,td,.command")].filter(el => {
                    const r = el.getBoundingClientRect();
                    return el.scrollWidth > el.clientWidth + 2 || r.right > bounds.right + 1 || r.left < bounds.left - 1;
                }).map(el => el.textContent.slice(0,100));
                return { width: bounds.width, height: bounds.height, broken, overflow,
                    changeBlocks: poster.querySelectorAll(".change").length };
            });
            if (check.broken.length || check.overflow.length) throw new Error(`${fighter.key}: ${JSON.stringify(check)}`);
            const png = path.join(output, fighter.image);
            await page.locator(".poster").screenshot({ path: png });
            const stats = await sharp(png).stats();
            if (stats.entropy < 1 || stats.channels.every(channel => channel.stdev < 3)) throw new Error(`Blank image: ${fighter.key}`);
            qa.push({ fighter: fighter.key, ...check, entropy: stats.entropy, bytes: fs.statSync(png).size });
            console.log(`${fighter.name}: ${check.width}x${check.height}, PNG ${Math.round(fs.statSync(png).size / 1024)} KB`);
        }
        await page.goto(pathToFileURL(path.join(output, "index.html")).href);
        await page.selectOption("#fighter", { label: "英格丽德 · Ingrid" });
        await page.waitForURL("**/Ingrid.html");
        if (await page.locator(".poster").getAttribute("data-fighter") !== "Ingrid") throw new Error("Character selection failed");
        await page.click("#clean");
        if (await page.locator(".toolbar").isVisible()) throw new Error("Clean preview did not hide toolbar");
        await page.keyboard.press("Escape");
        if (!await page.locator(".toolbar").isVisible()) throw new Error("Clean preview did not restore toolbar");
        await page.getByRole("link", { name: "下一个角色", exact: true }).click();
        await page.waitForURL("**/Yasmine.html");
        await page.setViewportSize({ width: 390, height: 844 });
        await page.evaluate(() => document.fonts.ready);
        await page.waitForTimeout(120);
        const mobile = await page.evaluate(() => {
            const rect = document.querySelector(".poster").getBoundingClientRect();
            return { viewport: innerWidth, width: rect.width, scrollWidth: document.documentElement.scrollWidth,
                menuVisible: !!document.querySelector("#fighter") };
        });
        if (mobile.scrollWidth > mobile.viewport + 2 || mobile.width > mobile.viewport) throw new Error(`Mobile overflow: ${JSON.stringify(mobile)}`);
        await page.screenshot({ path: path.join(output, "手机预览.png"), fullPage: false });
        if (errors.length) throw new Error(`Browser errors: ${errors.join("; ")}`);
        fs.writeFileSync(path.join(output, "preview-validation.json"), JSON.stringify({ passed: true, pages: qa, mobile,
            controls: ["character_selection", "next_character", "clean_preview", "escape_restore"] }, null, 2));
        console.log("All 32 PNGs and desktop/mobile checks passed");
    } finally { await browser.close(); }
}
if (require.main === module) run(process.argv[2]).catch(error => { console.error(error); process.exitCode = 1; });
