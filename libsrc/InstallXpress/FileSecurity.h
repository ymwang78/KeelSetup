#pragma once

// A directory an elevated installer puts a LocalSystem service into (installx.FilePathSecure).
//
// Below C:\ every user may create folders and files (BUILTIN\Users has "create folders" and
// "create files" there, inherited by every new folder). Left at the inherited DACL, any user could
// add a plugin or a config fragment to an installed service's directory and have it loaded as
// SYSTEM; could create the directory before the administrator installs and own it; or could put a
// junction where the installer extracts or an uninstaller deletes.

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <string>
#include <vector>

#ifndef ERROR_REPARSE_POINT_ENCOUNTERED
#define ERROR_REPARSE_POINT_ENCOUNTERED 4395L
#endif

struct SecureDirectoryResult {
    bool ok = false;
    std::wstring problem;          // the path that made it refuse, empty when ok
    DWORD error = ERROR_SUCCESS;   // why: ERROR_REPARSE_POINT_ENCOUNTERED, ERROR_INVALID_OWNER, ...
};

namespace file_security {

// SYSTEM and Administrators full control, Users read & execute when usersCanRead; inherited by
// everything below, nothing inherited from above (P). Owner Administrators.
inline std::wstring securityDescriptorSddl(bool usersCanRead)
{
    std::wstring sddl = L"O:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";
    if (usersCanRead)
        sddl += L"(A;OICI;0x1200a9;;;BU)";  // FILE_GENERIC_READ | FILE_GENERIC_EXECUTE
    return sddl;
}

// "C:\\a/b\\" -> "C:\\a\\b" and its prefixes {"C:\\a", "C:\\a\\b"}. Only an absolute path on a
// drive letter is accepted.
inline bool splitDrivePath(const std::wstring& path, std::wstring& normalized, std::vector<std::wstring>& prefixes)
{
    normalized = path;
    for (auto& ch : normalized)
        if (ch == L'/') ch = L'\\';
    while (normalized.size() > 3 && normalized.back() == L'\\')
        normalized.pop_back();
    if (normalized.size() < 4 || !iswalpha(normalized[0]) || normalized[1] != L':' || normalized[2] != L'\\')
        return false;
    if (normalized.find(L"\\\\", 2) != std::wstring::npos)
        return false;  // an empty component, "C:\\a\\\\b"
    prefixes.clear();
    for (size_t i = 4; i <= normalized.size(); ++i) {
        if (i == normalized.size() || normalized[i] == L'\\')
            prefixes.push_back(normalized.substr(0, i));
    }
    return true;
}

inline bool tokenUserIs(PSID sid)
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        return false;
    BYTE buffer[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
    DWORD length = 0;
    bool same = GetTokenInformation(token, TokenUser, buffer, sizeof(buffer), &length)
        && EqualSid(sid, reinterpret_cast<TOKEN_USER*>(buffer)->User.Sid);
    CloseHandle(token);
    return same;
}

// SYSTEM, Administrators, TrustedInstaller, or the (elevated) user running the installer. A
// directory another user created is owned by that user.
inline bool isTrustedOwner(PSID owner)
{
    if (IsWellKnownSid(owner, WinLocalSystemSid) || IsWellKnownSid(owner, WinBuiltinAdministratorsSid))
        return true;
    PSID trustedInstaller = nullptr;
    if (ConvertStringSidToSidW(L"S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464", &trustedInstaller)) {
        bool same = EqualSid(owner, trustedInstaller) != FALSE;
        LocalFree(trustedInstaller);
        if (same)
            return true;
    }
    return tokenUserIs(owner);
}

inline DWORD ownerIsTrusted(const std::wstring& path, bool& trusted)
{
    PSID owner = nullptr;
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    DWORD status = GetNamedSecurityInfoW(path.c_str(), SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION,
                                         &owner, nullptr, nullptr, nullptr, &descriptor);
    if (status != ERROR_SUCCESS)
        return status;
    trusted = owner != nullptr && isTrustedOwner(owner);
    LocalFree(descriptor);
    return ERROR_SUCCESS;
}

// The first reparse point (junction, symbolic link, mount point) inside dir, without following
// any; empty when there is none.
inline std::wstring findReparsePoint(const std::wstring& dir)
{
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW((dir + L"\\*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE)
        return std::wstring();
    std::wstring found;
    do {
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0)
            continue;
        std::wstring path = dir + L"\\" + data.cFileName;
        if (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
            found = path;
        else if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            found = findReparsePoint(path);
    } while (found.empty() && FindNextFileW(find, &data));
    FindClose(find);
    return found;
}

inline void enablePrivilege(const wchar_t* name)
{
    HANDLE token = nullptr;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &token))
        return;
    TOKEN_PRIVILEGES privileges{};
    privileges.PrivilegeCount = 1;
    privileges.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    if (LookupPrivilegeValueW(nullptr, name, &privileges.Privileges[0].Luid))
        AdjustTokenPrivileges(token, FALSE, &privileges, 0, nullptr, nullptr);
    CloseHandle(token);
}

inline SecureDirectoryResult fail(const std::wstring& problem, DWORD error)
{
    SecureDirectoryResult result;
    result.problem = problem;
    result.error = error;
    return result;
}

}  // namespace file_security

// Deletes a directory and everything in it, read-only files included (installx.FilePathDelete).
// A reparse point (junction, directory or file symbolic link, mount point), at the top or inside,
// is removed itself and never followed: an elevated installer or uninstaller must not delete
// whatever a link someone put in its tree points at.
inline bool deleteDirectoryTree(const std::wstring& dir)
{
    DWORD flags = GetFileAttributesW(dir.c_str());
    if (flags == INVALID_FILE_ATTRIBUTES)
        return false;
    if (flags & FILE_ATTRIBUTE_REPARSE_POINT)
        return (flags & FILE_ATTRIBUTE_DIRECTORY) ? RemoveDirectoryW(dir.c_str()) != FALSE : DeleteFileW(dir.c_str()) != FALSE;
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW((dir + L"\\*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE)
        return false;
    bool ok = true;
    do {
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0)
            continue;
        std::wstring path = dir + L"\\" + data.cFileName;
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !(data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
            ok = deleteDirectoryTree(path);
        } else if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            ok = RemoveDirectoryW(path.c_str()) != FALSE;  // a directory link: the link only
        } else {
            SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
            ok = DeleteFileW(path.c_str()) != FALSE;       // a file, or a file link: the link only
        }
    } while (ok && FindNextFileW(find, &data));
    FindClose(find);
    if (!ok)
        return false;
    SetFileAttributesW(dir.c_str(), FILE_ATTRIBUTE_NORMAL);
    return RemoveDirectoryW(dir.c_str()) != FALSE;
}

// Makes path a directory only SYSTEM and Administrators can change, creating it (and missing
// parents, with the same protection) as needed. Refuses, changing nothing it did not create, when
// the path or one of its parents is a reparse point or not a directory, when one of them existed
// and another user owns it (the owner of a parent can delete or rename what is below it), or when
// a reparse point is inside the path. Otherwise Administrators becomes the owner of the whole tree,
// which gets the protected DACL of securityDescriptorSddl() (explicit entries removed, so a file
// someone planted earlier keeps no rights of its own).
inline SecureDirectoryResult secureDirectory(const std::wstring& path, bool usersCanRead)
{
    using namespace file_security;
    std::wstring target;
    std::vector<std::wstring> prefixes;
    if (!splitDrivePath(path, target, prefixes))
        return fail(path, ERROR_BAD_PATHNAME);

    PSECURITY_DESCRIPTOR descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(securityDescriptorSddl(usersCanRead).c_str(),
                                                             SDDL_REVISION_1, &descriptor, nullptr))
        return fail(target, GetLastError());
    struct Releaser {
        PSECURITY_DESCRIPTOR descriptor;
        ~Releaser() { LocalFree(descriptor); }
    } releaser{descriptor};

    bool existed = true;
    SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor, FALSE};
    for (const auto& prefix : prefixes) {
        bool created = false;
        DWORD flags = GetFileAttributesW(prefix.c_str());
        if (flags == INVALID_FILE_ATTRIBUTES) {
            created = CreateDirectoryW(prefix.c_str(), &attributes) != FALSE;
            if (!created && GetLastError() != ERROR_ALREADY_EXISTS)
                return fail(prefix, GetLastError());
            flags = GetFileAttributesW(prefix.c_str());  // whatever is there now, ours or a racer's
            if (flags == INVALID_FILE_ATTRIBUTES)
                return fail(prefix, GetLastError());
        }
        if (flags & FILE_ATTRIBUTE_REPARSE_POINT)
            return fail(prefix, ERROR_REPARSE_POINT_ENCOUNTERED);
        if (!(flags & FILE_ATTRIBUTE_DIRECTORY))
            return fail(prefix, ERROR_DIRECTORY);
        if (!created) {
            bool trusted = false;
            DWORD status = ownerIsTrusted(prefix, trusted);
            if (status != ERROR_SUCCESS)
                return fail(prefix, status);
            if (!trusted)
                return fail(prefix, ERROR_INVALID_OWNER);
        }
        if (prefix == target)
            existed = !created;
    }

    if (existed) {
        std::wstring inner = findReparsePoint(target);
        if (!inner.empty())
            return fail(inner, ERROR_REPARSE_POINT_ENCOUNTERED);
    }

    PSID owner = nullptr;
    PACL dacl = nullptr;
    BOOL present = FALSE, defaulted = FALSE;
    GetSecurityDescriptorOwner(descriptor, &owner, &defaulted);
    GetSecurityDescriptorDacl(descriptor, &present, &dacl, &defaulted);
    // Administrators may make themselves the owner of anything a member created; files the service
    // (SYSTEM) wrote need the restore privilege, which an elevated token holds.
    enablePrivilege(L"SeRestorePrivilege");        // SE_RESTORE_NAME, whatever UNICODE is
    enablePrivilege(L"SeTakeOwnershipPrivilege");  // SE_TAKE_OWNERSHIP_NAME
    DWORD status = TreeResetNamedSecurityInfoW(const_cast<LPWSTR>(target.c_str()), SE_FILE_OBJECT,
                                               OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION
                                                   | PROTECTED_DACL_SECURITY_INFORMATION,
                                               owner, nullptr, dacl, nullptr, FALSE, nullptr,
                                               ProgressInvokeNever, nullptr);
    if (status != ERROR_SUCCESS)
        return fail(target, status);
    SecureDirectoryResult result;
    result.ok = true;
    return result;
}
