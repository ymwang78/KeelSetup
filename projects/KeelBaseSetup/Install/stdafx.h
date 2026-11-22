// stdafx.h : include file for standard system include files,
// or project specific include files that are used frequently, but
// are changed infrequently
//

#pragma once

// WIN7 SP1, 2023.11.7
#define _WIN32_WINNT	0x0601

#include "targetver.h"

#define WIN32_LEAN_AND_MEAN             // Exclude rarely-used stuff from Windows headers
// Windows Header Files:
#include <windows.h>

// C RunTime Header Files
#include <stdlib.h>
#include <malloc.h>
#include <memory.h>
#include <tchar.h>
#include <string>

#define UILIB_API
#include "DuiLib/UIlib.h"
using namespace DuiLib;

#ifndef PRODVER                     // product version
#define PRODVER L"3.0.0.1"
#endif

#define COMPANYNAME L"TaijiControl" // company name
#define PRODUCTNAME L"KeelBase"     // product name
#define APPEXENAME  L"kbased.exe"   // main program
