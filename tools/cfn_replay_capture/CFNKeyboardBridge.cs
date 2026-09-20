using System;
using System.IO;
using System.Diagnostics;
using System.Text.Json;
using System.Threading;
using System.Runtime.InteropServices;
using REFrameworkNET;
using REFrameworkNET.Attributes;

// Only OS keyboard input. Never calls game methods or reads game objects.
public static class CFNKeyboardBridge {
    [StructLayout(LayoutKind.Sequential)] public struct KeyboardInput {
        public ushort VirtualKey, Scan; public uint Flags, Time; public UIntPtr Extra;
    }
    [StructLayout(LayoutKind.Explicit, Size = 32)] public struct InputUnion {
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Input {
        public uint Type; public InputUnion Data;
    }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint key, uint mapType);
    static readonly CancellationTokenSource Stop = new();
    static readonly string Token = Guid.NewGuid().ToString("N");
    static string Root, LastId;
    static Thread Worker;
    public static bool AllowedKey(int key) => (key >= 0x30 && key <= 0x39) || (key >= 0x41 && key <= 0x5a) ||
        (key >= 0x70 && key <= 0x87) || (key >= 0x21 && key <= 0x28) || key == 0x20;
    public static bool AllowedPressMilliseconds(int value) => value == 45 || value == 30 || value == 20 || value == 12;
    public static int ReadMenuKey(string[] lines) {
        int result = -1;
        bool found = false;
        foreach (var line in lines) {
            var parts = line.Split('=', 2);
            if (parts.Length != 2 || parts[0].Trim() != "REFrameworkConfig_MenuKey_V2") continue;
            if (found || !int.TryParse(parts[1].Trim(), out result)) return -1;
            found = true;
        }
        return AllowedKey(result) || result == 0x2d ? result : -1;
    }
    public static int ReadPressMilliseconds(JsonElement request) {
        if (!request.TryGetProperty("press_ms", out var value)) return 45;
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var n) && AllowedPressMilliseconds(n) ? n : -1;
    }
    public static string Validate(string token, string expected, string id, string previous, int key, double ageMs,
        bool foreground, bool overlay, bool held, bool hideOverlay = false) {
        if (token != expected || string.IsNullOrEmpty(id) || id == previous) return "stale";
        if (ageMs < 0 || ageMs > 500) return "expired";
        if (!AllowedKey(key) && !(hideOverlay && key == 0x2d)) return "key_unavailable";
        if (!foreground) return "focus_lost";
        if (overlay && !hideOverlay) return "close_overlay";
        if (held) return "key_held";
        return "ready";
    }
    static void Write(string name, object data) {
        var path = Path.Combine(Root, name);
        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(data));
        File.Move(path + ".tmp", path, true);
    }
    public static bool TryFileIteration(Action iteration) {
        try { iteration(); return true; }
        catch (JsonException) { return false; }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }
    static bool Foreground() {
        GetWindowThreadProcessId(GetForegroundWindow(), out var pid);
        return pid == Environment.ProcessId;
    }
    static bool ModifiersHeld() {
        foreach (var key in new[] { 0x10, 0x11, 0x12, 0x5b, 0x5c })
            if ((GetAsyncKeyState(key) & 0x8000) != 0) return true;
        return false;
    }
    static Input Key(int key, bool up) {
        var flags = 8u | (up ? 2u : 0u) | (key >= 0x21 && key <= 0x28 || key == 0x2d ? 1u : 0u);
        return new Input { Type = 1, Data = new InputUnion { Keyboard = new KeyboardInput {
            Scan = (ushort)MapVirtualKey((uint)key, 0), Flags = flags } } };
    }
    public static bool OverlayNeedsToggle(bool current, bool desired) => current != desired;
    static string Tap(int key, int pressMs, out double heldMs, bool hideOverlay = false, bool showOverlay = false) {
        heldMs = 0;
        if (!AllowedPressMilliseconds(pressMs)) return "press_unavailable";
        if (!Foreground()) return "focus_lost";
        if (hideOverlay && !OverlayNeedsToggle(API.IsDrawingUI(), showOverlay)) return "sent";
        if (!hideOverlay && API.IsDrawingUI()) return "close_overlay";
        var down = Key(key, false);
        if (down.Data.Keyboard.Scan == 0) return "key_unavailable";
        if (SendInput(1, new[] { down }, Marshal.SizeOf<Input>()) != 1) return "send_failed";
        var started = Stopwatch.GetTimestamp();
        bool released = false;
        try { Stop.Token.WaitHandle.WaitOne(pressMs); }
        finally {
            // Always release our own press, including cancellation or a focus change.
            var up = Key(key, true);
            released = SendInput(1, new[] { up }, Marshal.SizeOf<Input>()) == 1;
            heldMs = (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency;
            if (!released)
                API.LogError("[CFN keyboard] Key release failed");
        }
        return released ? "sent" : "release_failed";
    }
    static bool Cancelled(string id) {
        var path = Path.Combine(Root, "cfn-keyboard-cancel.json");
        if (!File.Exists(path)) return false;
        using var json = JsonDocument.Parse(File.ReadAllText(path));
        return json.RootElement.GetProperty("token").GetString() == Token &&
            json.RootElement.GetProperty("id").GetString() == id;
    }
    [PluginEntryPoint]
    public static void Main() {
        if (Marshal.SizeOf<Input>() != 40) throw new InvalidOperationException("Unexpected INPUT layout");
        // The process executable directory, not the source compiler working directory.
        Root = Path.Combine(Path.GetDirectoryName(Environment.ProcessPath), "reframework", "data");
        Directory.CreateDirectory(Root);
        Worker = new Thread(Run) { IsBackground = true, Name = "CFN replay keyboard" };
        Worker.Start();
    }
    static void Run() {
        DateTime nextReady = DateTime.MinValue;
        int retryDelay = 10;
        while (!Stop.IsCancellationRequested) {
            try {
                bool completed = TryFileIteration(() => {
                if (DateTime.UtcNow >= nextReady) {
                    Write("cfn-keyboard-ready.json", new { token = Token, pid = Environment.ProcessId, protocol = 1,
                        updated_at = DateTimeOffset.UtcNow.ToUnixTimeSeconds(), press_ms_options = new[] {45, 30, 20, 12}, hide_overlay = true, restore_overlay = true });
                    nextReady = DateTime.UtcNow.AddSeconds(2);
                }
                var path = Path.Combine(Root, "cfn-keyboard-request.json");
                if (File.Exists(path)) {
                    var age = (DateTime.UtcNow - File.GetLastWriteTimeUtc(path)).TotalMilliseconds;
                    if (age >= 0 && age <= 500) {
                        using var json = JsonDocument.Parse(File.ReadAllText(path));
                        var r = json.RootElement;
                        var id = r.GetProperty("id").GetString();
                        var token = r.GetProperty("token").GetString();
                        if (token == Token && id != LastId) {
                            var actionName = r.TryGetProperty("action", out var action) ? action.GetString() : null;
                            bool show = actionName == "show_overlay";
                            bool hide = actionName == "hide_overlay" || show;
                            var key = hide ? ReadMenuKey(File.ReadAllLines(Path.Combine(Path.GetDirectoryName(Environment.ProcessPath), "re2_fw_config.txt")))
                                : r.GetProperty("key").GetInt32();
                            var pressMs = ReadPressMilliseconds(r);
                            double heldMs = 0;
                            var status = Validate(token, Token, id, LastId, key, age, Foreground(),
                                API.IsDrawingUI(), ModifiersHeld() || (key > 0 && (GetAsyncKeyState(key) & 0x8000) != 0), hide);
                            LastId = id; // Consume before SendInput; never retry a command.
                            if (status == "ready" && pressMs < 0) status = "press_unavailable";
                            if (status == "ready")
                                status = Stop.IsCancellationRequested || Cancelled(id) ? "cancelled" : Tap(key, pressMs, out heldMs, hide, show);
                            Write("cfn-keyboard-response.json", new { token = Token, id, status, press_ms = pressMs, held_ms = heldMs });
                        }
                    }
                }
                });
                // Retry file exchange, never a consumed key. Request age and LastId still apply.
                retryDelay = completed ? 10 : Math.Min(250, retryDelay * 2);
            } catch (Exception ex) { API.LogError("[CFN keyboard] " + ex.Message); return; }
            Stop.Token.WaitHandle.WaitOne(retryDelay);
        }
    }
    [PluginExitPoint]
    public static void OnUnload() { Stop.Cancel(); Worker?.Join(1000); }
}
