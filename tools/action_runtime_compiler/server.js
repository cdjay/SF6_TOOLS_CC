#!/usr/bin/env node
"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");
const { spawn } = require("child_process");
const archive = require("./archive_builder.js");

const ROOT = path.join(__dirname, "html");
const HOST = "127.0.0.1";
const PORT = Number(process.env.SF6CC_COMPILER_PORT || 8765);
const CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8"
};

archive.ensureStorage(ROOT);

function sendJson(response, status, value) {
    const body = Buffer.from(JSON.stringify(value));
    response.writeHead(status, {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Length": body.length,
        "Cache-Control": "no-store"
    });
    response.end(body);
}

function readJson(request) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        let length = 0;
        request.on("data", chunk => {
            length += chunk.length;
            if (length > 1024 * 1024) {
                reject(new Error("请求过大。"));
                request.destroy();
                return;
            }
            chunks.push(chunk);
        });
        request.on("end", () => {
            try {
                resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
            } catch (_error) {
                reject(new Error("请求不是有效 JSON。"));
            }
        });
        request.on("error", reject);
    });
}

function state() {
    return {
        output_root: ROOT,
        directories: {
            acbcm: path.join(ROOT, "acbcm"),
            char: path.join(ROOT, "char"),
            latest: path.join(ROOT, "latest"),
            latest_exceptions: path.join(ROOT, "latest_exceptions"),
            latest_modern: path.join(ROOT, "latest_modern")
        },
        versions: archive.listVersionManifests(ROOT).map(item => ({
            version: item.version,
            created_at: item.manifest.created_at,
            character_count: (item.manifest.characters || []).length
        }))
    };
}

function openFolder(kind) {
    if (!new Set(["acbcm", "char", "latest", "latest_exceptions", "latest_modern"]).has(kind)) throw new Error("不支持的目录类型。");
    const target = path.join(ROOT, kind);
    archive.ensureStorage(ROOT);
    const child = spawn("explorer.exe", [target], { detached: true, stdio: "ignore" });
    child.unref();
    return target;
}

async function handleApi(request, response, pathname) {
    if (request.method === "GET" && pathname === "/api/state") {
        sendJson(response, 200, state());
        return true;
    }
    if (request.method !== "POST") return false;
    const body = await readJson(request);
    if (pathname === "/api/scan") {
        sendJson(response, 200, archive.scanDumpDirectory(body.dump_directory));
        return true;
    }
    if (pathname === "/api/build") {
        const result = archive.buildArchive({
            dumpDirectory: body.dump_directory,
            version: body.version,
            stems: body.stems,
            compareVersion: body.compare_version || null,
            useExceptions: body.use_exceptions === true,
            outputRoot: ROOT
        });
        sendJson(response, 200, result);
        return true;
    }
    if (pathname === "/api/open-folder") {
        sendJson(response, 200, { opened: openFolder(body.kind) });
        return true;
    }
    return false;
}

function serveStatic(response, pathname) {
    const relative = pathname === "/" ? "index.html" : decodeURIComponent(pathname.slice(1));
    const filename = path.resolve(ROOT, relative);
    if (!filename.startsWith(`${path.resolve(ROOT)}${path.sep}`) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) {
        sendJson(response, 404, { error: "Not found" });
        return;
    }
    const body = fs.readFileSync(filename);
    response.writeHead(200, {
        "Content-Type": CONTENT_TYPES[path.extname(filename).toLowerCase()] || "application/octet-stream",
        "Content-Length": body.length,
        "Cache-Control": "no-store"
    });
    response.end(body);
}

const server = http.createServer(async (request, response) => {
    const pathname = new URL(request.url, `http://${HOST}:${PORT}`).pathname;
    try {
        const origin = request.headers.origin;
        if (origin && origin !== `http://${HOST}:${PORT}` && origin !== `http://localhost:${PORT}`) {
            sendJson(response, 403, { error: "拒绝来自非本地编译器页面的请求。" });
            return;
        }
        if (pathname.startsWith("/api/")) {
            if (!await handleApi(request, response, pathname)) sendJson(response, 404, { error: "Unknown API" });
            return;
        }
        if (request.method !== "GET") {
            sendJson(response, 405, { error: "Method not allowed" });
            return;
        }
        serveStatic(response, pathname);
    } catch (error) {
        sendJson(response, 400, { error: error.message });
    }
});

server.listen(PORT, HOST, () => {
    const url = `http://${HOST}:${PORT}/`;
    console.log(`SF6CC AC+BCM 可视化编译器: ${url}`);
    console.log(`输出目录: ${ROOT}`);
    if (process.argv.includes("--open")) {
        const child = spawn("explorer.exe", [url], { detached: true, stdio: "ignore" });
        child.unref();
    }
});
