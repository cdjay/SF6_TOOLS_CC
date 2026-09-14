using System.Text;
using SF6CC.OfflineRecordingBank;

static class Tests
{
    static int passed;
    static byte[] Document(int fighter = 28, int next = 1) => Encoding.UTF8.GetBytes(
        "{\"schema\":\"sf6cc.training_record_bank.draft1\",\"fighter_id\":" + fighter
        + ",\"source_player\":\"P2\",\"next_id\":" + next + ",\"records\":[]}");
    static void Assert(bool value) { if (!value) throw new Exception("Assertion failed"); }
    static void Fails(Action action)
    {
        try { action(); } catch (IOException) { return; } catch (UnauthorizedAccessException) { return; }
        catch (System.IO.InvalidDataException) { return; }
        catch (ArgumentException) { return; } catch (System.Text.Json.JsonException) { return; }
        throw new Exception("Expected bounded failure");
    }
    static void Test(string name, Action<string> run)
    {
        // All test files are isolated under the system temporary directory.
        string root = Path.Combine(Path.GetTempPath(), "sf6cc-bank-store-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try { run(root); passed++; Console.WriteLine("PASS " + name); }
        finally
        {
            string absolute = Path.GetFullPath(root);
            string temp = Path.GetFullPath(Path.GetTempPath());
            if (!absolute.StartsWith(temp, StringComparison.OrdinalIgnoreCase)
                || !Path.GetFileName(absolute).StartsWith("sf6cc-bank-store-", StringComparison.Ordinal))
                throw new Exception("Refusing unsafe cleanup");
            Directory.Delete(absolute, recursive: true);
        }
    }
    static void RunLua(string mode, string input, string output)
    {
        var start = new System.Diagnostics.ProcessStartInfo(Environment.GetEnvironmentVariable("SF6CC_LUA") ?? "lua")
        {
            UseShellExecute = false, CreateNoWindow = true,
            WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true, RedirectStandardError = true,
        };
        start.ArgumentList.Add(Path.GetFullPath("tools/training_record_bank/storage-tests/roundtrip.lua"));
        start.ArgumentList.Add(mode); start.ArgumentList.Add(input); start.ArgumentList.Add(output);
        using var child = System.Diagnostics.Process.Start(start)!;
        var stdout = child.StandardOutput.ReadToEndAsync();
        var stderr = child.StandardError.ReadToEndAsync();
        if (!child.WaitForExit(30000))
        {
            child.Kill(); child.WaitForExit();
            throw new Exception("Lua interchange test timed out");
        }
        if (child.ExitCode != 0) throw new Exception("Lua interchange failed: " + stderr.GetAwaiter().GetResult());
        Assert(stdout.GetAwaiter().GetResult().Contains("PASS Lua JSON", StringComparison.Ordinal));
    }
    static void Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--exit-before-replace")
        {
            var store = new AtomicBankStore(args[1]);
            var saved = store.Read(28);
            Assert(saved.Bytes != null);
            store.Fault = stage => { if (stage == "closed") Environment.Exit(73); };
            store.Save(28, Document(next: 2), saved.Version);
            throw new Exception("Exit boundary not reached");
        }
        Test("create replace reopen and no-op", root =>
        {
            var store = new AtomicBankStore(root);
            Assert(store.Read(28).Bytes == null);
            var saved = store.Save(28, Document(), null);
            Assert(saved.Version?.Length == 64);
            Assert(new AtomicBankStore(root).Read(28).Bytes!.SequenceEqual(Document()));
            string path = Path.Combine(root, "fighter-28.json");
            File.SetLastWriteTimeUtc(path, new DateTime(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc));
            store.Save(28, Document(), saved.Version);
            Assert(File.GetLastWriteTimeUtc(path).Year == 2000);
            var changed = store.Save(28, Document(next: 2), saved.Version);
            Assert(changed.Version != saved.Version);
            Assert(store.Read(28).Bytes!.SequenceEqual(Document(next: 2)));
        });
        foreach (string stage in new[] { "created", "written", "flushed", "closed" })
            Test("failure at " + stage + " keeps last complete bank", root =>
            {
                var store = new AtomicBankStore(root);
                var saved = store.Save(28, Document(), null);
                store.Fault = point => { if (point == stage) throw new IOException("injected"); };
                Fails(() => store.Save(28, Document(next: 2), saved.Version));
                Assert(new AtomicBankStore(root).Read(28).Bytes!.SequenceEqual(Document()));
                Assert(Directory.GetFiles(root, "*.tmp").Length == 0);
            });
        Test("failed initial save and abandoned temp never become a bank", root =>
        {
            var store = new AtomicBankStore(root) { Fault = _ => throw new IOException("injected") };
            Fails(() => store.Save(28, Document(), null));
            File.WriteAllText(Path.Combine(root, "fighter-28.abandoned.tmp"), "{");
            Assert(new AtomicBankStore(root).Read(28).Bytes == null);
            store.Fault = null;
            store.Save(28, Document(), null);
            Assert(File.ReadAllText(Path.Combine(root, "fighter-28.abandoned.tmp")) == "{");
        });
        Test("stale writer refuses external edits and deletion", root =>
        {
            var a = new AtomicBankStore(root);
            var saved = a.Save(28, Document(), null);
            var b = new AtomicBankStore(root);
            b.Save(28, Document(next: 2), saved.Version);
            Fails(() => a.Save(28, Document(next: 3), saved.Version));
            Assert(a.Read(28).Bytes!.SequenceEqual(Document(next: 2)));
            File.Delete(Path.Combine(root, "fighter-28.json"));
            Fails(() => a.Save(28, Document(), saved.Version));
            Assert(a.Read(28).Bytes == null);
        });
        Test("changes during temporary write are detected", root =>
        {
            var store = new AtomicBankStore(root);
            var saved = store.Save(28, Document(), null);
            store.Fault = stage => { if (stage == "closed") File.WriteAllBytes(Path.Combine(root, "fighter-28.json"), Document(next: 4)); };
            Fails(() => store.Save(28, Document(next: 2), saved.Version));
            Assert(store.Read(28).Bytes!.SequenceEqual(Document(next: 4)));
        });
        Test("unreadable and corrupt are errors never missing", root =>
        {
            var store = new AtomicBankStore(root);
            var saved = store.Save(28, Document(), null);
            string path = Path.Combine(root, "fighter-28.json");
            using (var held = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            {
                Fails(() => store.Read(28));
                Fails(() => store.Save(28, Document(next: 2), saved.Version));
            }
            File.WriteAllText(path, "{");
            Fails(() => store.Read(28));
            Fails(() => store.Save(28, Document(), null));
            Assert(File.ReadAllText(path) == "{");
        });
        Test("cooperative writer lock cannot be bypassed", root =>
        {
            var store = new AtomicBankStore(root);
            var saved = store.Save(28, Document(), null);
            using var held = new FileStream(Path.Combine(root, "fighter-28.json.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            Fails(() => store.Save(28, Document(next: 2), saved.Version));
            Assert(store.Read(28).Version == saved.Version);
        });
        Test("process exit before replacement leaves old bank recoverable", root =>
        {
            var store = new AtomicBankStore(root);
            var saved = store.Save(28, Document(), null);
            var start = new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!)
            {
                UseShellExecute = false, CreateNoWindow = true,
                WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
            };
            if (Path.GetFileNameWithoutExtension(Environment.ProcessPath!).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(System.Reflection.Assembly.GetExecutingAssembly().Location);
            start.ArgumentList.Add("--exit-before-replace");
            start.ArgumentList.Add(root);
            using var child = System.Diagnostics.Process.Start(start)!;
            if (!child.WaitForExit(10000))
            {
                child.Kill(); child.WaitForExit();
                throw new Exception("Child exit test timed out");
            }
            Assert(child.ExitCode == 73);
            Assert(Directory.GetFiles(root, "*.tmp").Length == 1);
            var reopened = new AtomicBankStore(root);
            Assert(reopened.Read(28).Version == saved.Version);
            reopened.Save(28, Document(next: 3), saved.Version);
            Assert(reopened.Read(28).Bytes!.SequenceEqual(Document(next: 3)));
        });
        Test("character isolation envelope duplicates and size limits", root =>
        {
            var store = new AtomicBankStore(root);
            var saved = store.Save(28, Document(), null);
            Fails(() => store.Save(19, Document(), null));
            Fails(() => store.Save(-1, Document(), null));
            Fails(() => store.Save(28, new byte[AtomicBankStore.MaxBytes + 1], saved.Version));
            Fails(() => store.Save(28, Encoding.UTF8.GetBytes("{\"schema\":1,\"schema\":2}"), saved.Version));
            store.Save(19, Document(19), null);
            Assert(store.Read(28).Version == saved.Version && store.Read(19).Bytes!.SequenceEqual(Document(19)));
        });
        Test("pinned offline JSON dependency bytes", _ =>
        {
            var hash = System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes("tools/training_record_bank/vendor/dkjson.lua"));
            Assert(Convert.ToHexString(hash).Equals("EB3BF160688FB395A2DB6BC52EEFF4F7855A6321D2B41BDC754554D13F4E7D44", StringComparison.Ordinal));
        });
        Test("real Lua JSON native filesystem reopen preserves content and stable IDs", root =>
        {
            var store = new AtomicBankStore(Path.Combine(root, "banks"));
            string input = Path.Combine(root, "input.json"), output = Path.Combine(root, "output.json");
            File.WriteAllBytes(input, Document());
            RunLua("seed", input, output);
            var saved = store.Save(28, File.ReadAllBytes(output), null);
            var reloaded = new AtomicBankStore(Path.Combine(root, "banks")).Read(28);
            Assert(reloaded.Version == saved.Version);
            using (var doc = System.Text.Json.JsonDocument.Parse(reloaded.Bytes!))
            {
                var records = doc.RootElement.GetProperty("records");
                Assert(records.GetArrayLength() == 2);
                Assert(records[0].GetProperty("recording").GetProperty("fields").ValueKind == System.Text.Json.JsonValueKind.Object);
                Assert(records[0].GetProperty("name").GetString() == "中文名称");
            }
            File.WriteAllBytes(input, reloaded.Bytes!);
            RunLua("verify", input, output);
            var next = store.Save(28, File.ReadAllBytes(output), reloaded.Version);
            Assert(next.Version != saved.Version);
            using var final = System.Text.Json.JsonDocument.Parse(store.Read(28).Bytes!);
            Assert(final.RootElement.GetProperty("next_id").GetInt32() == 5);
            Assert(final.RootElement.GetProperty("records")[2].GetProperty("id").GetInt32() == 4);
        });
        Test("real Lua 200-record JSON is completely persisted", root =>
        {
            string input = Path.Combine(root, "input.json"), output = Path.Combine(root, "output.json");
            File.WriteAllBytes(input, Document());
            RunLua("capacity", input, output);
            var store = new AtomicBankStore(Path.Combine(root, "banks"));
            var saved = store.Save(28, File.ReadAllBytes(output), null);
            Assert(store.Read(28).Bytes!.SequenceEqual(saved.Bytes!));
            using var final = System.Text.Json.JsonDocument.Parse(saved.Bytes!);
            Assert(final.RootElement.GetProperty("records").GetArrayLength() == 200);
            Assert(final.RootElement.GetProperty("records")[199].GetProperty("id").GetInt32() == 200);
        });
        Console.WriteLine(passed + " atomic bank storage tests passed");
    }
}
