-- Run from the repository root: lua tests/test_component_selection.lua
-- The TaijiMPC6 component page: default selection, dependencies across groups, the three group
-- states, /components, which archives StartSetup extracts in which order, and that StartSetup and
-- PostSetup only touch the selected components.
local ROOT = "C:\\Test path\\中文"
local MB = 1024 * 1024
local SIZES = {[150] = 27, [151] = 68, [152] = 925, [160] = 73, [161] = 84,
               [170] = 235, [171] = 1, [180] = 8, [181] = 31, [190] = 18}
-- The marker directory of each item under ROOT (an installed item has it).
local MARKERS = {
    ["Common.Runtime"] = "Common\\vcredist", ["Common.Ident"] = "Common\\Ident32",
    ["Common.WinPy313"] = "WinPy313", ["TaijiMPC.HostVM"] = "HostVM",
    ["TaijiMPC.TaijiMPC6"] = "TaiJiMPC6", ["DataService.Svr"] = "TaiJiDataSvc",
    ["DataService.Client"] = "TaiJiDataClient", ["TaijiSim.OPCSim"] = "TaiJiOPCSim",
    ["TaijiSim.PYSim"] = "TaiJiPYSim", ["Tool.RUS"] = "Tools",
}
local SYSTEM = "C:\\Windows\\System32"

local installed, missing, args, files, registry, commands, ui, unzipped, failed, errors, chosenPath

local function startsWith(text, prefix)
    return text:sub(1, #prefix):lower() == prefix:lower()
end

HRootKey = {HKEY_LOCAL_MACHINE = 2}
CSIDL = {COMMON_DESKTOPDIRECTORY = 25, COMMON_STARTMENU = 22}
RunBatchFile = function(path) table.insert(commands, "bat " .. path) return true end
ErrorHint = function(message) table.insert(errors, message) end
installx = {
    PackageInfo = function(res)
        if missing[res] or SIZES[res] == nil then return nil end
        return {size = SIZES[res] * MB, entries = 10}
    end,
    FilePathExists = function(path)
        if files[path] then return true end
        for key, marker in pairs(MARKERS) do
            local base = ROOT .. "\\" .. marker
            if installed[key] and (path:lower() == base:lower() or startsWith(path, base .. "\\")) then
                return true
            end
        end
        return false
    end,
    RegGetValue = function(root, path, name)
        local values = registry[path:lower()]
        if values == nil then return nil end
        if name == "" then return true end
        return values[name:lower()]
    end,
    RegSetValue = function(root, path, name, value)
        table.insert(commands, "reg " .. path .. "|" .. name .. "=" .. tostring(value))
        registry[path:lower()] = registry[path:lower()] or {}
        registry[path:lower()][name:lower()] = value
        return true
    end,
    RegDeleteValue = function() return true end,
    RegGetDefaultValue = function() return nil end,
    LogPrint = function() end,
    SysACP = function() return 936 end,
    SysGetArg = function(name) return args[name] end,
    SetupFailed = function(reason) failed = reason return true end,
    RunAsAdmin = function() return true end,
    DiskFreeSpace = function() return 100 * 1024 * MB end,
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
    DuiAttribute = function(name, attribute, value) ui.attributes[name .. "." .. attribute] = value return true end,
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
    ProcessExecute = function(command) table.insert(commands, "exec " .. command) return true end,
    ProcessKill = function(name) table.insert(commands, "kill " .. name) return true end,
    FilePathMkdir = function() return true end,
    FilePathChoose = function() return chosenPath end,
    FilePathUnzip = function(resourceIDs, directory)
        assert(directory == ROOT, directory)
        unzipped = resourceIDs
        return true
    end,
    FilePathCopy = function() return true, 0 end,
    FilePathDelete = function(path) table.insert(commands, "delete " .. path) files[path] = nil return true end,
    FilePathListFiles = function() return {"100-tjsysid.xml"} end,
    FilePathGetSpecialLocation = function(id)
        if id == 0x25 then return SYSTEM end
        return "C:\\Users\\Public\\Desktop"
    end,
    FilePathCreateShortCut = function(link) table.insert(commands, "shortcut " .. link) return true end,
    FilePathCreateDirectory = function() return true end,
    HostVMSubvmNames = function() return {} end,
}

-- installedKeys: items installed under ROOT; missingRes: archives this installer lacks.
local function scenario(options)
    options = options or {}
    installed, missing, args, files = {}, {}, options.args or {}, {}
    registry, commands, unzipped, failed, errors = {}, {}, nil, nil, {}
    ui = {visible = {}, text = {}, selected = {}, enabled = {}, attributes = {}, tab = 0}
    for _, key in ipairs(options.installed or {}) do installed[key] = true end
    for _, res in ipairs(options.missing or {}) do missing[res] = true end
    for _, service in ipairs(options.services or {}) do
        registry[("SYSTEM\\CurrentControlSet\\Services\\" .. service):lower()] = {}
    end
    registry["software\\taijicontrol"] = {installpath = ROOT}
    files[SYSTEM .. "\\icu.dll"] = true
    files[ROOT .. "\\HostVM\\hostvm.xml"] = true
    assert(loadfile("projects/TaijiMPC6/Install/Install.lua"))()
    OnInitialize()
end

local count = 0
local function check(condition, label)
    count = count + 1
    assert(condition, "case " .. count .. ": " .. label)
end

local ALL = {"Common.Runtime", "Common.Ident", "Common.WinPy313", "TaijiMPC.HostVM", "TaijiMPC.TaijiMPC6",
             "DataService.Svr", "DataService.Client", "TaijiSim.OPCSim", "TaijiSim.PYSim", "Tool.RUS"}
local function selection()
    local list = {}
    for _, key in ipairs(ALL) do
        if ComponentSelected(key) then table.insert(list, key) end
    end
    return table.concat(list, ",")
end
local function hasCommand(pattern)
    for _, command in ipairs(commands) do
        if command:find(pattern, 1, true) then return true end
    end
    return false
end

-- Fresh install: everything is selected, the page shows it, and the biggest archive goes first.
scenario()
check(selection() == table.concat(ALL, ","), "fresh install selects all: " .. selection())
for _, group in ipairs({"Common", "TaijiMPC", "DataService", "TaijiSim", "Tool"}) do
    check(ComponentGroupState(group) == "all", group .. " all")
    check(ui.selected["grp_" .. group] == true, group .. " checkbox")
end
check(ui.enabled["item_Common_Runtime"] == false and ui.selected["item_Common_Runtime"] == true, "runtime locked")
check(ui.text["item_Common_WinPy313"]:find("925 MB", 1, true) ~= nil, "size in label: " .. ui.text["item_Common_WinPy313"])
local plan = ComponentPlan()
check(#plan == 10 and plan[1].res == 152 and plan[2].res == 170 and plan[#plan].res == 171, "biggest first")

-- Deselecting the Common group keeps the required runtime and takes what needs the deselected
-- Python and identification components with it: HostVM, the data collector and PYSim.
OnSelChanged("grp_Common", false)
check(selection() == "Common.Runtime,TaijiMPC.TaijiMPC6,DataService.Svr,TaijiSim.OPCSim,Tool.RUS",
      "common off: " .. selection())
check(ComponentGroupState("Common") == "partial" and ComponentGroupState("TaijiMPC") == "partial", "partial states")
check(ui.selected["grp_Common"] == false and ui.attributes["grp_Common.foreimage"] ~= "", "partial checkbox drawn")
check(ui.attributes["grp_Tool.foreimage"] == "", "full group has no partial mark")
check(ui.text["comphintlab"]:find("HostVM", 1, true) ~= nil, "hint names HostVM: " .. ui.text["comphintlab"])
-- Selecting HostVM brings both dependencies back.
OnSelChanged("item_TaijiMPC_HostVM", true)
check(ComponentSelected("Common.WinPy313") and ComponentSelected("Common.Ident"), "deps selected")
check(ComponentGroupState("Common") == "all", "common all again")
check(ui.text["comphintlab"]:find("Python 3.13", 1, true) ~= nil, "hint names the deps: " .. ui.text["comphintlab"])
-- The required runtime cannot be deselected.
OnSelChanged("item_Common_Runtime", false)
check(ComponentSelected("Common.Runtime") and ui.selected["item_Common_Runtime"] == true, "runtime stays")
-- A group click on a partial group fills it, on a full group clears it.
check(ComponentGroupState("TaijiSim") == "partial", "PYSim left with Python")
OnSelChanged("grp_TaijiSim", true)
check(ComponentGroupState("TaijiSim") == "all", "partial group filled")
OnSelChanged("grp_TaijiSim", false)
check(not ComponentSelected("TaijiSim.OPCSim") and not ComponentSelected("TaijiSim.PYSim"), "group off")
check(ui.selected["grp_TaijiSim"] == false and ui.attributes["grp_TaijiSim.foreimage"] == "", "empty group")
OnSelChanged("grp_TaijiSim", true)
check(ComponentSelected("TaijiSim.OPCSim") and ComponentSelected("TaijiSim.PYSim"), "group on")

-- Upgrade: only the installed components are selected. An installed TaiJiDataSvc keeps its database:
-- never selected, its checkbox disabled. Deselecting the installed Python keeps HostVM.
scenario({installed = {"Common.Runtime", "Common.Ident", "Common.WinPy313", "TaijiMPC.HostVM", "DataService.Svr"}})
check(selection() == "Common.Runtime,Common.Ident,Common.WinPy313,TaijiMPC.HostVM", "upgrade: " .. selection())
check(ui.enabled["item_DataService_Svr"] == false and ui.selected["item_DataService_Svr"] == false, "svr kept")
check(SelectComponent("DataService.Svr", true) == false and not ComponentSelected("DataService.Svr"), "svr locked")
check(ComponentGroupState("DataService") == "none", "kept svr does not count")
OnSelChanged("grp_DataService", true)
check(ComponentSelected("DataService.Client") and ComponentGroupState("DataService") == "all", "client via group")
OnSelChanged("item_Common_WinPy313", false)
check(ComponentSelected("TaijiMPC.HostVM") and not ComponentSelected("Common.WinPy313"), "installed dep satisfies HostVM")
check(ui.text["item_TaijiMPC_HostVM"]:find("已安装", 1, true) ~= nil, "installed label")

-- An installer without WinPy313.7z hides it, and HostVM cannot be selected on a machine without it.
scenario({missing = {152}})
check(ui.visible["item_Common_WinPy313"] == false and not ComponentSelected("Common.WinPy313"), "hidden")
check(not ComponentSelected("TaijiMPC.HostVM"), "HostVM not selectable without Python: " .. selection())
check(SelectComponent("TaijiMPC.HostVM", true) == false, "HostVM refused")
-- ... but it can where Python is already installed.
scenario({missing = {152}, installed = {"Common.WinPy313", "TaijiMPC.HostVM"}})
check(ComponentSelected("TaijiMPC.HostVM"), "HostVM with installed Python")

-- /components: exactly the named groups and items plus what they need and the required runtime.
scenario({args = {components = "TaijiMPC, dataservice.client"}})
check(selection() == "Common.Runtime,Common.Ident,Common.WinPy313,TaijiMPC.HostVM,TaijiMPC.TaijiMPC6,DataService.Client",
      "/components: " .. selection())
-- An unknown name stops a silent install instead of leaving it waiting.
scenario({args = {components = "TaijiSim.OPCSim,Nonsense", s = true}})
check(#errors == 1 and errors[1]:find("Nonsense", 1, true), "unknown name reported")
StartSetup()
check(failed ~= nil and unzipped == nil, "silent install refused")
-- A bare runtime is no installation.
scenario({args = {components = "Common.Runtime"}})
StartSetup()
check(unzipped == nil and #errors == 1, "nothing selected refused")

-- StartSetup extracts the selected archives, biggest first, and stops only what they hold open.
scenario({installed = {"Common.Runtime", "Common.WinPy313", "Common.Ident", "TaijiMPC.HostVM", "TaijiMPC.TaijiMPC6"},
          services = {"HostVM"}, args = {components = "Common.WinPy313,TaijiSim.OPCSim"}})
StartSetup()
check(table.concat(unzipped, ",") == "152,150,180", "archives: " .. table.concat(unzipped, ","))
check(hasCommand("service stop HostVM") and not hasCommand("service remove HostVM"), "HostVM only stopped")
check(hasCommand("kill TaiJiOPCSim.exe") and not hasCommand("kill TaiJiMPC.exe"), "client left running")
-- Progress runs by unpacked bytes over the three archives.
OnUnzipProgress(152, 10, 0, 925 * MB, 480 * MB)
check(ui.percent == 5 + math.floor(87 * 480 / 960), "progress " .. tostring(ui.percent))
OnUnzipProgress(150, 10, 0, 27 * MB, 480 * MB)
check(ui.percent == 92, "progress end " .. tostring(ui.percent))
commands = {}
check(PostSetup() == true, "post setup")
check(hasCommand("service start HostVM") and not hasCommand("service install HostVM"), "HostVM restarted, not reinstalled")
check(hasCommand("GBDA_Install_Prereq_x86.msi") and not hasCommand("GBDA_Install_Prereq_x64.msi"), "OPC x86 only")
check(not hasCommand("-RegServer"), "no TaiJiOPCSim.exe on disk yet in this test, so nothing registered")
check(not hasCommand("haspdinst.exe") and not hasCommand("shortcut "), "no HASP, no shortcuts")
local components = registry[("Software\\TaijiControl\\TaiJiMPC6\\Components"):lower()]
check(components["common.winpy313"] and components["taijisim.opcsim"] and components["common.runtime"]
      and components["taijimpc.hostvm"] == nil, "components recorded")
local uninstall = registry[("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\TaiJiMPC6"):lower()]
check(uninstall.uninstallstring == ROOT .. "\\Uninstall\\UnInstall.exe", "uninstaller path")
check(uninstall.displayicon == ROOT .. "\\TaiJiMPC6\\TaiJiMPC.exe", "installed client keeps its icon")

-- Selected HostVM: service removed before and installed after; client: shortcuts; Ident: HASP.
-- A fresh DataService.Client registers its service with the collector's own script; PYSim on an
-- upgrade just starts the service its script registered before.
scenario({installed = {"TaijiSim.PYSim"}, services = {"TaiJiOPCSim"},
          args = {components = "TaijiMPC,DataService.Client,TaijiSim.PYSim"}})
files[ROOT .. "\\Uninstall\\UnInstall.exe"] = true
files[ROOT .. "\\TaiJiMPC6\\UnInstall.exe"] = true
StartSetup()
check(hasCommand("service remove HostVM") and hasCommand("net.exe stop TaiJiOPCSim")
      and hasCommand("kill taiji-opcsim-server.exe"), "stopped for upgrade")
commands = {}
check(PostSetup() == true, "post setup 2")
check(hasCommand("service install HostVM") and hasCommand("service start HostVM"), "HostVM installed")
check(hasCommand("haspdinst.exe") and hasCommand("shortcut "), "HASP and shortcuts")
check(hasCommand("GBDA_Install_Prereq_x64.msi") and hasCommand("GBDA_Install_Prereq_x86.msi"), "both OPC halves")
check(hasCommand("bat " .. ROOT .. "\\TaiJiDataClient\\install_TaijiDataCollector.bat"), "collector registered")
check(hasCommand("net.exe start TaiJiOPCSim") and not hasCommand("install_taijiopcsim.bat"), "PYSim restarted")
check(not hasCommand("install_TaiJiDataSvc.bat"), "data server untouched")
check(hasCommand("delete " .. ROOT .. "\\TaiJiMPC6\\UnInstall.exe"), "stale uninstaller removed")

-- Without the client the finish page offers neither starting it nor autostart, and Add/Remove
-- Programs shows the uninstaller's icon. The data collector only launches DataCollector.py, so
-- it brings WinPy313 along, and PythonEnv is written before its service starts.
scenario({args = {components = "DataService"}})
StartSetup()
check(table.concat(unzipped, ",") == "152,170,150,171", "data service archives: " .. table.concat(unzipped, ","))
commands = {}
check(PostSetup() == true, "post setup 3")
check(ui.visible["runbtn"] == false and ui.selected["runbtn"] == false and ui.visible["pyenvbtn"] ~= false, "finish page")
uninstall = registry[("Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\TaiJiMPC6"):lower()]
check(uninstall.displayicon == ROOT .. "\\Uninstall\\UnInstall.exe", "uninstaller icon")
check(hasCommand("install_TaiJiDataSvc.bat") and not hasCommand("HostVM.exe"), "no HostVM touched")
local function position(pattern)
    for index, command in ipairs(commands) do
        if command:find(pattern, 1, true) then return index end
    end
    return math.huge
end
local pythonEnvAt = position("reg Software\\TaijiControl\\PythonEnv|PythonPath=" .. ROOT .. "\\WinPy313\\python")
check(pythonEnvAt < position("install_TaijiDataCollector.bat"), "PythonEnv before the collector starts")
check(position("reg Software\\TaijiControl|InstallPath=") < position("install_python_env.bat"), "InstallPath before the script reads it")
-- The script writes WinPy312; WinPy313 is written again after it.
local last = 0
for index, command in ipairs(commands) do
    if command:find("reg Software\\TaijiControl\\PythonEnv|InstallPath=", 1, true) then last = index end
end
check(last > position("install_python_env.bat"), "PythonEnv restored after install_python_env.bat")
-- PYSim's pySim.exe is a launcher of pySim.py as well.
scenario({args = {components = "TaijiSim.PYSim"}})
check(selection() == "Common.Runtime,Common.WinPy313,TaijiSim.PYSim", "PYSim needs Python: " .. selection())

-- HostVM browses the local DA servers through OpcEnum, which only the x86 package installs.
scenario({args = {components = "TaijiMPC.HostVM"}})
StartSetup()
commands = {}
check(PostSetup() == true, "post setup 4")
check(hasCommand("GBDA_Install_Prereq_x86.msi") and hasCommand("GBDA_Install_Prereq_x64.msi"), "HostVM gets both OPC halves")

-- An explicitly requested component this installer cannot install fails a silent install
-- instead of being dropped; an installed one stays as it is and counts as satisfied.
scenario({missing = {160}, args = {components = "TaijiMPC.HostVM,Tool.RUS", s = true}})
check(#errors == 1 and errors[1]:find("TaijiMPC.HostVM", 1, true) ~= nil, "unavailable reported: " .. tostring(errors[1]))
StartSetup()
check(failed ~= nil and unzipped == nil, "silent install refused for a missing archive")
scenario({missing = {160}, installed = {"Common.WinPy313", "Common.Ident", "TaijiMPC.HostVM"},
          args = {components = "TaijiMPC.HostVM,Tool.RUS", s = true}})
check(#errors == 0, "installed HostVM satisfies the request")
StartSetup()
check(failed == nil and table.concat(unzipped, ",") == "150,190", "kept HostVM: " .. table.concat(unzipped or {}, ","))
-- The same for a dependency: HostVM's Python missing from the installer and from the machine.
scenario({missing = {152}, args = {components = "TaijiMPC.HostVM", s = true}})
StartSetup()
check(failed ~= nil and unzipped == nil, "unsatisfiable dependency refused")

-- Changing the install path re-checks dependencies: Python and Identification were installed at
-- the old path, so deselecting them kept HostVM; at an empty path HostVM needs them again.
scenario({installed = {"Common.Runtime", "Common.Ident", "Common.WinPy313", "TaijiMPC.HostVM"}})
OnSelChanged("item_Common_WinPy313", false)
OnSelChanged("item_Common_Ident", false)
check(ComponentSelected("TaijiMPC.HostVM") and not ComponentSelected("Common.WinPy313"), "kept by installed deps")
chosenPath = "D:\\Empty"
OnButtonClick("browfilebtn")
check(ComponentSelected("Common.WinPy313") and ComponentSelected("Common.Ident") and ComponentSelected("TaijiMPC.HostVM"),
      "deps selected again at the new path: " .. selection())
check(ui.text["comphintlab"]:find("HostVM", 1, true) ~= nil, "hint after path change: " .. tostring(ui.text["comphintlab"]))
-- Where the installer lacks WinPy313, HostVM cannot stay selected at the new path.
scenario({missing = {152}, installed = {"Common.Runtime", "Common.Ident", "Common.WinPy313", "TaijiMPC.HostVM"}})
check(ComponentSelected("TaijiMPC.HostVM"), "HostVM with Python installed at the old path")
OnButtonClick("browfilebtn")
check(not ComponentSelected("TaijiMPC.HostVM"), "HostVM dropped at the new path: " .. selection())
chosenPath = nil

print("Component selection: " .. count .. " cases passed")
