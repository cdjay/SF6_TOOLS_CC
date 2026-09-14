using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;

namespace SF6CC.OfflineRecordingBank;

// Offline storage only. The Lua bank model remains the authority for recording semantics.
public sealed class AtomicBankStore
{
    public const int MaxBytes = 16 * 1024 * 1024;
    private readonly string root;
    public sealed record Snapshot(byte[]? Bytes, string? Version);

#if BANK_STORE_TEST
    internal Action<string>? Fault;
#endif
    [System.Diagnostics.Conditional("BANK_STORE_TEST")]
    private void Checkpoint(string stage)
    {
#if BANK_STORE_TEST
        Fault?.Invoke(stage);
#endif
    }

    public AtomicBankStore(string rootDirectory)
    {
        if (!Path.IsPathFullyQualified(rootDirectory)) throw new ArgumentException("An absolute bank root is required");
        root = Path.GetFullPath(rootDirectory);
        CheckAncestors();
    }

    private string Target(int fighterId)
    {
        if (fighterId < 0) throw new ArgumentOutOfRangeException(nameof(fighterId));
        return Path.Combine(root, "fighter-" + fighterId.ToString(System.Globalization.CultureInfo.InvariantCulture) + ".json");
    }

    private static void RejectLink(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Linked bank paths are unsupported");
        }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
    }

    private void CheckAncestors()
    {
        for (DirectoryInfo? node = new(root); node != null; node = node.Parent) RejectLink(node.FullName);
    }

    private static string Version(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private static void ValidateEnvelope(byte[] bytes, int fighterId)
    {
        if (bytes.Length == 0 || bytes.Length > MaxBytes) throw new InvalidDataException("Bank size exceeds bounds");
        using var json = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 12 });
        static void RejectDuplicateKeys(JsonElement element)
        {
            if (element.ValueKind == JsonValueKind.Object)
            {
                var names = new HashSet<string>(StringComparer.Ordinal);
                foreach (var property in element.EnumerateObject())
                {
                    if (!names.Add(property.Name)) throw new InvalidDataException("Duplicate JSON key");
                    RejectDuplicateKeys(property.Value);
                }
            }
            else if (element.ValueKind == JsonValueKind.Array)
                foreach (var item in element.EnumerateArray()) RejectDuplicateKeys(item);
        }
        RejectDuplicateKeys(json.RootElement);
        var doc = json.RootElement;
        if (doc.ValueKind != JsonValueKind.Object || !doc.TryGetProperty("schema", out var schema))
            throw new InvalidDataException("Missing bank schema");
        bool legacy = schema.GetString() == "sf6cc.training_record_bank.draft1";
        var names = legacy ? new[] { "schema", "fighter_id", "source_player", "next_id", "records" }
            : new[] { "schema", "fighter_id", "source_player", "next_id", "records", "record_refs" };
        if (doc.ValueKind != JsonValueKind.Object || doc.EnumerateObject().Count() != names.Length
            || names.Any(name => !doc.TryGetProperty(name, out _)))
            throw new InvalidDataException("Unknown bank envelope");
        if ((!legacy && schema.GetString() != "sf6cc.training_record_bank.draft2")
            || doc.GetProperty("fighter_id").GetInt32() != fighterId
            || doc.GetProperty("source_player").GetString() != "P2"
            || doc.GetProperty("next_id").GetInt32() < 1
            || doc.GetProperty("records").ValueKind != JsonValueKind.Array
            || doc.GetProperty("records").GetArrayLength() > 200)
            throw new InvalidDataException("Bank character, schema or capacity mismatch");
        if (!legacy && (doc.GetProperty("record_refs").ValueKind != JsonValueKind.Array
            || doc.GetProperty("record_refs").GetArrayLength() > 600))
            throw new InvalidDataException("Recording reference envelope exceeds bounds");
    }

    public Snapshot Read(int fighterId)
    {
        CheckAncestors();
        string target = Target(fighterId);
        RejectLink(target);
        try
        {
            using var stream = new FileStream(target, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length == 0 || stream.Length > MaxBytes) throw new InvalidDataException("Bank size exceeds bounds");
            var bytes = new byte[checked((int)stream.Length)];
            stream.ReadExactly(bytes);
            if (stream.ReadByte() != -1) throw new IOException("Bank changed while reading");
            ValidateEnvelope(bytes, fighterId);
            return new Snapshot(bytes, Version(bytes));
        }
        catch (FileNotFoundException) { return new Snapshot(null, null); }
        catch (DirectoryNotFoundException) { return new Snapshot(null, null); }
    }

    // Returns only after a full flush/close and same-directory atomic publication.
    // Callers must first validate through the Lua model and explicitly request save.
    public Snapshot Save(int fighterId, byte[] content, string? expectedVersion)
    {
        string target = Target(fighterId);
        if (content == null || content.Length == 0 || content.Length > MaxBytes)
            throw new InvalidDataException("Bank size exceeds bounds");
        byte[] bytes = (byte[])content.Clone();
        ValidateEnvelope(bytes, fighterId);
        if (expectedVersion != null && (expectedVersion.Length != 64
            || expectedVersion.Any(c => !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f'))))
            throw new ArgumentException("Invalid saved version");
        CheckAncestors();
        Directory.CreateDirectory(root);
        CheckAncestors();
        string lockPath = target + ".lock";
        RejectLink(lockPath);
        // Keep the lock filename after close: unlinking it can split cooperative locks.
        using var guard = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        Snapshot before = Read(fighterId);
        if (before.Version != expectedVersion) throw new IOException("Saved bank changed externally");
        var result = new Snapshot(bytes, Version(bytes));
        if (before.Bytes != null && before.Bytes.AsSpan().SequenceEqual(bytes)) return result;
        string temporary = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                Checkpoint("created");
                stream.Write(bytes);
                Checkpoint("written");
                stream.Flush(flushToDisk: true);
                Checkpoint("flushed");
            }
            Checkpoint("closed");
            if (Read(fighterId).Version != expectedVersion) throw new IOException("Saved bank changed during write");
            if (before.Bytes == null) File.Move(temporary, target, overwrite: false);
            else File.Replace(temporary, target, destinationBackupFileName: null);
            return result;
        }
        finally
        {
            // Only our unique temporary file may be cleaned; never delete the target.
            try { File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
