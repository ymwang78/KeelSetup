#pragma once
class InstallLua;
class ResourceHandler;

class CUninstallMainFrame : public WindowImplBase
{
public:
	// silent: /s, no confirmation and no window; the uninstaller closes itself when done.
	explicit CUninstallMainFrame(bool silent = false);
	~CUninstallMainFrame();

public:
	void InitWindow();
	// Loads UnInstall.lua and calls OnInitialize(), once: on DUI_MSGTYPE_WINDOWINIT, or directly
	// for a silent uninstall, whose window is never shown and so never gets that message.
	void WindowInitialized();
	void StartSilentUnInstall();
	LPCTSTR GetWindowClassName(void) const;
    ResourceHandler* LoadResourceFile(UINT uId, LPCTSTR lpType);

	virtual CDuiString GetSkinFile();
	virtual CDuiString GetSkinFolder();
	virtual UILIB_RESOURCETYPE GetResourceType() const;

	virtual void OnFinalMessage(HWND hWnd);
	virtual void Notify(TNotifyUI& msg);
	virtual LRESULT HandleMessage(UINT uMsg, WPARAM wParam, LPARAM lParam);
	virtual LRESULT HandleCustomMessage(UINT uMsg, WPARAM wParam, LPARAM lParam, BOOL& bHandled);

public:
	static unsigned int _stdcall UnInstallThread(void* param);
	void ClearUnInstall();
	void UnInstall();
	void KillProcess();
	bool IsInInstallDir(const std::wstring& path) const;
	static std::string ParentDir(std::string dir);
	BOOL ProcessPrivilege(BOOL bEnable);
	void GetUnInstallSize(std::wstring &strFile, int &nUnInstall);
	void DeleteAllFile(std::wstring &strFile, int &nCurUnInstall, int nUnInstall);

public:
	HANDLE m_hThread;
	bool m_bUninstall;
	bool m_bSilent;
	bool m_bWindowInitialized;
	std::wstring m_filepath;
	std::string  m_strUnInstallDir;
	std::wstring m_strname;
	std::wstring m_strplid;
    InstallLua* m_luaPtr;
	CProgressUI*	m_pUnInstallprogress;
	CButtonUI*		m_pStarUnInstallbtn;
	CButtonUI*		m_pUnFinishbtn;
	CButtonUI*      m_pCloseBtn;
    std::map<UINT, ResourceHandler*> m_resHandlerMap;
};
