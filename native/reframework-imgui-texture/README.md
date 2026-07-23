# reframework-imgui-texture

`reframework-imgui-texture` is a small REFramework native plugin that exposes
PNG-backed ImGui drawing to Lua without adding another Present hook or another
Dear ImGui implementation.

It resolves the cimgui functions already exported by REFramework, reserves
custom rectangles in REFramework's existing ImGui font atlas, copies the
decoded RGBA pixels into those rectangles once, and draws them with
`ImDrawList::AddImage` plus per-image UV coordinates.

The audited REFramework DX12 build initializes ImGui in legacy single-SRV mode.
Registering multiple standalone `ImTextureData` objects would make every image
overwrite the same descriptor. Sharing the existing font-atlas GPU texture
avoids that collision, keeps text rendering intact, and lets REFramework's
current DX11 or DX12 backend own upload and device-reset recreation.

## Lua API

```lua
local handle = texture.load("buttonsAndArrows/1.png")
texture.draw(handle, 100, 100, 32, 32)
local width, height = texture.size(handle)
texture.release(handle)
texture.clear_cache()
```

Only relative PNG paths under `<gamedir>/reframework/images/` are accepted.
Absolute paths, rooted paths, non-PNG files, and `..` components are rejected.
Handles are monotonically increasing Lua integers and never expose GPU
pointers.

`texture.draw()` aspect-fits the original image into the requested rectangle,
so non-square resources are not stretched. Missing or undecodable PNGs are
cached as failed entries, logged once, and draw `[PNG missing]` as the visible
fallback.

Decoded RGBA bytes remain cached so a cleared or rebuilt font atlas can be
repopulated without reading or decoding the PNG again. `release()` and
`clear_cache()` invalidate Lua handles immediately and retire atlas rectangles
after two existing REFramework present callbacks, avoiding reuse while older
draw data may still reference the pixels.

## Build

The project is pinned to the REFramework commit used by the audited runtime:
`a0e9010fb0449dc9d824b5978ee759eeaf50f7c6`.

```powershell
cmake -S native/reframework-imgui-texture `
      -B <build-dir> `
      -G "Visual Studio 17 2022" -A x64 `
      -DREFRAMEWORK_SOURCE_DIR=<reframework-source>
cmake --build <build-dir> --config Release
```

The DLL is emitted as:

`<build-dir>/bin/Release/reframework-imgui-texture.dll`

REFramework does not expose a successful-plugin hot-unload callback and does
not hot-unload initialized plugins. Script resets are supported by
re-registering the Lua table against the new state. Process shutdown releases
resources with the process; explicit `release()` and `clear_cache()` retire
their font-atlas regions during normal runtime.
