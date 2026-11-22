# KeelBaseSetup

KeelBase 的 Windows 安装程序（InstallXpress 框架：DuiLib 界面 + Lua 脚本 + 内嵌 7z 组件包），
产物是单个 `KeelBaseSetup_<版本>.exe`。

KeelBase 在 Windows 上作为 KeelHost 的模块运行（KeelHost 是 LocalSystem 的 Windows 服务，模块插件
`kh_keelbase.dll` 由它的工作进程加载）。KeelHost 改名前的名字在 Windows 上还要沿用一个大版本
（ymwang78/KeelHost#49）：`HostVM.exe`、`hostvm.xml`、服务名 `HostVM`、目录 `<安装目录>\HostVM`。
安装程序沿用这些名字，和 TaijiMPC6 共用同一个安装根目录、同一个 HostVM 目录和服务。

## 组件

| 组件 | 资源 ID | 7z 包 | 装到哪里 |
|---|---|---|---|
| Common.Runtime（必装） | 150 | Common.7z | `Common\vcredist\vc_redist.x64.exe`、`KeelBase\UnInstall.exe` |
| Common.OpcCore | 151 | OpcCore.7z | `Common\opc\GBDA_Install_Prereq_x64.msi`、`..._x86.msi` |
| KeelBase.Host | 160 | KeelHost.7z | `HostVM\`：`HostVM.exe`、`KeelHost.exe`、`zce.dll` 及其依赖、`hostvm.default.xml` |
| KeelBase.Server（依赖 Host） | 161 | KeelBaseServer.7z | `HostVM\modules\KeelBase\`（`kh_keelbase.dll`、`module.xml`、`kbase_client.dll`）、`HostVM\keelhost.d\020-kbase.xml.template` |
| KeelBase.Tools | 162 | KeelBaseTools.7z | `KeelBase\kbased.exe`（有 kbasecli.exe 时一并带上） |

首次安装默认全选；升级（本安装程序在同一目录装过）默认选上次装的组件。同一目录里只有 TaijiMPC6
装的 HostVM 时不算升级：KeelBase 模块要与本包的 KeelHost 配套，所以 Host 也默认选上。

## 安装做了什么

1. 检查服务名对应的 Windows 服务：不存在，或者运行的就是 `<安装目录>\HostVM\HostVM.exe`
   （或 `KeelHost.exe`）才继续；属于别处安装的 KeelHost 时拒绝安装，既不停也不接管它。
2. 选了 Host 或 Server 且服务在运行：`HostVM.exe service stop <服务>`（等到服务和工作进程都停下）。
   服务不删不重建，现场改过的登录账户、恢复选项都保留。
3. 解压选中的组件包。
4. Host：`hostvm.xml` 和 `keelhost.xml` 都不存在时，从 `hostvm.default.xml` 生成 `hostvm.xml`
   （与 TaijiMPC6 用同一份种子 `apps/KeelDeck/dist/hostvm/hostvm.xml`）。两者同时存在 KeelHost 拒绝启动，
   所以已有 `keelhost.xml` 时不生成 `hostvm.xml`。
5. Server：`keelhost.d\020-kbase.xml` 不存在时从模板生成（实例 `kbase01`，REST 8080、数据端口 9090；
   它的配置 `kbase_server.json` 和数据 `data\` 在 `hostvm.xml` 的 `projects_dir` 下的 `kbase01\`，
   默认种子里是 `<安装目录>\TaiJiMPC_Projects\kbase01`，首次启动预分配约 4.2 GB）。已存在的归现场所有，升级不动。
   现场已在 `hostvm.xml` 或任何片段（`keelhost.d\`、`hostvm.d\`）里声明了模板里的全部 subvm 时不生成；
   只声明了一部分时报错中止。片段放在 `keelhost.d\` 而不是 `hostvm.d\`：TaijiMPC6 安装程序看到
   `hostvm.d\` 里有任何 XML 就不再初始化自己的片段。
6. VC++ 运行库：注册表里的 x64 运行库版本低于随包的 `vc_redist.x64.exe` 时安装。
7. OpcCore：64 位、32 位两半各自检查（接口代理/存根、OpcEnum 是否已注册且文件在），缺哪半装哪半。
   KeelBase 的 OPC DA/HDA 服务和它的客户端都要它；KeelBase 不自带接口代理。
8. 注册表：`HKLM\Software\TaijiControl\KeelBase`（`InstallPath`、`Version`、`ServiceName`、
   `Components\<组件>`），卸载项 `...\Uninstall\KeelBase`。共用的 `Software\TaijiControl\InstallPath`
   只在没有别的产品设过时写入。
9. Host：服务不存在时 `service install <服务>`；然后 `service start <服务>`。只装 Server 时，
   服务原来在运行就重新启动，原来停着就保持停着。

完成页可勾选“把命令行工具目录加入 PATH”（`<安装目录>\KeelBase`）。

## 命令行

```
KeelBaseSetup_3.0.0.1.exe /s                                   静默安装，失败时退出码非 0
KeelBaseSetup_3.0.0.1.exe /s /path=D:\TaijiControl             安装目录
KeelBaseSetup_3.0.0.1.exe /s /service=KeelHost2                KeelHost 的 Windows 服务名（默认 HostVM）
KeelBaseSetup_3.0.0.1.exe /s /components=KeelBase.Server       只装指定的组/组件（及其依赖、必装组件）
UnInstall.exe /s                                               静默卸载
```

不认识的组件名、`/path=` 不是本机磁盘上的绝对路径、`/service=` 含字母数字和 `._-` 以外的字符时，
静默安装直接失败，界面安装在错误提示里说明。安装日志：`%APPDATA%\Tai-Ji Control\KeelBase_install.log`。

## 卸载

`<安装目录>\KeelBase\UnInstall.exe`（“应用和功能”里的 KeelBase 指向它，需要管理员权限）：

- 停止 KeelHost 服务（只停本安装目录的），删除 `HostVM\modules\KeelBase` 和 `keelhost.d\020-kbase.xml`（及模板）。
- KeelHost 是本安装程序装的、且 TaijiMPC6 没装在同一目录时，删除服务和整个 `HostVM\`；
  否则保留 KeelHost，服务原来在运行就重新启动，TaijiMPC6 的实例照常运行。
- KeelBase 实例的数据（在 KeelHost 的工程目录里）一律保留；OPC Core Components 和 VC++ 运行库不卸载。
- 删除注册表项、PATH 里的 `<安装目录>\KeelBase`，最后由卸载程序删除 `KeelBase\` 目录和自身。

## 构建

前提：KeelHost（`hosts/KeelHost/KeelHost.sln`，Release，输出 `bin\x64\HostVM\`，含
`modules\KeelBase\kh_keelbase.dll`）和 KeelBase（`modules/KeelBase/kbase.sln`，Release）已编好；
装有 Visual Studio（MSBuild、vswhere）和 7-Zip。

```
python projects/KeelBaseSetup/build_KeelBaseSetup.py --version 3.0.0.1
```

脚本依次：编卸载程序 → 按组件暂存到 `bin\stage\` → 检查每个 exe/dll 的导入（必须在同目录、`HostVM\`、
Windows 或随包 VC++ 运行库里）和 `module.xml` → 打 `Install\res\*.7z` 并核对包内文件 → 把版本号
（以及随包 vc_redist 的版本）写进 `Install.lua`、两个 `.rc`，编安装程序后改回 →
`bin\x64\Release\KeelBaseSetup_<版本>.exe`。各输入目录可用 `--host-dir`、`--module-dir`、`--kbase-bin`、
`--kbasecli`、`--host-config`、`--opc-dir`、`--vc-redist` 覆盖；`--stage-only` 只到打包为止。

`vc_redist.x64.exe` 默认取 Visual Studio 里最新 MSVC 工具集的那份：二进制需要不低于编译它们的工具集的运行库。

## 测试

```
lua tests/test_keelbase_setup.lua
```

用桩替代 `installx.*`，覆盖默认选择与升级、安装目录和服务名及其命令行、服务归属检查、停启服务的时机、
`hostvm.xml` / `keelhost.xml` 与实例片段、VC++ 运行库版本判断、注册表，以及卸载时独占或与 TaijiMPC6 共用 KeelHost 的情况。

## 已知限制

- KeelBase 实例自己登记的 OPC DA/HDA 注册表项（`opcda_register_on_start`）卸载时不清除，
  需要时在卸载前用 `kbasecli <实例> opcda unregister`。
- KeelBase 仓库还没有 kbasecli 的 Windows 工程，`--kbase-bin` 里没有 `kbasecli.exe` 时工具组件只带 `kbased.exe`。
- 卸载后 `Common\` 可能剩一个空目录（框架没有“目录为空才删”的接口）。
- 界面图片沿用 TaijiMPC6 的。
- TaijiMPC6 的卸载程序不认识 KeelBase：同一目录里先卸 TaijiMPC6，会连 `HostVM\`（含 KeelBase 模块）和
  `Software\TaijiControl` 一起删掉，KeelBase 的卸载项还在但已不能用。

## 实测（2026-11-23，Windows Server 2025，本机已装 TaijiMPC6 与它的 HostVM 服务）

- 不给 `/service=`：安装程序发现 `HostVM` 服务属于 `C:\TaijiControl`，退出码 1，没有建目录、没写注册表，HostVM 服务不受影响。
- `/s /path=<测试目录> /service=KeelBaseSetupTest`（预置了改过端口的 `hostvm.xml`）：退出码 0，服务以 LocalSystem 运行，
  `keelhost.d\020-kbase.xml` 生成，kbase01 的 `/health` 返回 `engine_open: true`；VC++ 运行库与 OPC 核心组件已在，按检查跳过。
- 同一安装包再装一遍：服务停→替换→启，没有重建；现场改过的 `020-kbase.xml` 和写进实例的位号都在。
- `UnInstall.exe /s`：服务删除，`HostVM\`、`KeelBase\`、`Common\vcredist`、`Common\opc` 删除，实例数据保留，注册表清理干净，共享的 `InstallPath` 不动。
- 没测：图形界面（只校验了两份界面 XML 能解析，静默安装时加载过中文那份）、全新机器上安装 VC++ 运行库与 OPC 核心组件。
