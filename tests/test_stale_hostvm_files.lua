-- Run from the repository root: lua tests/test_stale_hostvm_files.lua
-- RemoveStaleHostVMFiles() deletes what an earlier HostVM.7z left in HostVM\ that the current one no
-- longer carries: HostVM\modules\py\zcepy.dll, which moved to HostVM\ next to zce.dll and would be
-- loaded ahead of it by the py module. Only once HostVM\zcepy.dll is there: an old-layout package
-- has no other copy. PostSetup() runs it when it installs HostVM, before the service starts, and
-- stops the setup when the file cannot be deleted.
local ROOT = "C:\\Test path\\中文"
local HOSTVM = ROOT .. "\\HostVM\\"
local STALE = HOSTVM .. "modules\\py\\zcepy.dll"
local fs, deletes, errors, logs, calls, failDelete

-- Everything PostSetup() might call past the HostVM checks is recorded, so a case can tell that the
-- setup stopped before it.
installx = setmetatable({
    FilePathExists = function(path) return fs[path] ~= nil end,
    -- The binding clears the read-only flag itself, so only failDelete (a locked file, no
    -- permission) makes it fail.
    FilePathDelete = function(path)
        table.insert(deletes, path)
        if failDelete or not fs[path] then return false end
        fs[path] = nil
        return true
    end,
    LogPrint = function(message) table.insert(logs, message) end,
}, {
    __index = function(_, name)
        return function() table.insert(calls, name) end
    end,
})
ErrorHint = function(message) table.insert(errors, message) end
assert(loadfile("projects/TaijiMPC6/Install/Install.lua"))()
ResetInstallPath(ROOT)

local function reset()
    deletes, errors, logs, calls, failDelete = {}, {}, {}, {}, false
    fs = {
        [HOSTVM .. "zce.dll"] = "zce",
        [HOSTVM .. "zcepy.dll"] = "zcepy",
        [HOSTVM .. "modules\\py\\kh_py.dll"] = "py module",
    }
end
local count = 0
local function check(expected)
    assert(RemoveStaleHostVMFiles() == expected, "case " .. count)
    assert((#errors > 0) == not expected, "error hint " .. count)
    count = count + 1
end

-- A fresh install, or an upgrade from a package that already had the new layout: nothing to do.
reset(); check(true)
assert(#deletes == 0)

-- Upgrade over an install whose py module still carried zcepy.dll: only that copy goes.
reset(); fs[STALE] = "old zcepy"; check(true)
assert(fs[STALE] == nil and #deletes == 1 and deletes[1] == STALE)
assert(fs[HOSTVM .. "zcepy.dll"] == "zcepy" and fs[HOSTVM .. "modules\\py\\kh_py.dll"] == "py module")
assert(#logs == 1 and logs[1]:find(STALE, 1, true))

-- A HostVM.7z still in the old layout: modules\py\zcepy.dll is the only copy and stays.
reset(); fs[HOSTVM .. "zcepy.dll"] = nil; fs[STALE] = "zcepy of this package"; check(true)
assert(fs[STALE] == "zcepy of this package" and #deletes == 0)
assert(#logs == 1 and logs[1]:find("Keep", 1, true))

-- It cannot be deleted (HostVM still running, no permission): fail rather than start a HostVM
-- whose py workers would load it.
reset(); fs[STALE] = "old zcepy"; failDelete = true; check(false)
assert(fs[STALE] == "old zcepy" and errors[1]:find(STALE, 1, true))

-- PostSetup() stops there too, before the runtimes, the registry and the service.
reset(); fs[STALE] = "old zcepy"; failDelete = true
ComponentSelected = function(key) return key == "TaijiMPC.HostVM" end
InstallHostVMConfig = function() return true end
InstallHostVMFragments = function() return true end
assert(PostSetup() == false)
assert(#calls == 0, "PostSetup went on: " .. table.concat(calls, ", "))
count = count + 1

print("Stale HostVM files: " .. count .. " cases passed")
