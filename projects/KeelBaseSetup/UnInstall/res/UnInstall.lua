-- KeelBase UnInstall script.
-- HRootKey, CSIDL, RunBatchFile, ErrorHint are provided by the framework base library.
--
-- The native host (CUninstallMainFrame) drives the UI, then calls:
--   OnInitialize()  -- when the window is ready
--   PreSetup()      -- after the user confirms (at once for /s), on the worker thread
-- and afterwards ends the kbased.exe of the install path, recursively deletes the directory the
-- running UnInstall.exe lives in (<InstallPath>\Uninstall), self-deletes it, and removes the
-- install path if nothing is left in it.
--
-- PreSetup() undoes the rest of projects/KeelBaseSetup/Install/Install.lua: KeelBase's own KeelHost
-- service, Host\, Tools\ and Redist\, the registry entries and the PATH entry. The instances' data in
-- Data\ (KeelHost's projects_dir) is never deleted, nor are the OPC Core Components and the VC++
-- runtime, which other software may use. Nothing outside the install path is touched: a service of
-- the recorded name that runs another installation's KeelHost stays as it is.

local DEFAULT_PATH = "C:\\TaijiControl\\KeelBase"
local DEFAULT_SERVICE = "KeelBase"
local PRODUCT_KEY = "Software\\TaijiControl\\KeelBase"
local UNINSTALL_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall"

local _dirInstall = DEFAULT_PATH
local _dirHost = DEFAULT_PATH .. "\\Host"
-- The directory that holds the running UnInstall.exe; the native host removes it.
local _dirExeHome = DEFAULT_PATH .. "\\Uninstall"
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
    _dirInstall = NormalizePath(NonEmpty(installPath) or DEFAULT_PATH)
    if _dirInstall:match("^%a:$") then _dirInstall = _dirInstall .. "\\" end
    _dirHost = Join(_dirInstall, "Host")
    _dirExeHome = Join(_dirInstall, "Uninstall")
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

-- Remove the given entries from the system PATH (reverse of Install's SysPathAdd). RegSetValue
-- keeps PATH a REG_EXPAND_SZ.
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
    return SamePath(exe, Join(_dirHost, "KeelHost.exe")) or SamePath(exe, Join(_dirHost, "HostVM.exe"))
end

local function serviceRunning(name)
    local state = installx.ServiceState(name)
    return state == "running" or state == "start_pending" or state == "continue_pending"
end

local function hostCommand(args, waitSec)
    installx.LogPrint("KeelHost.exe " .. args)
    installx.ProcessExecute("\"" .. Join(_dirHost, "KeelHost.exe") .. "\" " .. args, true, waitSec)
end

function OnInitialize()
    resetInstallPath(regGet(PRODUCT_KEY, "InstallPath"))
    _serviceName = NonEmpty(regGet(PRODUCT_KEY, "ServiceName")) or DEFAULT_SERVICE

    local acp = installx.SysACP()
    if acp == 936 then
        _strResource = _strResourceCN
    else
        _strResource = _strResourceEN
    end

    installx.LogPrint("UnInstall OnInitialize, install path: " .. _dirInstall .. ", service: " .. _serviceName)
end

function PreSetup()
    installx.LogPrint("UnInstall PreSetup begin")

    -- 1. KeelBase's KeelHost service: "service stop" waits until it and its workers have stopped.
    if ServiceIsOurs() then
        if serviceRunning(_serviceName) then
            hostCommand("service stop " .. _serviceName, 120)
        end
        hostCommand("service remove " .. _serviceName, 60)
    end

    -- 2. The program directories. Data\ stays; Uninstall\ is the native host's.
    deleteIfExists(_dirHost)
    deleteIfExists(Join(_dirInstall, "Tools"))
    deleteIfExists(Join(_dirInstall, "Redist"))

    -- 3. Registry and PATH.
    removePathEntries(Join(_dirInstall, "Tools"))
    installx.RegDeleteKey(HRootKey.HKEY_LOCAL_MACHINE, "Software\\TaijiControl", "KeelBase")
    installx.RegDeleteKey(HRootKey.HKEY_LOCAL_MACHINE, UNINSTALL_KEY, "KeelBase")

    installx.LogPrint("UnInstall PreSetup done, exe home left for native cleanup: " .. _dirExeHome)
end

function PostSetup()
end

function OnButtonClick(btnName)
end

function QueryByKey(keyName)
    if keyName == "InstallPath" then
        return _dirInstall
    elseif keyName == "AppHome" then
        return _dirExeHome
    end
end
