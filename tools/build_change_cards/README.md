# 角色资料对比截图页

只读研究／展示工具，不修改游戏、指令语义、官网冻结资料或运行时。输出到用户明确指定的桌面目录；下载的官方素材、研究 JSON、PNG 和网页均不提交。

```powershell
node --max-old-space-size=4096 tools/build_change_cards/research.js release/acbcm-changes-0803-1013-verified release/acbcm-deep-research-0803-1013
node tools/build_change_cards/test.js
node tools/build_change_cards/build.js "C:/Users/76025/Desktop/街霸6_0803对比1013_角色改动"
```

`research.js` 复用只读对象图核对器和现有AC模型，不产生新的运行时解析规则。额外引用链只用于当前构建的证据追踪；LockKey参数引用明确保留未批准标记。

`content.js` 是有证据边界的展示摘要，不是平衡数据库或第二语义源。底层完整差异保持在研究JSON内；已知未知项必须继续显示，不用文案把未解码标志解释成具体游戏行为。

`build.js` 获取官方语言资料和角色图片，按用户要求保留没有核实中文名称的官方英文原名，并提供指令。所有页面无需服务器，直接打开index.html。原图来源和SHA256写入manifest.json。

`render.js` 使用工作区现有Playwright与sharp生成32张PNG并验证独立页面、资源、文本边界、切换、纯净预览、手机缩放与图片非空；不引入运行时网页依赖。

研究覆盖与无法证明的部分见 [研究说明](研究说明.md)。
