// installx.RegGetValue / RegSetValue: the value types and lengths they read and write.
// Uses a scratch key under HKEY_CURRENT_USER\Software, deleted afterwards.
#include <gtest/gtest.h>
#include <string>
#include "../libsrc/InstallXpress/RegistryValue.h"

class RegistryValueFixture : public ::testing::Test {
protected:
    HKEY key = nullptr;
    std::wstring path;
    void SetUp() override {
        path = L"Software\\KeelSetupTest\\RegistryValue" + std::to_wstring(GetCurrentProcessId());
        ASSERT_EQ(RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0, KEY_ALL_ACCESS, nullptr, &key, nullptr),
                  ERROR_SUCCESS);
    }
    void TearDown() override {
        RegCloseKey(key);
        RegDeleteTreeW(HKEY_CURRENT_USER, path.c_str());
        RegDeleteKeyW(HKEY_CURRENT_USER, L"Software\\KeelSetupTest");
    }
    void setRaw(const wchar_t* name, DWORD type, const std::wstring& text) {
        ASSERT_EQ(RegSetValueExW(key, name, 0, type, reinterpret_cast<const BYTE*>(text.c_str()),
                                 static_cast<DWORD>((text.size() + 1) * sizeof(wchar_t))), ERROR_SUCCESS);
    }
    DWORD typeOf(const wchar_t* name) {
        DWORD type = 0;
        EXPECT_EQ(RegQueryValueExW(key, name, nullptr, &type, nullptr, nullptr), ERROR_SUCCESS);
        return type;
    }
};

// A service's ImagePath is REG_EXPAND_SZ: the installer checks which executable a service runs.
TEST_F(RegistryValueFixture, ExpandStringIsReadUnexpanded) {
    setRaw(L"ImagePath", REG_EXPAND_SZ, L"\"%SystemRoot%\\HostVM\\HostVM.exe\" daemon HostVM");
    RegistryValue value = readRegistryValue(key, L"ImagePath");
    ASSERT_EQ(value.kind, RegistryValue::String);
    EXPECT_EQ(value.text, L"\"%SystemRoot%\\HostVM\\HostVM.exe\" daemon HostVM");
}

// The system PATH is often longer than the 1024 bytes the reader used to stop at.
TEST_F(RegistryValueFixture, LongStringIsReadWhole) {
    std::wstring text;
    for (int i = 0; i < 400; ++i) text += L"C:\\Dir" + std::to_wstring(i) + L";";
    ASSERT_GT(text.size() * sizeof(wchar_t), 4096u);
    setRaw(L"Path", REG_EXPAND_SZ, text);
    RegistryValue value = readRegistryValue(key, L"Path");
    ASSERT_EQ(value.kind, RegistryValue::String);
    EXPECT_EQ(value.text, text);
}

TEST_F(RegistryValueFixture, DwordAndMissingAndOtherTypes) {
    ASSERT_EQ(writeRegistryDword(key, L"Installed", 1), ERROR_SUCCESS);
    EXPECT_EQ(typeOf(L"Installed"), static_cast<DWORD>(REG_DWORD));
    RegistryValue value = readRegistryValue(key, L"Installed");
    ASSERT_EQ(value.kind, RegistryValue::Number);
    EXPECT_EQ(value.number, 1u);
    EXPECT_EQ(readRegistryValue(key, L"Absent").kind, RegistryValue::Missing);
    const BYTE blob[3] = {1, 2, 3};
    ASSERT_EQ(RegSetValueExW(key, L"Blob", 0, REG_BINARY, blob, sizeof(blob)), ERROR_SUCCESS);
    EXPECT_EQ(readRegistryValue(key, L"Blob").kind, RegistryValue::Unsupported);
}

// Rewriting PATH must keep it REG_EXPAND_SZ, or its %SystemRoot% entries stop working; a new
// value or a REG_SZ one is REG_SZ. The terminator is stored.
TEST_F(RegistryValueFixture, StringWriteKeepsExpandType) {
    setRaw(L"Path", REG_EXPAND_SZ, L"%SystemRoot%\\system32;C:\\Old");
    ASSERT_EQ(writeRegistryString(key, L"Path", L"%SystemRoot%\\system32"), ERROR_SUCCESS);
    EXPECT_EQ(typeOf(L"Path"), static_cast<DWORD>(REG_EXPAND_SZ));
    EXPECT_EQ(readRegistryValue(key, L"Path").text, L"%SystemRoot%\\system32");

    ASSERT_EQ(writeRegistryString(key, L"InstallPath", L"C:\\TaijiControl"), ERROR_SUCCESS);
    EXPECT_EQ(typeOf(L"InstallPath"), static_cast<DWORD>(REG_SZ));
    DWORD type = 0, size = 0;
    ASSERT_EQ(RegQueryValueExW(key, L"InstallPath", nullptr, &type, nullptr, &size), ERROR_SUCCESS);
    EXPECT_EQ(size, (wcslen(L"C:\\TaijiControl") + 1) * sizeof(wchar_t));
}

// A non-ASCII value comes back as written (the Lua side converts it to and from UTF-8).
TEST_F(RegistryValueFixture, UnicodeRoundTrip) {
    ASSERT_EQ(writeRegistryString(key, L"InstallPath", L"D:\\测试\\KeelBase"), ERROR_SUCCESS);
    EXPECT_EQ(readRegistryValue(key, L"InstallPath").text, L"D:\\测试\\KeelBase");
}

#ifndef USE_GTEST_MAIN
int main(int argc, char** argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
#endif
