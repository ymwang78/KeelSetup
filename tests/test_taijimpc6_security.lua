-- Run from the repository root: lua tests/test_taijimpc6_security.lua
-- TaijiMPC6 runs its components as SYSTEM (HostVM and the other services), elevated (the
-- uninstaller) or for every user (the client), from directories below C:\, where every user may
-- create files. StartSetup secures (installx.FilePathSecure) the directories of every component
-- that is selected or installed, before it stops or extracts anything; hostvm.d\ and
-- TaiJiDataSvc\data\ without any access for Users; a root it creates itself; and HostVM's projects
-- directories from hostvm.xml, or in PostSetup once a fresh install has created hostvm.xml. A refused
-- path stops the installation. /path= chooses the install root.
local ROOT = "C:\\Test path\\中文"
local MB = 1024 * 1024
local SIZES = {[150] = 27, [151] = 68, [152] = 925, [160] = 73, [161] = 84,
               [170] = 235, [171] = 1, [181] = 31, [190] = 18}
local MARKERS = {
    ["Common.Runtime"] = "Common\\vcredist", ["Common.Ident"] = "Common\\Ident32",
    ["Common.WinPy313"] = "WinPy313", ["TaijiMPC.HostVM"] = "HostVM",
    ["TaijiMPC.TaijiMPC6"] = "TaiJiMPC6", ["DataService.Svr"] = "TaiJiDataSvc",
    ["DataService.Client"] = "TaiJiDataClient", ["TaijiSim.PYSim"] = "TaiJiPYSim",
    ["Tool.RUS"] = "Tools",
}
local SYSTEM = "C:\\Windows\\System32"
local DEFAULT_INFO = {projects_dir = "../TaiJiMPC_Projects", metadb_path = "../TaiJiMPC_Projects/subvm.db"}

local root, installed, missing, args, files, registry, commands, logs, errors, failed, unzipped, unzipDir
local rootExists, unsafe, hostvmInfo, chosenPath

local function lower(path) return path:lower() end
local function startsWith(text, prefix) return text:sub(1, #prefix):lower() == prefix:lower() end

local function exists(path)
    local key = lower(path)
    if files[key] then return true end
    if path:match("^%a:$") then return true end  -- a drive
    -- An installed item has everything below its marker directory, but no dot file (hostvm.d's
    -- .hostvm-fragments.pending marker of an interrupted initialization).
    if path:match("\\%.[^\\]*$") then return false end
    for item, marker in pairs(MARKERS) do
        local base = root .. "\\" .. marker
        if installed[item] and (key == lower(base) or startsWith(path, base .. "\\")) then return true end
    end
    if key == lower(root) then
        if rootExists or next(installed) ~= nil then return true end
        for name in pairs(files) do
            if startsWith(name, root .. "\\") then return true end
        end
    end
    return false
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
    FilePathExists = exists,
    -- Recorded as "secure <path>{<private subdirs>}", " private" when Users get no access at all.
    FilePathSecure = function(path, usersCanRead, privateSubdirs)
        assert(type(usersCanRead) == "boolean", "usersCanRead for " .. path)
        assert(privateSubdirs == nil or type(privateSubdirs) == "table", "privateSubdirs for " .. path)
        local names = (privateSubdirs and #privateSubdirs > 0) and ("{" .. table.concat(privateSubdirs, ";") .. "}") or ""
        table.insert(commands, "secure " .. path .. names .. (usersCanRead and "" or " private"))
        if unsafe[lower(path)] then return false, path .. "\\junction", 4395 end
        files[lower(path)] = true
        return true
    end,
    HostVMInfoAttribute = function(path, name)
        assert(path == root .. "\\HostVM\\hostvm.xml", path)
        if not exists(path) or hostvmInfo == nil then return nil end
        local value = hostvmInfo[name]
        if value == nil then return false end
        return value
    end,
    RegGetValue = function(_, path, name)
        local values = registry[lower(path)]
        if values == nil then return nil end
        if name == "" then return true end
        return values[lower(name)]
    end,
    RegSetValue = function(_, path, name, value)
        registry[lower(path)] = registry[lower(path)] or {}
        registry[lower(path)][lower(name)] = value
        return true
    end,
    RegDeleteValue = function() return true end,
    RegGetDefaultValue = function() return nil end,
    LogPrint = function(...) table.insert(logs, table.concat({...})) end,
    SysACP = function() return 936 end,
    SysGetArg = function(name) return args[name] end,
    SetupFailed = function(reason) failed = reason return true end,
    ServiceState = function() return nil end,
    RunAsAdmin = function() return true end,
    DiskFreeSpace = function() return 100 * 1024 * MB end,
    DuiVisible = function(_, visible) if visible == nil then return false end return true end,
    DuiText = function() return true end,
    DuiOptionSelect = function(_, selected, notify)
        if selected == nil then return false end
        assert(notify == false)
        return true
    end,
    DuiEnable = function() return true end,
    DuiAttribute = function() return true end,
    DuiTextColor = function() return true end,
    DuiTabSelect = function(_, index) if index == nil then return 0 end return true end,
    DuiSetBkImage = function() return true end,
    DuiWindowPos = function() return true end,
    DuiProgress = function() return true end,
    DuiMessage = function() return true end,
    ProcessExecute = function(command) table.insert(commands, "exec " .. command) return true end,
    ProcessKill = function(name) table.insert(commands, "kill " .. name) return true end,
    FilePathMkdir = function() return true end,
    FilePathChoose = function() return chosenPath end,
    FilePathUnzip = function(resourceIDs, directory)
        table.insert(commands, "unzip " .. directory)
        unzipped, unzipDir = resourceIDs, directory
        return true
    end,
    FilePathCopy = function(_, destination) files[lower(destination)] = true return true, 0 end,
    FilePathDelete = function(path) files[lower(path)] = nil return true end,
    FilePathListFiles = function() return {"100-tjsysid.xml"} end,
    FilePathGetSpecialLocation = function(id)
        if id == 0x25 then return SYSTEM end
        return "C:\\Users\\Public\\Desktop"
    end,
    FilePathCreateShortCut = function() return true end,
    FilePathCreateDirectory = function() return true end,
    HostVMSubvmNames = function() return {} end,
}

-- installed: items installed under the root; rootExists: the root is there (as it is once anything
-- is installed); hostvmXml: HostVM\hostvm.xml exists (default: when HostVM is installed);
-- info: its hostvm_info attributes (nil: unreadable); unsafe: paths FilePathSecure refuses.
local function scenario(options)
    options = options or {}
    root = ROOT
    installed, missing, args, files, registry = {}, {}, options.args or {}, {}, {}
    commands, logs, errors, failed, unzipped, unzipDir = {}, {}, {}, nil, nil, nil
    rootExists = options.rootExists ~= false
    unsafe = {}
    hostvmInfo = DEFAULT_INFO
    if options.info ~= nil then hostvmInfo = options.info end
    if options.unreadable then hostvmInfo = nil end
    for _, key in ipairs(options.installed or {}) do installed[key] = true end
    for _, res in ipairs(options.missing or {}) do missing[res] = true end
    for _, path in ipairs(options.unsafe or {}) do unsafe[lower(path)] = true end
    if options.root then root = options.root else registry["software\\taijicontrol"] = {installpath = ROOT} end
    files[lower(SYSTEM .. "\\icu.dll")] = true
    local hostvmXml = options.hostvmXml
    if hostvmXml == nil then hostvmXml = installed["TaijiMPC.HostVM"] == true end
    if hostvmXml then files[lower(root .. "\\HostVM\\hostvm.xml")] = true end
    assert(loadfile("projects/TaijiMPC6/Install/Install.lua"))()
    OnInitialize()
end

local count = 0
local function check(condition, label)
    count = count + 1
    assert(condition, "case " .. count .. ": " .. label)
end

-- The secured paths in order, relative to the root ("." for the root itself), " private" marking
-- those without access for Users.
local function secured()
    local list = {}
    for _, command in ipairs(commands) do
        local path = command:match("^secure (.*)$")
        if path then
            if path == root then
                path = "."
            elseif startsWith(path, root .. "\\") then
                path = path:sub(#root + 2)
            end
            table.insert(list, path)
        end
    end
    return table.concat(list, ",")
end

local function count_of(text)
    local n = 0
    for _, command in ipairs(commands) do
        if command == text then n = n + 1 end
    end
    return n
end

local function indexOf(pattern)
    for i, command in ipairs(commands) do
        if command:find(pattern, 1, true) then return i end
    end
    return nil
end

-- Every secure comes before anything is stopped, run or extracted.
local function securedFirst()
    local lastSecure, firstOther = 0, nil
    for i, command in ipairs(commands) do
        if command:match("^secure ") then
            lastSecure = i
        elseif firstOther == nil then
            firstOther = i
        end
    end
    return firstOther == nil or lastSecure < firstOther
end

-- hostvm.d\ and TaiJiDataSvc\data\ are private subdirectories of their component's call, so Users
-- can read them at no point; one that is not there yet is created by a call of its own, without
-- access for Users, before the archive fills it.
local ALL_DIRS = "Common,Uninstall,WinPy313,HostVM{hostvm.d},HostVM\\hostvm.d private,TaijiMPC6,"
    .. "TaiJiDataSvc{data},TaiJiDataSvc\\data private,TaiJiDataClient,TaiJiPYSim,Tools"

-- A fresh install into a new root secures the root, then every component's directories (Common\
-- once, though two items fill it); all before anything else happens.
scenario({rootExists = false})
StartSetup()
check(secured() == ".," .. ALL_DIRS, "fresh: " .. secured())
check(securedFirst(), "secured before anything is stopped or extracted")
check(unzipped ~= nil and unzipDir == ROOT, "extracted into the root")
-- No hostvm.xml yet: PostSetup secures the projects directory once it has created hostvm.xml,
-- before the service is installed and first creates it; the metadb, in the same directory, adds
-- nothing.
check(secured():find("Projects", 1, true) == nil, "no projects directory before hostvm.xml")
check(PostSetup() == true, "post setup")
local projects = indexOf("secure " .. ROOT .. "\\TaiJiMPC_Projects")
check(projects ~= nil and count_of("secure " .. ROOT .. "\\TaiJiMPC_Projects") == 1, "projects secured once: " .. secured())
check(projects < indexOf("service install HostVM"), "projects secured before the service is installed")

-- An existing root is left as it is: other products live there (KeelBase keeps Users out of its
-- Data\, which securing the root would reset).
scenario()
StartSetup()
check(secured() == ALL_DIRS, "existing root not secured: " .. secured())

-- A drive as the install root is never secured itself.
scenario({root = "E:", args = {path = "E:\\", components = "Tool.RUS"}})
StartSetup()
check(secured() == "Common,Uninstall,Tools", "drive root: " .. secured())
check(unzipDir == "E:", "drive root extracts into E: " .. tostring(unzipDir))

-- An upgrade secures what is installed too, selected or not: an installed component runs from its
-- directory as it is. Nothing of a component that is neither is created. hostvm.xml exists, so
-- HostVM's projects directory (where the site keeps it) is secured right away.
scenario({installed = {"Common.Runtime", "TaijiMPC.HostVM", "DataService.Svr"}, args = {components = "Tool.RUS"},
          info = {projects_dir = "../MyProjects", metadb_path = "../MyProjects/subvm.db"}})
StartSetup()
-- The existing hostvm.d\ and data\ need no call of their own.
check(secured() == "Common,Uninstall,HostVM{hostvm.d},TaiJiDataSvc{data},Tools,MyProjects", "upgrade: " .. secured())
check(securedFirst(), "upgrade secured first")
commands = {}
check(PostSetup() == true and secured() == "", "PostSetup secures nothing more: " .. secured())
-- An installed component this installer has no archive for is secured as well.
scenario({installed = {"Common.Runtime", "TaijiSim.PYSim"}, missing = {181}, args = {components = "Tool.RUS"}})
StartSetup()
check(secured() == "Common,Uninstall,TaiJiPYSim,Tools", "installed without archive: " .. secured())

-- HostVM upgraded: the projects directory is secured before HostVM is stopped, and not again later.
scenario({installed = {"Common.Runtime", "Common.WinPy313", "Common.Ident", "TaijiMPC.HostVM"},
          args = {components = "TaijiMPC.HostVM"}})
StartSetup()
check(indexOf("secure " .. ROOT .. "\\TaiJiMPC_Projects") < indexOf("--stop HostVM"), "projects before the stop")
check(securedFirst(), "HostVM upgrade secured first")
check(PostSetup() == true and count_of("secure " .. ROOT .. "\\TaiJiMPC_Projects") == 1, "projects secured once")

-- Where hostvm.xml puts the projects: relative to HostVM\, absolute, slashes either way. Only
-- directories below the install root are secured (one elsewhere belongs to the site and is logged),
-- and one inside HostVM\ already is.
local function projectsFor(info)
    scenario({installed = {"Common.Runtime", "TaijiMPC.HostVM"}, args = {components = "Tool.RUS"}, info = info})
    StartSetup()
    local list = {}
    for path in secured():gmatch("[^,]+") do
        if not ({Common = true, Uninstall = true, ["HostVM{hostvm.d}"] = true, Tools = true})[path] then
            table.insert(list, path)
        end
    end
    return table.concat(list, ",")
end
local function logged(text)
    for _, line in ipairs(logs) do
        if line:find(text, 1, true) then return true end
    end
    return false
end
check(projectsFor({projects_dir = "..\\P1", metadb_path = "../Meta/subvm.db"}) == "P1,Meta", "two directories")
check(projectsFor({projects_dir = "../P/", metadb_path = "..\\p\\subvm.db"}) == "P", "same directory once")
check(projectsFor({projects_dir = ROOT .. "\\Abs"}) == "Abs", "absolute below the root")
check(projectsFor({projects_dir = "./../Dot"}) == "Dot", "dot components")
check(projectsFor({projects_dir = "projects", metadb_path = "projects/subvm.db"}) == "", "inside HostVM\\ already secured")
check(projectsFor({projects_dir = "D:\\Elsewhere"}) == "" and logged("D:\\Elsewhere is outside"), "outside the root logged")
check(projectsFor({projects_dir = "..\\..\\Up"}) == "" and logged("is outside"), "above the root")
check(projectsFor({projects_dir = "\\\\server\\share\\p"}) == "", "UNC")
check(projectsFor({projects_dir = "D:relative"}) == "", "drive-relative")
check(projectsFor({}) == "", "no attributes")
scenario({installed = {"Common.Runtime", "TaijiMPC.HostVM"}, args = {components = "Tool.RUS"}, unreadable = true})
StartSetup()
check(unzipped ~= nil and logged("Cannot read projects_dir"), "unreadable hostvm.xml does not stop the install")

-- A refused path (a junction, a directory another user created) stops everything: nothing after it
-- is secured, nothing stopped or extracted, and a silent install fails naming the path and error.
scenario({args = {s = true}, unsafe = {ROOT .. "\\HostVM"}, installed = {"TaijiMPC.HostVM", "Common.Runtime"}})
StartSetup()
check(failed ~= nil and failed:find(ROOT .. "\\HostVM\\junction", 1, true) ~= nil and failed:find("4395", 1, true) ~= nil,
      "message names it: " .. tostring(failed))
-- (The upgrade selects HostVM's missing dependencies: WinPy313 comes before it.)
check(secured() == "Common,Uninstall,WinPy313,HostVM{hostvm.d}", "nothing secured after the refusal: " .. secured())
check(indexOf("kill ") == nil and indexOf("exec ") == nil and unzipped == nil, "nothing stopped or extracted")
scenario({args = {s = true}, rootExists = false, unsafe = {ROOT}})
StartSetup()
check(failed ~= nil and secured() == "." and unzipped == nil, "refused new root")
-- So does a refused new private subdirectory (another user created it after all).
scenario({args = {s = true}, rootExists = false, unsafe = {ROOT .. "\\HostVM\\hostvm.d"}})
StartSetup()
check(failed ~= nil and failed:find("hostvm.d", 1, true) ~= nil and unzipped == nil
      and secured() == ".,Common,Uninstall,WinPy313,HostVM{hostvm.d},HostVM\\hostvm.d private", "refused hostvm.d: " .. secured())
scenario({args = {s = true}, installed = {"Common.Runtime", "TaijiMPC.HostVM"}, unsafe = {ROOT .. "\\TaiJiMPC_Projects"}})
StartSetup()
check(failed ~= nil and failed:find("TaiJiMPC_Projects", 1, true) ~= nil and indexOf("--stop HostVM") == nil
      and unzipped == nil, "refused projects directory stops before HostVM")
-- On a fresh install the projects directory is refused in PostSetup: setup fails before the service
-- is installed.
scenario({rootExists = false, unsafe = {ROOT .. "\\TaiJiMPC_Projects"}})
StartSetup()
check(PostSetup() == false and errors[#errors]:find("TaiJiMPC_Projects", 1, true) ~= nil, "PostSetup refusal reported")
check(indexOf("service install HostVM") == nil and indexOf("service start HostVM") == nil, "service not installed")

-- /path= picks the root (trailing and forward slashes normalized), ahead of the recorded one.
scenario({root = "D:\\Scratch\\Sub", rootExists = false, args = {path = "D:/Scratch/Sub/", components = "Tool.RUS"}})
check(QueryByKey("InstallPath") == "D:\\Scratch\\Sub", "path normalized: " .. tostring(QueryByKey("InstallPath")))
StartSetup()
check(secured() == ".,Common,Uninstall,Tools" and unzipDir == "D:\\Scratch\\Sub", "/path used: " .. secured())
-- A /path that is not an absolute path on a local drive stops a silent install before anything.
for _, bad in ipairs({"relative\\dir", "\\\\server\\share", "D:relative"}) do
    scenario({args = {s = true, path = bad}})
    StartSetup()
    check(failed ~= nil and failed:find(bad, 1, true) ~= nil and secured() == "" and unzipped == nil,
          "bad /path " .. bad .. ": " .. tostring(failed))
    check(QueryByKey("InstallPath") == ROOT, "bad /path replaced by the recorded root")
end

-- A path chosen on the page is the one secured.
scenario({args = {components = "Tool.RUS"}})
chosenPath = "D:\\Chosen"
OnButtonClick("browfilebtn")
root, rootExists = "D:\\Chosen", false
StartSetup()
check(secured() == ".,Common,Uninstall,Tools" and unzipDir == "D:\\Chosen", "chosen path: " .. secured())

print("TaijiMPC6 directory security: " .. count .. " cases passed")
