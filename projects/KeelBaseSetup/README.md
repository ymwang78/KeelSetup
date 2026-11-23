# KeelBaseSetup

KeelBase 的 Windows 安装程序（InstallXpress 框架：DuiLib 界面 + Lua 脚本 + 内嵌 7z 组件包），
产物是单个 `KeelBaseSetup_<版本>.exe`。

KeelBase 在 Windows 上作为 KeelHost 的模块运行：KeelHost 是 LocalSystem 的 Windows 服务，模块插件
`kh_keelbase.dll` 由它的工作进程加载，KeelDeck 的 KeelBasePlugin 经 KeelHost 控制面管理实例。
KeelBase 用**自己的一份 KeelHost**，与其他产品（TaijiMPC6）安装的 HostVM 服务完全分开：自己的
`KeelHost.exe` / `zce.dll`、自己的 Windows 服务（默认 `KeelBase`）、自己的端口，安装、升级、卸载
互不影响。

## 目录与端口

安装目录默认 `C:\TaijiControl\KeelBase`（共享根 `HKLM\Software\TaijiControl\InstallPath` 存在时取它下面的 `KeelBase\`）：

```
<安装目录>\
  Host\                      KeelHost.exe、zce.dll 及其依赖
    keelhost.default.xml     配置种子（dist/keelhost.xml），首次安装复制成 keelhost.xml
    keelhost.d\020-kbase.xml 实例 kbase01（首次安装从 .template 生成）
    modules\KeelBase\        kh_keelbase.dll、module.xml、kbase_client.dll
    log\
  Data\                      KeelHost 的 projects_dir：kbase01\（kbase_server.json、data\）、subvm.db
  Tools\                     kbased.exe（构建里有 kbasecli.exe 时一并带上）
  Redist\                    vc_redist.x64.exe、opc\GBDA_Install_Prereq_x64/x86.msi
  Uninstall\UnInstall.exe
```

| 端口 | 用途 |
|---|---|
| 7820/TCP | KeelHost 控制面（zmis，KeelDeck 连这里） |
| 7820/UDP | KeelHost 日志收集 |
| 7821/TCP | KeelHost 事件（storm） |
| 8080/TCP、9090/TCP | 实例 kbase01 的 REST 与数据端口（实例默认值，在 `Data\kbase01\kbase_server.json` 里改） |

7820/7821 在 IANA 未分配（7811–7844 段），避开了 TaijiMPC6 的 HostVM 用的 22500/22501，也避开了
Clash 系代理软件的默认端口 7890/7891（Clash Verge Rev 是 7897）。端口在 `Host\keelhost.xml` 里改，
它归现场所有，升级不覆盖。

## 组件

| 组件 | 资源 ID | 7z 包 | 内容 |
|---|---|---|---|
| Common.Runtime（必装） | 150 | Common.7z | `Redist\vc_redist.x64.exe`、`Uninstall\UnInstall.exe` |
| Common.OpcCore | 151 | OpcCore.7z | `Redist\opc\` 两个 Graybox OPC 核心组件安装包 |
| KeelBase.Server | 160 | KeelBaseServer.7z | `Host\` 整个：KeelHost、配置种子、KeelBase 模块、实例片段模板 |
| KeelBase.Tools | 161 | KeelBaseTools.7z | `Tools\kbased.exe`（及 kbasecli.exe） |

首次安装默认全选；升级（本安装程序在同一目录装过）默认选上次装的组件。

## 安装做了什么

1. 检查服务名对应的 Windows 服务：不存在，或者运行的就是 `<安装目录>\Host\KeelHost.exe` 才继续；
   属于别处安装时拒绝，既不停也不接管它。其他产品的 HostVM 服务与此无关，不会被碰。
2. 加固安装目录（`installx.FilePathSecure`）：C:\ 默认允许所有用户在下面建目录、建文件，继承下来
   谁都能往 `Host\keelhost.d\` 放片段、往 `Host\modules\` 放插件，被 KeelHost 以 SYSTEM 加载。所以：
   路径上或目录里有 junction / 符号链接、目录（或它的上级）的所有者不是 SYSTEM / Administrators /
   TrustedInstaller / 当前安装的管理员时拒绝安装；否则整棵树所有者改为 Administrators，DACL 改为受保护的
   SYSTEM 和 Administrators 完全控制、Users 读和执行（显式条目清掉）。`Data\` 再单独加固，Users 没有任何权限
   （实例的 `kbase_server.json` 里有 token）。
3. 选了 Server 且服务在运行：`KeelHost.exe service stop <服务>`（等到服务和工作进程都停下）。
   服务不删不重建，现场改过的登录账户、恢复选项都保留。
4. 解压选中的组件包。
5. Server：`keelhost.xml` 和 `hostvm.xml` 都不存在时，从 `keelhost.default.xml` 生成 `keelhost.xml`
   （两者同时存在 KeelHost 拒绝启动）；`keelhost.d\020-kbase.xml` 不存在、且现场没在主配置或别的片段里
   声明模板里的 subvm 时从模板生成；只声明了一部分时报错中止。已有的都归现场所有，升级不动。
6. VC++ 运行库：注册表里的 x64 运行库版本低于随包的 `vc_redist.x64.exe` 时安装。
7. OpcCore：64 位、32 位两半各自检查（接口代理/存根、OpcEnum 是否已注册且文件在），缺哪半装哪半。
   KeelBase 的 OPC DA/HDA 服务和它的客户端都要它；KeelBase 不自带接口代理。
8. 注册表：只写 `HKLM\Software\TaijiControl\KeelBase`（`InstallPath`、`Version`、`ServiceName`、
   `Components\<组件>`）和卸载项 `...\Uninstall\KeelBase`；共享的 `Software\TaijiControl\InstallPath`
   只读不写。
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
UnInstall.exe /s                                               静默卸载
```

不认识的组件名、`/path=` 不是本机磁盘上的绝对路径、`/service=` 含字母数字和 `._-` 以外的字符时，
静默安装直接失败，界面安装在错误提示里说明。同一台机器装第二份时，除了 `/service=`，还要在它的
`Host\keelhost.xml` 和实例配置里换端口。安装日志：`%APPDATA%\Tai-Ji Control\KeelBase_install.log`。

## 卸载

`<安装目录>\Uninstall\UnInstall.exe`（“应用和功能”里的 KeelBase 指向它，需要管理员权限）：

- 服务运行的是本安装目录的 KeelHost 时，停止并删除它；别处安装的同名服务不碰。
- 删除 `Host\`、`Tools\`、`Redist\`、`Uninstall\`，只结束本安装目录里的 kbased.exe；目录里的 junction
  和链接只删链接本身，不跟进去。在确认对话框里取消就直接退出，什么都不删。
- `Data\`（实例数据）保留；安装目录空了才删除。OPC Core Components 和 VC++ 运行库不卸载。
- 删除注册表项和 PATH 里的 `<安装目录>\Tools`。

## 构建

前提：KeelHost（`hosts/KeelHost/KeelHost.sln`，Release，输出 `bin\x64\HostVM\`，含
`modules\KeelBase\kh_keelbase.dll`）和 KeelBase（`modules/KeelBase/kbase.sln`，Release）已编好；
装有 Visual Studio（MSBuild、vswhere）和 7-Zip。

```
python projects/KeelBaseSetup/build_KeelBaseSetup.py --version 3.0.0.1
```

脚本依次：编卸载程序 → 按组件暂存到 `bin\stage\` → 检查每个 exe/dll 的导入（必须在同目录、`Host\`、
Windows 或随包 VC++ 运行库里）和 `module.xml`，并对暂存的 KeelHost + 模块 + 实例跑
`KeelHost.exe module check` → 打 `Install\res\*.7z` 并核对包内文件 → 把版本号（以及随包 vc_redist 的版本）
写进 `Install.lua`、两个 `.rc`，编安装程序后改回 → `bin\x64\Release\KeelBaseSetup_<版本>.exe`。
各输入可用 `--host-dir`、`--module-dir`、`--kbase-bin`、`--kbasecli`、`--host-config`、`--opc-dir`、
`--vc-redist` 覆盖；`--stage-only` 只到打包为止。

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
- 界面图片沿用 TaijiMPC6 的。

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
