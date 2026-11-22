-- KeelBase setup script.
-- HRootKey, CSIDL, RunBatchFile, ErrorHint are provided by the framework base library.
--
-- KeelBase runs on Windows as a module of KeelHost (still called HostVM there: HostVM.exe, hostvm.xml,
-- the Windows service HostVM and the directory <InstallPath>\HostVM keep their names for one major
-- version, ymwang78/KeelHost#49). This setup installs:
--   HostVM\                         KeelHost itself and its default site config (KeelBase.Host)
--   HostVM\modules\KeelBase\        the KeelBase module plugin (KeelBase.Server)
--   HostVM\keelhost.d\020-kbase.xml the instance kbase01, from its .template (KeelBase.Server)
--   KeelBase\                       the uninstaller (Common.Runtime) and kbased / kbasecli (KeelBase.Tools)
--   Common\vcredist, Common\opc     the VC++ runtime and the OPC Core Components installers
-- It shares <InstallPath>, HostVM\ and the HostVM service with TaijiMPC6, whose installer seeds the
-- same hostvm.xml and only looks at hostvm.d\, so the KeelBase fragment goes to keelhost.d\.
--
-- Command line (also for a silent /s install):
--   /path=<dir>         install root instead of the recorded or default one
--   /service=<name>     Windows service name of KeelHost instead of the recorded one or HostVM
--   /components=<list>  groups ("KeelBase") and items ("KeelBase.Tools") besides the required ones

-- Resource ID constants (mirrors resource.h)
local RES = {
    LICENSE  = 133,  -- IDR_REGCONTENT1
    BACKGROUND = 138, -- IDB_RES_BACKGROUND
}

-- build_KeelBaseSetup.py writes the release version and the version of the bundled
-- vc_redist.x64.exe here at build time and restores them afterwards.
local _VERSION = "3.0.0.1"
local VC_REDIST_VERSION = "14.52.37029.0"

local DEFAULT_ROOT = "C:\\TaijiControl"
local DEFAULT_SERVICE = "HostVM"
local SHARED_KEY = "Software\\TaijiControl"            -- InstallPath, shared with TaijiMPC6
local PRODUCT_KEY = SHARED_KEY .. "\\KeelBase"          -- InstallPath, Version, ServiceName
local COMPONENTS_KEY = PRODUCT_KEY .. "\\Components"    -- "Group.Item" = version that installed it
local UNINST_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\KeelBase"

-- Files of the HostVM directory this setup reads or writes, relative to it.
local HOST_DEFAULT_CONFIG = "hostvm.default.xml"
local HOST_CONFIGS = {"hostvm.xml", "keelhost.xml"}     -- main config: KeelHost refuses to start with both
local FRAGMENT_DIRS = {"keelhost.d", "hostvm.d"}
local KBASE_FRAGMENT = "keelhost.d\\020-kbase.xml"
local KBASE_FRAGMENT_TEMPLATE = KBASE_FRAGMENT .. ".template"

local _dirCompany = DEFAULT_ROOT
local _dirHostVM = DEFAULT_ROOT .. "\\HostVM"
local _dirKeelBase = DEFAULT_ROOT .. "\\KeelBase"
local _serviceName = DEFAULT_SERVICE

local _bCustomPath = false

local _strResourceCN = {
	SETUP = "KeelBase 安装程序",
	CHOOSE_INSTALL_PATH = "选择安装路径",
	LICENSE = "安装许可协议",
	COMPONENTS = "选择安装组件",
	COMPONENTS_BACK = "返回",
	SPACE_NOT_ENOUGH = "系统空间不足",
	SPACE_HINT = "安装位置空间不足：需要约 %s，可用 %s，请另外选择安装位置",
	SPACE_LABEL = "所需空间约 %s，可用 %s",
	MKDIR_FAILED = "创建目录失败: ",
	LOADING = "正在加载",
	HOST_CONFIG_FAILED = "无法生成 KeelHost 配置文件: ",
	FRAGMENT_FAILED = "无法生成 KeelBase 实例配置: ",
	FRAGMENT_CONFLICT = "KeelBase 实例配置与现有 KeelHost 配置部分重名，请先处理: ",
	SERVICE_TAKEN = "Windows 服务 %s 属于另一处安装（%s），请安装到那个目录，或用 /service= 换一个服务名",
	BAD_SERVICE_NAME = "服务名只能包含字母、数字、点、下划线和减号: ",
	BAD_PATH = "安装路径必须是本机磁盘上的绝对路径: ",
	REQUIRED = "必装",
	INSTALLED = "已安装",
	INSTALLED_VERSION = "已安装版本 %s",
	NOTHING_SELECTED = "请至少选择一个组件",
	UNKNOWN_COMPONENT = "未知组件: ",
	UNAVAILABLE_COMPONENT = "本安装包无法安装的组件: ",
	HINT_ADDED = "已同时选择 %s（%s 需要）",
	HINT_REMOVED = "已同时取消 %s（它需要 %s）",
	HINT_MISSING = "无法选择 %s：安装包不含 %s",
	LIST_SEP = "、",
	HINT_SEP = "；",
}

local _strResourceEN = {
	SETUP = "KeelBase Setup",
	CHOOSE_INSTALL_PATH = "Choose Install Path",
	LICENSE = "License Agreement",
	COMPONENTS = "Select Components",
	COMPONENTS_BACK = "Back",
	SPACE_NOT_ENOUGH = "System space is not enough",
	SPACE_HINT = "Not enough space at the install path: needs about %s, %s free. Please choose another install path",
	SPACE_LABEL = "Needs about %s, %s free",
	MKDIR_FAILED = "Make dir failed: ",
	LOADING = "Loading",
	HOST_CONFIG_FAILED = "Failed to create the KeelHost config: ",
	FRAGMENT_FAILED = "Failed to create the KeelBase instance config: ",
	FRAGMENT_CONFLICT = "The KeelBase instance config partly clashes with the KeelHost config; resolve it first: ",
	SERVICE_TAKEN = "The Windows service %s belongs to another installation (%s). Install into that directory, or choose another service name with /service=",
	BAD_SERVICE_NAME = "A service name may only contain letters, digits, dots, underscores and dashes: ",
	BAD_PATH = "The install path must be an absolute path on a local drive: ",
	REQUIRED = "required",
	INSTALLED = "installed",
	INSTALLED_VERSION = "Installed version %s",
	NOTHING_SELECTED = "Select at least one component",
	UNKNOWN_COMPONENT = "Unknown component: ",
	UNAVAILABLE_COMPONENT = "Components this installer cannot install: ",
	HINT_ADDED = "Also selected %s (needed by %s)",
	HINT_REMOVED = "Also deselected %s (it needs %s)",
	HINT_MISSING = "Cannot select %s: this installer lacks %s",
	LIST_SEP = ", ",
	HINT_SEP = "; ",
}

local _strResource = _strResourceCN
local _lang = 1  -- index into the {Chinese, English} name pairs below

----------------------------------------------------------------------------------------------------
-- Paths

-- "C:\\Dir\\" -> "C:\\Dir"; forward slashes become backslashes. A drive root keeps its backslash.
local function NormalizePath(path)
    local value = tostring(path or ""):gsub("/", "\\")
    value = value:gsub("\\+$", "")
    if value:match("^%a:$") then value = value .. "\\" end
    return value
end

local function SamePath(a, b)
    return a ~= nil and b ~= nil and NormalizePath(a):lower() == NormalizePath(b):lower()
end

-- An absolute path on a drive ("C:\\..."); UNC and relative paths are refused, since the KeelHost
-- service runs as LocalSystem and cannot use a mapped drive or another machine's share.
local function IsLocalAbsolutePath(path)
    return tostring(path or ""):match("^%a:\\") ~= nil
end

local function Join(dir, name)
    if dir:sub(-1) == "\\" then return dir .. name end
    return dir .. "\\" .. name
end

function ResetInstallPath(installPath)
    _dirCompany = NormalizePath(installPath)
    _dirHostVM = Join(_dirCompany, "HostVM")
    _dirKeelBase = Join(_dirCompany, "KeelBase")
end

local function NonEmpty(value)
    if value == nil or value == true or value == false then return nil end
    value = tostring(value)
    if value == "" then return nil end
    return value
end

-- /path=, else where this setup installed KeelBase before, else the root other TaijiControl products
-- use, so that they share one HostVM directory and service, else the default.
function DefaultInstallPath()
    return NonEmpty(installx.SysGetArg("path"))
        or NonEmpty(installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, PRODUCT_KEY, "InstallPath"))
        or NonEmpty(installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, SHARED_KEY, "InstallPath"))
        or DEFAULT_ROOT
end

function DefaultServiceName()
    return NonEmpty(installx.SysGetArg("service"))
        or NonEmpty(installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, PRODUCT_KEY, "ServiceName"))
        or DEFAULT_SERVICE
end

-- The name goes into command lines and a registry path.
function ValidServiceName(name)
    return type(name) == "string" and name:match("^[%w%._%-]+$") ~= nil and #name <= 80
end

----------------------------------------------------------------------------------------------------
-- Components
--
-- The component page lists these groups and items. Every item is one INSTALLSOFT archive (res: its
-- ID in resource.h, file name in Install.rc); archives keep their paths relative to the install
-- root, so the installed layout does not depend on what was selected. A group only gathers its
-- items. The skin's controls are grp_<group> and item_<group>_<item>.
--   required  always installed; its checkbox is disabled
--   deps      items it cannot run without. Selecting it also selects those that are not
--             installed yet; deselecting one of those also deselects it
--   marker    path under the install root that exists once the item is installed
-- An item whose archive this installer does not carry (installx.PackageInfo returns nil) is hidden.
local COMPONENTS = {
    { id = "Common", name = {"公共组件", "Common"}, items = {
        { id = "Runtime", res = 150, required = true, marker = "KeelBase\\UnInstall.exe",
          name = {"基础运行库", "Runtime"},
          desc = {"VC++ 运行库和卸载程序", "VC++ runtime and the uninstaller"} },
        { id = "OpcCore", res = 151, marker = "Common\\opc\\GBDA_Install_Prereq_x64.msi",
          name = {"OPC 核心组件", "OPC Core Components"},
          desc = {"OPC DA/HDA 接口代理与 OpcEnum。KeelBase 的 OPC DA/HDA 服务和它的客户端都需要",
                  "OPC DA/HDA proxies and OpcEnum, needed by KeelBase's OPC DA/HDA server and its clients"} },
    }},
    { id = "KeelBase", name = {"KeelBase", "KeelBase"}, items = {
        { id = "Host", res = 160, marker = "HostVM\\HostVM.exe",
          name = {"KeelHost 服务", "KeelHost service"},
          desc = {"运行 KeelBase 实例的后台服务（Windows 服务 HostVM）",
                  "Background service that runs the KeelBase instances (Windows service HostVM)"} },
        { id = "Server", res = 161, marker = "HostVM\\modules\\KeelBase\\kh_keelbase.dll", deps = {"KeelBase.Host"},
          name = {"KeelBase 时序数据库", "KeelBase database"},
          desc = {"KeelBase 模块和默认实例 kbase01（REST 端口 8080，数据端口 9090）",
                  "The KeelBase module and the default instance kbase01 (REST port 8080, data port 9090)"} },
        { id = "Tools", res = 162, marker = "KeelBase\\kbased.exe",
          name = {"命令行工具", "Command-line tools"},
          -- kbasecli.exe goes along when the build has one (KeelBase has no Windows project for it yet).
          desc = {"独立运行的 kbased 等命令行工具", "Standalone kbased and other command-line tools"} },
    }},
}

local MB = 1024 * 1024
-- A group whose items are only partly selected draws a blue square inside its empty checkbox:
-- a solid patch of the checked checkbox in setup.png (IDB_RES_PNG), scaled into the middle.
local PARTIAL_IMAGE = "res='130' restype='png' source='602,3,606,7' dest='5,5,13,13'"

local _order = {}      -- items in page order
local _items = {}      -- "Group.Item" -> item
local _selected = {}   -- "Group.Item" -> true when it is to be installed in this run
local _installed = {}  -- "Group.Item" -> true when its marker exists under the install path
local _hint = nil      -- what the last click selected or deselected besides the clicked item
local _argError = nil  -- unknown names in /components, a bad /service or /path

local function L(pair)
    return pair[_lang] or pair[1]
end

local function FormatSize(bytes)
    if bytes >= 1024 * MB then
        return string.format("%.1f GB", bytes / (1024 * MB))
    end
    return string.format("%d MB", math.max(1, math.ceil(bytes / MB)))
end

-- true: always selected (required); nil: up to the user.
local function LockedState(item)
    if item.required then return true end
    return nil
end

local function GroupById(groupId)
    for _, group in ipairs(COMPONENTS) do
        if group.id:lower() == tostring(groupId):lower() then return group end
    end
end

function RefreshInstalledComponents()
    for _, item in ipairs(_order) do
        _installed[item.key] = installx.FilePathExists(Join(_dirCompany, item.marker)) == true
        if LockedState(item) ~= nil or item.info == nil then
            _selected[item.key] = (LockedState(item) == true and item.info ~= nil) or nil
        end
    end
end

-- Components this setup recorded when it installed KeelBase into the current install path.
local function RecordedComponents()
    local recorded, any = {}, false
    if not SamePath(installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, PRODUCT_KEY, "InstallPath"), _dirCompany) then
        return recorded, false
    end
    for _, item in ipairs(_order) do
        if NonEmpty(installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, COMPONENTS_KEY, item.key)) then
            recorded[item.key] = true
            any = true
        end
    end
    return recorded, any
end

-- Reads which archives the installer carries and what is installed, and selects the defaults:
-- everything for a first install, what this setup installed last time for an upgrade. Another
-- product's HostVM in the same directory does not make it an upgrade: the KeelBase module is built
-- against the KeelHost in this package, so the host is selected too.
function LoadComponents()
    _order, _items, _selected, _installed, _hint = {}, {}, {}, {}, nil
    for _, group in ipairs(COMPONENTS) do
        group.control = "grp_" .. group.id
        for _, item in ipairs(group.items) do
            item.group = group
            item.key = group.id .. "." .. item.id
            item.control = "item_" .. group.id .. "_" .. item.id
            item.info = installx.PackageInfo(item.res)
            if item.info == nil then
                installx.LogPrint("Component " .. item.key .. " not in this installer (resource " .. item.res .. ")")
            end
            table.insert(_order, item)
            _items[item.key] = item
        end
    end
    RefreshInstalledComponents()
    local recorded, upgrade = RecordedComponents()
    for _, item in ipairs(_order) do
        if item.info and LockedState(item) == nil and (not upgrade or recorded[item.key]) then
            -- Through SelectComponent: an item whose dependency is neither installed nor in this
            -- installer stays deselected.
            SelectComponent(item.key, true)
        end
    end
end

local function NewNotes()
    return {added = {}, removed = {}, missing = {}}
end

local function DependsOn(item, key)
    for _, dep in ipairs(item.deps or {}) do
        if dep == key then return true end
    end
    return false
end

-- Selects or deselects one item and whatever its dependencies require; notes (optional) collects
-- those extra changes for the hint line. Returns whether the item ends up as asked.
function SelectComponent(key, on, notes)
    local item = _items[key]
    if item == nil or item.info == nil then return false end
    local locked = LockedState(item)
    if locked ~= nil then
        return locked == on
    end
    if on then
        if _selected[key] then return true end
        for _, dep in ipairs(item.deps or {}) do
            local depItem = _items[dep]
            if not _installed[dep] and (depItem == nil or depItem.info == nil) then
                if notes then table.insert(notes.missing, {key, dep}) end
                return false
            end
        end
        _selected[key] = true
        for _, dep in ipairs(item.deps or {}) do
            if not _selected[dep] and not _installed[dep] then
                SelectComponent(dep, true, notes)
                if notes then table.insert(notes.added, {dep, key}) end
            end
        end
    else
        if not _selected[key] then return true end
        _selected[key] = nil
        if not _installed[key] then
            for _, other in ipairs(_order) do
                if _selected[other.key] and DependsOn(other, key) then
                    SelectComponent(other.key, false, notes)
                    if notes then table.insert(notes.removed, {other.key, key}) end
                end
            end
        end
    end
    return true
end

-- "all", "none" or "partial", over the items the user can have: a required item counts as selected.
function ComponentGroupState(groupId)
    local group = GroupById(groupId)
    local total, chosen = 0, 0
    for _, item in ipairs(group and group.items or {}) do
        if item.info then
            total = total + 1
            if _selected[item.key] then chosen = chosen + 1 end
        end
    end
    if total > 0 and chosen == total then return "all" end
    if chosen == 0 then return "none" end
    return "partial"
end

-- A click on a group selects all its items, or deselects them when all were selected.
function SelectComponentGroup(groupId, notes)
    local group = GroupById(groupId)
    if group == nil then return end
    local on = ComponentGroupState(group.id) ~= "all"
    for _, item in ipairs(group.items) do
        if item.info and LockedState(item) == nil then
            SelectComponent(item.key, on, notes)
        end
    end
end

-- /components=<names>: exactly the named groups and items (and what they need) besides the
-- required ones. Returns the names it does not know, and the requested items it cannot install
-- (no archive in this installer, or a dependency that is neither installed nor in it).
function ApplyComponentArg(text)
    _selected = {}
    for _, item in ipairs(_order) do
        if item.info and LockedState(item) == true then _selected[item.key] = true end
    end
    local unknown, unavailable = {}, {}
    for token in tostring(text):gmatch("[^,;%s]+") do
        local wanted = token:lower()
        local found = false
        for _, item in ipairs(_order) do
            if item.group.id:lower() == wanted or item.key:lower() == wanted then
                found = true
                if not SelectComponent(item.key, true) and not _installed[item.key] then
                    table.insert(unavailable, item.key)
                end
            end
        end
        if not found then table.insert(unknown, token) end
    end
    return unknown, unavailable
end

-- Selects the missing dependencies of every selected item again, or deselects an item whose
-- dependency cannot be had. Needed after the install path changes: a dependency that was
-- installed at the old path (so not selected) may be missing at the new one.
function ReconcileComponentDependencies(notes)
    local changed = true
    while changed do
        changed = false
        for _, item in ipairs(_order) do
            if _selected[item.key] and LockedState(item) == nil then
                for _, dep in ipairs(item.deps or {}) do
                    if not _selected[dep] and not _installed[dep] then
                        changed = true
                        local depItem = _items[dep]
                        if depItem and depItem.info and SelectComponent(dep, true, notes) then
                            if notes then table.insert(notes.added, {dep, item.key}) end
                        else
                            _selected[item.key] = nil
                            if notes then table.insert(notes.missing, {item.key, dep}) end
                            break
                        end
                    end
                end
            end
        end
    end
end

function ComponentSelected(key)
    return _selected[key] == true
end

-- Installed on this machine once this run is done.
function ComponentPresent(key)
    return _selected[key] == true or _installed[key] == true
end

-- The archives this run extracts, biggest first: the extractor runs a few at a time, and the
-- biggest archive started last would finish last.
function ComponentPlan()
    local plan = {}
    for _, item in ipairs(_order) do
        if _selected[item.key] and item.info then table.insert(plan, item) end
    end
    table.sort(plan, function(a, b)
        if a.info.size ~= b.info.size then return a.info.size > b.info.size end
        return a.res < b.res
    end)
    return plan
end

-- Bytes the install path must have free: all of a new component, a tenth of one that is
-- overwritten (only its growth), and room for the KeelBase instance's first data files
-- (its container and WAL are preallocated: about 4.2 GB with the defaults).
local INSTANCE_DATA_BYTES = 4500 * MB
function ComponentSpaceNeeded()
    local need = 100 * MB
    for _, item in ipairs(ComponentPlan()) do
        if _installed[item.key] then
            need = need + item.info.size // 10
        else
            need = need + item.info.size
        end
    end
    if ComponentSelected("KeelBase.Server") and not _installed["KeelBase.Server"] then
        need = need + INSTANCE_DATA_BYTES
    end
    return need
end

local function FreeSpaceAt(path)
    local root = tostring(path):match("^%a:\\") or tostring(path):match("^%a:$")
    if root and #root == 2 then root = root .. "\\" end
    return installx.DiskFreeSpace(root or path)
end

local function DescribeNotes(notes)
    local function names(keys)
        local list = {}
        for _, key in ipairs(keys) do table.insert(list, L(_items[key].name)) end
        return table.concat(list, _strResource.LIST_SEP)
    end
    local parts = {}
    -- Group the items added for one dependent: "selected A, B (needed by C)".
    local addedBy, addedOrder = {}, {}
    for _, entry in ipairs(notes.added) do
        if addedBy[entry[2]] == nil then
            addedBy[entry[2]] = {}
            table.insert(addedOrder, entry[2])
        end
        table.insert(addedBy[entry[2]], entry[1])
    end
    for _, by in ipairs(addedOrder) do
        table.insert(parts, string.format(_strResource.HINT_ADDED, names(addedBy[by]), L(_items[by].name)))
    end
    for _, entry in ipairs(notes.removed) do
        table.insert(parts, string.format(_strResource.HINT_REMOVED, L(_items[entry[1]].name), L(_items[entry[2]].name)))
    end
    for _, entry in ipairs(notes.missing) do
        local dep = _items[entry[2]]
        table.insert(parts, string.format(_strResource.HINT_MISSING, L(_items[entry[1]].name), dep and L(dep.name) or entry[2]))
    end
    if #parts == 0 then return nil end
    return table.concat(parts, _strResource.HINT_SEP)
end

local function ComponentLabel(item)
    local text = L(item.name) .. "  " .. FormatSize(item.info.size)
    if item.required then
        text = text .. " · " .. _strResource.REQUIRED
    elseif _installed[item.key] then
        text = text .. " · " .. _strResource.INSTALLED
    end
    return text
end

local function ComponentTooltip(item)
    local text = L(item.desc)
    if _installed[item.key] then
        local version = installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, COMPONENTS_KEY, item.key)
        if version ~= nil and version ~= "" then
            text = text .. "\n" .. string.format(_strResource.INSTALLED_VERSION, tostring(version))
        end
    end
    return text
end

local function SetAttribute(control, name, value)
    if installx.DuiAttribute then installx.DuiAttribute(control, name, value) end
end

-- Writes the selection state into the component page. DuiOptionSelect(..., false) does not send
-- selectchanged, so this does not re-enter OnSelChanged.
function RefreshComponentPage()
    for _, group in ipairs(COMPONENTS) do
        local shown, selectable = false, false
        for _, item in ipairs(group.items) do
            installx.DuiVisible(item.control, item.info ~= nil)
            if item.info then
                shown = true
                local locked = LockedState(item)
                selectable = selectable or locked == nil
                installx.DuiText(item.control, ComponentLabel(item))
                installx.DuiOptionSelect(item.control, _selected[item.key] == true, false)
                installx.DuiEnable(item.control, locked == nil)
                SetAttribute(item.control, "tooltip", ComponentTooltip(item))
            end
        end
        local state = ComponentGroupState(group.id)
        installx.DuiVisible(group.control, shown)
        installx.DuiText(group.control, L(group.name))
        installx.DuiOptionSelect(group.control, state == "all", false)
        installx.DuiEnable(group.control, selectable)
        SetAttribute(group.control, "foreimage", state == "partial" and PARTIAL_IMAGE or "")
    end
    installx.DuiText("compbackbtn", _strResource.COMPONENTS_BACK)
    installx.DuiText("comphintlab", _hint or "")
    installx.DuiTextColor("comphintlab", 0xFF5DA5FF)
    local need, free = ComponentSpaceNeeded(), FreeSpaceAt(_dirCompany)
    installx.DuiText("compspacelab", string.format(_strResource.SPACE_LABEL, FormatSize(need), free and FormatSize(free) or "?"))
    installx.DuiTextColor("compspacelab", (free and free < need) and 0xFFFF0000 or 0xFF7F7F7F)
end

----------------------------------------------------------------------------------------------------
-- Pages

local function ShowMainPage()
    installx.DuiTabSelect("installlayout", 0)
    installx.DuiVisible("sureportlayout", true)
    installx.DuiVisible("custombtn", true)
    installx.DuiText("titletext", _strResource.SETUP)
    installx.DuiTextColor("titletext", 0xFFFFFFFF)
    installx.DuiSetBkImage("mainlayout", "res='" .. RES.BACKGROUND .. "' restype='png' source='0,0,600,221' corner='300,208,5,5'")
end

local function ShowComponentPage()
    if (installx.DuiVisible("customlayout")) then
        CustomLayeroutHide()
    end
    installx.DuiTabSelect("installlayout", 2)
    -- The page uses the height of the bottom bar, whose links do not apply to it.
    installx.DuiVisible("sureportlayout", false)
    installx.DuiText("titletext", _strResource.COMPONENTS)
    installx.DuiTextColor("titletext", 0xFF5DA5FF)
    installx.DuiSetBkImage("mainlayout", "res='" .. RES.BACKGROUND .. "' restype='png' source='20,210,80,216'")
    RefreshComponentPage()
end

local function AddArgError(problems, message)
    table.insert(problems, message)
end

function OnInitialize()
	local acp = installx.SysACP()
	if acp == 936 then
		_strResource, _lang = _strResourceCN, 1
	else
		_strResource, _lang = _strResourceEN, 2
	end
	installx.LogPrint("ACP: ", acp)

	local problems = {}
	local path = DefaultInstallPath()
	if not IsLocalAbsolutePath(path) then
		AddArgError(problems, _strResource.BAD_PATH .. tostring(path))
		path = DEFAULT_ROOT
	end
	ResetInstallPath(path)
	installx.DuiText("pathedit", _dirCompany)

	_serviceName = DefaultServiceName()
	if not ValidServiceName(_serviceName) then
		AddArgError(problems, _strResource.BAD_SERVICE_NAME .. tostring(_serviceName))
		_serviceName = DEFAULT_SERVICE
	end
	installx.LogPrint("Install path " .. _dirCompany .. ", KeelHost service " .. _serviceName)

	LoadComponents()
	local arg = installx.SysGetArg("components")
	if type(arg) == "string" then
		local unknown, unavailable = ApplyComponentArg(arg)
		if #unknown > 0 then
			AddArgError(problems, _strResource.UNKNOWN_COMPONENT .. table.concat(unknown, ", "))
		end
		if #unavailable > 0 then
			AddArgError(problems, _strResource.UNAVAILABLE_COMPONENT .. table.concat(unavailable, ", "))
		end
	end
	if #problems > 0 then
		-- A silent install refuses to start rather than install something else than asked; with
		-- the page the user can correct the selection or the path.
		_argError = table.concat(problems, _strResource.HINT_SEP)
		installx.LogPrint(_argError)
		ErrorHint(_argError)
	end
	RefreshComponentPage()
end

function OnButtonClick(btnName)
	installx.LogPrint("OnButtonClick: ", btnName)
    if (btnName == "custombtn") then
        _bCustomPath = not _bCustomPath
        installx.DuiVisible("customlayout", _bCustomPath)
        if (_bCustomPath) then
            installx.DuiWindowPos("_MainFrame", 0, 0, 600, 428)
        else
            installx.DuiWindowPos("_MainFrame", 0, 0, 600, 380)
        end
    elseif (btnName == "browfilebtn") then
        local installPath = installx.FilePathChoose(_strResource.CHOOSE_INSTALL_PATH, _dirCompany)
        if installPath ~= nil and installPath ~= "" then
            if not IsLocalAbsolutePath(installPath) then
                ErrorHint(_strResource.BAD_PATH .. installPath)
                return
            end
            ResetInstallPath(installPath)
            installx.DuiText("pathedit", _dirCompany)
            -- Installed components, and so dependencies and space, belong to the install path.
            RefreshInstalledComponents()
            local notes = NewNotes()
            ReconcileComponentDependencies(notes)
            _hint = DescribeNotes(notes)
            RefreshComponentPage()
        end
    elseif (btnName == "closebtn") then
        if (installx.DuiTabSelect("installlayout") > 0) then
            ShowMainPage()
        else
            installx.DuiMessage(0x10, 0, 0) -- WM_CLOSE
        end
    elseif (btnName == "nextbtn") then
        -- Step two: the components; starinstallbtn on that page starts the installation.
        ShowComponentPage()
    elseif (btnName == "compbackbtn") then
        ShowMainPage()
    elseif (btnName == "lookprotbtn") then
        if (installx.DuiVisible("customlayout")) then
            CustomLayeroutHide()
        end
        installx.DuiTabSelect("installlayout", 1)
        installx.DuiVisible("custombtn", false)
        installx.DuiText("titletext", _strResource.LICENSE)
        installx.DuiTextColor("titletext", 0xFF5DA5FF)
        installx.DuiText("portcontent", RES.LICENSE)
        installx.DuiSetBkImage("mainlayout", "res='" .. RES.BACKGROUND .. "' restype='png' source='20,210,80,216'")
    elseif (btnName == "starinstallbtn") then
        StartSetup()
    elseif (btnName == "starusebtn") then
        _FinishInstall()
    end
end

function OnSelChanged(btnName, isSelected)
    if (btnName == "protcheckbtn") then
        installx.DuiEnable("nextbtn", isSelected)
        return
    end
    local groupId = btnName:match("^grp_(%w+)$")
    local groupOfItem, itemId = btnName:match("^item_(%w+)_(%w+)$")
    if groupId == nil and groupOfItem == nil then
        return
    end
    -- The option has already flipped itself; the page is redrawn from the selection either way.
    -- Once the user picks components, a bad /components argument no longer matters; a bad /service
    -- or /path was already replaced by the default.
    if _argError then
        _argError = nil
        installx.DuiVisible("errortiplab", false)
    end
    local notes = NewNotes()
    if groupId then
        SelectComponentGroup(groupId, notes)
    else
        SelectComponent(groupOfItem .. "." .. itemId, isSelected, notes)
    end
    _hint = DescribeNotes(notes)
    RefreshComponentPage()
end

local _image_index = 0
local _lastPercent = 0   -- prevents progress bar going backwards during parallel extraction
local _unzipTotal = 0    -- unpacked bytes of the archives being extracted
local _unzipDone = 0

-- Extraction runs from 5% to 92%, by unpacked bytes over all selected archives: one message per
-- archive entry, nCurrentSize being that entry's size.
function OnUnzipProgress(nNotifyID, nTotalFileNum, nCurFileIndex, nTotalSize, nCurrentSize)
	-- The completion callback (-1) does not move the bar; PostSetup takes it from here.
	if nCurFileIndex == -1 or nTotalFileNum == -1 then
		return
	end
	_unzipDone = _unzipDone + (nCurrentSize or 0)
	if _unzipTotal <= 0 then
		return
	end
	local percent = 5 + math.floor(87 * math.min(_unzipDone, _unzipTotal) / _unzipTotal)
	-- Clamp to avoid backwards steps when packages extract in parallel
	if percent <= _lastPercent then return end
	_lastPercent = percent

	local bgRes = "res='" .. RES.BACKGROUND .. "' restype='png'"
	if _image_index < 3 and percent > 80 then
		_image_index = 3
		installx.DuiSetBkImage("mainlayout", bgRes .. " source='0,666,600,886' corner='300,208,5,5'")
	elseif _image_index < 2 and percent > 50 then
		_image_index = 2
		installx.DuiSetBkImage("mainlayout", bgRes .. " source='0,444,600,664' corner='300,208,5,5'")
	elseif _image_index < 1 and percent > 15 then
		_image_index = 1
		installx.DuiSetBkImage("mainlayout", bgRes .. " source='0,222,600,442' corner='300,208,5,5'")
	end
	installx.DuiProgress("installprogress", percent, _strResource.LOADING  .. " " .. percent .. "%" )
end

-- Returns false and the message to show when the system drive or the install path lacks space.
function CheckDiskSpace()
    local freeSystemSpace = installx.DiskFreeSpace("")
    if (freeSystemSpace ~= nil and freeSystemSpace <= 10*1024*1024) then
        return false, _strResource.SPACE_NOT_ENOUGH
    end
    -- An unknown free space (the drive cannot be queried) does not block the install.
    local need, free = ComponentSpaceNeeded(), FreeSpaceAt(_dirCompany)
    if (free ~= nil and free < need) then
        return false, string.format(_strResource.SPACE_HINT, FormatSize(need), FormatSize(free))
    end
    return true
end

function CustomLayeroutHide()
    installx.DuiVisible("customlayout", false)
    installx.DuiWindowPos("_MainFrame", 0, 0, 600, 380)
end

----------------------------------------------------------------------------------------------------
-- The KeelHost service

local _hostExisted = false    -- the service existed before this run
local _restartHost = false    -- it was running and was stopped only to replace files it loads

local function ServiceKey(name)
    return "SYSTEM\\CurrentControlSet\\Services\\" .. name
end

local function ServiceExists(name)
    return installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, ServiceKey(name), "") ~= nil
end

-- Whether a service is running (or on its way there). A pause for an upgrade of files it loads
-- restores exactly this: a service an administrator stopped stays stopped.
local function ServiceRunning(name)
    local state = installx.ServiceState(name)
    return state == "running" or state == "start_pending" or state == "continue_pending"
end

-- The executable a service runs, from its ImagePath: "\"C:\\..\\HostVM.exe\" daemon HostVM", or the
-- same unquoted. nil when there is no such service.
function ServiceExecutable(name)
    local image = NonEmpty(installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, ServiceKey(name), "ImagePath"))
    if image == nil then return nil end
    local quoted = image:match('^%s*"([^"]+)"')
    if quoted then return quoted end
    return image:match("^%s*(.-%.[eE][xX][eE])") or image
end

-- A service of that name is fine when it does not exist or runs the KeelHost of this install path.
-- Anything else belongs to another installation, which this setup must neither stop nor replace.
function CheckServiceOwner()
    local exe = ServiceExecutable(_serviceName)
    if exe == nil then
        return true
    end
    for _, name in ipairs({"HostVM.exe", "KeelHost.exe"}) do
        if SamePath(exe, Join(_dirHostVM, name)) then return true end
    end
    return false, string.format(_strResource.SERVICE_TAKEN, _serviceName, exe)
end

local function HostCommand(args, waitSec)
    installx.LogPrint("HostVM.exe " .. args)
    installx.ProcessExecute("\"" .. Join(_dirHostVM, "HostVM.exe") .. "\" " .. args, true, waitSec or 60)
end

-- Stops the KeelHost service before its files or the KeelBase module it loads are replaced. The
-- service is not removed: an upgrade keeps whatever the site changed in it (account, recovery).
-- "service stop" waits until the service has stopped, workers included.
function StopSelectedComponents()
    _hostExisted = ServiceExists(_serviceName)
    _restartHost = false
    if not (ComponentSelected("KeelBase.Host") or ComponentSelected("KeelBase.Server")) then
        return
    end
    if _hostExisted then
        _restartHost = ServiceRunning(_serviceName)
        if _restartHost then
            HostCommand("service stop " .. _serviceName, 120)
        end
    end
end

function StartSetup()

	installx.LogPrint("Require Admin Promote ...")
    isAdmin = installx.RunAsAdmin()

    local function fail(message)
        ErrorHint(message)
        -- The installation starts from the component page: say it there too, in red, where the
        -- user can correct the selection. The next change on the page puts the hint back.
        if installx.DuiTabSelect("installlayout") == 2 then
            installx.DuiText("comphintlab", tostring(message))
            installx.DuiTextColor("comphintlab", 0xFFFF0000)
        end
        -- A silent install has nobody to correct the selection and would wait forever.
        if installx.SysGetArg("s") then installx.SetupFailed(message) end
    end
    if _argError then
        return fail(_argError)
    end
    -- The page keeps the selection consistent; this also covers any path the page did not see.
    ReconcileComponentDependencies()
    local plan, optional = ComponentPlan(), 0
    for _, item in ipairs(plan) do
        if not item.required then optional = optional + 1 end
    end
    if optional == 0 then
        return fail(_strResource.NOTHING_SELECTED)
    end

    local ownerOk, ownerError = CheckServiceOwner()
    if not ownerOk then
        return fail(ownerError)
    end

	installx.LogPrint("CheckDiskSpace ...")
    local spaceOk, spaceError = CheckDiskSpace()
    if not spaceOk then
        return fail(spaceError)
    end

	installx.LogPrint("Check Exists " .. _dirCompany .. " ...")
	if not installx.FilePathExists(_dirCompany) then
		installx.LogPrint("Makedir " .. _dirCompany .. " ...")
		if (not installx.FilePathMkdir(_dirCompany)) then
			return fail(_strResource.MKDIR_FAILED .. _dirCompany)
		end
	end

    StopSelectedComponents()

    if installx.DuiTabSelect("installlayout") > 0 then
        ShowMainPage()
    end
    CustomLayeroutHide()
    installx.DuiVisible("custombtn", false)
    installx.DuiVisible("errortiplab", false)

    installx.DuiEnable("closebtn", false)
    installx.DuiVisible("nextbtn", false)
    installx.DuiVisible("starinstallbtn", false)
    installx.DuiVisible("sureportlayout", false)
    installx.DuiVisible("installprogress", true)

	local resourceIDs = {}
	_unzipTotal, _unzipDone, _lastPercent = 0, 0, 0
	for _, item in ipairs(plan) do
		installx.LogPrint("Install component " .. item.key .. " (resource " .. item.res .. ", " .. FormatSize(item.info.size) .. ")")
		table.insert(resourceIDs, item.res)
		_unzipTotal = _unzipTotal + item.info.size
	end
	for _, item in ipairs(_order) do
		if item.info and not _selected[item.key] then
			installx.LogPrint("Skip component " .. item.key .. (_installed[item.key] and " (installed, kept as is)" or ""))
		end
	end
	installx.FilePathUnzip(resourceIDs, _dirCompany)
end

----------------------------------------------------------------------------------------------------
-- KeelHost configuration

-- The package ships HostVM\hostvm.default.xml (the site config seed every product line shares) but
-- never hostvm.xml: once a main config exists it belongs to the site (ports, threads, projects_dir),
-- so an upgrade keeps it. KeelHost reads keelhost.xml or, for one more major version, hostvm.xml,
-- and refuses to start when both exist, so neither is created next to the other. hostvm.xml is the
-- name TaijiMPC6's installer looks for. Returns false after showing the error when a first install
-- cannot get a main config.
function InstallHostConfig()
    for _, name in ipairs(HOST_CONFIGS) do
        local path = Join(_dirHostVM, name)
        if installx.FilePathExists(path) then
            installx.LogPrint("Keep existing KeelHost config: " .. path)
            return true
        end
    end
    local siteConfig = Join(_dirHostVM, HOST_CONFIGS[1])
    -- true: fail if it exists, which also protects a config created after the check above.
    if installx.FilePathCopy(Join(_dirHostVM, HOST_DEFAULT_CONFIG), siteConfig, true) then
        installx.LogPrint("Created KeelHost config from " .. HOST_DEFAULT_CONFIG)
        return true
    end
    ErrorHint(_strResource.HOST_CONFIG_FAILED .. siteConfig)
    return false
end

-- Subvm names declared in the main configs and in the XML fragments of keelhost.d\ and hostvm.d\
-- (KeelHost merges both). Returns nil and the file when one cannot be read: KeelHost would not
-- start with it either.
function DeclaredSubvmNames()
    local declared = {}
    for _, name in ipairs(HOST_CONFIGS) do
        local path = Join(_dirHostVM, name)
        if installx.FilePathExists(path) then
            local names = installx.HostVMSubvmNames(path, false)
            if names == nil then return nil, path end
            for _, vmname in ipairs(names) do declared[vmname] = path end
        end
    end
    for _, dir in ipairs(FRAGMENT_DIRS) do
        local directory = Join(_dirHostVM, dir)
        if installx.FilePathExists(directory) then
            local files = installx.FilePathListFiles(directory)
            if files == nil then return nil, directory end
            table.sort(files)
            for _, file in ipairs(files) do
                if file:lower():match("%.xml$") then
                    local path = Join(directory, file)
                    local names = installx.HostVMSubvmNames(path, true)
                    if names == nil then return nil, path end
                    for _, vmname in ipairs(names) do declared[vmname] = path end
                end
            end
        end
    end
    return declared
end

-- The instance kbase01 comes from keelhost.d\020-kbase.xml.template, copied to 020-kbase.xml on the
-- first install. An existing 020-kbase.xml is the site's (it may have been edited) and is kept.
-- When the site already declares every subvm of the template elsewhere (in hostvm.xml, say), the
-- fragment is not created: KeelHost refuses to start when a fragment repeats a declared name. Only
-- some of them declared is a conflict this setup cannot resolve. Returns false after showing the
-- error.
function InstallKeelBaseFragment()
    local fragment = Join(_dirHostVM, KBASE_FRAGMENT)
    local template = Join(_dirHostVM, KBASE_FRAGMENT_TEMPLATE)
    if installx.FilePathExists(fragment) then
        installx.LogPrint("Keep existing KeelBase instance config: " .. fragment)
        return true
    end
    local names = installx.HostVMSubvmNames(template, true)
    if names == nil or #names == 0 then
        ErrorHint(_strResource.FRAGMENT_FAILED .. template)
        return false
    end
    local declared, unreadable = DeclaredSubvmNames()
    if declared == nil then
        ErrorHint(_strResource.FRAGMENT_FAILED .. unreadable)
        return false
    end
    local overlaps, where = 0, {}
    for _, vmname in ipairs(names) do
        if declared[vmname] then
            overlaps = overlaps + 1
            table.insert(where, vmname .. " (" .. declared[vmname] .. ")")
        end
    end
    if overlaps == #names then
        installx.LogPrint("KeelBase instance already declared, not creating " .. fragment .. ": " .. table.concat(where, ", "))
        return true
    elseif overlaps > 0 then
        ErrorHint(_strResource.FRAGMENT_CONFLICT .. table.concat(where, ", "))
        return false
    end
    local ok, copyError = installx.FilePathCopy(template, fragment, true)
    if ok then
        installx.LogPrint("Created KeelBase instance config " .. fragment)
        return true
    end
    -- CopyFile can leave a partial destination; one that already existed (ERROR_FILE_EXISTS,
    -- ERROR_ALREADY_EXISTS) was written by someone else and is not ours to delete.
    if copyError ~= 80 and copyError ~= 183 and installx.FilePathExists(fragment) then
        installx.FilePathDelete(fragment)
    end
    ErrorHint(_strResource.FRAGMENT_FAILED .. fragment)
    return false
end

----------------------------------------------------------------------------------------------------
-- Runtimes

-- Numeric fields of a dotted version ("14.52.37025.0" -> {14, 52, 37025, 0}), or nil.
local function ParseVersion(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("^[vV]", "")
    local fields = {}
    for field in (text .. "."):gmatch("([^.]*)%.") do
        if not field:match("^%d+$") then
            return nil
        end
        table.insert(fields, tonumber(field))
    end
    return fields
end

-- True when dotted version `version` is older than `minimum`, compared field by field as numbers.
-- Missing trailing fields count as 0; a value that is not a dotted version counts as older.
function VersionOlderThan(version, minimum)
    local have, want = ParseVersion(version), ParseVersion(minimum)
    if have == nil then
        return true
    end
    for i = 1, math.max(#have, #want) do
        local a, b = have[i] or 0, want[i] or 0
        if a ~= b then
            return a < b
        end
    end
    return false
end

-- The x64 VC++ runtime this machine has, as "major.minor.build", or nil. The binaries need at least
-- the runtime of the toolset that built them, which is the one bundled.
local VC_RUNTIME_KEY = "SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64"
function InstalledVcRuntime()
    local function value(name) return installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, VC_RUNTIME_KEY, name) end
    if tonumber(value("Installed")) ~= 1 then
        return nil
    end
    local major, minor, build = tonumber(value("Major")), tonumber(value("Minor")), tonumber(value("Bld"))
    if major == nil or minor == nil or build == nil then
        return nil
    end
    return string.format("%d.%d.%d", major, minor, build)
end

function InstallVcRuntime()
    local installed = InstalledVcRuntime()
    -- The bundled redist's own file version has four fields; the registry has three.
    local bundled = VC_REDIST_VERSION:match("^(%d+%.%d+%.%d+)") or VC_REDIST_VERSION
    if installed ~= nil and not VersionOlderThan(installed, bundled) then
        installx.LogPrint("Skip VC++ runtime, " .. installed .. " installed")
        return
    end
    installx.ProcessExecute("\"" .. _dirCompany .. "\\Common\\vcredist\\vc_redist.x64.exe\" /install /quiet /norestart", true, 300)
end

-- OPC core components come in two Graybox packages, one per bitness, and each carries what the
-- other lacks: x86 has OpcEnum.exe (32-bit only), through which clients browse for servers, and the
-- 32-bit proxy/stubs for 32-bit clients; x64 has the 64-bit proxy/stubs, which the KeelBase OPC
-- DA/HDA server inside the 64-bit KeelHost needs to marshal its interfaces. Each is checked on its
-- own, so a machine where other OPC software installed one half still gets the other.
local OPC_IID_IOPCSERVER = "{39C13A4D-011E-11D0-9675-0020AFD8ADB3}"       -- proxy/stub in opcproxy.dll
local OPC_IID_IOPCSERVERLIST = "{13486D50-4821-11D2-A494-3CB306C10000}"   -- proxy/stub in opccomn_ps.dll
local OPC_CLSID_OPCSERVERLIST = "{13486D51-4821-11D2-A494-3CB306C10000}"  -- OpcEnum.exe

-- Default value of an HKCR key, or nil. Not RegGetValue(root, path, ""): that only reports that the
-- key exists, which an empty leftover key passes too.
local function RegDefault(path)
    local value = installx.RegGetDefaultValue(HRootKey.HKEY_CLASSES_ROOT, path)
    if value == nil or value == "" then
        return nil
    end
    return tostring(value)
end

-- True when the file a COM server registration points at exists. LocalServer32 may be quoted and
-- carry arguments. In the 32-bit view ("WOW6432Node\\") System32 means SysWOW64, which is where a
-- 32-bit process gets redirected; this installer is 64-bit and is not.
local function ComServerFileExists(view, serverPath)
    if serverPath == nil then
        return false
    end
    local path = serverPath:match('^"([^"]+)"') or serverPath
    if view ~= "" then
        local first, last = path:lower():find("\\system32\\", 1, true)
        if first then
            path = path:sub(1, first) .. "SysWOW64" .. path:sub(last)
        end
    end
    return installx.FilePathExists(path)
end

-- True when COM in the given registry view ("" or "WOW6432Node\\") can marshal the interface: it
-- names a proxy/stub class, and that class's DLL is on disk.
local function OpcProxyUsable(view, iid)
    local proxyClsid = RegDefault(view .. "Interface\\" .. iid .. "\\ProxyStubClsid32")
    if proxyClsid == nil then
        return false
    end
    return ComServerFileExists(view, RegDefault(view .. "CLSID\\" .. proxyClsid .. "\\InprocServer32"))
end

local function OpcProxiesUsable(view)
    return OpcProxyUsable(view, OPC_IID_IOPCSERVER) and OpcProxyUsable(view, OPC_IID_IOPCSERVERLIST)
end

-- OpcEnum is only ever registered in the 32-bit view.
local function OpcEnumUsable()
    local view = "WOW6432Node\\"
    return ComServerFileExists(view, RegDefault(view .. "CLSID\\" .. OPC_CLSID_OPCSERVERLIST .. "\\LocalServer32"))
end

function InstallOpcCoreComponents()
    local opcDir = _dirCompany .. "\\Common\\opc\\"
    if OpcProxiesUsable("") then
        installx.LogPrint("Skip OPC core components x64, already registered")
    else
        installx.ProcessExecute("\"" .. opcDir .. "GBDA_Install_Prereq_x64.msi\" /quiet /norestart", true, 300)
    end
    if OpcProxiesUsable("WOW6432Node\\") and OpcEnumUsable() then
        installx.LogPrint("Skip OPC core components x86, already registered")
    else
        installx.ProcessExecute("\"" .. opcDir .. "GBDA_Install_Prereq_x86.msi\" /quiet /norestart", true, 300)
    end
end

----------------------------------------------------------------------------------------------------
-- Post setup

local function Progress(percent)
	installx.DuiProgress("installprogress", percent, _strResource.LOADING  .. " " .. percent .. "%" )
end

local function SetBothViews(path, name, value)
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, "Software\\" .. path, name, value)
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, "Software\\WOW6432Node\\" .. path, name, value)
end

function WriteRegistry()
    -- The shared root is the default of every TaijiControl installer. It is written when no other
    -- product has set it; a different root of another product stays: it is where its HostVM is.
    if NonEmpty(installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, SHARED_KEY, "InstallPath")) == nil then
        SetBothViews("TaijiControl", "InstallPath", _dirCompany)
    end
    local function set(name, value)
        installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, PRODUCT_KEY, name, value)
    end
    set("InstallPath", _dirCompany)
    set("Version", _VERSION)
    set("ServiceName", _serviceName)
    for _, item in ipairs(_order) do
        if _selected[item.key] then
            installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, COMPONENTS_KEY, item.key, _VERSION)
        end
    end

    local uninstaller = Join(_dirKeelBase, "UnInstall.exe")
    local function uninst(name, value)
        installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, UNINST_KEY, name, value)
    end
    uninst("DisplayName", "KeelBase")
    uninst("DisplayVersion", _VERSION)
    uninst("Publisher", "Tai-Ji Soft")
    uninst("DisplayIcon", uninstaller)
    uninst("InstallLocation", _dirCompany)
    uninst("UninstallString", "\"" .. uninstaller .. "\"")
end

-- Returning false tells the installer that setup did not complete: it shows the failure and
-- enables the close button instead of moving on to the finish page. Every step belongs to a
-- selected component; nothing of a component that was not selected is touched.
function PostSetup()

    local host = ComponentSelected("KeelBase.Host")
    local server = ComponentSelected("KeelBase.Server")

    -- Without a main config KeelHost cannot start, and without its fragment the instance is not
    -- there. Checking them first means a failure stops before any runtime, registry or service is
    -- touched.
    if host and not InstallHostConfig() then
        return false
    end
    if server and not InstallKeelBaseFragment() then
        return false
    end

	Progress(94)
    InstallVcRuntime()

	Progress(95)
    if ComponentSelected("Common.OpcCore") then
        InstallOpcCoreComponents()
    end

	Progress(97)
    WriteRegistry()

	Progress(98)
    if host and not ServiceExists(_serviceName) then
        HostCommand("service install " .. _serviceName, 60)
    end
    if host or _restartHost then
        HostCommand("service start " .. _serviceName, 120)
    end

    -- The finish page only offers what was installed.
    if not ComponentPresent("KeelBase.Tools") then
        installx.DuiOptionSelect("pathbtn", false, false)
        installx.DuiVisible("pathbtn", false)
    end

	Progress(100)
    return true
end

function _FinishInstall()
    if installx.DuiOptionSelect("pathbtn") then
        local ok, errdesc = installx.SysPathAdd(_dirKeelBase)
        if not ok then
            installx.LogPrint(errdesc)
        end
    end
end

function QueryByKey(keyName)
    if (keyName == "InstallPath") then
        return _dirCompany
    end
end
