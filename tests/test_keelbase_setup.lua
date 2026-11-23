-- Run from the repository root: lua tests/test_keelbase_setup.lua
-- KeelBaseSetup: default selection and upgrades, the install path and service name and their
-- command-line overrides, the check that the KeelHost service belongs to this install path, when
-- the service is stopped, installed and started, the KeelHost config and the KeelBase instance
-- fragment, the VC++ runtime check, the registry, and the uninstaller.
local ROOT = "C:\\Test path\\中文"
local INSTALL = ROOT .. "\\KeelBase"
local HOST = INSTALL .. "\\Host"
local MB = 1024 * 1024
local SIZES = {[150] = 26, [151] = 7, [160] = 15, [161] = 4}
local MARKERS = {
    ["Common.Runtime"] = "Uninstall\\UnInstall.exe",
    ["Common.OpcCore"] = "Redist\\opc\\GBDA_Install_Prereq_x64.msi",
    ["KeelBase.Server"] = "Host\\modules\\KeelBase\\kh_keelbase.dll",
    ["KeelBase.Tools"] = "Tools\\kbased.exe",
}
local ITEM_OF_RES = {[150] = "Common.Runtime", [151] = "Common.OpcCore", [160] = "KeelBase.Server", [161] = "KeelBase.Tools"}
local ALL = {"Common.Runtime", "Common.OpcCore", "KeelBase.Server", "KeelBase.Tools"}
local PRODUCT_KEY = "software\\taijicontrol\\keelbase"
local COMPONENTS_KEY = PRODUCT_KEY .. "\\components"
local SHARED_KEY = "software\\taijicontrol"
local VC_KEY = "software\\microsoft\\visualstudio\\14.0\\vc\\runtimes\\x64"
local UNINSTALL_KEY = "software\\microsoft\\windows\\currentversion\\uninstall\\keelbase"
local ENV_KEY = "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment"

local files, registry, args, commands, ui, unzipped, failed, errors, serviceStates, subvms, freeBytes, missing
local unsafePaths    -- lowercased paths installx.FilePathSecure refuses
local startedState   -- the state a service is in after "service start": a string, or one per second
local sleptMs, startedAtMs = 0, 0

local function lower(path) return path:lower() end

local function addFile(path) files[lower(path)] = path end

local function dirOf(path) return path:match("^(.*)\\[^\\]+$") end

local function exists(path)
    local key = lower(path)
    if files[key] then return true end
    for file in pairs(files) do
        if file:sub(1, #key + 1) == key .. "\\" then return true end
    end
    return false
end

local function setReg(path, name, value)
    registry[lower(path)] = registry[lower(path)] or {}
    registry[lower(path)][name:lower()] = value
end

local function getReg(path, name)
    local values = registry[lower(path)]
    if values == nil then return nil end
    if name == "" then return true end
    return values[name:lower()]
end

local function service(name, state, exe)
    setReg("SYSTEM\\CurrentControlSet\\Services\\" .. name, "ImagePath", "\"" .. exe .. "\" daemon " .. name)
    serviceStates[name] = state
end

HRootKey = {HKEY_CLASSES_ROOT = 0, HKEY_LOCAL_MACHINE = 2}
CSIDL = {COMMON_DESKTOPDIRECTORY = 25, COMMON_STARTMENU = 22}
RunBatchFile = function(path) table.insert(commands, "bat " .. path) return true end
ErrorHint = function(message) table.insert(errors, message) end
installx = {
    PackageInfo = function(res)
        if missing[res] or SIZES[res] == nil then return nil end
        return {size = SIZES[res] * MB, entries = 10}
    end,
    FilePathExists = exists,
    RegGetValue = function(root, path, name) return getReg(path, name) end,
    RegGetDefaultValue = function() return nil end,
    RegSetValue = function(root, path, name, value)
        assert(type(value) == "string", "only strings are written: " .. name)
        table.insert(commands, "reg " .. path .. "|" .. name .. "=" .. value)
        setReg(path, name, value)
        return true
    end,
    RegDeleteValue = function(root, path, name)
        table.insert(commands, "regdel " .. path .. "|" .. name)
        if registry[lower(path)] then registry[lower(path)][name:lower()] = nil end
        return true
    end,
    RegDeleteKey = function(root, path, key)
        table.insert(commands, "regdelkey " .. path .. "\\" .. key)
        local prefix = lower(path .. "\\" .. key)
        for existing in pairs(registry) do
            if existing == prefix or existing:sub(1, #prefix + 1) == prefix .. "\\" then registry[existing] = nil end
        end
        return true
    end,
    LogPrint = function() end,
    SysACP = function() return 936 end,
    SysGetArg = function(name) return args[name] end,
    SysPathAdd = function(path) table.insert(commands, "path " .. path) return true end,
    SetupFailed = function(reason) failed = reason return true end,
    ServiceState = function(name)
        local state = serviceStates[name]
        if type(state) == "table" then
            return state[math.min(#state, (sleptMs - startedAtMs) // 1000 + 1)]
        end
        return state
    end,
    Sleep = function(ms) sleptMs = sleptMs + ms end,
    RunAsAdmin = function() return true end,
    DiskFreeSpace = function() return freeBytes end,
    DuiVisible = function(name, visible)
        if visible == nil then return ui.visible[name] == true end
        ui.visible[name] = visible
        return true
    end,
    DuiText = function(name, text) ui.text[name] = text return true end,
    DuiOptionSelect = function(name, selected, notify)
        if selected == nil then return ui.selected[name] == true end
        assert(notify == false, "Install.lua must not re-enter OnSelChanged: " .. name)
        ui.selected[name] = selected
        return true
    end,
    DuiEnable = function(name, enabled) ui.enabled[name] = enabled return true end,
    DuiAttribute = function() return true end,
    DuiTextColor = function() return true end,
    DuiTabSelect = function(name, index)
        if index == nil then return ui.tab end
        ui.tab = index
        return true
    end,
    DuiSetBkImage = function() return true end,
    DuiWindowPos = function() return true end,
    DuiProgress = function(name, percent) ui.percent = percent return true end,
    DuiMessage = function() return true end,
    ProcessExecute = function(command)
        table.insert(commands, "exec " .. command)
        local verb, name = command:match("\" service (%a+) ([%w%._%-]+)$")
        if verb == "start" then serviceStates[name], startedAtMs = startedState, sleptMs end
        if verb == "stop" then serviceStates[name] = "stopped" end
        return 0
    end,
    ProcessKill = function(name) table.insert(commands, "kill " .. name) return true end,
    FilePathMkdir = function() error("the install path is created by FilePathSecure") end,
    FilePathSecure = function(path, usersCanRead, private)
        table.insert(commands, "secure " .. path .. " users=" .. tostring(usersCanRead)
                     .. (private and " private=" .. table.concat(private, ",") or ""))
        if unsafePaths[lower(path)] then return false, path .. "\\junction", 4395 end
        return true
    end,
    FilePathChoose = function() return nil end,
    FilePathUnzip = function(resourceIDs, directory)
        assert(directory == INSTALL, directory)
        unzipped = resourceIDs
        return true
    end,
    FilePathCopy = function(source, destination, failIfExists)
        if not files[lower(source)] then return false, 2 end
        if failIfExists and files[lower(destination)] then return false, 80 end
        table.insert(commands, "copy " .. source .. " -> " .. destination)
        addFile(destination)
        return true, 0
    end,
    FilePathDelete = function(path)
        table.insert(commands, "delete " .. path)
        local key = lower(path)
        for file in pairs(files) do
            if file == key or file:sub(1, #key + 1) == key .. "\\" then files[file] = nil end
        end
        return true
    end,
    FilePathListFiles = function(directory)
        local list = {}
        for _, path in pairs(files) do
            if lower(dirOf(path) or "") == lower(directory) then table.insert(list, path:match("[^\\]+$")) end
        end
        return list
    end,
    FilePathGetSpecialLocation = function() return "C:\\Users\\Public\\Desktop" end,
    HostVMSubvmNames = function(path)
        local names = subvms[lower(path)]
        if names == false then return nil end
        return names or {}
    end,
}

-- options.installed: items whose marker exists under INSTALL; options.recorded: items this setup
-- recorded for options.recordedPath (default INSTALL); options.services: name -> {state, exe};
-- options.sharedRoot: Software\TaijiControl\InstallPath (default ROOT, false for none).
local function reset(options)
    options = options or {}
    files, registry, args, commands = {}, {}, options.args or {}, {}
    unzipped, failed, errors, serviceStates, subvms, missing = nil, nil, {}, {}, {}, {}
    unsafePaths, startedState = {}, options.startedState or "running"
    for _, path in ipairs(options.unsafe or {}) do unsafePaths[lower(path)] = true end
    ui = {visible = {}, text = {}, selected = {}, enabled = {}, tab = 0}
    freeBytes = 100 * 1024 * MB
    for _, key in ipairs(options.installed or {}) do addFile(INSTALL .. "\\" .. MARKERS[key]) end
    for _, res in ipairs(options.missing or {}) do missing[res] = true end
    if options.sharedRoot ~= false then setReg(SHARED_KEY, "InstallPath", options.sharedRoot or ROOT) end
    if options.recorded then
        setReg(PRODUCT_KEY, "InstallPath", options.recordedPath or INSTALL)
        for _, key in ipairs(options.recorded) do setReg(COMPONENTS_KEY, key, "3.0.0.0") end
    end
    if options.serviceName then setReg(PRODUCT_KEY, "ServiceName", options.serviceName) end
    for name, spec in pairs(options.services or {}) do service(name, spec[1], spec[2]) end
    if options.vcRuntime then
        setReg(VC_KEY, "Installed", 1)
        local major, minor, build = options.vcRuntime:match("(%d+)%.(%d+)%.(%d+)")
        setReg(VC_KEY, "Major", tonumber(major))
        setReg(VC_KEY, "Minor", tonumber(minor))
        setReg(VC_KEY, "Bld", tonumber(build))
    end
end

local function install(options)
    reset(options)
    assert(loadfile("projects/KeelBaseSetup/Install/Install.lua"))()
    OnInitialize()
end

local count = 0
local function check(condition, label)
    count = count + 1
    assert(condition, "case " .. count .. ": " .. label)
end

local function selection()
    local list = {}
    for _, key in ipairs(ALL) do
        if ComponentSelected(key) then table.insert(list, key) end
    end
    return table.concat(list, ",")
end

-- Index of the first command containing text, or nil.
local function commandAt(text)
    for i, command in ipairs(commands) do
        if command:find(text, 1, true) then return i end
    end
end

local SERVICE_COMMAND = "KeelHost.exe\" service"

-- Extracts what StartSetup chose and runs PostSetup as the framework does after extraction: the
-- archives' files appear under INSTALL.
local function runSetup()
    commands = {}
    StartSetup()
    if unzipped == nil then return false end
    for _, res in ipairs(unzipped) do
        addFile(INSTALL .. "\\" .. MARKERS[ITEM_OF_RES[res]])
        if res == 160 then
            addFile(HOST .. "\\KeelHost.exe")
            addFile(HOST .. "\\keelhost.default.xml")
            addFile(HOST .. "\\keelhost.d\\020-kbase.xml.template")
            subvms[lower(HOST .. "\\keelhost.d\\020-kbase.xml.template")] = {"kbase01"}
        end
    end
    return PostSetup()
end

----------------------------------------------------------------------------------------------------
-- Selection

-- First install: everything selected, the biggest archive first, KeelBase\ under the shared root.
install()
check(selection() == table.concat(ALL, ","), "first install selects all: " .. selection())
check(ui.text["pathedit"] == INSTALL, "install path under the shared root: " .. tostring(ui.text["pathedit"]))
check(ui.enabled["item_Common_Runtime"] == false and ui.selected["item_Common_Runtime"] == true, "runtime locked")
local plan = ComponentPlan()
check(#plan == 4 and plan[1].res == 150 and plan[#plan].res == 161, "biggest first")
OnSelChanged("grp_KeelBase", false)
check(selection() == "Common.Runtime,Common.OpcCore", "group off: " .. selection())
OnSelChanged("item_KeelBase_Server", true)
check(ComponentGroupState("KeelBase") == "partial", "partial group")

-- Upgrade: what this setup installed last time.
install({installed = {"Common.Runtime", "KeelBase.Server"}, recorded = {"Common.Runtime", "KeelBase.Server"}})
check(selection() == "Common.Runtime,KeelBase.Server", "upgrade keeps the recorded set: " .. selection())
-- The record of another install path does not count: selecting that path below is a first install.
install({installed = {"KeelBase.Server"}, recorded = {"Common.Runtime"}, recordedPath = "D:\\Elsewhere",
         args = {path = INSTALL}})
check(selection() == table.concat(ALL, ","), "other path's record ignored: " .. selection())

-- /components picks exactly those besides the required ones.
install({args = {components = "KeelBase.Tools"}})
check(selection() == "Common.Runtime,KeelBase.Tools", "/components: " .. selection())
install({args = {components = "KeelBase.Nope", s = true}})
runSetup()
check(failed ~= nil and failed:find("KeelBase.Nope", 1, true) ~= nil and unzipped == nil, "unknown component fails a silent install")
-- An archive this installer lacks hides the item.
install({missing = {161}})
check(not ComponentSelected("KeelBase.Tools") and ui.visible["item_KeelBase_Tools"] == false, "missing archive hidden")

----------------------------------------------------------------------------------------------------
-- Install path and service name

install({sharedRoot = false})
check(ui.text["pathedit"] == "C:\\TaijiControl\\KeelBase", "default path without any record")
install({args = {path = "D:\\KB\\"}})
check(ui.text["pathedit"] == "D:\\KB", "/path= wins, trailing backslash dropped: " .. ui.text["pathedit"])
install({recorded = {"Common.Runtime"}, recordedPath = "E:\\KeelBase root"})
check(ui.text["pathedit"] == "E:\\KeelBase root", "recorded KeelBase path wins over the shared root")
install({args = {path = "\\\\server\\share", s = true}})
runSetup()
check(failed ~= nil and failed:find("server", 1, true) ~= nil and unzipped == nil, "UNC path refused")
install({args = {service = "bad name", s = true}})
runSetup()
check(failed ~= nil and unzipped == nil, "bad service name refused")

----------------------------------------------------------------------------------------------------
-- The KeelHost service

-- A KeelBase service of another install path is neither stopped nor taken.
install({args = {s = true}, services = {KeelBase = {"running", "D:\\Other\\KeelBase\\Host\\KeelHost.exe"}}})
check(runSetup() == false and unzipped == nil, "foreign service blocks the install")
check(failed:find("D:\\Other\\KeelBase\\Host\\KeelHost.exe", 1, true) ~= nil, "message names the other exe: " .. failed)
check(commandAt("service stop") == nil, "foreign service not stopped")
-- /service= picks another name next to it.
install({args = {s = true, service = "KeelBase2"}, services = {KeelBase = {"running", "D:\\Other\\KeelBase\\Host\\KeelHost.exe"}}})
check(runSetup() == true, "own service name installs")
check(commandAt("service install KeelBase2") and commandAt("service start KeelBase2"), "own service installed and started")
check(commandAt("service stop") == nil, "the other KeelBase service untouched")
check(getReg(PRODUCT_KEY, "ServiceName") == "KeelBase2", "service name recorded")

-- First install next to TaijiMPC6's HostVM service, which this setup does not care about:
-- KeelBase's own service is created, then started; config seeded, fragment created.
install({services = {HostVM = {"running", ROOT .. "\\HostVM\\HostVM.exe"}}})
check(runSetup() == true, "first install completes")
local installAt, startAt = commandAt("service install KeelBase"), commandAt("service start KeelBase")
check(installAt and startAt and installAt < startAt, "service installed, then started")
check(commandAt(HOST .. "\\KeelHost.exe\" service install KeelBase"), "service runs KeelBase's own KeelHost")
check(commandAt("HostVM") == nil, "nothing of TaijiMPC6's HostVM touched")
check(commandAt("copy " .. HOST .. "\\keelhost.default.xml -> " .. HOST .. "\\keelhost.xml"), "keelhost.xml seeded")
check(commandAt("copy " .. HOST .. "\\keelhost.d\\020-kbase.xml.template -> " .. HOST .. "\\keelhost.d\\020-kbase.xml"),
      "instance fragment created")
check(commandAt("service stop") == nil, "nothing to stop")
check(commandAt(INSTALL .. "\\Redist\\opc\\GBDA_Install_Prereq_x64.msi") and commandAt("GBDA_Install_Prereq_x86.msi"),
      "OPC core components installed")
check(commandAt(INSTALL .. "\\Redist\\vc_redist.x64.exe"), "VC++ runtime installed when missing")
check(ui.percent == 100, "progress at 100")

-- Upgrade with the service running: stopped before extraction, started after, not recreated.
install({installed = {"Common.Runtime", "KeelBase.Server"}, recorded = {"Common.Runtime", "KeelBase.Server"},
         services = {KeelBase = {"running", HOST .. "\\KeelHost.exe"}}})
addFile(HOST .. "\\keelhost.xml")
addFile(HOST .. "\\keelhost.d\\020-kbase.xml")
check(runSetup() == true, "upgrade completes")
check(commandAt("service stop KeelBase") and commandAt("secure ") < commandAt("service stop KeelBase"),
      "stopped after securing, before extraction: " .. tostring(commands[1]))
check(commandAt("service install") == nil and commandAt("service start KeelBase"), "started again, not recreated")
check(commandAt("copy") == nil, "site config and fragment kept")
-- A stopped service is not stopped again, and starts with the upgraded files.
install({installed = {"Common.Runtime", "KeelBase.Server"}, recorded = {"Common.Runtime", "KeelBase.Server"},
         services = {KeelBase = {"stopped", HOST .. "\\KeelHost.exe"}}})
addFile(HOST .. "\\keelhost.xml")
check(runSetup() == true and commandAt("service stop") == nil and commandAt("service start KeelBase"), "stopped service started")
-- The tools alone do not touch the service.
install({args = {components = "KeelBase.Tools"}, installed = {"KeelBase.Server"},
         services = {KeelBase = {"running", HOST .. "\\KeelHost.exe"}}})
check(runSetup() == true and commandAt(SERVICE_COMMAND) == nil, "tools leave the service alone")
check(ui.visible["pathbtn"] ~= false, "PATH option offered with the tools")
_FinishInstall()
check(commandAt("path ") == nil, "PATH unchanged unless asked")
ui.selected["pathbtn"] = true
_FinishInstall()
check(commandAt("path " .. INSTALL .. "\\Tools"), "Tools added to PATH when asked")
install({args = {components = "KeelBase.Server"}})
runSetup()
check(ui.visible["pathbtn"] == false, "no PATH option without the tools")

----------------------------------------------------------------------------------------------------
-- The install path holds a LocalSystem service: only SYSTEM and Administrators may change it

-- Secured before anything else happens. Data\ is a private subdirectory of that call, so Users
-- cannot read it at any point, not even between two calls.
local SECURE_INSTALL = "secure " .. INSTALL .. " users=true private=Data"
install({services = {KeelBase = {"running", HOST .. "\\KeelHost.exe"}}, installed = {"KeelBase.Server"},
         recorded = {"Common.Runtime", "KeelBase.Server"}})
addFile(INSTALL .. "\\Data\\kbase01\\kbase_server.json")
runSetup()
check(commands[1] == SECURE_INSTALL, "install path secured first, Data\\ private: " .. tostring(commands[1]))
check(commandAt("\\Data users=") == nil, "an existing Data\\ needs no second call")
-- A first install creates Data\ for the database with a call of its own.
install()
runSetup()
check(commands[1] == SECURE_INSTALL and commands[2] == "secure " .. INSTALL .. "\\Data users=false",
      "Data\\ created without Users: " .. tostring(commands[2]))
-- Tools alone: no Data\ is created; an existing one is still private.
install({args = {components = "KeelBase.Tools"}})
runSetup()
check(commands[1] == SECURE_INSTALL and commandAt("\\Data users=") == nil, "no Data\\ for the tools")
-- A path FilePathSecure refuses (a junction, another user's directory) stops everything.
install({args = {s = true}, unsafe = {INSTALL}, services = {KeelBase = {"running", HOST .. "\\KeelHost.exe"}}})
check(runSetup() == false and unzipped == nil, "unsafe install path refused")
check(failed:find(INSTALL .. "\\junction", 1, true) ~= nil and failed:find("4395", 1, true) ~= nil, "message names it: " .. failed)
check(commandAt("service stop") == nil, "service not stopped for a refused path")

-- A service that does not come up fails the installation instead of reporting success.
install({startedState = "stopped"})
check(runSetup() == false, "service not running fails PostSetup")
check(errors[#errors]:find("KeelBase", 1, true) ~= nil and errors[#errors]:find(HOST .. "\\log", 1, true) ~= nil,
      "message names the service and its logs: " .. tostring(errors[#errors]))
install({startedState = "start_pending"})
check(runSetup() == true, "a service still starting is not a failure")
-- KeelHost reports running before it opens its ports: a port in use stops it a moment later.
install({startedState = {"running", "running", "stopped"}})
check(runSetup() == false and errors[#errors]:find("stopped", 1, true) ~= nil, "service that stops after starting fails")
install({startedState = {"running", "running", "running", "running", "running", "running", "running"}})
local before = sleptMs
check(runSetup() == true and sleptMs - before >= 5000, "a service that stays up is watched for 5 s")

----------------------------------------------------------------------------------------------------
-- KeelHost config and the instance fragment

-- hostvm.xml is a main config too: no keelhost.xml next to it (KeelHost refuses both).
install()
addFile(HOST .. "\\hostvm.xml")
check(runSetup() == true and commandAt("keelhost.xml") == nil, "hostvm.xml kept, no keelhost.xml")
-- The site declared kbase01 in keelhost.xml already: no fragment, no error.
install()
addFile(HOST .. "\\keelhost.xml")
subvms[lower(HOST .. "\\keelhost.xml")] = {"kbase01"}
check(runSetup() == true and commandAt("020-kbase.xml") == nil, "declared instance: no fragment")
-- ... or in another fragment.
install()
addFile(HOST .. "\\keelhost.xml")
addFile(HOST .. "\\keelhost.d\\010-site.xml")
subvms[lower(HOST .. "\\keelhost.d\\010-site.xml")] = {"kbase01"}
check(runSetup() == true and commandAt("020-kbase.xml") == nil, "instance in another fragment: no fragment")
-- An unreadable config stops the install before any service or registry change.
install()
addFile(HOST .. "\\keelhost.xml")
subvms[lower(HOST .. "\\keelhost.xml")] = false
check(runSetup() == false, "unreadable keelhost.xml fails")
check(errors[#errors]:find("keelhost.xml", 1, true) ~= nil and commandAt("reg ") == nil and commandAt(SERVICE_COMMAND) == nil,
      "nothing changed after the failure")
-- A template that partly clashes with the site config fails.
install()
addFile(HOST .. "\\keelhost.xml")
subvms[lower(HOST .. "\\keelhost.xml")] = {"kbase02"}
StartSetup()
addFile(HOST .. "\\keelhost.d\\020-kbase.xml.template")
subvms[lower(HOST .. "\\keelhost.d\\020-kbase.xml.template")] = {"kbase01", "kbase02"}
check(PostSetup() == false and errors[#errors]:find("kbase02", 1, true) ~= nil, "partial clash fails: " .. tostring(errors[#errors]))

----------------------------------------------------------------------------------------------------
-- Runtimes, space and registry

install({vcRuntime = "14.52.37029"})
runSetup()
check(commandAt("vc_redist.x64.exe") == nil, "same or newer VC++ runtime kept")
install({vcRuntime = "14.44.35211"})
runSetup()
check(commandAt("vc_redist.x64.exe"), "older VC++ runtime upgraded")
check(VersionOlderThan("14.9.1", "14.10.0") and not VersionOlderThan("v14.52.37029", "14.52.37025"), "numeric version order")

-- The database's first data files need room too.
install({args = {s = true}})
freeBytes = 1024 * MB
check(runSetup() == false and failed ~= nil and unzipped == nil, "not enough space fails")

-- Only KeelBase's own keys: the shared root is read for the default path, never written.
install()
runSetup()
check(commandAt("reg Software\\TaijiControl|") == nil and getReg(SHARED_KEY, "InstallPath") == ROOT, "shared root not written")
check(getReg(PRODUCT_KEY, "InstallPath") == INSTALL and getReg(PRODUCT_KEY, "ServiceName") == "KeelBase", "KeelBase keys")
check(getReg(UNINSTALL_KEY, "UninstallString") == "\"" .. INSTALL .. "\\Uninstall\\UnInstall.exe\"", "uninstall entry quoted")
for _, key in ipairs(ALL) do
    check(getReg(COMPONENTS_KEY, key) ~= nil, "component recorded: " .. key)
end
install({sharedRoot = false})
INSTALL, HOST = "C:\\TaijiControl\\KeelBase", "C:\\TaijiControl\\KeelBase\\Host"
runSetup()
check(getReg(SHARED_KEY, "InstallPath") == nil, "shared root not created either")
INSTALL, HOST = ROOT .. "\\KeelBase", ROOT .. "\\KeelBase\\Host"

----------------------------------------------------------------------------------------------------
-- Uninstall

local function uninstall(options)
    reset(options)
    addFile(HOST .. "\\KeelHost.exe")
    addFile(HOST .. "\\keelhost.xml")
    addFile(HOST .. "\\keelhost.d\\020-kbase.xml")
    addFile(INSTALL .. "\\Redist\\vc_redist.x64.exe")
    addFile(INSTALL .. "\\Data\\kbase01\\data\\container_0.raw")
    setReg(ENV_KEY, "Path", "C:\\Windows;" .. INSTALL .. "\\Tools\\;C:\\Tools")
    assert(loadfile("projects/KeelBaseSetup/UnInstall/res/UnInstall.lua"))()
    OnInitialize()
    commands = {}
    PreSetup()
end

local EVERYTHING = {"Common.Runtime", "Common.OpcCore", "KeelBase.Server", "KeelBase.Tools"}

uninstall({installed = EVERYTHING, recorded = EVERYTHING, services = {KeelBase = {"running", HOST .. "\\KeelHost.exe"}},
           sharedRoot = ROOT})
local stopAt, removeAt = commandAt("service stop KeelBase"), commandAt("service remove KeelBase")
check(stopAt and removeAt and stopAt < removeAt, "own service stopped and removed")
check(not exists(HOST) and not exists(INSTALL .. "\\Tools") and not exists(INSTALL .. "\\Redist"), "program directories deleted")
check(exists(INSTALL .. "\\Data\\kbase01\\data\\container_0.raw"), "instance data kept")
check(registry[PRODUCT_KEY] == nil and registry[COMPONENTS_KEY] == nil and registry[UNINSTALL_KEY] == nil, "registry entries removed")
check(getReg(SHARED_KEY, "InstallPath") == ROOT and commandAt("regdel ") == nil, "shared root untouched")
check(getReg(ENV_KEY, "Path") == "C:\\Windows;C:\\Tools", "PATH entry removed: " .. tostring(getReg(ENV_KEY, "Path")))
-- A stopped service is only removed.
uninstall({installed = EVERYTHING, recorded = EVERYTHING, services = {KeelBase = {"stopped", HOST .. "\\KeelHost.exe"}}})
check(commandAt("service stop") == nil and commandAt("service remove KeelBase"), "stopped service removed")
-- A service of that name that runs another installation's KeelHost is not touched.
uninstall({installed = EVERYTHING, recorded = EVERYTHING, services = {KeelBase = {"running", "D:\\Other\\KeelBase\\Host\\KeelHost.exe"}}})
check(commandAt(SERVICE_COMMAND) == nil and not exists(HOST), "other installation's service untouched")
-- The recorded service name is used; TaijiMPC6's HostVM service is never touched.
uninstall({installed = EVERYTHING, recorded = EVERYTHING, serviceName = "KeelBase2",
           services = {KeelBase2 = {"running", HOST .. "\\KeelHost.exe"}, HostVM = {"running", ROOT .. "\\HostVM\\HostVM.exe"}}})
check(commandAt("service stop KeelBase2") and commandAt("service remove KeelBase2") and commandAt("HostVM") == nil,
      "recorded service name used, HostVM untouched")
-- PATH without the entry is not rewritten.
uninstall({installed = EVERYTHING, recorded = EVERYTHING})
setReg(ENV_KEY, "Path", "C:\\Windows")
commands = {}
PreSetup()
check(commandAt("reg " .. ENV_KEY) == nil, "PATH not rewritten when it has no entry")

print("KeelBaseSetup: " .. count .. " cases passed")
