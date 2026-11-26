-- Run from the repository root: lua tests/test_vc_runtime.lua
-- InstallVcRuntime() runs the bundled vc_redist.x64.exe unless the registry already records an x64
-- VC++ runtime at least as new as VC_REDIST_VERSION. Checking only Installed kept 14.29 on a site
-- machine, where 6.3.45.24 then failed to start with 0xc0000142.
local VC_KEY = "SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64"
local registry, commands, errors, upgradeTo

installx = {
    RegGetValue = function(root, path, name)
        assert(root == HRootKey.HKEY_LOCAL_MACHINE)
        assert(path == VC_KEY, path)
        return registry[name]
    end,
    -- vc_redist: records the version it brings, or nothing when it fails.
    ProcessExecute = function(command, hidden, waitSeconds)
        table.insert(commands, {command = command, hidden = hidden, wait = waitSeconds})
        if upgradeTo then
            local major, minor, build = upgradeTo:match("^(%d+)%.(%d+)%.(%d+)")
            registry = {Installed = 1, Major = tonumber(major), Minor = tonumber(minor), Bld = tonumber(build)}
        end
        return true
    end,
    LogPrint = function() end,
}
HRootKey = {HKEY_LOCAL_MACHINE = 0x80000002}
ErrorHint = function(message) table.insert(errors, message) end

local script = "projects/TaijiMPC6/Install/Install.lua"
local source = assert(io.open(script, "rb")):read("a")
-- build_TaijiMPC6.py rewrites exactly this line; keep its shape.
local bundled = source:match('\nlocal VC_REDIST_VERSION = "(%d+%.%d+%.%d+%.%d+)"\r?\n')
assert(bundled, "local VC_REDIST_VERSION = \"a.b.c.d\" not found in " .. script)
local required = bundled:match("^(%d+%.%d+%.%d+)")
assert(loadfile(script))()

local function runtime(version, installed)
    if version == nil then
        return {Installed = installed}
    end
    local major, minor, build = version:match("^(%d+)%.(%d+)%.(%d+)")
    return {Installed = installed or 1, Major = tonumber(major), Minor = tonumber(minor), Bld = tonumber(build)}
end

local function bump(version, field, delta)
    local fields = {}
    for value in version:gmatch("%d+") do
        table.insert(fields, tonumber(value))
    end
    fields[field] = fields[field] + delta
    return table.concat(fields, ".")
end

local count = 0
local function check(label, state, expectRun, expectResult, expectError)
    registry, commands, errors, upgradeTo = state.registry, {}, {}, state.upgradeTo
    local result = InstallVcRuntime()
    assert(result == expectResult, label .. ": result " .. tostring(result))
    assert((#commands == 1) == expectRun, label .. ": runs " .. #commands)
    if expectRun then
        local run = commands[1]
        assert(run.command == "\"C:\\TaijiControl\\Common\\vcredist\\vc_redist.x64.exe\" /install /quiet /norestart",
               label .. ": " .. run.command)
        assert(run.hidden == true and run.wait == 300, label .. ": hidden, waits up to 300 s")
    end
    assert((#errors == 1) == expectError, label .. ": hints " .. #errors)
    count = count + 1
end

-- No runtime, an unreadable one, or one older than the bundled: vc_redist runs and brings it.
local older = {
    {"no key", {}},
    {"Installed = 0", runtime(nil, 0)},
    {"Installed without a version", runtime(nil, 1)},
    {"14.29 (the site machine)", runtime("14.29.30133")},
    {"14.44", runtime("14.44.35211")},
    {"older build", runtime(bump(required, 3, -1))},
    {"older minor, newer build", runtime(bump(bump(required, 2, -1), 3, 50000))},
    {"version but Installed = 0", runtime(required, 0)},
}
for _, case in ipairs(older) do
    check(case[1], {registry = case[2], upgradeTo = required}, true, true, false)
end

-- Already the bundled version or newer: left alone. Fields compare as numbers, not strings.
local current = {
    {"same", runtime(required)},
    {"newer build", runtime(bump(required, 3, 1))},
    {"newer minor, older build", runtime(bump(bump(required, 2, 1), 3, -30000))},
    {"newer minor 100", runtime(bump(required, 2, 100 - tonumber(required:match("^%d+%.(%d+)"))))},
    {"newer major", runtime(bump(required, 1, 1))},
}
for _, case in ipairs(current) do
    check(case[1], {registry = case[2]}, false, true, false)
end

-- vc_redist ran but the runtime is still too old, or still missing: setup stops and says why.
check("vc_redist failed", {registry = runtime("14.29.30133")}, true, false, true)
assert(errors[1]:find("14.29.30133", 1, true) and errors[1]:find(required, 1, true)
       and errors[1]:find("C:\\TaijiControl\\Common\\vcredist\\vc_redist.x64.exe", 1, true), errors[1])
check("vc_redist failed, no runtime", {registry = {}}, true, false, true)
check("vc_redist brought an older one", {registry = {}, upgradeTo = bump(required, 3, -1)}, true, false, true)

-- A custom install root: the redist is run from there.
ResetInstallPath("D:\\Custom 目录")
registry, commands, errors, upgradeTo = runtime("14.29.30133"), {}, {}, required
assert(InstallVcRuntime() == true and #commands == 1)
assert(commands[1].command == "\"D:\\Custom 目录\\Common\\vcredist\\vc_redist.x64.exe\" /install /quiet /norestart",
       commands[1].command)
count = count + 1

print("VC++ runtime installer: " .. count .. " cases passed")
