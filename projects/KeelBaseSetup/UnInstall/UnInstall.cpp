// UnInstall.cpp : entry point of the KeelBase uninstaller. The product-specific cleanup is in
// res/UnInstall.lua; /s uninstalls without asking and without showing the window.
//

#include "stdafx.h"
#include "UnInstall.h"
#include <shlobj.h>
#include <shellapi.h>
#include "MainFrame.h"

static bool IsSilentCommandLine()
{
	int argc = 0;
	LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
	if (!argv)
		return false;
	bool silent = false;
	for (int i = 1; i < argc && !silent; ++i)
		silent = _wcsicmp(argv[i], L"/s") == 0;
	LocalFree(argv);
	return silent;
}

int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPWSTR    lpCmdLine,
                     _In_ int       nCmdShow)
{
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);
	::CoInitialize(NULL);
	::OleInitialize(NULL);

	CPaintManagerUI::SetInstance(hInstance);
	CPaintManagerUI::SetResourcePath(CPaintManagerUI::GetInstancePath() + _T(".."));

	const bool silent = IsSilentCommandLine();
	CUninstallMainFrame* pMainFrame = new CUninstallMainFrame(silent);
	if (pMainFrame)
	{
		pMainFrame->Create(NULL, _T("KeelBase 卸载"), UI_CLASSSTYLE_DIALOG, WS_EX_STATICEDGE | WS_EX_APPWINDOW, 0, 0, 0, 0);
		if (silent)
			pMainFrame->StartSilentUnInstall();
		else
			pMainFrame->ShowWindow();
		CPaintManagerUI::MessageLoop();
	}

	::OleUninitialize();
	::CoUninitialize();

    return (int)0;
}
