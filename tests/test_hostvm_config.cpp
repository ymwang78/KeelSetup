#include <gtest/gtest.h>
#include <filesystem>
#include <fstream>
#include "../libsrc/InstallXpress/HostVMConfig.h"

class HostVMConfigTest : public ::testing::Test {
protected:
    std::filesystem::path path;
    void SetUp() override {
        wchar_t directory[MAX_PATH], filename[MAX_PATH];
        ASSERT_NE(GetTempPathW(MAX_PATH, directory), 0u);
        ASSERT_NE(GetTempFileNameW(directory, L"hvm", 0, filename), 0u);
        path = filename;
    }
    void TearDown() override { std::filesystem::remove(path); }
    bool parse(const char* xml, const wchar_t* root, std::vector<std::wstring>& names) {
        std::ofstream file(path, std::ios::binary);
        file << xml;
        file.close();
        return readHostVMSubvmNames(path.wstring(), root, names);
    }
    bool info(const char* xml, const wchar_t* name, std::wstring& value, bool& found) {
        std::ofstream file(path, std::ios::binary);
        file << xml;
        file.close();
        return readHostVMInfoAttribute(path.wstring(), name, value, found);
    }
};
TEST_F(HostVMConfigTest, InfoAttributeIsReadFromTheActiveElement) {
    std::wstring value;
    bool found = false;
    // UTF-8 with BOM, as the configs are saved; a commented-out hostvm_info does not count.
    ASSERT_TRUE(info("\xEF\xBB\xBF<hostvm_server><!-- <hostvm_info projects_dir='old'/> -->"
                     "<hostvm_info threadnum='2' projects_dir='../\xE5\xB7\xA5\xE7\xA8\x8B&amp;x'/>"
                     "<subvm_info vmname='a' projects_dir='no'/></hostvm_server>",
                     L"projects_dir", value, found));
    EXPECT_TRUE(found);
    EXPECT_EQ(value, L"../工程&x");
}
TEST_F(HostVMConfigTest, InfoAttributeMissingIsFoundFalse) {
    std::wstring value = L"stale";
    bool found = true;
    ASSERT_TRUE(info("<hostvm_server><hostvm_info threadnum='2'/></hostvm_server>", L"projects_dir", value, found));
    EXPECT_FALSE(found);
    EXPECT_TRUE(value.empty());
    ASSERT_TRUE(info("<hostvm_server><log projects_dir='x'/></hostvm_server>", L"projects_dir", value, found));
    EXPECT_FALSE(found);
}
TEST_F(HostVMConfigTest, InfoAttributeRejectsFragmentsMalformedAndMissingFiles) {
    std::wstring value;
    bool found = false;
    EXPECT_FALSE(info("<hostvm_fragment><hostvm_info projects_dir='x'/></hostvm_fragment>", L"projects_dir", value, found));
    EXPECT_FALSE(info("<hostvm_server><hostvm_info projects_dir='x'/>", L"projects_dir", value, found));
    EXPECT_FALSE(readHostVMInfoAttribute(path.wstring() + L".missing", L"projects_dir", value, found));
}
TEST_F(HostVMConfigTest, ReadsActiveNamesAndIgnoresComments) {
    std::vector<std::wstring> names;
    ASSERT_TRUE(parse("<hostvm_server><!-- <subvm_info vmname='ident'/> -->"
                      "<subvm_info vmname='host&#112;y'/></hostvm_server>", L"hostvm_server", names));
    ASSERT_EQ(names, std::vector<std::wstring>{L"hostpy"});
}
TEST_F(HostVMConfigTest, ReadsMultipleFragmentNames) {
    std::vector<std::wstring> names;
    ASSERT_TRUE(parse("<hostvm_fragment><subvm_info vmname='a'/><subvm_info vmname='b'/></hostvm_fragment>",
                      L"hostvm_fragment", names));
    ASSERT_EQ(names.size(), 2u);
}
TEST_F(HostVMConfigTest, RejectsMalformedWrongRootAndMissingNames) {
    for (const char* xml : {"<hostvm_server>", "<wrong/>",
                           "<hostvm_server><subvm_info/></hostvm_server>"}) {
        std::vector<std::wstring> names;
        EXPECT_FALSE(parse(xml, L"hostvm_server", names));
    }
}
TEST_F(HostVMConfigTest, RejectsDTD) {
    std::vector<std::wstring> names;
    EXPECT_FALSE(parse("<!DOCTYPE hostvm_server [<!ENTITY x 'hostpy'>]>"
                       "<hostvm_server><subvm_info vmname='&x;'/></hostvm_server>", L"hostvm_server", names));
}
#ifndef USE_GTEST_MAIN
int main(int argc, char** argv) {
    ::testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
}
#endif
