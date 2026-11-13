-- HRootKey, CSIDL, RunBatchFile, ErrorHint are provided by the framework base library.

-- Resource ID constants (mirrors resource.h)
local RES = {
    LICENSE  = 133,  -- IDR_REGCONTENT1
    BACKGROUND = 138, -- IDB_RES_BACKGROUND
}

-- apps/KeelDeck/build_TaijiMPC6.py writes the release version here at build time and restores it afterwards.
local _VERSION = "5.2.41.3"
local _dirCompany = "C:\\TaijiControl"
local _dirExeHomeDir = _dirCompany .. "\\TaiJiMPC6"
local _dirExeFullPath = _dirCompany .. "\\TaiJiMPC6\\TaiJiMPC.exe"

local _bCustomPath = false

local _strResourceCN = {
	SETUP = "泰极MPC安装程序",
	CHOOSE_INSTALL_PATH = "选择安装路径",
	LICENSE = "安装许可协议",
	COMPONENTS = "选择安装组件",
	COMPONENTS_OK = "确定",
	SPACE_NOT_ENOUGH = "系统空间不足",
	SPACE_HINT = "安装位置空间不足：需要约 %s，可用 %s，请另外选择安装位置",
	SPACE_LABEL = "所需空间约 %s，可用 %s",
	MKDIR_FAILED = "创建目录失败: ",
	LOADING = "正在加载",
	HOSTVM_CONFIG_FAILED = "无法生成 HostVM 配置文件: ",
	ICU_FAILED = "无法部署 ICU 运行库: ",
	REQUIRED = "必装",
	INSTALLED = "已安装",
	INSTALLED_VERSION = "已安装版本 %s",
	KEPT = "已安装，保留现有数据，不会重新安装",
	NOTHING_SELECTED = "请至少选择一个组件",
	UNKNOWN_COMPONENT = "未知组件: ",
	HINT_ADDED = "已同时选择 %s（%s 需要）",
	HINT_REMOVED = "已同时取消 %s（它需要 %s）",
	HINT_MISSING = "无法选择 %s：安装包不含 %s",
	LIST_SEP = "、",
	HINT_SEP = "；",
}

local _strResourceEN = {
	SETUP = "Setup",
	CHOOSE_INSTALL_PATH = "Choose Install Path",
	LICENSE = "License Agreement",
	COMPONENTS = "Select Components",
	COMPONENTS_OK = "OK",
	SPACE_NOT_ENOUGH = "System space is not enough",
	SPACE_HINT = "Not enough space at the install path: needs about %s, %s free. Please choose another install path",
	SPACE_LABEL = "Needs about %s, %s free",
	MKDIR_FAILED = "Make dir failed: ",
	LOADING = "Loading",
	HOSTVM_CONFIG_FAILED = "Failed to create the HostVM config: ",
	ICU_FAILED = "Failed to deploy the ICU runtime: ",
	REQUIRED = "required",
	INSTALLED = "installed",
	INSTALLED_VERSION = "Installed version %s",
	KEPT = "Installed; the existing data is kept and it is not reinstalled",
	NOTHING_SELECTED = "Select at least one component",
	UNKNOWN_COMPONENT = "Unknown component: ",
	HINT_ADDED = "Also selected %s (needed by %s)",
	HINT_REMOVED = "Also deselected %s (it needs %s)",
	HINT_MISSING = "Cannot select %s: this installer lacks %s",
	LIST_SEP = ", ",
	HINT_SEP = "; ",
}

local _strResource = _strResourceCN
local _lang = 1  -- index into the {Chinese, English} name pairs below

function ResetInstallPath(installPath)
    _dirCompany = installPath
    _dirExeHomeDir = _dirCompany .. "\\TaiJiMPC6"
    _dirExeFullPath = _dirCompany .. "\\TaiJiMPC6\\TaiJiMPC.exe"
end

----------------------------------------------------------------------------------------------------
-- Components
--
-- The component page lists these groups and items. Every item is one INSTALLSOFT archive (res: its
-- ID in resource.h, file name in Install.rc); archives keep their paths relative to the install
-- root, so the installed layout does not depend on what was selected. A group only gathers its
-- items. The skin's controls are grp_<group> and item_<group>_<item>.
--   required         always installed; its checkbox is disabled
--   deps             items it cannot run without. Selecting it also selects those that are not
--                    installed yet; deselecting one of those also deselects it
--   marker           path under the install root that exists once the item is installed
--   keepIfInstalled  never extracted over an existing installation (TaiJiDataSvc keeps its database)
-- An item whose archive this installer does not carry (installx.PackageInfo returns nil) is hidden.
-- /components=<list> on the command line selects groups ("TaijiMPC") and items ("TaijiSim.OPCSim").
local COMPONENTS = {
    { id = "Common", name = {"公共组件", "Common"}, items = {
        { id = "Runtime", res = 150, required = true, marker = "Common\\vcredist",
          name = {"基础运行库", "Runtime"},
          desc = {"VC++ 运行库、ICU、OPC 核心组件和卸载程序", "VC++ runtime, ICU, OPC core components and the uninstaller"} },
        { id = "Ident", res = 151, marker = "Common\\Ident32",
          name = {"辨识组件", "Identification"},
          desc = {"32 位辨识 Worker、它的运行库和加密狗驱动", "32-bit identification worker, its runtime and the Sentinel driver"} },
        { id = "WinPy313", res = 152, marker = "WinPy313\\python\\python.exe",
          name = {"Python 3.13 环境", "Python 3.13"},
          desc = {"WinPy313，含 MPC 算法包", "WinPy313 with the MPC algorithm packages"} },
    }},
    { id = "TaijiMPC", name = {"TaijiMPC", "TaijiMPC"}, items = {
        { id = "HostVM", res = 160, marker = "HostVM\\HostVM.exe", deps = {"Common.WinPy313", "Common.Ident"},
          name = {"HostVM 服务", "HostVM service"},
          desc = {"后台服务，运行 MPC 算法与辨识", "Background service running MPC and identification"} },
        { id = "TaijiMPC6", res = 161, marker = "TaiJiMPC6\\TaiJiMPC.exe",
          name = {"TaijiMPC6 客户端", "TaijiMPC6 client"},
          desc = {"TaijiMPC6 组态与监控客户端", "TaijiMPC6 configuration and monitoring client"} },
    }},
    { id = "DataService", name = {"DataService", "DataService"}, items = {
        { id = "Svr", res = 170, marker = "TaiJiDataSvc", keepIfInstalled = true,
          name = {"数据服务 Svr", "Data server"},
          desc = {"TaiJiDataSvc 数据库服务（PostgreSQL）", "TaiJiDataSvc database service (PostgreSQL)"} },
        { id = "Client", res = 171, marker = "TaiJiDataClient\\DataCollector.exe",
          name = {"数据采集 Client", "Data collector"},
          desc = {"TaiJiDataCollector 采集服务", "TaiJiDataCollector service"} },
    }},
    { id = "TaijiSim", name = {"TaijiSim", "TaijiSim"}, items = {
        { id = "OPCSim", res = 180, marker = "TaiJiOPCSim\\bin\\TaiJiOPCSim.exe",
          name = {"OPC 仿真 OPCSim", "OPC simulator"},
          desc = {"TaiJiOPCSim，32 位 OPC DA 仿真服务器", "TaiJiOPCSim, a 32-bit OPC DA simulation server"} },
        { id = "PYSim", res = 181, marker = "TaiJiPYSim\\opcserver_win_i386\\taiji-opcsim-server.exe",
          name = {"Python 仿真 PYSim", "Python simulator"},
          desc = {"TaiJiPYSim 仿真服务", "TaiJiPYSim simulation service"} },
    }},
    { id = "Tool", name = {"Tool", "Tools"}, items = {
        { id = "RUS", res = 190, marker = "Tools\\RUS_TJC.exe",
          name = {"RUS_TJC 授权工具", "RUS_TJC license tool"},
          desc = {"加密狗授权更新工具", "Sentinel license update tool"} },
    }},
}

-- Installed components and the version that installed them, for upgrades and the uninstaller.
local COMPONENTS_KEY = "Software\\TaijiControl\\TaiJiMPC6\\Components"
-- A group whose items are only partly selected draws a blue square inside its empty checkbox:
-- a solid patch of the checked checkbox in setup.png (IDB_RES_PNG), scaled into the middle.
local PARTIAL_IMAGE = "res='130' restype='png' source='602,3,606,7' dest='5,5,13,13'"
local MB = 1024 * 1024

local _order = {}      -- items in page order
local _items = {}      -- "Group.Item" -> item
local _selected = {}   -- "Group.Item" -> true when it is to be installed in this run
local _installed = {}  -- "Group.Item" -> true when its marker exists under the install path
local _hint = nil      -- what the last click selected or deselected besides the clicked item
local _argError = nil  -- unknown names in /components

local function L(pair)
    return pair[_lang] or pair[1]
end

local function FormatSize(bytes)
    if bytes >= 1024 * MB then
        return string.format("%.1f GB", bytes / (1024 * MB))
    end
    return string.format("%d MB", math.max(1, math.ceil(bytes / MB)))
end

-- true: always selected (required); false: never selected (kept installation); nil: up to the user.
local function LockedState(item)
    if item.required then return true end
    if item.keepIfInstalled and _installed[item.key] then return false end
    return nil
end

local function GroupById(groupId)
    for _, group in ipairs(COMPONENTS) do
        if group.id:lower() == tostring(groupId):lower() then return group end
    end
end

function RefreshInstalledComponents()
    for _, item in ipairs(_order) do
        _installed[item.key] = installx.FilePathExists(_dirCompany .. "\\" .. item.marker) == true
        local locked = LockedState(item)
        if locked ~= nil or item.info == nil then
            _selected[item.key] = (locked == true and item.info ~= nil) or nil
        end
    end
end

-- Reads which archives the installer carries and what is installed, and selects the defaults:
-- everything for a fresh install, the installed components for an upgrade.
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
    local upgrade = false
    for _, item in ipairs(_order) do
        if item.info and not item.required and _installed[item.key] then upgrade = true end
    end
    for _, item in ipairs(_order) do
        if item.info and LockedState(item) == nil and (not upgrade or _installed[item.key]) then
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

-- "all", "none" or "partial", over the items the user can have: a required item counts as
-- selected, a kept installation (never selected) does not count.
function ComponentGroupState(groupId)
    local group = GroupById(groupId)
    local total, chosen = 0, 0
    for _, item in ipairs(group and group.items or {}) do
        if item.info and LockedState(item) ~= false then
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
-- required ones. Returns the names it does not know.
function ApplyComponentArg(text)
    _selected = {}
    for _, item in ipairs(_order) do
        if item.info and LockedState(item) == true then _selected[item.key] = true end
    end
    local unknown = {}
    for token in tostring(text):gmatch("[^,;%s]+") do
        local wanted = token:lower()
        local found = false
        for _, item in ipairs(_order) do
            if item.group.id:lower() == wanted or item.key:lower() == wanted then
                found = true
                SelectComponent(item.key, true)
            end
        end
        if not found then table.insert(unknown, token) end
    end
    return unknown
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
-- overwritten (only its growth), and some room for the post-setup steps.
function ComponentSpaceNeeded()
    local need = 100 * MB
    for _, item in ipairs(ComponentPlan()) do
        if _installed[item.key] then
            need = need + item.info.size // 10
        else
            need = need + item.info.size
        end
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
        table.insert(parts, string.format(_strResource.HINT_MISSING, L(_items[entry[1]].name), entry[2]))
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
    if item.keepIfInstalled and _installed[item.key] then
        text = text .. "\n" .. _strResource.KEPT
    end
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
    installx.DuiText("compokbtn", _strResource.COMPONENTS_OK)
    installx.DuiText("comphintlab", _hint or "")
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

function OnInitialize()
    _dirCompany = installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, "Software\\TaijiControl", "InstallPath")
    if (_dirCompany == nil or _dirCompany == "") then
        _dirCompany = "C:\\TaijiControl"
    end
    ResetInstallPath(_dirCompany)
    installx.DuiText("pathedit", _dirCompany)
	local acp = installx.SysACP()
	if acp == 936 then
		_strResource, _lang = _strResourceCN, 1
	else
		_strResource, _lang = _strResourceEN, 2
	end
	installx.LogPrint("ACP: ", acp)

	LoadComponents()
	local arg = installx.SysGetArg("components")
	if type(arg) == "string" then
		local unknown = ApplyComponentArg(arg)
		if #unknown > 0 then
			-- A silent install refuses to start; with the page the user can correct the selection.
			_argError = _strResource.UNKNOWN_COMPONENT .. table.concat(unknown, ", ")
			installx.LogPrint(_argError)
			ErrorHint(_argError)
		end
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
            installx.DuiText("pathedit", installPath)
            ResetInstallPath(installPath)
            -- Installed components, and so locks and space, belong to the install path.
            RefreshInstalledComponents()
            RefreshComponentPage()
        end
    elseif (btnName == "closebtn") then
        if (installx.DuiTabSelect("installlayout") > 0) then
            ShowMainPage()
        else
            installx.DuiMessage(0x10, 0, 0) -- WM_CLOSE
        end
    elseif (btnName == "compbtn") then
        ShowComponentPage()
    elseif (btnName == "compokbtn") then
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
	elseif (btnName == "bootstartbtn") then
	elseif (btnName == "runbtn") then
	elseif (btnName == "showtxbtn") then
    end
end

function OnSelChanged(btnName, isSelected)
    if (btnName == "protcheckbtn") then
        installx.DuiEnable("starinstallbtn", isSelected)
        return
    end
    local groupId = btnName:match("^grp_(%w+)$")
    local groupOfItem, itemId = btnName:match("^item_(%w+)_(%w+)$")
    if groupId == nil and groupOfItem == nil then
        return
    end
    -- The option has already flipped itself; the page is redrawn from the selection either way.
    -- Once the user picks components, a bad /components argument no longer matters.
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
	-- If this is the callback with completion values (-1), skip updating progress here
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

function CheckDiskSpace()
    local freeSystemSpace = installx.DiskFreeSpace("")
    if (freeSystemSpace ~= nil and freeSystemSpace <= 10*1024*1024) then
        ErrorHint(_strResource.SPACE_NOT_ENOUGH)
        return false
    end
    -- An unknown free space (the drive cannot be queried) does not block the install.
    local need, free = ComponentSpaceNeeded(), FreeSpaceAt(_dirCompany)
    if (free ~= nil and free < need) then
        ErrorHint(string.format(_strResource.SPACE_HINT, FormatSize(need), FormatSize(free)))
        return false
    end
    return true
end

function CustomLayeroutHide()
    installx.DuiVisible("customlayout", false)
    installx.DuiWindowPos("_MainFrame", 0, 0, 600, 380)
end

----------------------------------------------------------------------------------------------------
-- Services and processes of the components

local HOSTVM_SERVICE = "HostVM"
-- Windows services the install_*.bat of a component registers, and the process to make sure of.
local SERVICES = {
    ["DataService.Svr"] = {name = "TaiJiDataSvc", install = "TaiJiDataSvc\\install_TaiJiDataSvc.bat"},
    ["DataService.Client"] = {name = "TaiJiDataCollector", exe = "DataCollector.exe",
                              install = "TaiJiDataClient\\install_TaijiDataCollector.bat"},
    ["TaijiSim.PYSim"] = {name = "TaiJiOPCSim", exe = "taiji-opcsim-server.exe",
                          install = "TaiJiPYSim\\install_taijiopcsim.bat"},
}

local _restartHostVM = false  -- HostVM was stopped only because files it loads are upgraded

local function ServiceExists(name)
    return installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, "SYSTEM\\CurrentControlSet\\Services\\" .. name, "") ~= nil
end

local function HostVM(args)
    installx.ProcessExecute("\"" .. _dirCompany .. "\\HostVM\\HostVM.exe\" " .. args)
end

-- Stops what holds files of the selected components open. Nothing of a component that is not
-- selected is stopped, except HostVM while the WinPy313 or identification files it loads are
-- replaced; PostSetup starts it again.
function StopSelectedComponents()
    _restartHostVM = false
    if ComponentSelected("TaijiSim.OPCSim") then
        installx.LogPrint("KillProcesses TaiJiOPCSim.exe ...")
        installx.ProcessKill("TaiJiOPCSim.exe")
    end
    if ComponentSelected("TaijiMPC.TaijiMPC6") then
        installx.LogPrint("KillProcesses TaiJiMPC.exe ...")
        installx.ProcessKill("TaiJiMPC.exe")
    end

    local hostvmFilesChange = ComponentSelected("Common.WinPy313") or ComponentSelected("Common.Ident")
    if ComponentSelected("TaijiMPC.HostVM") then
        HostVM("--stop HostVM")
        HostVM("service stop HostVM")
        HostVM("--uninstall HostVM")
        HostVM("service remove HostVM")
        installx.LogPrint("KillProcesses HostVM.exe ...")
        installx.ProcessKill("HostVM.exe")
    elseif hostvmFilesChange and _installed["TaijiMPC.HostVM"] then
        HostVM("--stop HostVM")
        HostVM("service stop HostVM")
        installx.ProcessKill("HostVM.exe")
        _restartHostVM = ServiceExists(HOSTVM_SERVICE)
    end
    if ComponentSelected("Common.Ident") then
        installx.ProcessKill("TaijiIdent32.exe")
    end

    for key, service in pairs(SERVICES) do
        if ComponentSelected(key) and ServiceExists(service.name) then
            installx.LogPrint("Stop service " .. service.name .. " ...")
            installx.ProcessExecute("net.exe stop " .. service.name, true, 60)
            if service.exe then installx.ProcessKill(service.exe) end
        end
    end
end

-- A selected component's service: registered by its install_*.bat on a fresh install, started
-- again on an upgrade (the scripts refuse to register a service that exists).
local function SetupComponentService(key, waitSec)
    local service = SERVICES[key]
    if not ComponentSelected(key) then
        return
    end
    if ServiceExists(service.name) then
        installx.ProcessExecute("net.exe start " .. service.name, true, waitSec)
    else
        RunBatchFile(_dirCompany .. "\\" .. service.install, waitSec)
    end
end

function StartSetup()

	installx.LogPrint("Require Admin Promote ...")
    isAdmin = installx.RunAsAdmin()

    local function fail(message)
        ErrorHint(message)
        -- A silent install has nobody to correct the selection and would wait forever.
        if installx.SysGetArg("s") then installx.SetupFailed(message) end
    end
    if _argError then
        return fail(_argError)
    end
    local plan, optional = ComponentPlan(), 0
    for _, item in ipairs(plan) do
        if not item.required then optional = optional + 1 end
    end
    if optional == 0 then
        return fail(_strResource.NOTHING_SELECTED)
    end

	installx.LogPrint("CheckDiskSpace ...")
    if ( not CheckDiskSpace() ) then
        if installx.SysGetArg("s") then installx.SetupFailed("not enough disk space") end
        return
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

-- The package ships HostVM\hostvm.default.xml but never hostvm.xml: once hostvm.xml exists it belongs
-- to the site (ports, thread counts, the ident secret key), so an upgrade must keep it. Only a fresh
-- install, where hostvm.xml does not exist yet, starts from the bundled default.
-- Returns false when a fresh install cannot get a hostvm.xml, after showing the error.
function InstallHostVMConfig()
    local defaultConfig = _dirCompany .. "\\HostVM\\hostvm.default.xml"
    local siteConfig = _dirCompany .. "\\HostVM\\hostvm.xml"
    if installx.FilePathExists(siteConfig) then
        installx.LogPrint("Keep existing HostVM config: " .. siteConfig)
        return true
    end
    -- CopyFile bFailIfExists also protects a config created after the existence check.
    if installx.FilePathCopy(defaultConfig, siteConfig, true) then
        installx.LogPrint("Created HostVM config from " .. defaultConfig)
        return true
    end
    ErrorHint(_strResource.HOSTVM_CONFIG_FAILED .. siteConfig)
    return false
end

-- Templates never overwrite site XML. A pending marker prevents incomplete copies from
-- being accepted as site configuration after a crash or a failed rollback.
function InstallHostVMFragments()
    local directory = _dirCompany .. "\\HostVM\\hostvm.d"
    local pending = directory .. "\\.hostvm-fragments.pending"
    local function failed(path)
        ErrorHint(_strResource.HOSTVM_CONFIG_FAILED .. path)
        return false
    end
    if installx.FilePathExists(pending) then
        installx.LogPrint("Incomplete HostVM initialization. Recover generated XML before removing " .. pending)
        return failed(pending)
    end
    local files, errorCode = installx.FilePathListFiles(directory)
    if files == nil then
        installx.LogPrint("Cannot enumerate HostVM fragments: ", errorCode)
        return failed(directory)
    end
    for _, name in ipairs(files) do
        if name:lower():match("%.xml$") then
            installx.LogPrint("Keep existing HostVM fragments: " .. directory)
            return true
        end
    end
    local siteNames = installx.HostVMSubvmNames(_dirCompany .. "\\HostVM\\hostvm.xml", false)
    if siteNames == nil then return failed("hostvm.xml") end
    local existing = {}
    for _, name in ipairs(siteNames) do existing[name] = true end
    table.sort(files)
    local selected, templateCount, planned = {}, 0, {}
    for _, name in ipairs(files) do
        if name:lower():match("^1%d%d%-.*%.xml%.template$") then
            templateCount = templateCount + 1
            local names = installx.HostVMSubvmNames(directory .. "\\" .. name, true)
            if names == nil or #names == 0 then return failed(name) end
            local overlaps = 0
            for _, vmname in ipairs(names) do
                if existing[vmname] then overlaps = overlaps + 1 end
            end
            if overlaps == #names then
                installx.LogPrint("Keep main-config declarations; skip template " .. name)
            elseif overlaps > 0 then
                -- Never drop the non-overlapping services or rewrite an operator's template.
                installx.LogPrint("Template partially conflicts with hostvm.xml: " .. name)
                return failed(name)
            else
                for _, vmname in ipairs(names) do
                    if planned[vmname] then return failed(name) end
                    planned[vmname] = true
                end
                table.insert(selected, name)
            end
        end
    end
    if templateCount == 0 then return failed(directory) end
    if #selected == 0 then return true end
    if not installx.FilePathCreateDirectory(pending) then return failed(pending) end
    local created = {}
    for _, name in ipairs(selected) do
        local destination = directory .. "\\" .. name:sub(1, -10)
        local ok, copyError = installx.FilePathCopy(directory .. "\\" .. name, destination, true)
        if not ok then
            -- CopyFile can leave a partial destination. Do not delete a concurrent writer's
            -- existing file when bFailIfExists reports ERROR_FILE_EXISTS/ALREADY_EXISTS.
            if copyError ~= 80 and copyError ~= 183 then
                table.insert(created, destination)
            end
            local clean = copyError ~= 80 and copyError ~= 183
            for _, path in ipairs(created) do
                if installx.FilePathExists(path) and not installx.FilePathDelete(path) then
                    clean = false
                    installx.LogPrint("HostVM rollback could not delete " .. path)
                end
            end
            -- A raced-in XML is not ours to delete, but it must not make a retry
            -- accept this interrupted initialization as a complete site configuration.
            local remaining = installx.FilePathListFiles(directory)
            if remaining == nil then
                clean = false
            else
                for _, filename in ipairs(remaining) do
                    if filename:lower():match("%.xml$") then clean = false end
                end
            end
            if clean and not installx.FilePathDelete(pending) then
                installx.LogPrint("HostVM rollback marker retained: " .. pending)
            end
            return failed(destination)
        end
        table.insert(created, destination)
    end
    if not installx.FilePathDelete(pending) then return failed(pending) end
    return true
end

-- Qt6Core.dll imports icuuc.dll, and the TaiJiMPC6\icuuc.dll in the package forwards every export to
-- icu.dll, which Windows only has from Windows 10 1903 on (not on Server 2016/2019). Where it is
-- missing TaiJiMPC.exe cannot start, so Common\icu's matching icu.dll and icuuc.dll go into TaiJiMPC6\.
-- Where Windows has icu.dll the client uses it, so a TaiJiMPC6\icu.dll is removed: icu.dll is not a
-- KnownDLL and a copy next to the exe would shadow the system one. The archive never carries it; it
-- is left by this fallback before an OS upgrade, or was put there by hand for an earlier version.
-- UnInstall.lua removes TaiJiMPC6\ with both. Returns false when a copy or that removal fails, after
-- showing the error.
local CSIDL_SYSTEM = 0x0025  -- not in install_base.lua's CSIDL table
function InstallIcuFallback()
    local systemDir = installx.FilePathGetSpecialLocation(CSIDL_SYSTEM)
    if systemDir ~= nil and installx.FilePathExists(systemDir .. "\\icu.dll") then
        local local_icu = _dirExeHomeDir .. "\\icu.dll"
        if installx.FilePathExists(local_icu) then
            -- FilePathDelete clears the read-only flag those hand-made copies tend to carry.
            if not installx.FilePathDelete(local_icu) then
                ErrorHint(_strResource.ICU_FAILED .. local_icu)
                return false
            end
            installx.LogPrint("Removed " .. local_icu .. ", which shadowed the system icu.dll")
        end
        installx.LogPrint("Use system ICU: " .. systemDir .. "\\icu.dll")
        return true
    end
    for _, name in ipairs({"icu.dll", "icuuc.dll"}) do
        local destination = _dirExeHomeDir .. "\\" .. name
        -- false: overwrite, so icuuc.dll from Win32.7z is replaced by the one that matches icu.dll.
        local ok, copyError = installx.FilePathCopy(_dirCompany .. "\\Common\\icu\\" .. name, destination, false)
        if ok then
            installx.LogPrint("No system icu.dll; deployed " .. destination)
        elseif installx.FilePathExists(destination) then
            -- E.g. a read-only icu.dll copied there by hand for an earlier version, which already worked.
            installx.LogPrint("Keep existing " .. destination .. ", copy failed: " .. tostring(copyError))
        else
            ErrorHint(_strResource.ICU_FAILED .. destination)
            return false
        end
    end
    return true
end

-- OPC core components come in two Graybox packages, one per bitness, and each carries what the
-- other lacks:
--   x86: OpcEnum.exe (the OPC server browser, which only exists as 32-bit) and the 32-bit
--        proxy/stubs. Needed by the 32-bit DA servers TaiJiOPCSim and TaiJiPYSim\opcserver_win_i386,
--        and by every client that browses servers through OpcEnum.
--   x64: the 64-bit proxy/stubs only. Needed by HostVM's DA client (libidh, x64) to talk to DA
--        servers and to the 32-bit OpcEnum.
-- Each package is checked on its own, so a machine where other OPC software already installed the
-- 32-bit half still gets the 64-bit half.
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

-- wantX86 / wantX64: whether the selected components need that half; nil means yes.
function InstallOpcCoreComponents(wantX86, wantX64)
    local opcDir = _dirCompany .. "\\Common\\opc\\"
    if wantX86 == false then
        installx.LogPrint("Skip OPC core components x86, no selected component needs them")
    elseif OpcProxiesUsable("WOW6432Node\\") and OpcEnumUsable() then
        installx.LogPrint("Skip OPC core components x86, already registered")
    else
        installx.ProcessExecute("\"" .. opcDir .. "GBDA_Install_Prereq_x86.msi\" /quiet")
    end
    if wantX64 == false then
        installx.LogPrint("Skip OPC core components x64, no selected component needs them")
    elseif OpcProxiesUsable("") then
        installx.LogPrint("Skip OPC core components x64, already registered")
    else
        installx.ProcessExecute("\"" .. opcDir .. "GBDA_Install_Prereq_x64.msi\" /quiet")
    end
end

-- TaiJi.OPC.Sim, the 32-bit DA server TaiJiOPCSim.exe. Its CLSID is in the 32-bit registry view;
-- AppID keys are shared by both views, so they are written without WOW6432Node.
local TAIJIOPCSIM_CLSID = "{A48A6241-A024-4F99-B105-5DF8CCEA66BA}"

-- Registers TaiJiOPCSim.exe and runs it as the Interactive User. With the default DCOM identity (the
-- launching user) HostVM, a SYSTEM service, gets its own TaiJiOPCSim.exe in session 0 that desktop
-- OPC tools cannot see; as the Interactive User every client shares the one in the console session.
-- The flip side: with nobody logged on, activation fails. Skipped when TaiJiOPCSim is not installed,
-- so no COM keys point at a missing exe. UnInstall.lua deletes the same keys.
function RegisterTaiJiOPCSim()
    local exe = _dirCompany .. "\\TaiJiOPCSim\\bin\\TaiJiOPCSim.exe"
    if not installx.FilePathExists(exe) then
        installx.LogPrint("Skip TaiJiOPCSim registration, not installed: " .. exe)
        return
    end
    installx.ProcessExecute("\"" .. exe .. "\" -RegServer", false, 10)

    -- After -RegServer, which writes the CLSID key but no AppID.
    local HKLM = HRootKey.HKEY_LOCAL_MACHINE
    local clsidKey = "SOFTWARE\\Classes\\WOW6432Node\\CLSID\\" .. TAIJIOPCSIM_CLSID
    local appIdKey = "SOFTWARE\\Classes\\AppID\\" .. TAIJIOPCSIM_CLSID
    installx.RegSetValue(HKLM, clsidKey .. "\\Implemented Categories", "", "")
    installx.RegSetValue(HKLM, clsidKey .. "\\Implemented Categories\\{63D5F430-CFE4-11d1-B2C8-0060083BA1FB}", "", "")
    installx.RegSetValue(HKLM, clsidKey .. "\\Implemented Categories\\{63D5F432-CFE4-11d1-B2C8-0060083BA1FB}", "", "")
    installx.RegSetValue(HKLM, clsidKey, "AppID", TAIJIOPCSIM_CLSID)
    installx.RegSetValue(HKLM, appIdKey, "", "TaiJiOPCSim")
    installx.RegSetValue(HKLM, appIdKey, "RunAs", "Interactive User")
    installx.RegSetValue(HKLM, "SOFTWARE\\Classes\\AppID\\TaiJiOPCSim.exe", "AppID", TAIJIOPCSIM_CLSID)
end

-- Version of the bundled Common\hasp\haspdinst.exe; change it together with that file. The
-- Envelope-protected tjonlinelib DLLs need at least this Sentinel LDK run-time.
local HASP_RUNTIME_VERSION = "10.33"

-- Numeric fields of a dotted version ("10.31" -> {10, 31}), or nil when the value is not one.
local function ParseVersion(text)
    if type(text) ~= "string" then
        return nil
    end
    local fields = {}
    for field in (text .. "."):gmatch("([^.]*)%.") do
        if not field:match("^%d+$") then
            return nil
        end
        table.insert(fields, tonumber(field))
    end
    return fields
end

-- True when dotted version `version` is older than `minimum`, compared field by field as numbers
-- (as strings, "10.31" < "8.31" and "9.12" > "10.33"). Missing trailing fields count as 0. A value
-- that is not a dotted version, nil included, counts as older.
local function VersionOlderThan(version, minimum)
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

-- Runs haspdinst unless the installed run-time is already HASP_RUNTIME_VERSION or newer. Treating an
-- unreadable version as too old is safe: haspdinst itself does not downgrade a newer run-time.
function InstallHaspRuntime()
    local installed = installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, "SOFTWARE\\Aladdin Knowledge Systems\\HASP\\Driver\\Installer", "DrvPkgVersion")
    if not VersionOlderThan(installed, HASP_RUNTIME_VERSION) then
        installx.LogPrint("Skip Sentinel run-time, " .. installed .. " already installed")
        return
    end
    installx.ProcessExecute("\"" .. _dirCompany .. "\\Common\\hasp\\haspdinst.exe\" -install -nomsg")
end

local function Progress(percent)
	installx.DuiProgress("installprogress", percent, _strResource.LOADING  .. " " .. percent .. "%" )
end

local function SetBothViews(path, name, value)
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, "Software\\" .. path, name, value)
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, "Software\\WOW6432Node\\" .. path, name, value)
end

-- Returning false tells the installer that setup did not complete: it shows the failure and
-- enables the close button instead of moving on to the finish page. Every step belongs to a
-- selected component; nothing of a component that was not selected is touched.
function PostSetup()

    local hostvm = ComponentSelected("TaijiMPC.HostVM")
    local client = ComponentSelected("TaijiMPC.TaijiMPC6")
    local winpy = ComponentSelected("Common.WinPy313")

    -- Without hostvm.xml the HostVM service cannot start. Checking it first means a failure stops
    -- before any runtime, service, registry or shortcut is touched.
    if hostvm and (not InstallHostVMConfig() or not InstallHostVMFragments()) then
        return false
    end
    -- Likewise for the client, which cannot start without ICU.
    if client and not InstallIcuFallback() then
        return false
    end

	Progress(94)
    local vcRedist = installx.RegGetValue(HRootKey.HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64", "Installed")
    if (vcRedist == nil or vcRedist == 0) then
        installx.ProcessExecute("\"" .. _dirCompany .. "\\Common\\vcredist\\vc_redist.x64.exe\" /install /quiet /norestart", true, 60)
    end

	Progress(95)
    -- x86: the 32-bit DA servers and OpcEnum; x64: HostVM's DA client.
    InstallOpcCoreComponents(ComponentSelected("TaijiSim.OPCSim") or ComponentSelected("TaijiSim.PYSim"), hostvm)

	Progress(96)
    if ComponentSelected("TaijiSim.OPCSim") then
        RegisterTaiJiOPCSim()
    end
    -- The Envelope-protected tjonlinelib DLLs of the identification worker need the run-time.
    if ComponentSelected("Common.Ident") then
        InstallHaspRuntime()
    end

    if hostvm or winpy then
        RunBatchFile(_dirCompany .. "\\HostVM\\install_python_env.bat", 10)
    end
    SetupComponentService("DataService.Svr", 30)
    SetupComponentService("DataService.Client", 30)
    SetupComponentService("TaijiSim.PYSim", 30)

	Progress(97)
    SetBothViews("TaijiControl", "InstallPath", _dirCompany)
    SetBothViews("TaijiControl\\TaiJiMPC6", "Version", _VERSION)
    if ComponentPresent("TaijiMPC.TaijiMPC6") then
        SetBothViews("TaijiControl\\TaiJiMPC6", "APPPath", _dirExeFullPath)
    end
    if ComponentPresent("Common.WinPy313") then
        local pythonDir = _dirCompany .. "\\WinPy313\\python"
        SetBothViews("TaijiControl\\PythonEnv", "InstallPath", pythonDir)
        -- install_python_env.bat above still writes WinPy312 here.
        SetBothViews("TaijiControl\\PythonEnv", "PythonPath", pythonDir)
        SetBothViews("TaijiControl\\PythonEnv", "Version", "3.13")
    end
    for _, item in ipairs(_order) do
        if _selected[item.key] then
            installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, COMPONENTS_KEY, item.key, _VERSION)
        end
    end

    if client then
        local desktopDir = installx.FilePathGetSpecialLocation(CSIDL.COMMON_DESKTOPDIRECTORY)
        installx.FilePathCreateShortCut(desktopDir .. "\\TaiJiMPC6.lnk", _dirExeFullPath, _dirExeHomeDir, "TaiJiMPC6")

        local startMenuDir = installx.FilePathGetSpecialLocation(CSIDL.COMMON_STARTMENU)
        installx.FilePathMkdir(startMenuDir .. "\\Programs\\TaijiControl")
        installx.FilePathCreateShortCut(startMenuDir .. "\\Programs\\TaijiControl\\TaiJiMPC6.lnk", _dirExeFullPath, _dirExeHomeDir, "TaiJiMPC6")
    end

	Progress(98)
    if hostvm then
        HostVM("service install HostVM")
        HostVM("service start HostVM")
    elseif _restartHostVM then
        HostVM("service start HostVM")
    end

	Progress(99)

    -- Common.7z (always installed) carries the uninstaller, so every combination of components
    -- can be uninstalled. Earlier packages put it into TaiJiMPC6\, where it is now stale.
    local uninstaller = _dirCompany .. "\\Uninstall\\UnInstall.exe"
    local staleUninstaller = _dirExeHomeDir .. "\\UnInstall.exe"
    if installx.FilePathExists(uninstaller) and installx.FilePathExists(staleUninstaller) then
        installx.FilePathDelete(staleUninstaller)
    end
    -- The first RegSetValue below creates the TaiJiMPC6 key.
    local UNINST_KEY = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\TaiJiMPC6"
    local icon = ComponentPresent("TaijiMPC.TaijiMPC6") and _dirExeFullPath or uninstaller
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, UNINST_KEY, "DisplayIcon", icon)
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, UNINST_KEY, "DisplayName", "Tai-Ji MPC6")
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, UNINST_KEY, "DisplayVersion", _VERSION)
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, UNINST_KEY, "Publisher", "Tai-Ji Soft")
    installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, UNINST_KEY, "UninstallString", uninstaller)

    -- The finish page only offers what was installed.
    if not ComponentPresent("TaijiMPC.TaijiMPC6") then
        for _, option in ipairs({"runbtn", "bootstartbtn"}) do
            installx.DuiOptionSelect(option, false, false)
            installx.DuiVisible(option, false)
        end
    end
    if not ComponentPresent("Common.WinPy313") then
        installx.DuiOptionSelect("pyenvbtn", false, false)
        installx.DuiVisible("pyenvbtn", false)
    end

	Progress(100)
    return true
end

function _FinishInstall()
    local runSelected = installx.DuiOptionSelect("runbtn")
    if (runSelected) then
        installx.ProcessExecute(_dirExeFullPath, false, 0)
    end

    local runOnStartSelected = installx.DuiOptionSelect("bootstartbtn")
    if (runOnStartSelected) then
        installx.RegSetValue(HRootKey.HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", "TaijiMPC", _dirExeFullPath)
    else
        installx.RegDeleteValue(HRootKey.HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run", "TaijiMPC")
    end

    local setPyEnv = installx.DuiOptionSelect("pyenvbtn")
    if (setPyEnv) then
        local issucess, errdesc = installx.SysPathAdd(_dirCompany .. "\\WinPy313\\python")
        if not issucess then
            installx.LogPrint(errdesc)
        end

        issucess, errdesc = installx.SysPathAdd(_dirCompany .. "\\WinPy313\\python\\Scripts")
        if not issucess then
            installx.LogPrint(errdesc)
        end

        issucess, errdesc = installx.SysEnvSet("PYTHONHOME", _dirCompany .. "\\WinPy313\\python")
        if not issucess then
            installx.LogPrint(errdesc)
        end
    end

    showTxtSelected = installx.DuiOptionSelect("showtxbtn")
    if showTxtSelected then
        -- show update ？ show install log?
    end
end

function QueryByKey(keyName)
    if (keyName == "InstallPath") then
        return _dirCompany
    end
end
