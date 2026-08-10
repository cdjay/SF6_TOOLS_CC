-- AtomicDetector.lua
-- Stage 1 strict Atomic order comparator. Match is decided only by the
-- ordered (action_id, occurrence) sequence. Frames, command strings, display
-- text, Move UIDs and owner data are never equality inputs; they are retained
-- only as diagnostic context.

local AtomicDetector = {
    name = "ComboTrials.Raw.AtomicDetector",
    MODE = "strict_atomic_order_v1",
}

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")

local function is_action_id(value)
    return type(value) == "number"
        and value % 1 == 0
        and value >= 0
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function to_atoms(source, side)
    local instances
    if AtomicTrace.is_trace(source) then
        instances = source:get_instances()
    elseif type(source) == "table" and type(source.instances) == "table" then
        instances = source.instances
    elseif type(source) == "table" and type(source[1]) == "table" then
        instances = source
    else
        return nil, "invalid_" .. side
    end

    local atoms = {}
    local seen = {}
    local count = 0
    for index, instance in ipairs(instances) do
        if type(instance) ~= "table" or not is_action_id(instance.action_id) then
            return nil, "invalid_" .. side
        end
        if instance.step ~= nil and instance.step ~= index then
            return nil, "invalid_" .. side
        end
        local occurrence = (seen[instance.action_id] or 0) + 1
        if instance.occurrence ~= nil and instance.occurrence ~= occurrence then
            return nil, "invalid_" .. side
        end
        seen[instance.action_id] = occurrence
        atoms[index] = {
            action_id = instance.action_id,
            occurrence = occurrence,
            instance = instance,
        }
        count = index
    end
    for key in pairs(instances) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return nil, "invalid_" .. side
        end
    end
    return atoms
end

local function copy_diagnostic(atom)
    if atom == nil then return nil end
    local instance = {}
    for key, value in pairs(atom.instance) do
        instance[key] = clone(value)
    end
    return {
        action_id = atom.action_id,
        occurrence = atom.occurrence,
        instance = instance,
    }
end

local function sequence_summary(atoms)
    local summary = {}
    for index, atom in ipairs(atoms) do
        summary[index] = {
            action_id = atom.action_id,
            occurrence = atom.occurrence,
        }
    end
    return summary
end

function AtomicDetector.compare(expected, actual)
    local expected_atoms, expected_err = to_atoms(expected, "expected")
    if expected_atoms == nil then
        return nil, { error = expected_err }
    end
    local actual_atoms, actual_err = to_atoms(actual, "actual")
    if actual_atoms == nil then
        return nil, { error = actual_err }
    end

    local match = true
    local first_divergence = nil
    local limit = math.max(#expected_atoms, #actual_atoms)
    for step = 1, limit do
        local expected_atom = expected_atoms[step]
        local actual_atom = actual_atoms[step]
        if expected_atom == nil then
            match = false
            first_divergence = {
                step = step,
                reason = "unexpected_extra",
                expected = nil,
                actual = copy_diagnostic(actual_atom),
            }
            break
        end
        if actual_atom == nil then
            match = false
            first_divergence = {
                step = step,
                reason = "missing_expected",
                expected = copy_diagnostic(expected_atom),
                actual = nil,
            }
            break
        end
        if expected_atom.action_id ~= actual_atom.action_id
            or expected_atom.occurrence ~= actual_atom.occurrence then
            match = false
            first_divergence = {
                step = step,
                reason = "action_mismatch",
                expected = copy_diagnostic(expected_atom),
                actual = copy_diagnostic(actual_atom),
            }
            break
        end
    end

    return match, {
        mode = AtomicDetector.MODE,
        match = match,
        expected_count = #expected_atoms,
        actual_count = #actual_atoms,
        first_divergence = first_divergence,
        expected_sequence = sequence_summary(expected_atoms),
        actual_sequence = sequence_summary(actual_atoms),
    }
end

return AtomicDetector
