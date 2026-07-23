# REFramework ImGui 纹理接口审计

审计目标是本机 Street Fighter 6 使用的 REFramework：

- 版本：`1.5.9.1+487-a0e9010f`
- 对应提交：`a0e9010fb0449dc9d824b5978ee759eeaf50f7c6`

## Lua binding 结论

`src/mods/bindings/ImGui.cpp` 没有向 Lua 注册以下能力：

- `imgui.image`
- `imgui.image_button`
- `ImDrawList.add_image`
- PNG 或其他图片解码
- GPU texture 创建、销毁或 `ImTextureID`
- Lua 设备重建回调

本机 `dinput8.dll` 的字符串和导出表复核结果与源码一致：Lua 可见的
DrawList 只有线段、矩形、圆、多边形、路径和文字等几何接口。

## 可复用的原生能力与 DX12 限制

同一 `dinput8.dll` 已导出 cimgui 的正式图片和用户纹理生命周期：

- `ImTextureData_ImTextureData`
- `ImTextureData_Create`
- `ImTextureData_GetPixels`
- `ImTextureData_GetTexRef`
- `ImTextureData_SetStatus`
- `igRegisterUserTexture`
- `igUnregisterUserTexture`
- `igGetBackgroundDrawList_Nil`
- `ImDrawList_AddImage`

REFramework plugin API 1.15 还提供：

- `on_lua_state_created`
- `on_lua_state_destroyed`
- `on_imgui_frame`
- `on_device_reset`

第一次实机验证进一步确认：该 REFramework 的 DX12 初始化仍使用
`LegacySingleSrvCpuDescriptor` / `LegacySingleSrvGpuDescriptor`，只允许一张
同时存在的 ImGui GPU 纹理。把十张 PNG 分别注册为用户纹理会反复覆盖同一个
SRV；表现为所有方向图标都显示最后加载的 `di.png`，并且字体采样出现红黑
破图。

因此不能直接把上述用户纹理导出当作“多纹理 API”使用。可行的纯 ImGui 路径
是复用 REFramework 已有字体图集：

- 用 `ImFontAtlas_AddCustomRect` 为 PNG 分配区域；
- 把 WIC 解码的原始 RGBA 像素复制到字体图集；
- 用字体图集 `ImTextureRef` 和每张图片自己的 UV 调用
  `ImDrawList_AddImage`；
- 由 REFramework 当前 DX11/DX12 backend 上传同一张字体图集 GPU 纹理并
  处理设备重建。

桥接只注册 REFramework 已有 `on_present` 生命周期中的回调来处理未锁定的
字体图集，不建立第二个 Present hook，不复制 Dear ImGui。

## A：ImGui + D2D 图片混合

优点：

- `d2d.Image` 已能解码并显示正式 PNG。
- 实现量小。

缺点：

- 恢复 `reframework-d2d.dll` 依赖。
- SF6 的 DX12 路径会重新引入 D3D11-on-12。
- D2D 使用独立 present 生命周期，和 ImGui HUD 存在时序及设备重建耦合。
- 无法满足纯 ImGui 实验版本删除 D2D DLL 后运行的目标。

## B：纯 ImGui texture bridge

优点：

- 使用 REFramework 已有 ImGui context、draw list 和 DX11/DX12 backend。
- 不新增 Present hook，不加载 D3D11-on-12。
- 原 PNG 字节只读取、解码一次，RGBA 缓存在原生插件中。
- 所有图标共用 REFramework 已有字体图集 GPU 纹理，不额外占用 DX12 SRV。
- Lua 只持有整数 handle，不暴露字体图集、UV 或 GPU 指针。
- 设备重建后由现有 ImGui backend 重建字体图集并重新上传缓存像素。

代价：

- 插件与 REFramework 的 cimgui ABI 版本相关，必须针对当前运行时构建。
- REFramework plugin API 没有成功加载后的热卸载回调；其插件加载器本身也
  不热卸载已初始化插件。正常退出由操作系统回收，运行期资源通过
  `release()` 或 `clear_cache()` 安全退休。

## 实机验证与 DistanceViewer 接入

方案 B 已在上述 REFramework/DX12 运行时完成实机验证：

- `1.png`、`2.png`、`2_HOLD.png`、`6.png`、`6_HOLD.png`；
- `mp.png`、`hp.png`、`modern_m.png`、`dr.png`、`di.png`；
- 每张图片均以原始 80px、24px、32px、40px 并排显示；
- 透明背景、轮廓、颜色和长宽比均保持正确；
- 训练场内显示正常，字体图集未再出现纹理串图或字体破图。

验证后，`SF6_DistanceViewer.lua` 的指令绘制层已改用原始 PNG。当前
DistanceViewer 会按需缓存八方向、六种拳脚、`HOLD` 和 `THROW` 的整数
handle；指令解析、朝向翻转、距离计算、显示条件与布局逻辑均未修改。

实机日志确认插件和脚本正常加载，未出现 `on_present callback` /
`on_imgui_frame callback` 异常，也未加载 `d3d11on12.dll`。
