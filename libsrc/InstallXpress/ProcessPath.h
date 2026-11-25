#pragma once

#include <windows.h>
#include <tlhelp32.h>
#include <atlbase.h>
#include <string>

// Stop all instances of this installed executable, waiting for Windows to release the image.
inline DWORD stopProcessAtPath(const std::wstring& path)
{
    constexpr DWORD pathCapacity = 32768;
    wchar_t fullPath[pathCapacity];
    DWORD length = GetFullPathNameW(path.c_str(), pathCapacity, fullPath, nullptr);
    if (length == 0)
        return GetLastError();
    if (length >= pathCapacity)
        return ERROR_FILENAME_EXCED_RANGE;

    if (GetFileAttributesW(fullPath) == INVALID_FILE_ATTRIBUTES) {
        DWORD error = GetLastError();
        return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? ERROR_SUCCESS : error;
    }

    wchar_t target[pathCapacity];
    length = GetLongPathNameW(fullPath, target, pathCapacity);
    if (length == 0)
        return GetLastError();
    if (length >= pathCapacity)
        return ERROR_FILENAME_EXCED_RANGE;
    const wchar_t* slash = wcsrchr(target, L'\\');
    if (!slash || !slash[1])
        return ERROR_INVALID_NAME;
    const wchar_t* name = slash + 1;

    HANDLE snapshotHandle = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshotHandle == INVALID_HANDLE_VALUE)
        return GetLastError();
    ATL::CHandle snapshot(snapshotHandle);

    PROCESSENTRY32W entry = { sizeof(entry) };
    for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) {
        if (CompareStringOrdinal(entry.szExeFile, -1, name, -1, TRUE) != CSTR_EQUAL)
            continue;

        constexpr DWORD queryAndWait = PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE;
        ATL::CHandle process(OpenProcess(queryAndWait | PROCESS_TERMINATE, FALSE, entry.th32ProcessID));
        bool canTerminate = process.m_h != nullptr;
        if (!canTerminate) {
            // Query the image even if the process cannot be terminated, to skip other installations.
            process.Attach(OpenProcess(queryAndWait, FALSE, entry.th32ProcessID));
            if (!process.m_h) {
                DWORD error = GetLastError();
                if (error == ERROR_INVALID_PARAMETER)  // The process exited since the snapshot.
                    continue;
                return error;
            }
        }

        wchar_t image[pathCapacity];
        DWORD size = pathCapacity;
        if (!QueryFullProcessImageNameW(process, 0, image, &size)) {
            DWORD error = GetLastError();
            if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0)
                continue;
            return error;
        }
        // Resolve short directory names before checking the complete executable path.
        if (CompareStringOrdinal(image, -1, target, -1, TRUE) != CSTR_EQUAL) {
            length = GetLongPathNameW(image, fullPath, pathCapacity);
            if (length == 0 || length >= pathCapacity ||
                CompareStringOrdinal(fullPath, -1, target, -1, TRUE) != CSTR_EQUAL)
                continue;
        }

        if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0)
            continue;
        if (!canTerminate)
            return ERROR_ACCESS_DENIED;
        if (!TerminateProcess(process, 0)) {
            DWORD error = GetLastError();
            if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0)
                continue;
            return error;
        }

        DWORD result = WaitForSingleObject(process, 10000);
        if (result != WAIT_OBJECT_0)
            return result == WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError();
    }

    DWORD error = GetLastError();
    return error == ERROR_NO_MORE_FILES ? ERROR_SUCCESS : error;
}
