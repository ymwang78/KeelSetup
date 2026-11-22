-- Run from the repository root: lua tests/test_keelbase_setup.lua
-- KeelBaseSetup: default selection and upgrades, the install path and service name and their
-- command-line overrides, the check that the KeelHost service belongs to this install path, which
-- services are stopped and started, the KeelHost config and the KeelBase instance fragment, the VC++
-- runtime check, the registry, and the uninstaller with KeelHost of its own or shared with TaijiMPC6.
local ROOT = "C:\\Test path\\中文"
local HOST = ROOT .. "\\HostVM"
local MB = 1024 * 1024
local SIZES = {[150] = 26, [151] = 7, [160] = 9, [161] = 6, [162] = 4}
local MARKERS = {
    ["Common.Runtime"] = "KeelBase\\UnInstall.exe",
    ["Common.OpcCore"] = "Common\\opc\\GBDA_Install_Prereq_x64.msi",
    ["KeelBase.Host"] = "HostVM\\HostVM.exe",
    ["KeelBase.Server"] = "HostVM\\modules\\KeelBase\\kh_keelbase.dll",
    ["KeelBase.Tools"] = "KeelBase\\kbased.exe",
}
local ALL = {"Common.Runtime", "Common.OpcCore", "KeelBase.Host", "KeelBase.Server", "KeelBase.Tools"}
local PRODUCT_KEY = "software\\taijicontrol\\keelbase"
local COMPONENTS_KEY = PRODUCT_KEY .. "\\components"
local SHARED_KEY = "software\\taijicontrol"
local VC_KEY = "software\\microsoft\\visualstudio\\14.0\\vc\\runtimes\\x64"

local files, registry, args, commands, ui, unzipped, failed, errors, serviceStates, subvms, freeBytes, missing

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
        assert(type(value) == "string", "RegSetValue of a non-string writes garbage: " .. name)
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
    ServiceState = function(name) return serviceStates[name] end,
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
    ProcessExecute = function(command) table.insert(commands, "exec " .. command) return 0 end,
    ProcessKill = function(name) table.insert(commands, "kill " .. name) return true end,
    FilePathMkdir = function() return true end,
    FilePathChoose = function() return nil end,
    FilePathUnzip = function(resourceIDs, directory)
        assert(directory == ROOT, directory)
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
        for key, path in pairs(files) do
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

-- options.installed: items whose marker exists under ROOT; options.recorded: items this setup
-- recorded for ROOT (an earlier KeelBase install); options.services: name -> {state, exe}.
local function reset(options)
    options = options or {}
    files, registry, args, commands = {}, {}, options.args or {}, {}
    unzipped, failed, errors, serviceStates, subvms, missing = nil, nil, {}, {}, {}, {}
    ui = {visible = {}, text = {}, selected = {}, enabled = {}, tab = 0}
    freeBytes = 100 * 1024 * MB
    for _, key in ipairs(options.installed or {}) do addFile(ROOT .. "\\" .. MARKERS[key]) end
    for _, res in ipairs(options.missing or {}) do missing[res] = true end
    if options.sharedRoot ~= false then setReg(SHARED_KEY, "InstallPath", options.sharedRoot or ROOT) end
    if options.recorded then
        setReg(PRODUCT_KEY, "InstallPath", options.recordedRoot or ROOT)
        for _, key in ipairs(options.recorded) do setReg(COMPONENTS_KEY, key, "3.0.0.0") end
    end
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

-- Extracts what StartSetup chose and runs PostSetup as the framework does after extraction: the
-- archives' files appear under ROOT.
local function runSetup()
    commands = {}
    StartSetup()
    if unzipped == nil then return false end
    for _, res in ipairs(unzipped) do
        for key, marker in pairs(MARKERS) do
            local item = ({[150] = "Common.Runtime", [151] = "Common.OpcCore", [160] = "KeelBase.Host",
                           [161] = "KeelBase.Server", [162] = "KeelBase.Tools"})[res]
            if item == key then addFile(ROOT .. "\\" .. marker) end
        end
        if res == 160 then addFile(HOST .. "\\hostvm.default.xml") end
        if res == 161 then
            addFile(HOST .. "\\keelhost.d\\020-kbase.xml.template")
            subvms[lower(HOST .. "\\keelhost.d\\020-kbase.xml.template")] = {"kbase01"}
        end
    end
    return PostSetup()
end

----------------------------------------------------------------------------------------------------
-- Selection

-- First install: everything selected, the biggest archive first, the shared root as install path.
install()
check(selection() == table.concat(ALL, ","), "first install selects all: " .. selection())
check(ui.text["pathedit"] == ROOT, "install path from the shared root: " .. tostring(ui.text["pathedit"]))
check(ui.enabled["item_Common_Runtime"] == false and ui.selected["item_Common_Runtime"] == true, "runtime locked")
local plan = ComponentPlan()
check(#plan == 5 and plan[1].res == 150 and plan[#plan].res == 162, "biggest first")
-- Deselecting the host also deselects the database, which needs it.
OnSelChanged("item_KeelBase_Host", false)
check(not ComponentSelected("KeelBase.Server") and ComponentSelected("KeelBase.Tools"), "server follows host")
check(ui.text["comphintlab"]:find("KeelBase 时序数据库", 1, true) ~= nil, "hint names the database: " .. ui.text["comphintlab"])
OnSelChanged("item_KeelBase_Server", true)
check(ComponentSelected("KeelBase.Host"), "selecting the database selects the host")

-- Another product's KeelHost in this root is not an upgrade of KeelBase: the host is selected as
-- well (the module is built against the KeelHost of this package).
install({installed = {"KeelBase.Host", "Common.OpcCore"}})
check(selection() == table.concat(ALL, ","), "first install over TaijiMPC6 selects all: " .. selection())

-- Upgrade: what this setup installed last time, the host kept as it is.
install({installed = {"Common.Runtime", "KeelBase.Host", "KeelBase.Server"},
         recorded = {"Common.Runtime", "KeelBase.Server"}})
check(selection() == "Common.Runtime,KeelBase.Server", "upgrade keeps the recorded set: " .. selection())
-- The record of another install path does not count.
install({installed = {"KeelBase.Host"}, recorded = {"Common.Runtime", "KeelBase.Server"},
         recordedRoot = "D:\\Elsewhere"})
check(selection() == "Common.Runtime,KeelBase.Host,KeelBase.Server" or
      selection() == table.concat(ALL, ","), "other root's record ignored: " .. selection())

-- /components picks exactly those, plus what they need.
install({args = {components = "KeelBase.Server"}})
check(selection() == "Common.Runtime,KeelBase.Host,KeelBase.Server", "/components: " .. selection())
install({args = {components = "KeelBase.Nope", s = true}})
runSetup()
check(failed ~= nil and failed:find("KeelBase.Nope", 1, true) ~= nil and unzipped == nil, "unknown component fails a silent install")
-- An archive this installer lacks hides the item.
install({missing = {162}})
check(not ComponentSelected("KeelBase.Tools") and ui.visible["item_KeelBase_Tools"] == false, "missing archive hidden")

----------------------------------------------------------------------------------------------------
-- Install path and service name

install({sharedRoot = false})
check(ui.text["pathedit"] == "C:\\TaijiControl", "default root without any record")
install({args = {path = "D:\\KB\\"}})
check(ui.text["pathedit"] == "D:\\KB", "/path= wins, trailing backslash dropped: " .. ui.text["pathedit"])
install({recorded = {"Common.Runtime"}, recordedRoot = "E:\\KeelBase root"})
check(ui.text["pathedit"] == "E:\\KeelBase root", "recorded KeelBase root wins over the shared root")
install({args = {path = "\\\\server\\share", s = true}})
runSetup()
check(failed ~= nil and failed:find("server", 1, true) ~= nil and unzipped == nil, "UNC path refused")
install({args = {service = "bad name", s = true}})
runSetup()
check(failed ~= nil and unzipped == nil, "bad service name refused")

----------------------------------------------------------------------------------------------------
-- The KeelHost service

-- A service of that name that runs another installation's KeelHost is neither stopped nor taken.
install({args = {s = true}, services = {HostVM = {"running", "C:\\TaijiControl\\HostVM\\HostVM.exe"}}})
check(runSetup() == false and unzipped == nil, "foreign service blocks the install")
check(failed:find("C:\\TaijiControl\\HostVM\\HostVM.exe", 1, true) ~= nil, "message names the other exe: " .. failed)
check(commandAt("service stop") == nil, "foreign service not stopped")
-- /service= picks another name next to it.
install({args = {s = true, service = "KeelBaseTest"},
         services = {HostVM = {"running", "C:\\TaijiControl\\HostVM\\HostVM.exe"}}})
check(runSetup() == true, "own service name installs")
check(commandAt("service install KeelBaseTest") and commandAt("service start KeelBaseTest"), "own service installed and started")
check(commandAt(" HostVM") == nil or not commandAt("service stop HostVM"), "HostVM untouched")
check(getReg(PRODUCT_KEY, "ServiceName") == "KeelBaseTest", "service name recorded")

-- First install, no service: created, then started; config seeded, fragment created.
install()
check(runSetup() == true, "first install completes")
local installAt, startAt = commandAt("service install HostVM"), commandAt("service start HostVM")
check(installAt and startAt and installAt < startAt, "service installed, then started")
check(commandAt("copy " .. HOST .. "\\hostvm.default.xml -> " .. HOST .. "\\hostvm.xml"), "hostvm.xml seeded")
check(commandAt("copy " .. HOST .. "\\keelhost.d\\020-kbase.xml.template -> " .. HOST .. "\\keelhost.d\\020-kbase.xml"),
      "instance fragment created")
check(commandAt("service stop") == nil, "nothing to stop")
check(commandAt("GBDA_Install_Prereq_x64.msi") and commandAt("GBDA_Install_Prereq_x86.msi"), "OPC core components installed")
check(commandAt("vc_redist.x64.exe"), "VC++ runtime installed when missing")
check(ui.percent == 100, "progress at 100")

-- Upgrade with the service running here: stopped before extraction, started after, not recreated.
install({installed = {"Common.Runtime", "KeelBase.Host", "KeelBase.Server"},
         recorded = {"Common.Runtime", "KeelBase.Host", "KeelBase.Server"},
         services = {HostVM = {"running", HOST .. "\\HostVM.exe"}}})
addFile(HOST .. "\\hostvm.xml")
addFile(HOST .. "\\keelhost.d\\020-kbase.xml")
check(runSetup() == true, "upgrade completes")
check(commandAt("service stop HostVM") == 1, "stopped first: " .. tostring(commands[1]))
check(commandAt("service install") == nil and commandAt("service start HostVM"), "started again, not recreated")
check(commandAt("copy") == nil, "site config and fragment kept")
-- An administrator's stopped service: the database alone is upgraded and it stays stopped.
install({args = {components = "KeelBase.Server"}, installed = {"Common.Runtime", "KeelBase.Host", "KeelBase.Server"},
         recorded = {"Common.Runtime", "KeelBase.Server"}, services = {HostVM = {"stopped", HOST .. "\\HostVM.exe"}}})
addFile(HOST .. "\\hostvm.xml")
check(runSetup() == true and commandAt("\" service") == nil, "stopped service left stopped")
-- The tools alone do not touch the service.
install({args = {components = "KeelBase.Tools"}, installed = {"KeelBase.Host", "KeelBase.Server"},
         services = {HostVM = {"running", HOST .. "\\HostVM.exe"}}})
check(runSetup() == true and commandAt("\" service") == nil, "tools leave the service alone")
check(ui.visible["pathbtn"] ~= false, "PATH option offered with the tools")
_FinishInstall()
check(commandAt("path " .. ROOT .. "\\KeelBase") == nil, "PATH unchanged unless asked")
ui.selected["pathbtn"] = true
_FinishInstall()
check(commandAt("path " .. ROOT .. "\\KeelBase"), "PATH entry added when asked")
install({args = {components = "KeelBase.Server"}})
runSetup()
check(ui.visible["pathbtn"] == false, "no PATH option without the tools")

----------------------------------------------------------------------------------------------------
-- KeelHost config and the instance fragment

-- keelhost.xml is the site's main config: no hostvm.xml next to it (KeelHost refuses both).
install()
addFile(HOST .. "\\keelhost.xml")
check(runSetup() == true and commandAt("hostvm.xml") == nil, "keelhost.xml kept, no hostvm.xml")
-- The site declared kbase01 in hostvm.xml already: no fragment, no error.
install()
addFile(HOST .. "\\hostvm.xml")
subvms[lower(HOST .. "\\hostvm.xml")] = {"zmis", "kbase01"}
check(runSetup() == true and commandAt("020-kbase.xml") == nil, "declared instance: no fragment")
-- ... or in a hostvm.d fragment of another product.
install()
addFile(HOST .. "\\hostvm.xml")
addFile(HOST .. "\\hostvm.d\\100-tjsysid.xml")
addFile(HOST .. "\\hostvm.d\\150-kb.xml")
subvms[lower(HOST .. "\\hostvm.d\\150-kb.xml")] = {"kbase01"}
check(runSetup() == true and commandAt("020-kbase.xml") == nil, "instance in hostvm.d: no fragment")
-- An unreadable config stops the install before any service or registry change.
install()
addFile(HOST .. "\\hostvm.xml")
subvms[lower(HOST .. "\\hostvm.xml")] = false
check(runSetup() == false, "unreadable hostvm.xml fails")
check(errors[#errors]:find("hostvm.xml", 1, true) ~= nil and commandAt("reg ") == nil and commandAt("service install") == nil,
      "nothing changed after the failure")
-- A template that partly clashes with the site config fails.
install()
addFile(HOST .. "\\hostvm.xml")
subvms[lower(HOST .. "\\hostvm.xml")] = {"kbase02"}
StartSetup()
addFile(HOST .. "\\HostVM.exe")
addFile(HOST .. "\\keelhost.d\\020-kbase.xml.template")
subvms[lower(HOST .. "\\keelhost.d\\020-kbase.xml.template")] = {"kbase01", "kbase02"}
check(PostSetup() == false and errors[#errors]:find("kbase02", 1, true) ~= nil, "partial clash fails: " .. tostring(errors[#errors]))

----------------------------------------------------------------------------------------------------
-- Runtimes, space and registry

install({vcRuntime = "14.52.37029"})
runSetup()
check(commandAt("vc_redist.x64.exe") == nil, "newer VC++ runtime kept")
install({vcRuntime = "14.44.35211"})
runSetup()
check(commandAt("vc_redist.x64.exe"), "older VC++ runtime upgraded")
check(VersionOlderThan("14.9.1", "14.10.0") and not VersionOlderThan("v14.52.37029", "14.52.37025"), "numeric version order")

-- The database's first data files need room too.
install({args = {s = true}})
freeBytes = 1024 * MB
check(runSetup() == false and failed ~= nil and unzipped == nil, "not enough space fails")

-- The shared root of another product stays; KeelBase records its own.
install({args = {path = "D:\\KB"}, sharedRoot = "C:\\TaijiControl"})
ROOT, HOST = "D:\\KB", "D:\\KB\\HostVM"
runSetup()
check(getReg(SHARED_KEY, "InstallPath") == "C:\\TaijiControl" and commandAt("reg Software\\TaijiControl|InstallPath") == nil,
      "other product's root kept")
check(getReg(PRODUCT_KEY, "InstallPath") == "D:\\KB", "KeelBase root recorded")
check(getReg("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\KeelBase", "UninstallString") == "\"D:\\KB\\KeelBase\\UnInstall.exe\"",
      "uninstall entry quoted")
ROOT, HOST = "C:\\Test path\\中文", "C:\\Test path\\中文\\HostVM"
install({sharedRoot = false})
ROOT, HOST = "C:\\TaijiControl", "C:\\TaijiControl\\HostVM"
runSetup()
check(getReg(SHARED_KEY, "InstallPath") == "C:\\TaijiControl" and getReg("Software\\WOW6432Node\\TaijiControl", "InstallPath") == "C:\\TaijiControl",
      "shared root written when nobody set it")
for _, key in ipairs(ALL) do
    check(getReg(COMPONENTS_KEY, key) ~= nil, "component recorded: " .. key)
end
ROOT, HOST = "C:\\Test path\\中文", "C:\\Test path\\中文\\HostVM"

----------------------------------------------------------------------------------------------------
-- Uninstall

local function uninstall(options)
    reset(options)
    for _, key in ipairs(options.installed or {}) do addFile(ROOT .. "\\" .. MARKERS[key]) end
    addFile(HOST .. "\\hostvm.xml")
    addFile(HOST .. "\\keelhost.d\\020-kbase.xml")
    addFile(HOST .. "\\keelhost.d\\020-kbase.xml.template")
    addFile(ROOT .. "\\Common\\vcredist\\vc_redist.x64.exe")
    setReg("SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", "Path",
           "C:\\Windows;" .. ROOT .. "\\KeelBase\\;C:\\Tools")
    if options.taijimpc6 then
        setReg("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\TaiJiMPC6", "DisplayName", "Tai-Ji MPC6")
    end
    setReg(PRODUCT_KEY, "ServiceName", options.serviceName or "HostVM")
    assert(loadfile("projects/KeelBaseSetup/UnInstall/res/UnInstall.lua"))()
    OnInitialize()
    commands = {}
    PreSetup()
end

local EVERYTHING = {"Common.Runtime", "Common.OpcCore", "KeelBase.Host", "KeelBase.Server", "KeelBase.Tools"}

-- KeelHost of its own: the service goes, and HostVM\ with it; the site's instance data is not there.
uninstall({installed = EVERYTHING, recorded = EVERYTHING, services = {HostVM = {"running", HOST .. "\\HostVM.exe"}}})
local stopAt, removeAt = commandAt("service stop HostVM"), commandAt("service remove HostVM")
check(stopAt and removeAt and stopAt < removeAt, "own service stopped and removed")
check(commandAt("delete " .. HOST .. "\\modules\\KeelBase"), "module deleted")
check(not exists(HOST), "HostVM deleted")
check(commandAt("service start") == nil, "not started again")
check(not exists(ROOT .. "\\Common\\vcredist") and not exists(ROOT .. "\\Common\\opc"), "runtime installers deleted")
check(getReg(SHARED_KEY, "InstallPath") == nil, "shared root removed with the last product")
check(registry[PRODUCT_KEY] == nil and registry[COMPONENTS_KEY] == nil, "KeelBase key removed")
check(registry["software\\microsoft\\windows\\currentversion\\uninstall\\keelbase"] == nil, "uninstall entry removed")
check(getReg("SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", "Path") == "C:\\Windows;C:\\Tools",
      "PATH entry removed: " .. tostring(getReg("SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", "Path")))

-- Shared with TaijiMPC6 in this root: only the module and the instance config go; the service
-- comes back for TaijiMPC6's instances; Common\ and the shared root stay.
uninstall({installed = EVERYTHING, recorded = EVERYTHING, taijimpc6 = true,
           services = {HostVM = {"running", HOST .. "\\HostVM.exe"}}})
check(commandAt("service stop HostVM") and commandAt("service remove") == nil, "shared service stopped, not removed")
check(commandAt("service start HostVM") > commandAt("delete " .. HOST .. "\\modules\\KeelBase"), "started again after the module went")
check(exists(HOST .. "\\HostVM.exe") and exists(HOST .. "\\hostvm.xml"), "shared KeelHost kept")
check(not exists(HOST .. "\\keelhost.d\\020-kbase.xml") and not exists(HOST .. "\\modules\\KeelBase"), "KeelBase parts removed")
check(exists(ROOT .. "\\Common\\vcredist") and getReg(SHARED_KEY, "InstallPath") == ROOT, "shared Common and root kept")
-- A stopped shared service stays stopped.
uninstall({installed = EVERYTHING, recorded = EVERYTHING, taijimpc6 = true,
           services = {HostVM = {"stopped", HOST .. "\\HostVM.exe"}}})
check(commandAt("\" service") == nil, "stopped shared service untouched")
-- A KeelHost this setup did not install stays, even without TaijiMPC6.
uninstall({installed = EVERYTHING, recorded = {"Common.Runtime", "KeelBase.Server"},
           services = {HostVM = {"running", HOST .. "\\HostVM.exe"}}})
check(exists(HOST .. "\\HostVM.exe") and commandAt("service remove") == nil and commandAt("service start HostVM"), "foreign KeelHost kept")
-- A service of that name that runs another installation's KeelHost is not touched.
uninstall({installed = EVERYTHING, recorded = EVERYTHING,
           services = {HostVM = {"running", "C:\\TaijiControl\\HostVM\\HostVM.exe"}}})
check(commandAt("\" service") == nil, "other installation's service untouched")
-- The recorded service name is used.
uninstall({installed = EVERYTHING, recorded = EVERYTHING, serviceName = "KeelBaseTest",
           services = {KeelBaseTest = {"running", HOST .. "\\HostVM.exe"}, HostVM = {"running", "C:\\TaijiControl\\HostVM\\HostVM.exe"}}})
check(commandAt("service stop KeelBaseTest") and commandAt("service remove KeelBaseTest") and commandAt("service stop HostVM") == nil,
      "recorded service name used")

print("KeelBaseSetup: " .. count .. " cases passed")
