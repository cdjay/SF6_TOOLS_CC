#include <reframework/API.h>
#include <lua.hpp>

#include <Windows.h>
#include <bcrypt.h>

#include <array>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace {

const REFrameworkPluginFunctions* g_functions{};
std::filesystem::path g_data_root;

constexpr std::string_view k_checkpoint_path =
    "SF6_TrainingRemoteControl_data/ComboTrialTelemetry/cumulative-checkpoint-v1.json";
constexpr std::string_view k_state_path =
    "SF6_TrainingRemoteControl_data/ComboTrialTelemetry/producer-state-v1.json";
constexpr std::string_view k_events_path =
    "SF6_TrainingRemoteControl_data/ComboTrialTelemetry/events.jsonl";

std::string windows_error(const char* operation, DWORD code = GetLastError()) {
    char buffer[128]{};
    std::snprintf(buffer, sizeof(buffer), "%s failed (Win32 %lu)", operation, code);
    return buffer;
}

int push_failure(lua_State* state, const std::string& message) {
    lua_pushnil(state);
    lua_pushlstring(state, message.data(), message.size());
    return 2;
}

std::optional<std::string> random_hex_16(std::string& error) {
    std::array<std::uint8_t, 16> bytes{};
    const NTSTATUS status = BCryptGenRandom(
        nullptr,
        bytes.data(),
        static_cast<ULONG>(bytes.size()),
        BCRYPT_USE_SYSTEM_PREFERRED_RNG
    );
    if (status < 0) {
        char buffer[96]{};
        std::snprintf(buffer, sizeof(buffer), "BCryptGenRandom failed (NTSTATUS 0x%08lX)",
            static_cast<unsigned long>(status));
        error = buffer;
        return std::nullopt;
    }
    static constexpr char hex[] = "0123456789abcdef";
    std::string result(32, '0');
    for (std::size_t index = 0; index < bytes.size(); ++index) {
        result[index * 2] = hex[bytes[index] >> 4];
        result[index * 2 + 1] = hex[bytes[index] & 0x0f];
    }
    return result;
}

std::optional<std::filesystem::path> allowed_target(
    std::string_view relative,
    bool allow_events,
    std::string& error
) {
    if (relative != k_checkpoint_path && relative != k_state_path
        && (!allow_events || relative != k_events_path)) {
        error = "path is not an allowed SF6CC telemetry file";
        return std::nullopt;
    }
    std::string normalized{relative};
    for (char& character : normalized) {
        if (character == '/') character = '\\';
    }
    return g_data_root / std::filesystem::path{normalized};
}

bool write_all(HANDLE file, const char* bytes, std::size_t size, std::string& error) {
    std::size_t written_total = 0;
    while (written_total < size) {
        const auto remaining = size - written_total;
        const DWORD chunk = static_cast<DWORD>(remaining > MAXDWORD ? MAXDWORD : remaining);
        DWORD written = 0;
        if (!WriteFile(file, bytes + written_total, chunk, &written, nullptr) || written == 0) {
            error = windows_error("WriteFile");
            return false;
        }
        written_total += written;
    }
    return true;
}

bool atomic_write(const std::filesystem::path& target, const char* bytes, std::size_t size,
    std::string& error) {
    std::error_code directory_error;
    std::filesystem::create_directories(target.parent_path(), directory_error);
    if (directory_error) {
        error = "create telemetry directory failed: " + directory_error.message();
        return false;
    }

    std::filesystem::path temporary;
    HANDLE file = INVALID_HANDLE_VALUE;
    for (int attempt = 0; attempt < 16 && file == INVALID_HANDLE_VALUE; ++attempt) {
        std::string random_error;
        auto suffix = random_hex_16(random_error);
        if (!suffix) {
            error = random_error;
            return false;
        }
        temporary = target;
        temporary += L".tmp." + std::wstring(suffix->begin(), suffix->end());
        file = CreateFileW(
            temporary.c_str(),
            GENERIC_WRITE,
            0,
            nullptr,
            CREATE_NEW,
            FILE_ATTRIBUTE_TEMPORARY,
            nullptr
        );
        if (file == INVALID_HANDLE_VALUE && GetLastError() != ERROR_FILE_EXISTS) {
            error = windows_error("CreateFileW");
            return false;
        }
    }
    if (file == INVALID_HANDLE_VALUE) {
        error = "could not allocate a unique telemetry temp file";
        return false;
    }

    bool ok = write_all(file, bytes, size, error);
    if (ok && !FlushFileBuffers(file)) {
        error = windows_error("FlushFileBuffers");
        ok = false;
    }
    if (!CloseHandle(file) && ok) {
        error = windows_error("CloseHandle");
        ok = false;
    }
    if (ok && !MoveFileExW(
        temporary.c_str(),
        target.c_str(),
        MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
    )) {
        error = windows_error("MoveFileExW");
        ok = false;
    }
    if (!ok) DeleteFileW(temporary.c_str());
    return ok;
}

int lua_atomic_write(lua_State* state) {
    std::size_t path_size = 0;
    std::size_t content_size = 0;
    const char* path = lua_tolstring(state, 1, &path_size);
    const char* content = lua_tolstring(state, 2, &content_size);
    if (path == nullptr || content == nullptr) return push_failure(state, "write requires path and bytes");

    const std::string_view relative{path, path_size};
    const std::size_t maximum = relative == k_checkpoint_path ? 524288U : 1048576U;
    if (content_size > maximum) return push_failure(state, "telemetry file exceeds native byte limit");

    std::string error;
    auto target = allowed_target(relative, false, error);
    if (!target || !atomic_write(*target, content, content_size, error)) return push_failure(state, error);
    lua_pushboolean(state, 1);
    return 1;
}

int lua_probe(lua_State* state) {
    std::size_t path_size = 0;
    const char* path = lua_tolstring(state, 1, &path_size);
    if (path == nullptr) return push_failure(state, "probe requires path");

    std::string error;
    auto target = allowed_target(std::string_view{path, path_size}, true, error);
    if (!target) return push_failure(state, error);

    const DWORD attributes = GetFileAttributesW(target->c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) {
        if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            return push_failure(state, "telemetry target is a directory");
        }
        lua_pushliteral(state, "exists");
        return 1;
    }

    const DWORD code = GetLastError();
    if (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND) {
        lua_pushliteral(state, "missing");
        return 1;
    }
    return push_failure(state, windows_error("GetFileAttributesW", code));
}

int lua_random_epoch(lua_State* state) {
    std::string error;
    auto epoch = random_hex_16(error);
    if (!epoch) return push_failure(state, error);
    lua_pushlstring(state, epoch->data(), epoch->size());
    return 1;
}

void register_lua_api(lua_State* state) {
    if (state == nullptr) return;
    if (g_functions != nullptr && g_functions->lock_lua != nullptr) g_functions->lock_lua();
    lua_createtable(state, 0, 3);
    lua_pushcclosure(state, lua_atomic_write, 0);
    lua_setfield(state, -2, "write");
    lua_pushcclosure(state, lua_probe, 0);
    lua_setfield(state, -2, "probe");
    lua_pushcclosure(state, lua_random_epoch, 0);
    lua_setfield(state, -2, "random_epoch");
    lua_setglobal(state, "sf6cc_atomic_file");
    if (g_functions != nullptr && g_functions->unlock_lua != nullptr) g_functions->unlock_lua();
}

std::optional<std::filesystem::path> game_directory(HMODULE module) {
    std::wstring buffer(32768, L'\0');
    const DWORD length = GetModuleFileNameW(module, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size()) return std::nullopt;
    buffer.resize(length);
    return std::filesystem::path{buffer}.parent_path();
}

} // namespace

extern "C" __declspec(dllexport) void reframework_plugin_required_version(
    REFrameworkPluginVersion* version) {
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch = REFRAMEWORK_PLUGIN_VERSION_PATCH;
    version->game_name = nullptr;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(
    const REFrameworkPluginInitializeParam* parameter) {
    if (parameter == nullptr || parameter->functions == nullptr || parameter->reframework_module == nullptr) {
        return false;
    }
    g_functions = parameter->functions;
    const auto root = game_directory(static_cast<HMODULE>(parameter->reframework_module));
    if (!root) return false;
    g_data_root = *root / L"reframework" / L"data";
    if (!g_functions->on_lua_state_created(register_lua_api)) return false;
    if (g_functions->log_info != nullptr) {
        g_functions->log_info("[reframework-sf6cc-atomic-file] loaded");
    }
    return true;
}
