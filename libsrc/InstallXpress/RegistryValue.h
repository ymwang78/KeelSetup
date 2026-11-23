#pragma once

// Registry values as the Lua API (installx.RegGetValue / RegSetValue) reads and writes them.

#include <windows.h>
#include <string>
#include <vector>

struct RegistryValue {
    enum Kind { Missing, Number, String, Unsupported };
    Kind kind = Missing;
    DWORD number = 0;      // REG_DWORD
    std::wstring text;     // REG_SZ, or REG_EXPAND_SZ as stored (unexpanded)
};

// Reads value `name` of an open key, of any length: REG_DWORD as a number; REG_SZ and REG_EXPAND_SZ
// (a service's ImagePath, the system PATH) as text, the latter unexpanded, as `reg query` shows it.
// Other types are Unsupported, an absent value Missing. An empty name reads the default value.
inline RegistryValue readRegistryValue(HKEY key, const std::wstring& name)
{
    RegistryValue result;
    std::vector<BYTE> data(1024 + sizeof(wchar_t));
    for (;;) {
        DWORD type = 0;
        // The spare wchar_t that RegQueryValueEx never writes keeps an unterminated string terminated.
        DWORD size = static_cast<DWORD>(data.size() - sizeof(wchar_t));
        LONG status = RegQueryValueExW(key, name.c_str(), nullptr, &type, data.data(), &size);
        if (status == ERROR_MORE_DATA) {
            data.assign(size + sizeof(wchar_t), 0);
            continue;  // the value grew in between: query its new size again
        }
        if (status != ERROR_SUCCESS)
            return result;
        switch (type) {
        case REG_DWORD:
            if (size < sizeof(DWORD)) {
                result.kind = RegistryValue::Unsupported;
                break;
            }
            result.kind = RegistryValue::Number;
            result.number = *reinterpret_cast<const DWORD*>(data.data());
            break;
        case REG_SZ:
        case REG_EXPAND_SZ: {
            data[size] = 0;
            data[size + 1] = 0;
            result.kind = RegistryValue::String;
            result.text = reinterpret_cast<const wchar_t*>(data.data());
            break;
        }
        default:
            result.kind = RegistryValue::Unsupported;
            break;
        }
        return result;
    }
}

// Writes a string value with its terminator. A value that exists as REG_EXPAND_SZ stays
// REG_EXPAND_SZ: rewriting the system PATH as REG_SZ would leave its %SystemRoot% entries
// unexpanded. Anything else is written as REG_SZ.
inline LONG writeRegistryString(HKEY key, const std::wstring& name, const std::wstring& value)
{
    DWORD type = REG_SZ;
    DWORD existing = 0;
    if (RegQueryValueExW(key, name.c_str(), nullptr, &existing, nullptr, nullptr) == ERROR_SUCCESS
        && existing == REG_EXPAND_SZ)
        type = REG_EXPAND_SZ;
    return RegSetValueExW(key, name.c_str(), 0, type, reinterpret_cast<const BYTE*>(value.c_str()),
                          static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}

inline LONG writeRegistryDword(HKEY key, const std::wstring& name, DWORD value)
{
    return RegSetValueExW(key, name.c_str(), 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value));
}
