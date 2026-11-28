# KeelBaseSetup

KeelBase 的 Windows 安装程序（InstallXpress 框架：DuiLib 界面 + Lua 脚本 + 内嵌 7z 组件包），
产物是单个 `KeelBaseSetup_<版本>.exe`。

KeelBase 在 Windows 上作为 KeelHost 的模块运行：KeelHost 是 LocalSystem 的 Windows 服务，模块插件
`kh_keelbase.dll` 由它的工作进程加载，KeelDeck 的 KeelBasePlugin 经 KeelHost 控制面管理实例。
KeelBase 用**自己的一份 KeelHost**，与其他产品（TaijiMPC6）安装的 HostVM 服务完全分开：自己的
`KeelHost.exe` / `zce.dll`、自己的 Windows 服务（默认 `KeelBase`）、自己的端口，安装、升级、卸载
互不影响。

## 目录与端口

首次安装默认使用 `C:\KeelCon\KeelBase`。升级沿用已记录的 KeelBase 安装目录，`/path=` 可显式指定目录。

```
<安装目录>\
  Host\                      KeelHost.exe、zce.dll 及其依赖
    keelhost.default.xml     配置种子（dist/keelhost.xml），首次安装复制成 keelhost.xml
    keelhost.d\020-kbase.xml 实例 kbase01（首次安装从 .template 生成）
    modules\KeelBase\        kh_keelbase.dll、module.xml、kbase_client.dll
    modules\KeelSim\         仿真后端与 Python 子进程（可选）
    modules\WinPy313\python\ KeelSim 使用的 Python 3.13 标准库和扩展
    modules\KeelTrace\       数据采集后端（可选）
    log\
  Data\                      KeelHost 的 projects_dir：kbase01\（kbase_server.json、data\）、subvm.db
  Deck\                      KeelDeck.exe、Qt 运行时和三项界面插件
  Tools\                     kbased.exe（构建里有 kbasecli.exe 时一并带上）
  Redist\                    vc_redist.x64.exe、opc\GBDA_Install_Prereq_x64/x86.msi
  Uninstall\UnInstall.exe
```

| 端口 | 用途 |
|---|---|
| 7820/TCP | KeelHost 控制面（zmis，KeelDeck 连这里） |
| 7820/UDP | KeelHost 日志收集 |
| 7821/TCP | KeelHost 事件（storm） |
| 7822–7825/TCP | 预留给现场需要固定端口的实例 |
| 7826/TCP、7827/TCP | 预留给 `ksim` 和 `ktrace` 实例 |
| 7828/TCP、7829/TCP | 新装默认实例 `kbase01` 的 REST 与数据端口（`Data\kbase01\kbase_server.json`） |

KeelBase 的固定端口统一保留在 `7820–7829`。控制面和事件端口在 `Host\keelhost.xml` 配置，
具名工作进程的固定端口在对应的 KeelHost 实例配置里设置。新安装的 kbase01 监听本机网卡，
由 KeelHost 自动分配实例 RPC 端口，KeelDeck 从 7820 获取。升级沿用已有实例配置。

## 组件

| 组件 | 资源 ID | 7z 包 | 内容 |
|---|---|---|---|
| Common.Runtime（必装） | 150 | Common.7z | `Redist\vc_redist.x64.exe`、`Uninstall\UnInstall.exe` |
| Common.OpcCore | 151 | OpcCore.7z | `Redist\opc\` 两个 Graybox OPC 核心组件安装包 |
| KeelBase.Server | 160 | KeelBaseServer.7z | `Host\` 整个：KeelHost、配置种子、KeelBase 模块、实例片段模板 |
| KeelBase.Tools | 161 | KeelBaseTools.7z | `Tools\kbased.exe`（及 kbasecli.exe） |
| KeelBase.KeelSim | 162 | KeelSim.7z | KeelSim 模块、`keelsim_pyhost.exe`、Python 3.13 运行时 |
| KeelBase.KeelTrace | 163 | KeelTrace.7z | KeelTrace 模块 |
| KeelBase.KeelDeck | 164 | KeelDeck.7z | KeelDeck 客户端及 KeelBase、KeelSim、KeelTrace 界面插件 |

首次安装时 KeelSim 和 KeelTrace 默认勾选，可分别取消。选中任一模块会同时选中 Server，让模块与随包的
KeelHost 一起安装或更新。升级时默认选中上次安装的组件。KeelHost 加载模块后可按需创建相应实例。
KeelDeck 客户端在首次安装和升级时均默认勾选，可取消或单独安装。安装后可用公共桌面的
`KeelBase` 快捷方式启动 `Deck\KeelDeck.exe`，新建连接时默认端口为 `7820`。
完成页的 Run 按钮打开本次安装目录中的客户端。

## 安装做了什么

1. 检查服务名对应的 Windows 服务：不存在，或者运行的就是 `<安装目录>\Host\KeelHost.exe` 才继续；
   属于别处安装时拒绝，既不停也不接管它。其他产品的 HostVM 服务与此无关，不会被碰。
2. 加固安装目录（`installx.FilePathSecure`）：C:\ 默认允许所有用户在下面建目录、建文件，继承下来
   谁都能往 `Host\keelhost.d\` 放片段、往 `Host\modules\` 放插件，被 KeelHost 以 SYSTEM 加载。所以：
   路径上或目录里有 junction / 符号链接、目录（或它的上级）的所有者不是 SYSTEM / Administrators /
   TrustedInstaller / 当前安装的管理员、已有目录里有别的用户建的文件或子目录（在宽松权限下被预先塞进来的，
   比如一个 `keelhost.d` 片段；普通用户建的文件所有者就是他自己，改不掉）时拒绝安装，提示里给出那个路径；
   已有目录先检查、再锁住根目录、再查一遍，最后才重设，堵住检查和重设之间的空档。否则整棵树所有者改为 Administrators，DACL 改为受保护的
   SYSTEM 和 Administrators 完全控制、Users 读和执行（显式条目清掉）。`Data\`（实例的 `kbase_server.json` 里有
   token）作为私有子目录在同一次调用里处理，Users 自始至终没有任何权限：锁根目录和整树重设都先用不给 Users 的
   DACL，`Data\` 设成受保护之后才在其余部分加上 Users 读；首次安装时 `Data\` 由单独一次调用直接按不给 Users 的权限创建。
3. 选了 Server 且服务在运行：`KeelHost.exe service stop <服务>`（等到服务和工作进程都停下）。
   服务不删不重建，现场改过的登录账户、恢复选项都保留。
4. 解压选中的组件包。
5. Server：`keelhost.xml` 和 `hostvm.xml` 都不存在时，从 `keelhost.default.xml` 生成 `keelhost.xml`
   （两者同时存在 KeelHost 拒绝启动）；`keelhost.d\020-kbase.xml` 不存在、且现场没在主配置或别的片段里
   声明模板里的 subvm 时从模板生成；只声明了一部分时报错中止。新建默认主配置时，如果 `Data\kbase01`
   下还没有 `kbase_server.json` 或旧版 `config.json`，写入 REST `7828` 和数据 `7829`。升级沿用现场配置。
6. VC++ 运行库：注册表里的 x64 运行库版本低于随包的 `vc_redist.x64.exe` 时安装。
7. OpcCore：64 位、32 位两半各自检查（接口代理/存根、OpcEnum 是否已注册且文件在），缺哪半装哪半。
   KeelBase 的 OPC DA/HDA 服务和它的客户端都要它；KeelBase 不自带接口代理。
8. 注册表：只写 `HKLM\Software\TaijiControl\KeelBase`（`InstallPath`、`Version`、`ServiceName`、
   `Components\<组件>`）和卸载项 `...\Uninstall\KeelBase`。
9. Server：服务不存在时 `service install <服务>`，然后 `service start <服务>`，再观察 5 秒：服务没在运行
   （端口被占、现场配置有误）就报安装失败（静默安装退出码 1），提示看 `Host\log`。要观察而不是立刻读状态，
   是因为 libzce 在 KeelHost 打开端口之前就把服务报成了 RUNNING。只装工具时不碰服务。

完成页可勾选“把命令行工具目录加入 PATH”（`<安装目录>\Tools`）。

## 命令行

```
KeelBaseSetup_3.0.0.1.exe /s                                   静默安装，失败时退出码非 0
KeelBaseSetup_3.0.0.1.exe /s /path=D:\KeelBase                 安装目录
KeelBaseSetup_3.0.0.1.exe /s /service=KeelBase2                服务名（同一台机器装第二份时用）
KeelBaseSetup_3.0.0.1.exe /s /components=KeelBase.Tools        只装指定的组/组件（及必装组件）
KeelBaseSetup_3.0.0.2.exe /s /components=KeelBase.KeelSim,KeelBase.KeelTrace
UnInstall.exe /s                                               静默卸载
```

不认识的组件名、`/path=` 不是本机磁盘上的绝对路径、`/service=` 含字母数字和 `._-` 以外的字符时，
静默安装直接失败，界面安装在错误提示里说明。同一台机器装第二份时，除了 `/service=`，还要在它的
`Host\keelhost.xml` 和实例配置里换端口。安装日志：`%APPDATA%\Tai-Ji Control\KeelBase_install.log`。

## 卸载

`<安装目录>\Uninstall\UnInstall.exe`（“应用和功能”里的 KeelBase 指向它，需要管理员权限）：

- 服务运行的是本安装目录的 KeelHost 时，停止并删除它；别处安装的同名服务不碰。
- 删除 `Host\`、`Deck\`、`Tools\`、`Redist\`、`Uninstall\`，只结束本安装目录里的 kbased.exe 和 KeelDeck.exe；目录里的 junction
  和链接只删链接本身，不跟进去。在确认对话框里取消就直接退出，什么都不删。
- `Data\`（实例数据）保留；安装目录空了才删除。OPC Core Components 和 VC++ 运行库不卸载。
- 删除安装程序创建的 `KeelBase` 桌面快捷方式、注册表项和 PATH 里的 `<安装目录>\Tools`。

## 构建

前提：KeelHost（`hosts/KeelHost/KeelHost.sln`，x64 Release，输出 `bin\x64\HostVM\`，含
KeelBase、KeelSim、KeelTrace 模块）和 KeelBase 工具（`modules/KeelBase/kbase.sln`，x64 Release）已编好。
KeelTrace 应使用支持 `kbase_client.dll` 的版本。打包机需要 Visual Studio、7-Zip 和 Windows x64 Python 3.13。

在 KeelDeck 目录按其 `THIRD_PARTY_RELEASE.md` 准备许可材料和匹配的 Qwt 源码归档，然后部署客户端。

```powershell
pwsh tools/package_windows.ps1 -BuildDir bin/x64/Release -Branding ../KeelSetup/projects/KeelBaseSetup/dist/branding-keelbase.ini -OutDir dist/package/KeelBase
```

在 KeelSetup 目录生成安装包。

```
python projects/KeelBaseSetup/build_KeelBaseSetup.py --version 3.0.0.6
```

脚本依次：编卸载程序 → 按组件暂存到 `bin\stage\` → 检查每个 exe/dll 的导入（必须在同目录、`Host\`、
Windows 或随包 VC++ 运行库里）和 `module.xml`，并对暂存的 KeelHost + 模块 + 实例跑
`KeelHost.exe module check` → 打 `Install\res\*.7z` 并核对包内文件 → 把版本号（以及随包 vc_redist 的版本）
写进 `Install.lua`、两个 `.rc`，编安装程序后改回 → `bin\x64\Release\KeelBaseSetup_<版本>.exe`。
各输入可用 `--host-dir`、`--module-dir`、`--keelsim-dir`、`--keeltrace-dir`、`--python-dir`、
`--kbase-bin`、`--kbasecli`、`--deck-dir`、`--host-config`、`--opc-dir`、`--vc-redist` 覆盖。
`--platform-toolset v145` 适用于只安装了 Visual Studio 18 工具集的机器，`--stage-only` 只到组件打包为止。

`vc_redist.x64.exe` 默认取 Visual Studio 里最新 MSVC 工具集的那份：二进制需要不低于编译它们的工具集的运行库。
OPC 安装包默认取 `apps/KeelDeck/bin/x64/Common/opc`（与 TaijiMPC6 同一份）。

## 测试

```
lua tests/test_keelbase_setup.lua
```

用桩替代 `installx.*`，覆盖默认选择与升级、安装目录和服务名及其命令行、服务归属检查、目录加固、停启服务的时机
与启动后的观察、`keelhost.xml` / `hostvm.xml` 与实例片段、VC++ 运行库版本判断、注册表（不写共享根）和卸载。
框架部分（目录加固、不跟随链接的删除、注册表读写）见 `tests/test_file_security.cpp`、`tests/test_registry_value.cpp`（gtest，需要管理员权限运行）。

## 已知限制

- KeelBase 实例自己登记的 OPC DA/HDA 注册表项（`opcda_register_on_start`）卸载时不清除，
  需要时在卸载前用 `kbasecli <实例> opcda unregister`。
- KeelBase 仓库还没有 kbasecli 的 Windows 工程时，工具组件只带 `kbased.exe`。
- 同机其他产品的模块要通过 KeelHost 发现 KeelBase 实例时，要指向 KeelBase 的 KeelHost（7820），
  它们不在同一套 KeelHost 里。

## 实测（2026-11-23，Windows Server 2025，本机另有 TaijiMPC6 的 HostVM 服务在跑）

- `/s /path=<测试目录>`（默认服务名 `KeelBase`）：服务以 LocalSystem 运行 `Host\KeelHost.exe`，监听
  7820（TCP、UDP）和 7821，kbase01 的 `/health` 返回 `engine_open: true`，数据在 `Data\kbase01\data`；
  HostVM 服务 PID 不变，共享 `InstallPath` 不变；VC++ 运行库与 OPC 核心组件已在，按检查跳过。
- 不带参数再装一遍：按记录的目录和服务名，服务停→替换→启，没有重建；改过的 `020-kbase.xml` 和写进实例的位号都在。
- `UnInstall.exe /s`：服务删除，只剩 `Data\`，注册表干净。只装工具再卸载：安装目录整个删掉。
- 安装后：安装目录所有者 Administrators、DACL 受保护（SYSTEM / Administrators 完全控制，Users 读和执行），
  `Data\` 只有 SYSTEM / Administrators；服务运行中再装一遍，重设 ACL 不影响实例，数据都在。
- 经 junction 的路径安装：退出码 1，日志 `FilePathSecure refused ...: error 4395`，junction 后面什么都没建。
- 7820 被占时安装：2 秒内退出码 1，提示服务没启动起来；端口空闲时 6 秒装完。
- 没测：图形界面（两份界面 XML 能解析，静默安装时加载过中文那份；卸载确认框里点取消的那条路径没点过）；
  全新机器上真正安装 VC++ 运行库和 OPC 核心组件；以普通用户身份实际尝试写入安装目录。
