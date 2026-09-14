-- Run against either the repository or the installed game reframework folder.
-- No repository fallback: missing deployed dependencies must fail this gate.
local root = arg[1] or "."
package.path = root .. "/autorun/?.lua;" .. root .. "/autorun/?/init.lua"
package.cpath = ""
local modules = {
    "SF6CCTrainingLibrary/Records", "SF6CCTrainingLibrary/Library", "SF6CCTrainingLibrary/NativeRecordingRuntime", "SF6CCTrainingLibrary/NativeRecordingNamePage",
}
for _, name in ipairs(modules) do
    assert(type(require(name)) == "table", "invalid module: " .. name)
    print("PASS deployed require " .. name)
end
for _, name in ipairs({ "SF6CCTrainingLibrary/Context", "SF6CCTrainingLibrary/NativeNoteEditor" }) do
    assert(package.searchpath(name, package.path), "missing deferred module: " .. name)
end
assert(loadfile(root .. "/autorun/SF6CC_TrainingLibrary.lua"))
print("PASS isolated training deployment dependency gate")
