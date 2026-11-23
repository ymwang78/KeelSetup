// installx.FilePathSecure: secureDirectory() in libsrc/InstallXpress/FileSecurity.h.
// Works in a scratch directory under %TEMP%, deleted afterwards. Run elevated: setting another
// owner and the protected DACL's Administrators owner need an administrator's token.
#include <gtest/gtest.h>
#include <filesystem>
#include <fstream>
#include <string>
#include "../libsrc/InstallXpress/FileSecurity.h"

namespace {

struct AceSummary {
    int total = 0;
    int explicitAces = 0;
    ACCESS_MASK users = 0, system = 0, administrators = 0, others = 0;
    bool isProtected = false;
    bool ownerIsAdministrators = false;
};

AceSummary summarize(const std::wstring& path)
{
    AceSummary summary;
    PSID owner = nullptr;
    PACL dacl = nullptr;
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    EXPECT_EQ(GetNamedSecurityInfoW(path.c_str(), SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
                                    &owner, nullptr, &dacl, nullptr, &descriptor), (DWORD)ERROR_SUCCESS);
    if (descriptor == nullptr)
        return summary;
    SECURITY_DESCRIPTOR_CONTROL control = 0;
    DWORD revision = 0;
    GetSecurityDescriptorControl(descriptor, &control, &revision);
    summary.isProtected = (control & SE_DACL_PROTECTED) != 0;
    summary.ownerIsAdministrators = IsWellKnownSid(owner, WinBuiltinAdministratorsSid) != FALSE;
    for (DWORD i = 0; dacl != nullptr && i < dacl->AceCount; ++i) {
        ACCESS_ALLOWED_ACE* ace = nullptr;
        if (!GetAce(dacl, i, reinterpret_cast<void**>(&ace)) || ace->Header.AceType != ACCESS_ALLOWED_ACE_TYPE)
            continue;
        ++summary.total;
        if (!(ace->Header.AceFlags & INHERITED_ACE) && !summary.isProtected)
            ++summary.explicitAces;
        PSID sid = &ace->SidStart;
        if (IsWellKnownSid(sid, WinBuiltinUsersSid)) summary.users |= ace->Mask;
        else if (IsWellKnownSid(sid, WinLocalSystemSid)) summary.system |= ace->Mask;
        else if (IsWellKnownSid(sid, WinBuiltinAdministratorsSid)) summary.administrators |= ace->Mask;
        else summary.others |= ace->Mask;
    }
    LocalFree(descriptor);
    return summary;
}

const ACCESS_MASK kWriteRights = FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA | FILE_WRITE_ATTRIBUTES
    | FILE_DELETE_CHILD | DELETE | WRITE_DAC | WRITE_OWNER | GENERIC_WRITE | GENERIC_ALL;

bool makeJunction(const std::wstring& link, const std::wstring& target)
{
    std::wstring command = L"cmd.exe /c mklink /J \"" + link + L"\" \"" + target + L"\" >nul";
    return _wsystem(command.c_str()) == 0;
}

void setSecurity(const std::wstring& path, const wchar_t* sddl, SECURITY_INFORMATION what)
{
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    ASSERT_TRUE(ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, SDDL_REVISION_1, &descriptor, nullptr));
    PSID owner = nullptr;
    PACL dacl = nullptr;
    BOOL present = FALSE, defaulted = FALSE;
    GetSecurityDescriptorOwner(descriptor, &owner, &defaulted);
    GetSecurityDescriptorDacl(descriptor, &present, &dacl, &defaulted);
    file_security::enablePrivilege(L"SeRestorePrivilege");
    EXPECT_EQ(SetNamedSecurityInfoW(const_cast<LPWSTR>(path.c_str()), SE_FILE_OBJECT, what, owner, nullptr, dacl, nullptr),
              (DWORD)ERROR_SUCCESS);
    LocalFree(descriptor);
}

}  // namespace

class SecureDirectoryFixture : public ::testing::Test {
protected:
    std::wstring base;
    void SetUp() override {
        wchar_t temp[MAX_PATH];
        ASSERT_NE(GetTempPathW(MAX_PATH, temp), 0u);
        base = std::wstring(temp) + L"KeelSetupFileSecurity" + std::to_wstring(GetCurrentProcessId());
        std::filesystem::remove_all(base);
        ASSERT_TRUE(CreateDirectoryW(base.c_str(), nullptr));
        base = std::filesystem::path(base).wstring();
        while (!base.empty() && base.back() == L'\\') base.pop_back();
    }
    void TearDown() override {
        // Junctions first, so that nothing is deleted through them.
        for (const wchar_t* link : {L"\\link", L"\\inside\\junction"})
            RemoveDirectoryW((base + link).c_str());
        std::error_code ignored;
        std::filesystem::remove_all(base, ignored);
    }
    void writeFile(const std::wstring& path) {
        std::filesystem::create_directories(std::filesystem::path(path).parent_path());
        std::ofstream(path) << "x";
    }
};

TEST_F(SecureDirectoryFixture, MissingDirectoriesAreCreatedProtected) {
    SecureDirectoryResult result = secureDirectory(base + L"\\a\\b", true);
    ASSERT_TRUE(result.ok) << result.error;
    for (const auto& path : {base + L"\\a", base + L"\\a\\b"}) {
        AceSummary summary = summarize(path);
        EXPECT_TRUE(summary.isProtected);
        EXPECT_TRUE(summary.ownerIsAdministrators);
        EXPECT_EQ(summary.system, (ACCESS_MASK)FILE_ALL_ACCESS);
        EXPECT_EQ(summary.administrators, (ACCESS_MASK)FILE_ALL_ACCESS);
        EXPECT_EQ(summary.users, (ACCESS_MASK)(FILE_GENERIC_READ | FILE_GENERIC_EXECUTE));
        EXPECT_EQ(summary.others, 0u);
    }
}

// A tree that existed with rights for everybody (a file someone planted keeps an explicit entry):
// afterwards Users can read, nobody but SYSTEM and Administrators can write, Administrators own it.
TEST_F(SecureDirectoryFixture, ExistingTreeLosesWriteRightsAndExplicitEntries) {
    std::wstring planted = base + L"\\tree\\keelhost.d\\900-planted.xml";
    writeFile(planted);
    setSecurity(base + L"\\tree", L"D:(A;OICI;FA;;;BU)", DACL_SECURITY_INFORMATION);
    setSecurity(planted, L"D:(A;;FA;;;WD)", DACL_SECURITY_INFORMATION);
    ASSERT_EQ(summarize(planted).others, (ACCESS_MASK)FILE_ALL_ACCESS);

    SecureDirectoryResult result = secureDirectory(base + L"\\tree", true);
    ASSERT_TRUE(result.ok) << result.error;
    for (const auto& path : {base + L"\\tree", base + L"\\tree\\keelhost.d", planted}) {
        AceSummary summary = summarize(path);
        EXPECT_TRUE(summary.ownerIsAdministrators) << path.c_str();
        EXPECT_EQ(summary.users & kWriteRights, 0u) << path.c_str();
        EXPECT_EQ(summary.others, 0u) << path.c_str();
        EXPECT_EQ(summary.explicitAces, 0) << path.c_str();
    }
}

// Data\: the instances' configs carry tokens, so not even readable by Users.
TEST_F(SecureDirectoryFixture, WithoutUsersNobodyElseHasAnEntry) {
    writeFile(base + L"\\data\\kbase01\\kbase_server.json");
    ASSERT_TRUE(secureDirectory(base + L"\\data", false).ok);
    AceSummary summary = summarize(base + L"\\data\\kbase01\\kbase_server.json");
    EXPECT_EQ(summary.users, 0u);
    EXPECT_EQ(summary.others, 0u);
    EXPECT_EQ(summary.system, (ACCESS_MASK)FILE_ALL_ACCESS);
}

// A junction on the way would make the installer extract, and start a service, somewhere else.
TEST_F(SecureDirectoryFixture, JunctionInThePathIsRefusedAndNothingIsCreatedBehindIt) {
    ASSERT_TRUE(CreateDirectoryW((base + L"\\real").c_str(), nullptr));
    ASSERT_TRUE(makeJunction(base + L"\\link", base + L"\\real"));
    SecureDirectoryResult result = secureDirectory(base + L"\\link\\KeelBase", true);
    EXPECT_FALSE(result.ok);
    EXPECT_EQ(result.error, (DWORD)ERROR_REPARSE_POINT_ENCOUNTERED);
    EXPECT_EQ(result.problem, base + L"\\link");
    EXPECT_FALSE(std::filesystem::exists(base + L"\\real\\KeelBase"));
}

TEST_F(SecureDirectoryFixture, JunctionInsideIsRefusedAndTheTreeIsLeftAsItWas) {
    ASSERT_TRUE(CreateDirectoryW((base + L"\\inside").c_str(), nullptr));
    ASSERT_TRUE(CreateDirectoryW((base + L"\\real").c_str(), nullptr));
    ASSERT_TRUE(makeJunction(base + L"\\inside\\junction", base + L"\\real"));
    SecureDirectoryResult result = secureDirectory(base + L"\\inside", true);
    EXPECT_FALSE(result.ok);
    EXPECT_EQ(result.problem, base + L"\\inside\\junction");
    EXPECT_FALSE(summarize(base + L"\\inside").isProtected);
    EXPECT_FALSE(summarize(base + L"\\real").isProtected);
}

// A directory another user created before the administrator installs (its owner can change its
// DACL back, or delete and replace what is below it) is refused, as the target or as a parent.
TEST_F(SecureDirectoryFixture, DirectoryOwnedByAnotherUserIsRefused) {
    ASSERT_TRUE(CreateDirectoryW((base + L"\\foreign").c_str(), nullptr));
    setSecurity(base + L"\\foreign", L"O:BU", OWNER_SECURITY_INFORMATION);
    SecureDirectoryResult target = secureDirectory(base + L"\\foreign", true);
    EXPECT_FALSE(target.ok);
    EXPECT_EQ(target.error, (DWORD)ERROR_INVALID_OWNER);
    SecureDirectoryResult child = secureDirectory(base + L"\\foreign\\KeelBase", true);
    EXPECT_FALSE(child.ok);
    EXPECT_EQ(child.problem, base + L"\\foreign");
    EXPECT_FALSE(std::filesystem::exists(base + L"\\foreign\\KeelBase"));
}

TEST_F(SecureDirectoryFixture, OnlyAbsoluteDrivePathsAreAccepted) {
    for (const wchar_t* path : {L"relative\\KeelBase", L"\\\\server\\share\\KeelBase", L"C:", L"C:\\", L"C:\\a\\\\b"}) {
        SecureDirectoryResult result = secureDirectory(path, true);
        EXPECT_FALSE(result.ok) << path;
        EXPECT_EQ(result.error, (DWORD)ERROR_BAD_PATHNAME) << path;
    }
}

// installx.FilePathDelete: a junction in the tree goes, what it points at stays.
TEST_F(SecureDirectoryFixture, DeleteRemovesJunctionsWithoutFollowingThem) {
    writeFile(base + L"\\real\\precious.txt");
    writeFile(base + L"\\inside\\program.exe");
    SetFileAttributesW((base + L"\\inside\\program.exe").c_str(), FILE_ATTRIBUTE_READONLY);
    ASSERT_TRUE(makeJunction(base + L"\\inside\\junction", base + L"\\real"));
    EXPECT_TRUE(deleteDirectoryTree(base + L"\\inside"));
    EXPECT_FALSE(std::filesystem::exists(base + L"\\inside"));
    EXPECT_TRUE(std::filesystem::exists(base + L"\\real\\precious.txt"));
    // A junction given as the directory itself is removed as a link too.
    ASSERT_TRUE(makeJunction(base + L"\\link", base + L"\\real"));
    EXPECT_TRUE(deleteDirectoryTree(base + L"\\link"));
    EXPECT_FALSE(std::filesystem::exists(base + L"\\link"));
    EXPECT_TRUE(std::filesystem::exists(base + L"\\real\\precious.txt"));
}

#ifndef USE_GTEST_MAIN
int main(int argc, char** argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
#endif
