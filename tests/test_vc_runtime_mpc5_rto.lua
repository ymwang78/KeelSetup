-- Run from the repository root: lua tests/test_vc_runtime_mpc5_rto.lua
-- The TaijiMPC (MPC5) and Rto installers run their bundled vc_redist.x64.exe unless the registry
-- already records an x64 VC++ runtime at least as new as VC_REDIST_VERSION, as TaijiMPC6's does
-- (tests/test_vc_runtime.lua). They used to check only Installed, so any older runtime was kept:
-- with one older than 14.40, programs built by VS 2026 against libzce fail to start (0xc0000142).
-- Each script is loaded into an environment of its own; the two define the same globals.
local VC_KEY = "SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64"
local HKLM = 0x80000002

local SCRIPTS = {
    {
        name = "TaijiMPC",
        path = "projects/TaijiMPC/Install/Install.lua",
        root = "C:\\TaijiControl",
        redist = "\\Common\\vcredist\\vc_redist.x64.exe",
        -- Written by the rest of PostSetup once the runtime is in place.
        registered = "Software\\TaijiControl",
    },
    {
        name = "Rto",
        path = "projects/Rto/Install/Install.lua",
        root = "C:\\ZJU",
        redist = "\\Common\\redist\\vc_redist.x64.exe",
        registered = "Software\\ZJU",
    },
}

-- What the scripts did: the commands they ran, the registry values they wrote, the errors shown.
local state

local function isRedist(command)
    return command:find("vc_redist.x64.exe", 1, true) ~= nil
end

local function load(script)
    local env = setmetatable({}, {__index = _G})
    local installx = {
        RegGetValue = function(root, path, name)
            if root == HKLM and path == VC_KEY then
                return state.registry[name]
            end
            return nil
        end,
        -- vc_redist records the version it brings, or nothing when it fails.
        ProcessExecute = function(command, hidden, waitSeconds)
            table.insert(state.commands, {command = command, hidden = hidden, wait = waitSeconds})
            if isRedist(command) and state.upgradeTo then
                local major, minor, build = state.upgradeTo:match("^(%d+)%.(%d+)%.(%d+)")
                state.registry = {Installed = 1, Major = tonumber(major), Minor = tonumber(minor), Bld = tonumber(build)}
            end
            return true
        end,
        RegSetValue = function(root, path, name, value)
            table.insert(state.written, path .. "|" .. tostring(name))
        end,
        FilePathGetSpecialLocation = function() return "C:\\Users\\Public\\Desktop" end,
    }
    -- Everything else PostSetup calls (progress, shortcuts, files) does nothing here.
    env.installx = setmetatable(installx, {__index = function() return function() end end})
    env.HRootKey = {HKEY_CLASSES_ROOT = 0x80000000, HKEY_LOCAL_MACHINE = HKLM}
    env.CSIDL = {COMMON_DESKTOPDIRECTORY = 0x19, COMMON_STARTMENU = 0x16}
    env.ErrorHint = function(message) table.insert(state.errors, message) end
    env.RunBatchFile = function(path) table.insert(state.commands, {command = "cmd " .. path}) end
    assert(loadfile(script, "t", env))()
    return env
end

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

local function reset(registry, upgradeTo)
    state = {registry = registry, upgradeTo = upgradeTo, commands = {}, written = {}, errors = {}}
end

local function redistRuns()
    local runs = {}
    for _, run in ipairs(state.commands) do
        if isRedist(run.command) then
            table.insert(runs, run)
        end
    end
    return runs
end

local count = 0

for _, target in ipairs(SCRIPTS) do
    local source = assert(io.open(target.path, "rb")):read("a")
    -- The packing script rewrites exactly this line; keep its shape.
    local bundled = source:match('\nlocal VC_REDIST_VERSION = "(%d+%.%d+%.%d+%.%d+)"\r?\n')
    assert(bundled, "local VC_REDIST_VERSION = \"a.b.c.d\" not found in " .. target.path)
    local required = bundled:match("^(%d+%.%d+%.%d+)")
    local env = load(target.path)
    local redistCommand = "\"" .. target.root .. target.redist .. "\" /install /quiet /norestart"

    local function check(label, registry, upgradeTo, expectRun, expectResult, expectError)
        label = target.name .. ", " .. label
        reset(registry, upgradeTo)
        local result = env.InstallVcRuntime()
        assert(result == expectResult, label .. ": result " .. tostring(result))
        local runs = redistRuns()
        assert(#state.commands == #runs, label .. ": only vc_redist runs")
        assert((#runs == 1) == expectRun, label .. ": runs " .. #runs)
        if expectRun then
            assert(runs[1].command == redistCommand, label .. ": " .. runs[1].command)
            assert(runs[1].hidden == true and runs[1].wait == 300, label .. ": hidden, waits up to 300 s")
        end
        assert((#state.errors == 1) == expectError, label .. ": hints " .. #state.errors)
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
        check(case[1], case[2], required, true, true, false)
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
        check(case[1], case[2], nil, false, true, false)
    end

    -- vc_redist ran but the runtime is still too old, or still missing: setup stops and says why.
    check("vc_redist failed", runtime("14.29.30133"), nil, true, false, true)
    local hint = state.errors[1]
    assert(hint:find("14.29.30133", 1, true) and hint:find(required, 1, true)
           and hint:find(target.root .. target.redist, 1, true), hint)
    check("vc_redist failed, no runtime", {}, nil, true, false, true)
    check("vc_redist brought an older one", {}, bump(required, 3, -1), true, false, true)

    -- PostSetup stops before registering anything when the runtime cannot be brought up to date.
    reset(runtime("14.29.30133"), nil)
    assert(env.PostSetup() == false, target.name .. ": PostSetup fails")
    assert(#state.commands == 1 and isRedist(state.commands[1].command), target.name .. ": nothing after vc_redist")
    assert(#state.written == 0 and #state.errors == 1, target.name .. ": nothing registered")
    count = count + 1

    -- With the runtime current PostSetup goes on as before, without running vc_redist.
    reset(runtime(required), nil)
    assert(env.PostSetup() ~= false, target.name .. ": PostSetup succeeds")
    assert(#redistRuns() == 0 and #state.errors == 0, target.name .. ": vc_redist left alone")
    local registered = false
    for _, value in ipairs(state.written) do
        registered = registered or value == target.registered .. "|InstallPath"
    end
    assert(registered, target.name .. ": the rest of PostSetup ran")
    count = count + 1

    -- And after vc_redist brought the runtime up to date.
    reset(runtime("14.29.30133"), required)
    assert(env.PostSetup() ~= false, target.name .. ": PostSetup succeeds after vc_redist")
    assert(#redistRuns() == 1 and #state.errors == 0, target.name .. ": vc_redist ran once")
    count = count + 1

    -- A custom install root: the redist is run from there.
    env.ResetInstallPath("D:\\Custom 目录")
    reset(runtime("14.29.30133"), required)
    assert(env.InstallVcRuntime() == true and #state.commands == 1)
    assert(state.commands[1].command == "\"D:\\Custom 目录" .. target.redist .. "\" /install /quiet /norestart",
           state.commands[1].command)
    count = count + 1
end

print("VC++ runtime installer (TaijiMPC, Rto): " .. count .. " cases passed")
