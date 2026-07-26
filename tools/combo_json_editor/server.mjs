import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
// 支持 CLI 参数转发（--port / --host 或 --port=... / --host=...），便于预览平台注入端口
const cliArgs = process.argv.slice(2);
function readArg(name) {
    const flagIndex = cliArgs.findIndex(arg => arg === `--${name}`);
    if (flagIndex >= 0 && cliArgs[flagIndex + 1]) return cliArgs[flagIndex + 1];
    const inline = cliArgs.find(arg => arg.startsWith(`--${name}=`));
    return inline ? inline.slice(name.length + 3) : undefined;
}
const port = Number(readArg("port") || process.env.SF6CC_JSON_EDITOR_PORT || process.env.PORT || 8776);
const host = readArg("host") || process.env.SF6CC_JSON_EDITOR_HOST || "127.0.0.1";
const contentTypes = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8"
};

http.createServer((request, response) => {
    try {
        const url = new URL(request.url, `http://${request.headers.host || "127.0.0.1"}`);
        const relative = decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname);
        const target = path.resolve(root, `.${relative}`);
        if (path.relative(root, target).startsWith("..") || !fs.statSync(target).isFile()) {
            response.writeHead(404).end("Not found");
            return;
        }
        response.writeHead(200, {
            "Content-Type": contentTypes[path.extname(target).toLowerCase()] || "application/octet-stream",
            "Cache-Control": "no-store"
        });
        fs.createReadStream(target).pipe(response);
    } catch {
        response.writeHead(404).end("Not found");
    }
}).listen(port, host, () => {
    console.log(`SF6CC 连段 JSON 元数据编辑器：http://${host}:${port}`);
    console.log("按 Ctrl+C 关闭。");
});
