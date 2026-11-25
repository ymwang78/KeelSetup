#include "stdafx.h"
#include "MainFrame.h"
#include "resource.h"
#include <ShlObj.h>
#include <process.h>
#include <shellapi.h>
#include <Shlwapi.h>
#include <atomic>
#include <InstallXpress/ProcessPath.h>
#include <Utility/log.h>
#include "Utility/Utility.h"
#include <Utility/DirUtility.h>
#include <InstallXpress/LuaExtention.h>
#include <Utility/ResourceHandler.h>

static std::atomic<int> uninstallExitCode{0};

int CUninstallMainFrame::GetExitCode()
{
	return uninstallExitCode.load();
}

#define  WMPROGRESS_TIMER WM_USER+1000
#define  WMPROGRESSFINISH_TIMER WM_USER+1001
#define  WM_INSTALLPROGRES_MSG WM_USER+2000

#define  PORGRESSSHOWSEPLEN 50	  //进度条显示定时器步长;
#define  PORGRESSHIDESEPLEN 20	  //进度条隐藏定时器步长;

#define  MOVESIZE 20
#define  LEFTOFFSET 40            //进度条左侧距离;
#define  BUTTONMINSIZE 200		  //按钮最小值;

CUninstallMainFrame::CUninstallMainFrame(bool silent)
	:m_bUninstall(false)
	,m_bSilent(silent)
	,m_bWindowInitialized(false)
{
	m_pUnInstallprogress = NULL;
	m_pStarUnInstallbtn = NULL;
	m_pUnFinishbtn = NULL;
	m_luaPtr = NULL;
	m_hThread = NULL;
	m_strname = _T("");
	m_strplid = _T("zdey");
}


CUninstallMainFrame::~CUninstallMainFrame()
{
	PostQuitMessage(0);
}

void CUninstallMainFrame::InitWindow()
{
	CenterWindow();
}

LPCTSTR CUninstallMainFrame::GetWindowClassName(void) const
{
	return _T("KeelBaseUnInstallFrame");
}

CDuiString CUninstallMainFrame::GetSkinFile()
{
	TCHAR szBuf[MAX_PATH] = { 0 };
	_stprintf_s(szBuf, MAX_PATH - 1, _T("%d"), IDR_MAIN_XML);
	return szBuf;
}

CDuiString CUninstallMainFrame::GetSkinFolder()
{
	return _T("");
}

UILIB_RESOURCETYPE CUninstallMainFrame::GetResourceType() const
{
	return UILIB_RESOURCE;
}

void CUninstallMainFrame::OnFinalMessage(HWND hWnd)
{
	delete this;
}

ResourceHandler* CUninstallMainFrame::LoadResourceFile(UINT uId, LPCTSTR lpType)
{
    auto iter = m_resHandlerMap.find(uId);
    if (iter != m_resHandlerMap.end())
        return iter->second;
    ResourceHandler* handler = new ResourceHandler(m_PaintManager.GetResourceDll(), MAKEINTRESOURCE(uId), lpType);
    if (handler->GetData() == NULL) {
        delete handler;
        return NULL;
    }
    m_resHandlerMap.insert(std::make_pair(uId, handler));
    return handler;
}

void CUninstallMainFrame::WindowInitialized()
{
	if (m_bWindowInitialized)
		return;
	m_bWindowInitialized = true;

	string file = CDirUtility::GetProgramPath();
	m_filepath = CTypeConvertUtil::StringToWstring(file);

	m_pUnInstallprogress = static_cast<CProgressUI*>(m_PaintManager.FindControl(_T("uninstallprogress")));
	m_pStarUnInstallbtn = static_cast<CButtonUI*>(m_PaintManager.FindControl(_T("staruninstallbtn")));
	m_pUnFinishbtn = static_cast<CButtonUI*>(m_PaintManager.FindControl(_T("uninstallfinishbtn")));
	m_pCloseBtn = static_cast<CButtonUI*>(m_PaintManager.FindControl(_T("closebtn")));
	m_luaPtr = new InstallLua(&m_PaintManager, UnicodeToUtf8(CDirUtility().Version()));
#ifdef DEBUG
	m_luaPtr->load_file("UnInstall.lua");
#else
	ResourceHandler* luaScript = LoadResourceFile(IDR_LUA_SCRIPT, _T("LUA_SCRIPT"));
	if (luaScript)
		m_luaPtr->load_string(std::string((const char*)luaScript->GetData(), luaScript->GetSize()).c_str());
#endif
	m_luaPtr->OnInitialize();
}

// /s: the same work as the confirmed button, without the confirmation, the start animation and the
// finish button; UnInstall() closes the uninstaller when it is done.
void CUninstallMainFrame::StartSilentUnInstall()
{
	WindowInitialized();
	m_hThread = (HANDLE)_beginthreadex(NULL, 0, &CUninstallMainFrame::UnInstallThread, this, 0, NULL);
}

void CUninstallMainFrame::Notify(TNotifyUI& msg)
{
	if (_tcsicmp(msg.sType, DUI_MSGTYPE_WINDOWINIT) == 0)
	{
		WindowInitialized();
	}
	else if (_tcsicmp(msg.sType, DUI_MSGTYPE_CLICK) == 0)
	{
		if (_tcsicmp(msg.pSender->GetName(), _T("staruninstallbtn")) == 0)
		{
			if (m_pStarUnInstallbtn) m_pStarUnInstallbtn->SetVisible(false);
			if (m_pUnInstallprogress) m_pUnInstallprogress->SetVisible(true);

			if (m_pCloseBtn) m_pCloseBtn->SetEnabled(false);
			SetTimer(this->GetHWND(), WMPROGRESS_TIMER, PORGRESSSHOWSEPLEN, 0);
		}
		else if (_tcsicmp(msg.pSender->GetName(), _T("uninstallfinishbtn")) == 0)
		{
			ClearUnInstall();
		}
		else if (_tcsicmp(msg.pSender->GetName(), _T("closebtn")) == 0)
		{
			if (m_bUninstall)
				ClearUnInstall();
			else
				PostMessage(WM_CLOSE, 0, 0);
		}
	}
}

LRESULT CUninstallMainFrame::HandleMessage(UINT uMsg, WPARAM wParam, LPARAM lParam)
{
	if (uMsg == WM_TIMER)
	{
		if (wParam == WMPROGRESS_TIMER)
		{
			if (NULL == m_pUnInstallprogress)
			{
				::KillTimer(this->GetHWND(), WMPROGRESS_TIMER);
			}
			else
			{
				RECT rc = m_pUnInstallprogress->GetPos();
				if (rc.left - MOVESIZE < LEFTOFFSET)
				{
					m_pUnInstallprogress->SetValue(15);
					::KillTimer(this->GetHWND(), WMPROGRESS_TIMER);
					m_hThread = (HANDLE)_beginthreadex(NULL, 0, &CUninstallMainFrame::UnInstallThread, this, 0, NULL);
					return 0;
				}
				rc.left -= MOVESIZE;
				rc.right += MOVESIZE;
				m_pUnInstallprogress->SetPos(rc);
			}
		}
		else if (WMPROGRESSFINISH_TIMER == wParam)
		{
			if (NULL == m_pUnInstallprogress)
			{
				::KillTimer(this->GetHWND(), WMPROGRESSFINISH_TIMER);
				return 0;
			}
			RECT rc = m_pUnInstallprogress->GetPos();
			if (rc.right - rc.left <= BUTTONMINSIZE)
			{
				::KillTimer(this->GetHWND(), WMPROGRESSFINISH_TIMER);
				m_pUnInstallprogress->SetVisible(false);
				m_pUnFinishbtn->SetVisible(true);
				if (m_pCloseBtn) m_pCloseBtn->SetEnabled(true);
				m_bUninstall = true;
				return 0;
			}
			rc.left += MOVESIZE;
			rc.right -= MOVESIZE;
			m_pUnInstallprogress->SetPos(rc);
		}
	}
	return WindowImplBase::HandleMessage(uMsg, wParam, lParam);
}

LRESULT CUninstallMainFrame::HandleCustomMessage(UINT uMsg, WPARAM wParam, LPARAM lParam, BOOL& bHandled)
{
	if (WM_INSTALLPROGRES_MSG == uMsg)
	{
		if (m_pUnInstallprogress)
		{
			DUITRACE(_T("- UnInstallprogress: %lu \n"), lParam);
			m_pUnInstallprogress->SetValue(lParam);
			CDuiString str;
			str.Format(_T("已卸载%d%%"), lParam);
			m_pUnInstallprogress->SetText(str.GetData());
		}
	}
	return WindowImplBase::HandleCustomMessage(uMsg, wParam, lParam, bHandled);
}

unsigned int _stdcall CUninstallMainFrame::UnInstallThread(void* param)
{
	CUninstallMainFrame* pThis = (CUninstallMainFrame*)param;
	if (NULL != pThis)
		pThis->UnInstall();
	return 0;
}

void CUninstallMainFrame::ClearUnInstall()
{
	CRegOperation reg;
    std::wstring strkey = L"Software" L"\\" COMPANYNAME;

	reg.DeleteKey(HKEY_CURRENT_USER, strkey.c_str(), PRODUCTNAME);

	// Once this process has exited: the uninstaller's own directory, then the install path above it,
	// which a plain rmdir only removes when nothing (the instances' Data\) is left in it.
	std::string syscmd = "/C ping 127.0.0.1 -n 5 > nul & rmdir /s /Q \"" + m_strUnInstallDir + "\" & rmdir \""
		+ ParentDir(m_strUnInstallDir) + "\"";
	ShellExecuteA(NULL, NULL, "cmd.exe", syscmd.c_str(), NULL, SW_HIDE);
	PostMessage(WM_CLOSE, 0, 0);
}

// "C:\\TaijiControl\\KeelBase\\Uninstall\\" -> "C:\\TaijiControl\\KeelBase": the install path, which
// holds the uninstaller's directory.
std::string CUninstallMainFrame::ParentDir(std::string dir)
{
	while (!dir.empty() && (dir.back() == '\\' || dir.back() == '/'))
		dir.pop_back();
	size_t slash = dir.find_last_of("\\/");
	return slash == std::string::npos ? dir : dir.substr(0, slash);
}

void CUninstallMainFrame::UnInstall()
{
	m_pUnInstallprogress->SetText(_T("已卸载1%..."));
	m_strUnInstallDir = CDirUtility::GetProgramInPath();
    std::wstring wstrdir = CTypeConvertUtil::StringToWstring(m_strUnInstallDir);

	CDuiString hintString;
	std::wstring installDir = CTypeConvertUtil::StringToWstring(ParentDir(m_strUnInstallDir));
	hintString.Format(L"是否卸载 KeelBase（%s）？KeelBase 服务和程序文件将被删除，实例数据（%s\\Data）保留。",
		installDir.c_str(), installDir.c_str());
	int ret = m_bSilent ? IDOK : MessageBox(GetHWND(), hintString, L"提示", MB_OKCANCEL);
	if (ret == IDCANCEL)
	{
		// Nothing was uninstalled: close. The finish animation would set m_bUninstall, and its
		// finish and close buttons would then call ClearUnInstall(), which deletes the uninstaller
		// and leaves the rest of the installation without one.
		PostMessage(WM_CLOSE, 0, 0);
		return;
	}

	// Use the same directory as Lua, which deletes Deck and Tools in PreSetup().
	std::wstring cleanupDir = m_luaPtr ? Utf82Unicode(m_luaPtr->QueryByKey_String("InstallPath")) : L"";
	if (cleanupDir.empty())
		cleanupDir = installDir;
	for (const wchar_t* executable : { L"\\Deck\\KeelDeck.exe", L"\\Tools\\kbased.exe" })
	{
		std::wstring path = cleanupDir + executable;
		DWORD error = stopProcessAtPath(path);
		if (error != ERROR_SUCCESS)
		{
			APPLOG(Log::LOG_ERROR)("Cannot stop %s (error %lu)\n", UnicodeToUtf8(path).c_str(), error);
			if (!m_bSilent)
			{
				hintString.Format(L"无法关闭 %s（错误 %lu）。请退出该程序后重新运行卸载。", path.c_str(), error);
				MessageBox(GetHWND(), hintString, L"KeelBase", MB_OK | MB_ICONERROR);
			}
			uninstallExitCode = 1;
			PostMessage(WM_CLOSE, 0, 0);
			return;
		}
	}

    // Product-specific cleanup (services, COM, registry, shortcuts, sibling
    // directories) is implemented in UnInstall.lua PreSetup().
    if (m_luaPtr)
        m_luaPtr->PreSetup();

	int nUnInstall = 0;  //要删除文件个数;
	int ndelindex = 0;	 //已删除文件个数;

	//计算卸载数量(文件夹为单位);
	GetUnInstallSize(wstrdir, nUnInstall);
	//删除文件();
	DeleteAllFile(wstrdir, ndelindex, nUnInstall);

	//设置进度条;
	m_pUnInstallprogress->SetValue(100);
	CDuiString str;
	str.Format(_T("已卸载%d%%"), 100);
	m_pUnInstallprogress->SetText(str.GetData());
	if (m_bSilent)
		ClearUnInstall();
	else
		SetTimer(this->GetHWND(), WMPROGRESSFINISH_TIMER, PORGRESSHIDESEPLEN, 0);
}

void CUninstallMainFrame::GetUnInstallSize(std::wstring &strFile, int &nUnInstall)
{
	if (strFile[strFile.length() - 1] != '\\')
	{
		strFile.append(1, '\\');
	}
	std::wstring szDir = strFile + L"*.*";

	BOOL bRet;
	WIN32_FIND_DATA FindFileData;
	HANDLE hFind;
	hFind = FindFirstFile(szDir.c_str(), &FindFileData);
	while (hFind != INVALID_HANDLE_VALUE)
	{
		bRet = ::FindNextFile(hFind, &FindFileData);
		if (!bRet) break;

		if (FindFileData.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY && !(FindFileData.cFileName[0] == '.')
			&& !(FindFileData.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT))
		{
			//如果是一个子目录，用递归继续往深一层找 ;
			std::wstring strPath(FindFileData.cFileName);
			strPath = strFile + strPath;
			GetUnInstallSize(strPath, nUnInstall);
		}
	}
	if (strFile[strFile.length() - 1] == '\\')
	{
		strFile = strFile.substr(0, strFile.length() - 1);
	}
	FindClose(hFind);
	nUnInstall++;
}

void CUninstallMainFrame::DeleteAllFile(std::wstring &strFile, int &nCurUnInstall, int nUnInstall)
{
	if (strFile[strFile.length() - 1] != '\\')
	{
		strFile.append(1, '\\');
	}
	std::wstring szDir = strFile + L"*.*";

	BOOL bRet;
	WIN32_FIND_DATA FindFileData;
	HANDLE hFind;
	hFind = FindFirstFile(szDir.c_str(), &FindFileData);
	while (hFind != INVALID_HANDLE_VALUE)
	{
		bRet = ::FindNextFile(hFind, &FindFileData);
		if (!bRet) break;

		if ((FindFileData.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) && !(FindFileData.cFileName[0] == '.'))
		{
			// A junction or link: remove the link itself, never what it points at.
			std::wstring strPath = strFile + FindFileData.cFileName;
			if (FindFileData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
				RemoveDirectory(strPath.c_str());
			else
				DeleteFile(strPath.c_str());
		}
		else if (FindFileData.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY && !(FindFileData.cFileName[0] == '.'))
		{
			//如果是一个子目录，用递归继续往深一层找 ;
			std::wstring strPath(FindFileData.cFileName);
			strPath = strFile + strPath;
			DeleteAllFile(strPath, nCurUnInstall, nUnInstall);
		}
		else if (!(FindFileData.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) && !(FindFileData.cFileName[0] == '.'))
		{
			//显示当前访问的文件(完整路径) ;
			std::wstring strPath(FindFileData.cFileName);
			strPath = strFile + strPath;

			if (_tcsicmp(strPath.c_str(), m_filepath.c_str()) != 0)
			{
				DeleteFile(strPath.c_str());
			}
		}
	}
	if (strFile[strFile.length() - 1] == '\\')
	{
		strFile = strFile.substr(0, strFile.length() - 1);
	}
	FindClose(hFind);
	SetFileAttributes(strFile.c_str(), FILE_ATTRIBUTE_NORMAL);
	RemoveDirectory(strFile.c_str());

	//更新进度条;
	nCurUnInstall++;
	int nprogressvalue = (nCurUnInstall) / (nUnInstall*1.0) * 100 + 15;
	if (nprogressvalue >= 100) nprogressvalue = 98;
	::PostMessage(this->GetHWND(), WM_INSTALLPROGRES_MSG, 0, nprogressvalue);
	Sleep(60);
}
