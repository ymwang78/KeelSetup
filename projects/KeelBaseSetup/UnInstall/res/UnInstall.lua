-- KeelBase UnInstall script.
-- HRootKey, CSIDL, RunBatchFile, ErrorHint are provided by the framework base library.
--
-- The native host (CUninstallMainFrame) drives the UI, then calls:
--   OnInitialize()  -- when the window is ready
--   PreSetup()      -- after the user confirms (at once for /s), on the worker thread
-- and afterwards recursively deletes the directory the running UnInstall.exe lives in
-- (<InstallPath>\KeelBase, with kbased.exe and kbasecli.exe) and self-deletes it.
--
-- PreSetup() undoes the rest of projects/KeelBaseSetup/Install/Install.lua. KeelHost (HostVM\ and
-- its Windows service) may be shared with TaijiMPC6, which installs it into the same root: it is
-- removed only when this setup installed it and TaijiMPC6 does not use it. Otherwise only the
-- KeelBase module and its instance config go, and a running service is started again so that the
-- other product's instances keep running. The data of the KeelBase instances (under the KeelHost
-- projects_dir, ..\TaiJiMPC_Projects by default) is never deleted, nor are the OPC Core Components
-- and the VC++ runtime, which other software may use.

local DEFAULT_ROOT = "C:\\TaijiControl"
local DEFAULT_SERVICE = "HostVM"
local SHARED_KEY = "Software\\TaijiControl"
local PRODUCT_KEY = SHARED_KEY .. "\\KeelBase"
local COMPONENTS_KEY = PRODUCT_KEY .. "\\Components"
local UNINSTALL_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
local KBASE_FRAGMENT = "keelhost.d\\020-kbase.xml"

local _dirCompany = DEFAULT_ROOT
local _dirHostVM = DEFAULT_ROOT .. "\\HostVM"
-- The directory that holds the running UnInstall.exe; the native host removes it.
local _dirExeHome = DEFAULT_ROOT .. "\\KeelBase"
local _serviceName = DEFAULT_SERVICE

local _strResourceCN = {
    SETUP        = "KeelBase 卸载程序",
    UNINSTALLING = "正在卸载",
}

local _strResourceEN = {
    SETUP        = "KeelBase Uninstall",
    UNINSTALLING = "Uninstalling",
}

local _strResource = _strResourceCN

local function NonEmpty(value)
    if value == nil or value == true or value == false then return nil end
    value = tostring(value)
    if value == "" then return nil end
    return value
end

local function NormalizePath(path)
    local value = tostring(path or ""):gsub("/", "\\")
    value = value:gsub("\\+$", "")
    return value
end

local function SamePath(a, b)
    return a ~= nil and b ~= nil and NormalizePath(a):lower() == NormalizePath(b):lower()
end

local function Join(dir, name)
    if dir:sub(-1) == "\\" then return dir .. name end
    return dir .. "\\" .. name
end

local function resetInstallPath(installPath)
    _dirCompany = NormalizePath(NonEmpty(installPath) or DEFAULT_ROOT)
    if _dirCompany:match("^%a:$") then _dirCompany = _dirCompany .. "\\" end
    _dirHostVM = Join(_dirCompany, "HostVM")
    _dirExeHome = Join(_dirCompany, "KeelBase")
end

local function regGet(path, name)
    return installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, path, name)
end

local function deleteIfExists(path)
    if path ~= nil and path ~= "" and installx.FilePathExists(path) then
        installx.LogPrint("Delete: " .. path)
        return installx.FilePathDelete(path)
    end
    return true
end

-- Remove the given entries from the system PATH (reverse of Install's SysPathAdd).
local function removePathEntries(...)
    local envKey = "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment"
    local pathValue = regGet(envKey, "Path")
    if pathValue == nil or pathValue == "" then
        return
    end

    local removals = {}
    for _, path in ipairs({ ... }) do
        removals[NormalizePath(path):lower()] = true
    end

    local kept, removed = {}, false
    for entry in tostring(pathValue):gmatch("([^;]+)") do
        if removals[NormalizePath(entry):lower()] then
            removed = true
        elseif entry ~= "" then
            table.insert(kept, entry)
        end
    end

    if removed then
        installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, envKey, "Path", table.concat(kept, ";"))
    end
end

local function serviceKey(name)
    return "SYSTEM\\CurrentControlSet\\Services\\" .. name
end

-- The executable a service runs, from its ImagePath, or nil when there is no such service.
local function serviceExecutable(name)
    local image = NonEmpty(regGet(serviceKey(name), "ImagePath"))
    if image == nil then return nil end
    local quoted = image:match('^%s*"([^"]+)"')
    if quoted then return quoted end
    return image:match("^%s*(.-%.[eE][xX][eE])") or image
end

-- The service runs the KeelHost of this install path (and not another installation's).
function ServiceIsOurs()
    local exe = serviceExecutable(_serviceName)
    if exe == nil then return false end
    return SamePath(exe, Join(_dirHostVM, "HostVM.exe")) or SamePath(exe, Join(_dirHostVM, "KeelHost.exe"))
end

local function serviceRunning(name)
    local state = installx.ServiceState(name)
    return state == "running" or state == "start_pending" or state == "continue_pending"
end

local function hostCommand(args, waitSec)
    installx.LogPrint("HostVM.exe " .. args)
    installx.ProcessExecute("\"" .. Join(_dirHostVM, "HostVM.exe") .. "\" " .. args, true, waitSec)
end

-- TaijiMPC6 is installed into this root: its uninstall entry exists and the root it uses (the
-- shared InstallPath) is ours. It then uses HostVM\ and the service, and Common\.
function TaijiMPC6Here()
    return regGet(UNINSTALL_KEY .. "\\TaiJiMPC6", "") ~= nil
        and SamePath(regGet(SHARED_KEY, "InstallPath"), _dirCompany)
end

local function installedComponent(key)
    return NonEmpty(regGet(COMPONENTS_KEY, key)) ~= nil
end

function OnInitialize()
    resetInstallPath(NonEmpty(regGet(PRODUCT_KEY, "InstallPath")) or regGet(SHARED_KEY, "InstallPath"))
    _serviceName = NonEmpty(regGet(PRODUCT_KEY, "ServiceName")) or DEFAULT_SERVICE

    local acp = installx.SysACP()
    if acp == 936 then
        _strResource = _strResourceCN
    else
        _strResource = _strResourceEN
    end

    installx.LogPrint("UnInstall OnInitialize, dirCompany: " .. _dirCompany .. ", service: " .. _serviceName)
end

function PreSetup()
    installx.LogPrint("UnInstall PreSetup begin")

    local shared = TaijiMPC6Here()
    -- KeelHost goes only when this setup installed it and nobody else uses it.
    local removeHost = installedComponent("KeelBase.Host") and not shared
    local ours = ServiceIsOurs()
    local wasRunning = ours and serviceRunning(_serviceName)

    -- 1. Stop KeelHost: the workers have the KeelBase module loaded. "service stop" waits until the
    --    service and its workers have stopped. A service of another installation is not touched.
    if wasRunning then
        hostCommand("service stop " .. _serviceName, 120)
    end
    if removeHost and ours then
        hostCommand("service remove " .. _serviceName, 60)
    end

    -- 2. The KeelBase module and the instance config this setup created. Fragments the site added
    --    for further KeelBase instances stay, and fail to load without the module, which says so in
    --    the KeelHost log.
    deleteIfExists(Join(_dirHostVM, "modules\\KeelBase"))
    deleteIfExists(Join(_dirHostVM, KBASE_FRAGMENT))
    deleteIfExists(Join(_dirHostVM, KBASE_FRAGMENT .. ".template"))

    -- 3. KeelHost itself, or the shared one started again for the other product's instances.
    if removeHost then
        deleteIfExists(_dirHostVM)
    elseif wasRunning then
        hostCommand("service start " .. _serviceName, 120)
    end

    -- 4. The runtime installers in Common\, unless TaijiMPC6 (whose Common.7z has them too) is here.
    if not shared then
        deleteIfExists(Join(_dirCompany, "Common\\vcredist"))
        if installedComponent("Common.OpcCore") then
            deleteIfExists(Join(_dirCompany, "Common\\opc"))
        end
    end

    -- 5. Registry and PATH. The shared InstallPath goes only when it is this root and no other
    --    product of this root still needs it.
    removePathEntries(_dirExeHome)
    if not shared and SamePath(regGet(SHARED_KEY, "InstallPath"), _dirCompany) then
        installx.RegDeleteValue(HRootKey.HKEY_LOCAL_MACHINE, SHARED_KEY, "InstallPath")
        installx.RegDeleteValue(HRootKey.HKEY_LOCAL_MACHINE, "Software\\WOW6432Node\\TaijiControl", "InstallPath")
    end
    installx.RegDeleteKey(HRootKey.HKEY_LOCAL_MACHINE, SHARED_KEY, "KeelBase")
    installx.RegDeleteKey(HRootKey.HKEY_LOCAL_MACHINE, UNINSTALL_KEY, "KeelBase")

    installx.LogPrint("UnInstall PreSetup done, exe home left for native cleanup: " .. _dirExeHome)
end

function PostSetup()
end

function OnButtonClick(btnName)
end

function QueryByKey(keyName)
    if keyName == "InstallPath" then
        return _dirCompany
    elseif keyName == "AppHome" then
        return _dirExeHome
    end
end
