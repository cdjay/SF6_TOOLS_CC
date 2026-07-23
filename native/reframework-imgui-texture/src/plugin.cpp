#include <reframework/API.h>

#include <lua.hpp>

#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#define CIMGUI_NO_EXPORT
#include <cimgui.h>

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cwctype>
#include <filesystem>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

static_assert(sizeof(ImTextureRef) == 16);
static_assert(offsetof(ImTextureData, Status) == 4);
static_assert(offsetof(ImTextureData, BackendUserData) == 8);
static_assert(offsetof(ImTextureData, TexID) == 16);
static_assert(offsetof(ImTextureData, UnusedFrames) == 80);
static_assert(sizeof(ImTextureData) == 88);

using GetCurrentContextFn = ImGuiContext* (*)();
using SetCurrentContextFn = void (*)(ImGuiContext*);
using GetIOFn = ImGuiIO* (*)();
using SetTextureStatusFn = void (*)(ImTextureData*, ImTextureStatus);
using AddCustomRectFn = ImFontAtlasRectId (*)(
    ImFontAtlas*,
    int,
    int,
    ImFontAtlasRect*
);
using RemoveCustomRectFn = void (*)(ImFontAtlas*, ImFontAtlasRectId);
using GetCustomRectFn = bool (*)(
    ImFontAtlas*,
    ImFontAtlasRectId,
    ImFontAtlasRect*
);
using GetBackgroundDrawListFn = ImDrawList* (*)();
using AddImageFn = void (*)(
    ImDrawList*,
    ImTextureRef,
    ImVec2,
    ImVec2,
    ImVec2,
    ImVec2,
    ImU32
);
using AddTextFn = void (*)(ImDrawList*, ImVec2, ImU32, const char*, const char*);

struct CImGuiApi {
    GetCurrentContextFn get_current_context{};
    SetCurrentContextFn set_current_context{};
    GetIOFn get_io{};
    SetTextureStatusFn set_texture_status{};
    AddCustomRectFn add_custom_rect{};
    RemoveCustomRectFn remove_custom_rect{};
    GetCustomRectFn get_custom_rect{};
    GetBackgroundDrawListFn get_background_draw_list{};
    AddImageFn add_image{};
    AddTextFn add_text{};
};

const REFrameworkPluginFunctions* g_functions{};
HMODULE g_reframework_module{};
std::filesystem::path g_image_root;
CImGuiApi g_imgui;
std::mutex g_mutex;
std::mutex g_log_mutex;
lua_State* g_lua{};
std::uint64_t g_next_handle{1};
std::uint64_t g_present_index{};

struct TextureEntry {
    std::uint64_t handle{};
    std::wstring cache_key;
    std::filesystem::path full_path;
    int width{};
    int height{};
    std::vector<std::uint8_t> decoded_rgba;
    ImFontAtlasRectId atlas_rect_id{-1};
    bool atlas_ready{};
    bool decode_failed{};
    std::string error;
};

struct RetiringRect {
    ImFontAtlasRectId atlas_rect_id{-1};
    std::uint64_t remove_after_present{};
};

std::unordered_map<std::uint64_t, std::unique_ptr<TextureEntry>> g_entries;
std::unordered_map<std::wstring, std::uint64_t> g_path_cache;
std::vector<RetiringRect> g_retiring;
std::unordered_set<std::string> g_logged_errors;

void log_info(const std::string& message) {
    if (g_functions != nullptr && g_functions->log_info != nullptr) {
        g_functions->log_info("[reframework-imgui-texture] %s", message.c_str());
    }
}

void log_error_once(const std::string& key, const std::string& message) {
    bool should_log = false;
    {
        std::scoped_lock lock{g_log_mutex};
        should_log = g_logged_errors.emplace(key).second;
    }

    if (should_log && g_functions != nullptr && g_functions->log_error != nullptr) {
        g_functions->log_error("[reframework-imgui-texture] %s", message.c_str());
    }
}

template <typename T>
bool resolve_export(T& target, const char* name) {
    target = reinterpret_cast<T>(GetProcAddress(g_reframework_module, name));
    if (target == nullptr) {
        log_error_once(
            std::string{"missing_export:"} + name,
            std::string{"缺少 REFramework cimgui 导出："} + name
        );
        return false;
    }
    return true;
}

bool resolve_cimgui_api() {
    bool ok = true;
    ok &= resolve_export(g_imgui.get_current_context, "igGetCurrentContext");
    ok &= resolve_export(g_imgui.set_current_context, "igSetCurrentContext");
    ok &= resolve_export(g_imgui.get_io, "igGetIO_Nil");
    ok &= resolve_export(g_imgui.set_texture_status, "ImTextureData_SetStatus");
    ok &= resolve_export(
        g_imgui.add_custom_rect,
        "ImFontAtlas_AddCustomRect"
    );
    ok &= resolve_export(
        g_imgui.remove_custom_rect,
        "ImFontAtlas_RemoveCustomRect"
    );
    ok &= resolve_export(
        g_imgui.get_custom_rect,
        "ImFontAtlas_GetCustomRect"
    );
    ok &= resolve_export(g_imgui.get_background_draw_list, "igGetBackgroundDrawList_Nil");
    ok &= resolve_export(g_imgui.add_image, "ImDrawList_AddImage");
    ok &= resolve_export(g_imgui.add_text, "ImDrawList_AddText_Vec2");
    return ok;
}

std::string hresult_message(const char* operation, HRESULT result) {
    char buffer[96]{};
    std::snprintf(
        buffer,
        sizeof(buffer),
        "%s failed (HRESULT 0x%08lX)",
        operation,
        static_cast<unsigned long>(result)
    );
    return buffer;
}

std::optional<std::wstring> utf8_to_wide(std::string_view text) {
    if (text.empty() || text.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        return std::nullopt;
    }

    const int source_size = static_cast<int>(text.size());
    const int required = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text.data(),
        source_size,
        nullptr,
        0
    );
    if (required <= 0) {
        return std::nullopt;
    }

    std::wstring converted(static_cast<std::size_t>(required), L'\0');
    const int written = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        text.data(),
        source_size,
        converted.data(),
        required
    );
    if (written != required) {
        return std::nullopt;
    }
    return converted;
}

std::wstring lowercase(std::wstring value) {
    std::transform(
        value.begin(),
        value.end(),
        value.begin(),
        [](wchar_t character) { return static_cast<wchar_t>(std::towlower(character)); }
    );
    return value;
}

bool path_is_inside(
    const std::filesystem::path& root,
    const std::filesystem::path& candidate
) {
    auto root_it = root.begin();
    auto candidate_it = candidate.begin();

    for (; root_it != root.end(); ++root_it, ++candidate_it) {
        if (candidate_it == candidate.end()) {
            return false;
        }
        if (lowercase(root_it->native()) != lowercase(candidate_it->native())) {
            return false;
        }
    }
    return true;
}

struct ResolvedPath {
    std::filesystem::path full_path;
    std::wstring cache_key;
};

std::optional<ResolvedPath> resolve_image_path(
    std::string_view relative_utf8,
    std::string& error
) {
    const auto relative_wide = utf8_to_wide(relative_utf8);
    if (!relative_wide.has_value()) {
        error = "路径不是有效 UTF-8";
        return std::nullopt;
    }

    std::wstring normalized_input = *relative_wide;
    std::replace(normalized_input.begin(), normalized_input.end(), L'/', L'\\');
    const std::filesystem::path relative_path{normalized_input};

    if (
        relative_path.empty() ||
        relative_path.is_absolute() ||
        relative_path.has_root_name() ||
        relative_path.has_root_directory()
    ) {
        error = "只允许 reframework/images 下的相对路径";
        return std::nullopt;
    }

    for (const auto& component : relative_path) {
        if (component == L"..") {
            error = "路径包含被禁止的 .. 组件";
            return std::nullopt;
        }
    }

    if (lowercase(relative_path.extension().native()) != L".png") {
        error = "只允许加载 PNG 文件";
        return std::nullopt;
    }

    std::error_code ec;
    const auto canonical_root = std::filesystem::weakly_canonical(g_image_root, ec);
    if (ec) {
        error = "无法解析固定图片目录";
        return std::nullopt;
    }

    auto candidate = std::filesystem::weakly_canonical(canonical_root / relative_path, ec);
    if (ec || !path_is_inside(canonical_root, candidate)) {
        error = "路径超出 reframework/images 固定目录";
        return std::nullopt;
    }

    if (std::filesystem::exists(candidate, ec) && !ec) {
        candidate = std::filesystem::canonical(candidate, ec);
        if (ec || !path_is_inside(canonical_root, candidate)) {
            error = "图片解析到固定目录之外";
            return std::nullopt;
        }
    }

    auto key_path = relative_path.lexically_normal().native();
    return ResolvedPath{candidate, lowercase(std::move(key_path))};
}

struct DecodedPng {
    int width{};
    int height{};
    std::vector<std::uint8_t> rgba;
};

std::optional<DecodedPng> decode_png_rgba(
    const std::filesystem::path& path,
    std::string& error
) {
    const HRESULT initialize_result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool should_uninitialize =
        initialize_result == S_OK || initialize_result == S_FALSE;
    if (FAILED(initialize_result) && initialize_result != RPC_E_CHANGED_MODE) {
        error = hresult_message("CoInitializeEx", initialize_result);
        return std::nullopt;
    }

    struct ComScope {
        bool enabled{};
        ~ComScope() {
            if (enabled) {
                CoUninitialize();
            }
        }
    } com_scope{should_uninitialize};

    ComPtr<IWICImagingFactory> factory;
    HRESULT result = CoCreateInstance(
        CLSID_WICImagingFactory2,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory)
    );
    if (FAILED(result)) {
        result = CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory)
        );
    }
    if (FAILED(result)) {
        error = hresult_message("Create WIC factory", result);
        return std::nullopt;
    }

    ComPtr<IWICBitmapDecoder> decoder;
    result = factory->CreateDecoderFromFilename(
        path.c_str(),
        nullptr,
        GENERIC_READ,
        WICDecodeMetadataCacheOnLoad,
        &decoder
    );
    if (FAILED(result)) {
        error = hresult_message("Open PNG", result);
        return std::nullopt;
    }

    ComPtr<IWICBitmapFrameDecode> frame;
    result = decoder->GetFrame(0, &frame);
    if (FAILED(result)) {
        error = hresult_message("Decode PNG frame", result);
        return std::nullopt;
    }

    UINT width = 0;
    UINT height = 0;
    result = frame->GetSize(&width, &height);
    if (FAILED(result) || width == 0 || height == 0 || width > 16384 || height > 16384) {
        error = FAILED(result)
            ? hresult_message("Read PNG size", result)
            : "PNG 尺寸无效或超过 16384";
        return std::nullopt;
    }

    const std::uint64_t byte_count =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height) * 4ULL;
    if (byte_count > std::numeric_limits<UINT>::max()) {
        error = "PNG 解码缓冲区过大";
        return std::nullopt;
    }

    ComPtr<IWICFormatConverter> converter;
    result = factory->CreateFormatConverter(&converter);
    if (FAILED(result)) {
        error = hresult_message("Create RGBA converter", result);
        return std::nullopt;
    }

    result = converter->Initialize(
        frame.Get(),
        GUID_WICPixelFormat32bppRGBA,
        WICBitmapDitherTypeNone,
        nullptr,
        0.0,
        WICBitmapPaletteTypeCustom
    );
    if (FAILED(result)) {
        error = hresult_message("Convert PNG to RGBA", result);
        return std::nullopt;
    }

    DecodedPng decoded;
    decoded.width = static_cast<int>(width);
    decoded.height = static_cast<int>(height);
    decoded.rgba.resize(static_cast<std::size_t>(byte_count));

    result = converter->CopyPixels(
        nullptr,
        width * 4,
        static_cast<UINT>(byte_count),
        decoded.rgba.data()
    );
    if (FAILED(result)) {
        error = hresult_message("Copy PNG pixels", result);
        return std::nullopt;
    }
    return decoded;
}

bool imgui_context_ready() {
    return
        g_imgui.get_current_context != nullptr &&
        g_imgui.get_current_context() != nullptr;
}

ImFontAtlas* current_font_atlas() {
    if (!imgui_context_ready() || g_imgui.get_io == nullptr) {
        return nullptr;
    }
    ImGuiIO* io = g_imgui.get_io();
    return io != nullptr ? io->Fonts : nullptr;
}

bool get_custom_rect(
    ImFontAtlas* atlas,
    ImFontAtlasRectId id,
    ImFontAtlasRect& rect
) {
    return
        atlas != nullptr &&
        id >= 0 &&
        g_imgui.get_custom_rect(atlas, id, &rect);
}

void include_update_rect(
    ImTextureRect& destination,
    const ImFontAtlasRect& source,
    bool& has_destination
) {
    if (!has_destination) {
        destination = ImTextureRect{
            source.x,
            source.y,
            source.w,
            source.h,
        };
        has_destination = true;
        return;
    }

    const unsigned int left = std::min<unsigned int>(
        destination.x,
        source.x
    );
    const unsigned int top = std::min<unsigned int>(
        destination.y,
        source.y
    );
    const unsigned int right = std::max<unsigned int>(
        destination.x + destination.w,
        source.x + source.w
    );
    const unsigned int bottom = std::max<unsigned int>(
        destination.y + destination.h,
        source.y + source.h
    );
    destination.x = static_cast<unsigned short>(left);
    destination.y = static_cast<unsigned short>(top);
    destination.w = static_cast<unsigned short>(right - left);
    destination.h = static_cast<unsigned short>(bottom - top);
}

void queue_retirement_locked(const TextureEntry& entry) {
    if (entry.atlas_rect_id < 0) {
        return;
    }
    g_retiring.push_back(RetiringRect{
        entry.atlas_rect_id,
        g_present_index + 2,
    });
}

void process_retiring_locked(ImFontAtlas* atlas) {
    if (atlas == nullptr) {
        return;
    }

    for (auto iterator = g_retiring.begin(); iterator != g_retiring.end();) {
        if (g_present_index < iterator->remove_after_present) {
            ++iterator;
            continue;
        }

        ImFontAtlasRect rect{};
        if (get_custom_rect(atlas, iterator->atlas_rect_id, rect)) {
            g_imgui.remove_custom_rect(atlas, iterator->atlas_rect_id);
        }
        iterator = g_retiring.erase(iterator);
    }
}

bool integrate_pending_locked(std::string& error) {
    ImFontAtlas* atlas = current_font_atlas();
    if (atlas == nullptr) {
        error = "ImGui 字体图集尚未就绪";
        return false;
    }
    if (atlas->Locked) {
        error = "ImGui 字体图集当前被锁定";
        return false;
    }

    process_retiring_locked(atlas);

    bool has_pending = false;
    for (auto& [handle, entry] : g_entries) {
        (void)handle;
        if (entry->decode_failed) {
            continue;
        }

        ImFontAtlasRect existing{};
        if (
            entry->atlas_rect_id >= 0 &&
            !get_custom_rect(atlas, entry->atlas_rect_id, existing)
        ) {
            entry->atlas_rect_id = -1;
            entry->atlas_ready = false;
        }

        if (entry->atlas_rect_id < 0) {
            entry->atlas_rect_id = g_imgui.add_custom_rect(
                atlas,
                entry->width,
                entry->height,
                nullptr
            );
            if (entry->atlas_rect_id < 0) {
                error = "ImGui 字体图集无法分配 PNG 区域";
                return false;
            }
        }
        has_pending |= !entry->atlas_ready;
    }

    if (!has_pending) {
        return true;
    }

    ImTextureData* texture = atlas->TexData;
    unsigned char* atlas_pixels =
        texture != nullptr ? texture->Pixels : nullptr;
    const int atlas_width = texture != nullptr ? texture->Width : 0;
    const int atlas_height = texture != nullptr ? texture->Height : 0;
    const int bytes_per_pixel =
        texture != nullptr ? texture->BytesPerPixel : 0;
    if (
        atlas_pixels == nullptr ||
        atlas_width <= 0 ||
        atlas_height <= 0 ||
        bytes_per_pixel != 4 ||
        texture->Format != ImTextureFormat_RGBA32
    ) {
        error = "ImGui 字体图集没有可写的 RGBA32 像素缓冲区";
        return false;
    }

    ImTextureRect update_rect{};
    bool has_update_rect = false;
    for (auto& [handle, entry] : g_entries) {
        (void)handle;
        if (entry->decode_failed || entry->atlas_ready) {
            continue;
        }

        ImFontAtlasRect rect{};
        if (!get_custom_rect(atlas, entry->atlas_rect_id, rect)) {
            error = "ImGui 字体图集区域失效";
            return false;
        }
        if (
            rect.w != entry->width ||
            rect.h != entry->height ||
            static_cast<int>(rect.x) + entry->width > atlas_width ||
            static_cast<int>(rect.y) + entry->height > atlas_height
        ) {
            error = "ImGui 字体图集区域尺寸异常";
            return false;
        }

        const std::size_t source_pitch =
            static_cast<std::size_t>(entry->width) * 4U;
        const std::size_t atlas_pitch =
            static_cast<std::size_t>(atlas_width) * 4U;
        for (int row = 0; row < entry->height; ++row) {
            unsigned char* destination =
                atlas_pixels +
                (static_cast<std::size_t>(rect.y + row) * atlas_pitch) +
                (static_cast<std::size_t>(rect.x) * 4U);
            const unsigned char* source =
                entry->decoded_rgba.data() +
                (static_cast<std::size_t>(row) * source_pitch);
            std::memcpy(destination, source, source_pitch);
        }

        entry->atlas_ready = true;
        include_update_rect(update_rect, rect, has_update_rect);
    }

    if (!has_update_rect) {
        return true;
    }

    atlas->TexPixelsUseColors = true;
    texture->UseColors = true;
    if (texture->Status == ImTextureStatus_OK) {
        texture->UpdateRect = update_rect;
        g_imgui.set_texture_status(texture, ImTextureStatus_WantUpdates);
    } else if (texture->Status == ImTextureStatus_WantUpdates) {
        ImFontAtlasRect previous{
            texture->UpdateRect.x,
            texture->UpdateRect.y,
            texture->UpdateRect.w,
            texture->UpdateRect.h,
            {},
            {},
        };
        include_update_rect(update_rect, previous, has_update_rect);
        texture->UpdateRect = update_rect;
    }
    return true;
}

void draw_fallback(float x, float y, const char* text) {
    if (!imgui_context_ready()) {
        return;
    }
    ImDrawList* draw_list = g_imgui.get_background_draw_list();
    if (draw_list == nullptr) {
        return;
    }
    g_imgui.add_text(draw_list, ImVec2{x, y}, 0xFF4040FFU, text, nullptr);
}

void retire_all_live_locked() {
    for (auto& [handle, entry] : g_entries) {
        (void)handle;
        queue_retirement_locked(*entry);
    }
    g_entries.clear();
    g_path_cache.clear();
}

int push_failure(lua_State* state, const std::string& message) {
    lua_pushnil(state);
    lua_pushlstring(state, message.data(), message.size());
    return 2;
}

std::optional<std::uint64_t> lua_handle(lua_State* state, int index) {
    int is_number = 0;
    const lua_Integer value = lua_tointegerx(state, index, &is_number);
    if (is_number == 0 || value <= 0) {
        return std::nullopt;
    }
    return static_cast<std::uint64_t>(value);
}

std::optional<float> lua_finite_number(lua_State* state, int index) {
    int is_number = 0;
    const lua_Number value = lua_tonumberx(state, index, &is_number);
    if (is_number == 0 || !std::isfinite(value)) {
        return std::nullopt;
    }
    if (
        value < -static_cast<lua_Number>(std::numeric_limits<float>::max()) ||
        value > static_cast<lua_Number>(std::numeric_limits<float>::max())
    ) {
        return std::nullopt;
    }
    return static_cast<float>(value);
}

int lua_texture_load(lua_State* state) {
    try {
        std::size_t length = 0;
        const char* path_text = lua_tolstring(state, 1, &length);
        if (path_text == nullptr) {
            return push_failure(state, "texture.load 需要 UTF-8 相对路径");
        }

        const std::string requested_path{path_text, length};
        std::string path_error;
        auto resolved = resolve_image_path(requested_path, path_error);
        if (!resolved.has_value()) {
            log_error_once(
                std::string{"path:"} + requested_path,
                requested_path + "： " + path_error
            );
            return push_failure(state, path_error);
        }

        {
            std::scoped_lock lock{g_mutex};
            const auto cached = g_path_cache.find(resolved->cache_key);
            if (cached != g_path_cache.end()) {
                lua_pushinteger(state, static_cast<lua_Integer>(cached->second));
                return 1;
            }
        }

        auto entry = std::make_unique<TextureEntry>();
        entry->full_path = resolved->full_path;
        entry->cache_key = resolved->cache_key;

        std::string decode_error;
        auto decoded = decode_png_rgba(entry->full_path, decode_error);
        if (decoded.has_value()) {
            entry->width = decoded->width;
            entry->height = decoded->height;
            entry->decoded_rgba = std::move(decoded->rgba);
        } else {
            entry->decode_failed = true;
            entry->error = decode_error;
            log_error_once(
                std::string{"decode:"} + requested_path,
                requested_path + "： " + decode_error
            );
        }

        std::scoped_lock lock{g_mutex};
        entry->handle = g_next_handle++;
        const std::uint64_t handle = entry->handle;
        g_path_cache.emplace(entry->cache_key, handle);

        g_entries.emplace(handle, std::move(entry));
        lua_pushinteger(state, static_cast<lua_Integer>(handle));
        return 1;
    } catch (const std::exception& exception) {
        return push_failure(state, exception.what());
    } catch (...) {
        return push_failure(state, "texture.load 发生未知错误");
    }
}

int lua_texture_draw(lua_State* state) {
    try {
        const auto handle = lua_handle(state, 1);
        const auto x = lua_finite_number(state, 2);
        const auto y = lua_finite_number(state, 3);
        const auto width = lua_finite_number(state, 4);
        const auto height = lua_finite_number(state, 5);
        if (
            !handle.has_value() ||
            !x.has_value() ||
            !y.has_value() ||
            !width.has_value() ||
            !height.has_value() ||
            *width <= 0.0F ||
            *height <= 0.0F
        ) {
            lua_pushboolean(state, 0);
            lua_pushliteral(state, "texture.draw 参数无效");
            return 2;
        }

        std::scoped_lock lock{g_mutex};
        const auto found = g_entries.find(*handle);
        if (found == g_entries.end()) {
            draw_fallback(*x, *y, "[texture invalid]");
            const std::string key = "invalid_handle:" + std::to_string(*handle);
            if (g_logged_errors.emplace(key).second && g_functions != nullptr) {
                g_functions->log_error(
                    "[reframework-imgui-texture] 无效或已释放的 handle: %llu",
                    static_cast<unsigned long long>(*handle)
                );
            }
            lua_pushboolean(state, 0);
            lua_pushliteral(state, "无效或已释放的 texture handle");
            return 2;
        }

        TextureEntry& entry = *found->second;
        if (entry.decode_failed) {
            draw_fallback(*x, *y, "[PNG missing]");
            lua_pushboolean(state, 0);
            lua_pushlstring(state, entry.error.data(), entry.error.size());
            return 2;
        }

        if (!entry.atlas_ready) {
            draw_fallback(*x, *y, "[texture pending]");
            lua_pushboolean(state, 0);
            lua_pushliteral(state, "PNG 正在等待 ImGui 字体图集上传");
            return 2;
        }

        if (!imgui_context_ready()) {
            lua_pushboolean(state, 0);
            lua_pushliteral(state, "ImGui context 尚未就绪");
            return 2;
        }

        ImDrawList* draw_list = g_imgui.get_background_draw_list();
        if (draw_list == nullptr) {
            lua_pushboolean(state, 0);
            lua_pushliteral(state, "无法取得 ImGui background draw list");
            return 2;
        }

        const float scale = std::min(
            *width / static_cast<float>(entry.width),
            *height / static_cast<float>(entry.height)
        );
        const float draw_width = static_cast<float>(entry.width) * scale;
        const float draw_height = static_cast<float>(entry.height) * scale;
        const float draw_x = *x + (*width - draw_width) * 0.5F;
        const float draw_y = *y + (*height - draw_height) * 0.5F;

        ImFontAtlas* atlas = current_font_atlas();
        ImFontAtlasRect rect{};
        if (!get_custom_rect(atlas, entry.atlas_rect_id, rect)) {
            entry.atlas_ready = false;
            draw_fallback(*x, *y, "[texture pending]");
            lua_pushboolean(state, 0);
            lua_pushliteral(state, "PNG 的 ImGui 字体图集区域已失效");
            return 2;
        }

        g_imgui.add_image(
            draw_list,
            atlas->TexRef,
            ImVec2{draw_x, draw_y},
            ImVec2{draw_x + draw_width, draw_y + draw_height},
            rect.uv0,
            rect.uv1,
            0xFFFFFFFFU
        );

        lua_pushboolean(state, 1);
        return 1;
    } catch (const std::exception& exception) {
        return push_failure(state, exception.what());
    } catch (...) {
        return push_failure(state, "texture.draw 发生未知错误");
    }
}

int lua_texture_size(lua_State* state) {
    const auto handle = lua_handle(state, 1);
    if (!handle.has_value()) {
        return push_failure(state, "texture.size 需要有效 handle");
    }

    std::scoped_lock lock{g_mutex};
    const auto found = g_entries.find(*handle);
    if (found == g_entries.end()) {
        return push_failure(state, "无效或已释放的 texture handle");
    }

    lua_pushinteger(state, found->second->width);
    lua_pushinteger(state, found->second->height);
    return 2;
}

int lua_texture_release(lua_State* state) {
    const auto handle = lua_handle(state, 1);
    if (!handle.has_value()) {
        lua_pushboolean(state, 0);
        return 1;
    }

    std::scoped_lock lock{g_mutex};
    const auto found = g_entries.find(*handle);
    if (found == g_entries.end()) {
        lua_pushboolean(state, 0);
        return 1;
    }

    g_path_cache.erase(found->second->cache_key);
    queue_retirement_locked(*found->second);
    g_entries.erase(found);
    lua_pushboolean(state, 1);
    return 1;
}

int lua_texture_clear_cache(lua_State* state) {
    std::scoped_lock lock{g_mutex};
    const lua_Integer count = static_cast<lua_Integer>(g_entries.size());
    retire_all_live_locked();
    lua_pushinteger(state, count);
    return 1;
}

void set_table_function(lua_State* state, const char* name, lua_CFunction function) {
    lua_pushcclosure(state, function, 0);
    lua_setfield(state, -2, name);
}

void register_lua_api(lua_State* state) {
    if (state == nullptr) {
        return;
    }

    if (g_functions != nullptr && g_functions->lock_lua != nullptr) {
        g_functions->lock_lua();
    }

    lua_getglobal(state, "texture");
    if (!lua_istable(state, -1)) {
        lua_pop(state, 1);
        lua_createtable(state, 0, 5);
    }

    set_table_function(state, "load", lua_texture_load);
    set_table_function(state, "draw", lua_texture_draw);
    set_table_function(state, "size", lua_texture_size);
    set_table_function(state, "release", lua_texture_release);
    set_table_function(state, "clear_cache", lua_texture_clear_cache);
    lua_setglobal(state, "texture");

    if (g_functions != nullptr && g_functions->unlock_lua != nullptr) {
        g_functions->unlock_lua();
    }
}

void on_lua_state_created(lua_State* state) {
    g_lua = state;
    register_lua_api(state);
}

void on_lua_state_destroyed(lua_State* state) {
    if (g_lua == state) {
        g_lua = nullptr;
    }
}

void on_imgui_frame(REFImGuiFrameCbData* data) {
    if (data == nullptr || data->context == nullptr) {
        return;
    }

    g_imgui.set_current_context(static_cast<ImGuiContext*>(data->context));
}

void on_present() {
    std::scoped_lock lock{g_mutex};
    ++g_present_index;

    std::string error;
    if (!integrate_pending_locked(error) && !g_entries.empty()) {
        log_error_once("atlas_integration:" + error, error);
    }
}

void on_device_reset() {
    std::scoped_lock lock{g_mutex};

    for (auto& [handle, entry] : g_entries) {
        (void)handle;
        if (!entry->decode_failed) {
            entry->atlas_ready = false;
        }
    }
}

std::optional<std::filesystem::path> get_game_directory(HMODULE module) {
    std::wstring buffer(32768, L'\0');
    const DWORD length = GetModuleFileNameW(
        module,
        buffer.data(),
        static_cast<DWORD>(buffer.size())
    );
    if (length == 0 || length >= buffer.size()) {
        return std::nullopt;
    }
    buffer.resize(length);
    return std::filesystem::path{buffer}.parent_path();
}

} // namespace

extern "C" __declspec(dllexport) void reframework_plugin_required_version(
    REFrameworkPluginVersion* version
) {
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch = REFRAMEWORK_PLUGIN_VERSION_PATCH;
    version->game_name = nullptr;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(
    const REFrameworkPluginInitializeParam* parameter
) {
    if (
        parameter == nullptr ||
        parameter->functions == nullptr ||
        parameter->reframework_module == nullptr
    ) {
        return false;
    }

    g_functions = parameter->functions;
    g_reframework_module = static_cast<HMODULE>(parameter->reframework_module);

    const auto game_directory = get_game_directory(g_reframework_module);
    if (!game_directory.has_value()) {
        log_error_once("game_directory", "无法确定游戏目录");
        return false;
    }
    g_image_root = *game_directory / L"reframework" / L"images";

    if (!resolve_cimgui_api()) {
        return false;
    }

    const bool callbacks_registered =
        g_functions->on_lua_state_created(on_lua_state_created) &&
        g_functions->on_lua_state_destroyed(on_lua_state_destroyed) &&
        g_functions->on_present(on_present) &&
        g_functions->on_imgui_frame(on_imgui_frame) &&
        g_functions->on_device_reset(on_device_reset);
    if (!callbacks_registered) {
        log_error_once("callbacks", "无法注册 REFramework 生命周期回调");
        return false;
    }

    log_info("已加载；图片根目录固定为 <gamedir>/reframework/images/");
    return true;
}
