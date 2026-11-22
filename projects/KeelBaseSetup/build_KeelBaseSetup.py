#!/usr/bin/env python3
"""Build the KeelBase Windows installer, KeelBaseSetup_<version>.exe.

Run with any Python 3.9+ on the build machine, after KeelHost (KeelHost.sln, Release) and KeelBase
(kbase.sln, Release) have been built:

    python build_KeelBaseSetup.py --version 3.0.0.1

Steps:
  1. MSBuild the uninstaller (UnInstall.exe goes into the required Common.7z).
  2. Stage every component archive under bin/stage/<archive>/, with the paths it gets under the
     install root, from the KeelHost and KeelBase build outputs (see COMPONENTS).
  3. Check the staged binaries: every DLL they import is in the same directory, in Windows or the
     VC++ runtime the installer brings; the module's module.xml names kh_keelbase.dll.
  4. Pack each component into Install/res/<archive>.7z and check the archive's members.
  5. Write the version (and the bundled vc_redist's) into Install.lua and the .rc files, MSBuild the
     installer, put the sources back, and copy Install.exe to KeelBaseSetup_<version>.exe.

The archives, the staging directory and the installer are build outputs (ignored by git).
"""

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path, PureWindowsPath

SETUP_ROOT = Path(__file__).resolve().parent
INSTALL_DIR = SETUP_ROOT / "Install"
UNINSTALL_DIR = SETUP_ROOT / "UnInstall"
RES_DIR = INSTALL_DIR / "res"
STAGE_ROOT = SETUP_ROOT / "bin" / "stage"
OUTPUT_DIR = SETUP_ROOT / "bin" / "x64" / "Release"
SLN_FILE = SETUP_ROOT / "KeelBaseSetup.sln"
INSTALL_LUA = INSTALL_DIR / "Install.lua"
INSTALL_RC = INSTALL_DIR / "Install.rc"
UNINSTALL_RC = UNINSTALL_DIR / "UnInstall.rc"
RESOURCE_H = INSTALL_DIR / "resource.h"
FRAGMENT_TEMPLATE = SETUP_ROOT / "dist" / "020-kbase.xml.template"

SEVEN_ZIP_ARGS = ["-t7z", "-mx=5", "-m0=LZMA2", "-md=16m", "-mfb=32", "-ms=64m", "-mmt=on"]

# KeelHost and what zce.dll needs (libpq and its OpenSSL / gettext / iconv / winpthread). The
# import check below fails the build when this list misses a DLL.
HOST_FILES = (
    "HostVM.exe",
    "KeelHost.exe",
    "zce.dll",
    "libpq.dll",
    "libssl-3-x64.dll",
    "libcrypto-3-x64.dll",
    "libintl-9.dll",
    "libiconv-2.dll",
    "libwinpthread-1.dll",
)

# DLLs the VC++ runtime component (vc_redist.x64.exe) installs into System32.
VC_RUNTIME_DLLS = re.compile(r"^(msvcp140(_\d+|_atomic_wait|_codecvt_ids)?|vcruntime140(_1|_threads)?|concrt140|vccorlib140|vcomp140)\.dll$", re.I)


def find_workspace(start):
    """The cxxproj workspace: the first parent with hosts/KeelHost and modules/KeelBase."""
    for parent in [start, *start.parents]:
        if (parent / "hosts" / "KeelHost").is_dir() and (parent / "modules" / "KeelBase").is_dir():
            return parent
    return None


def find_vswhere_install():
    vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    if not vswhere.exists():
        return None
    result = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires", "Microsoft.Component.MSBuild",
                             "-property", "installationPath"], capture_output=True, text=True)
    path = result.stdout.strip().splitlines()
    return Path(path[0]) if path else None


def find_msbuild():
    install = find_vswhere_install()
    if install:
        for candidate in sorted(install.glob("MSBuild/*/Bin/amd64/MSBuild.exe")) + sorted(install.glob("MSBuild/*/Bin/MSBuild.exe")):
            return candidate
    found = shutil.which("msbuild")
    return Path(found) if found else None


def find_vc_redist():
    """vc_redist.x64.exe of the newest MSVC toolset in Visual Studio: the binaries need at least the
    runtime of the toolset that built them."""
    install = find_vswhere_install()
    if not install:
        return None
    candidates = []
    for directory in (install / "VC" / "Redist" / "MSVC").glob("*"):
        if re.fullmatch(r"\d+\.\d+\.\d+", directory.name) and (directory / "vc_redist.x64.exe").is_file():
            candidates.append((tuple(int(x) for x in directory.name.split(".")), directory / "vc_redist.x64.exe"))
    return max(candidates)[1] if candidates else None


def find_seven_zip():
    for candidate in (shutil.which("7z"), r"C:\Program Files\7-Zip\7z.exe"):
        if candidate and Path(candidate).is_file():
            return Path(candidate)
    return None


def file_version(path):
    """FileVersion of a PE file, "a.b.c.d", from its VS_FIXEDFILEINFO as Windows reads it (a byte
    search could hit a signature inside an embedded archive)."""
    import ctypes
    from ctypes import wintypes
    version = ctypes.WinDLL("version")
    size = version.GetFileVersionInfoSizeW(str(path), None)
    if not size:
        raise ValueError(f"{path} has no version resource")
    buffer = ctypes.create_string_buffer(size)
    if not version.GetFileVersionInfoW(str(path), 0, size, buffer):
        raise ValueError(f"cannot read the version resource of {path}")
    info, length = ctypes.c_void_p(), wintypes.UINT()
    if not version.VerQueryValueW(buffer, "\\", ctypes.byref(info), ctypes.byref(length)):
        raise ValueError(f"{path} has no fixed file info")
    _signature, _struct, ms, ls = struct.unpack_from("<IIII", ctypes.string_at(info.value, length.value))
    return f"{ms >> 16}.{ms & 0xFFFF}.{ls >> 16}.{ls & 0xFFFF}"


def pe_imports(path):
    """Names of the DLLs a PE file imports, normal and delay-loaded."""
    data = Path(path).read_bytes()
    if data[:2] != b"MZ":
        raise ValueError(f"{path} is not a PE file")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError(f"{path} is not a PE file")
    sections_count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    directories = optional + (112 if magic == 0x20B else 96)
    sections = []
    for i in range(sections_count):
        base = optional + optional_size + 40 * i
        vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, base + 8)
        sections.append((va, max(vsize, rawsize), rawptr))

    def offset(rva):
        for va, size, rawptr in sections:
            if va <= rva < va + size:
                return rawptr + rva - va
        raise ValueError(f"{path}: RVA {rva:#x} is outside every section")

    def name_at(rva):
        start = offset(rva)
        return data[start:data.index(b"\0", start)].decode("ascii")

    names = []
    import_rva, _ = struct.unpack_from("<II", data, directories + 8 * 1)
    if import_rva:
        entry = offset(import_rva)
        while True:
            name_rva = struct.unpack_from("<I", data, entry + 12)[0]
            if name_rva == 0:
                break
            names.append(name_at(name_rva))
            entry += 20
    delay_rva, _ = struct.unpack_from("<II", data, directories + 8 * 13)
    if delay_rva:
        entry = offset(delay_rva)
        while True:
            name_rva = struct.unpack_from("<I", data, entry + 4)[0]
            if name_rva == 0:
                break
            names.append(name_at(name_rva))
            entry += 32
    return names


def import_is_available(name, search_dirs, system_dir):
    lower = name.lower()
    if lower.startswith(("api-ms-win-", "ext-ms-")) or VC_RUNTIME_DLLS.match(lower):
        return True
    if any((directory / name).is_file() for directory in search_dirs):
        return True
    return (system_dir / name).is_file()


class Component:
    def __init__(self, archive, res_id, files):
        self.archive = archive        # Install/res/<archive>
        self.res_id = res_id          # INSTALLSOFT resource ID, as in resource.h and Install.lua
        self.files = files            # {path under the install root: source file}


def collect_components(args):
    host_dir, module_dir, kbase_bin = args.host_dir, args.module_dir, args.kbase_bin
    common = {
        "Common/vcredist/vc_redist.x64.exe": args.vc_redist,
        "KeelBase/UnInstall.exe": OUTPUT_DIR / "UnInstall.exe",
    }
    opc = {
        "Common/opc/GBDA_Install_Prereq_x64.msi": args.opc_dir / "GBDA_Install_Prereq_x64.msi",
        "Common/opc/GBDA_Install_Prereq_x86.msi": args.opc_dir / "GBDA_Install_Prereq_x86.msi",
    }
    host = {f"HostVM/{name}": host_dir / name for name in HOST_FILES}
    host["HostVM/hostvm.default.xml"] = args.host_config
    server = {
        "HostVM/modules/KeelBase/kh_keelbase.dll": module_dir / "kh_keelbase.dll",
        "HostVM/modules/KeelBase/module.xml": module_dir / "module.xml",
        # The data-plane client other modules (SoftSensor, KeelTrace) load from the KeelBase module.
        "HostVM/modules/KeelBase/kbase_client.dll": kbase_bin / "kbase_client.dll",
        "HostVM/keelhost.d/020-kbase.xml.template": FRAGMENT_TEMPLATE,
    }
    tools = {"KeelBase/kbased.exe": kbase_bin / "kbased.exe"}
    kbasecli = args.kbasecli or kbase_bin / "kbasecli.exe"
    if kbasecli.is_file():
        tools["KeelBase/kbasecli.exe"] = kbasecli
    else:
        print(f"Note: {kbasecli} not found, KeelBaseTools.7z carries kbased.exe only "
              "(KeelBase has no Windows project for kbasecli yet; pass --kbasecli to add one)")
    return [
        Component("Common.7z", 150, common),
        Component("OpcCore.7z", 151, opc),
        Component("KeelHost.7z", 160, host),
        Component("KeelBaseServer.7z", 161, server),
        Component("KeelBaseTools.7z", 162, tools),
    ]


def check_sources(components):
    missing = [f"{source} (for {member})" for c in components for member, source in c.files.items()
               if not Path(source).is_file()]
    if missing:
        raise SystemExit("Missing build outputs:\n  " + "\n  ".join(missing))


def check_package_definitions(components):
    """Install.rc, resource.h and Install.lua must agree with the archives built here."""
    rc = INSTALL_RC.read_text(encoding="utf-8", errors="replace")
    header = RESOURCE_H.read_text(encoding="utf-8-sig")
    lua = INSTALL_LUA.read_text(encoding="utf-8")
    defines = {name: int(value) for name, value in re.findall(r"#define\s+(IDR_PKG_\w+)\s+(\d+)", header)}
    rc_archives = {}
    for name, file in re.findall(r"^(IDR_PKG_\w+)\s+INSTALLSOFT\s+\"res\\\\([^\"]+)\"", rc, re.M):
        if name not in defines:
            raise SystemExit(f"Install.rc uses {name}, which resource.h does not define")
        rc_archives[file] = defines[name]
    built = {c.archive: c.res_id for c in components}
    if rc_archives != built:
        raise SystemExit(f"Install.rc INSTALLSOFT {rc_archives} does not match the archives {built}")
    lua_ids = sorted(int(x) for x in re.findall(r"\bres\s*=\s*(\d+)", lua))
    if lua_ids != sorted(built.values()):
        raise SystemExit(f"Install.lua COMPONENTS res IDs {lua_ids} do not match the archives {sorted(built.values())}")


def check_module_xml(path):
    text = Path(path).read_text(encoding="utf-8-sig")
    if not re.search(r"<module\s+name=\"KeelBase\"", text) or 'windows="kh_keelbase.dll"' not in text:
        raise SystemExit(f"{path} does not describe module KeelBase with kh_keelbase.dll")
    if not re.search(r"<vmtype\s+name=\"KeelBase\"", text):
        raise SystemExit(f"{path} does not provide vmtype KeelBase")


def stage(components):
    if STAGE_ROOT.exists():
        shutil.rmtree(STAGE_ROOT)
    for component in components:
        root = STAGE_ROOT / Path(component.archive).stem
        for member, source in component.files.items():
            target = root / PureWindowsPath(member)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    print(f"Staged {sum(len(c.files) for c in components)} files under {STAGE_ROOT}")


def check_imports(components):
    """Every DLL a staged binary imports must be found where Windows will look at run time: the
    binary's own directory, HostVM/ (the KeelHost process loads the module), Windows, or the VC++
    runtime that Common.7z installs."""
    system_dir = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
    host_dir = STAGE_ROOT / "KeelHost" / "HostVM"
    problems = []
    for component in components:
        root = STAGE_ROOT / Path(component.archive).stem
        for member in component.files:
            path = root / PureWindowsPath(member)
            if path.suffix.lower() not in (".exe", ".dll"):
                continue
            search = [path.parent]
            if member.lower().startswith("hostvm/"):
                search.append(host_dir)
            for name in pe_imports(path):
                if not import_is_available(name, search, system_dir):
                    problems.append(f"{member} imports {name}, which the package does not carry")
    if problems:
        raise SystemExit("Unresolved imports:\n  " + "\n  ".join(problems))
    print("Import check passed")


def check_module_loads():
    """KeelHost from the package loads the KeelBase module from the package, and accepts the
    instance of the fragment template next to the seeded config, as a first install leaves them:
    `HostVM.exe module check` loads every module and checks every declared instance's vmtype
    (zce ABI and build id included) without starting anything."""
    check_root = STAGE_ROOT / "_check"
    if check_root.exists():
        shutil.rmtree(check_root)
    shutil.copytree(STAGE_ROOT / "KeelHost", check_root)
    shutil.copytree(STAGE_ROOT / "KeelBaseServer", check_root, dirs_exist_ok=True)
    host = check_root / "HostVM"
    shutil.copy2(host / "hostvm.default.xml", host / "hostvm.xml")
    shutil.copy2(host / "keelhost.d" / "020-kbase.xml.template", host / "keelhost.d" / "020-kbase.xml")
    result = subprocess.run([str(host / "HostVM.exe"), "module", "check"], cwd=host, capture_output=True,
                            text=True, timeout=120)
    print(result.stdout.strip())
    if result.returncode != 0 or not re.search(r"^ok\s+instance kbase01 \(KeelBase\)", result.stdout, re.M):
        raise SystemExit(f"HostVM.exe module check failed (exit {result.returncode}):\n{result.stdout}{result.stderr}")
    shutil.rmtree(check_root)


def pack(components, seven_zip):
    RES_DIR.mkdir(parents=True, exist_ok=True)
    for component in components:
        root = STAGE_ROOT / Path(component.archive).stem
        target = RES_DIR / component.archive
        temporary = target.with_suffix(".7z.tmp")
        if temporary.exists():
            temporary.unlink()
        members = sorted({PureWindowsPath(m).parts[0] for m in component.files})
        subprocess.run([str(seven_zip), "a", *SEVEN_ZIP_ARGS, str(temporary), *members],
                       cwd=root, check=True, stdout=subprocess.DEVNULL)
        listing = subprocess.run([str(seven_zip), "l", "-slt", str(temporary)], capture_output=True,
                                 text=True, check=True).stdout
        entries = re.findall(r"^Path = (.+)$\n(?:.+\n)*?^Attributes = (\S*)", listing, re.M)
        files = {path.replace("\\", "/").lower() for path, attributes in entries
                 if path != str(temporary) and not attributes.startswith("D")}
        expected = {m.lower() for m in component.files}
        if files != expected:
            temporary.unlink()
            raise SystemExit(f"{component.archive}: members {sorted(files)} differ from {sorted(expected)}")
        os.replace(temporary, target)
        print(f"Packed {target.name}: {len(files)} files, {target.stat().st_size // 1024} KiB")


def msbuild(msbuild_exe, target):
    subprocess.run([str(msbuild_exe), str(SLN_FILE), "/p:Configuration=Release", "/p:Platform=x64",
                    f"/t:{target}", "/m", "/nologo", "/v:minimal"], check=True)


def write_versions(version, vc_redist_version):
    """Writes the release version and the bundled vc_redist's into the sources; returns their
    original bytes for restore_sources()."""
    numbers = version.split(".")
    comma = ",".join(numbers)
    originals = {}

    def rewrite(path, substitutions):
        raw = path.read_bytes()
        originals[path] = raw
        text = raw.decode("utf-8")
        for pattern, replacement in substitutions:
            text, count = re.subn(pattern, replacement, text, flags=re.M)
            if count == 0:
                raise SystemExit(f"{path}: no match for {pattern}")
        path.write_bytes(text.encode("utf-8"))

    rewrite(INSTALL_LUA, [
        (r'^local _VERSION = "[^"]*"', f'local _VERSION = "{version}"'),
        (r'^local VC_REDIST_VERSION = "[^"]*"', f'local VC_REDIST_VERSION = "{vc_redist_version}"'),
    ])
    for rc in (INSTALL_RC, UNINSTALL_RC):
        rewrite(rc, [
            (r"^ FILEVERSION [\d,]+", f" FILEVERSION {comma}"),
            (r"^ PRODUCTVERSION [\d,]+", f" PRODUCTVERSION {comma}"),
            (r'VALUE "FileVersion", "[^"]*"', f'VALUE "FileVersion", "{version}"'),
            (r'VALUE "ProductVersion", "[^"]*"', f'VALUE "ProductVersion", "{version}"'),
        ])
    return originals


def restore_sources(originals):
    for path, raw in originals.items():
        path.write_bytes(raw)


def current_version():
    match = re.search(r'^local _VERSION = "([^"]*)"', INSTALL_LUA.read_text(encoding="utf-8"), re.M)
    return match.group(1) if match else None


def parse_args():
    workspace = find_workspace(SETUP_ROOT)
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", help="release version a.b.c.d (default: the one in Install.lua)")
    parser.add_argument("--workspace", type=Path, default=workspace, help="the cxxproj workspace (default: found above this script)")
    parser.add_argument("--host-dir", type=Path, help="KeelHost Release output (default: <workspace>/hosts/KeelHost/bin/x64/HostVM)")
    parser.add_argument("--module-dir", type=Path, help="the KeelBase module (default: <host-dir>/modules/KeelBase)")
    parser.add_argument("--kbase-bin", type=Path, help="KeelBase Release output (default: <workspace>/modules/KeelBase/bin/x64/Release)")
    parser.add_argument("--kbasecli", type=Path, help="kbasecli.exe to ship (default: <kbase-bin>/kbasecli.exe when it exists)")
    parser.add_argument("--host-config", type=Path, help="site config seed (default: <workspace>/apps/KeelDeck/dist/hostvm/hostvm.xml)")
    parser.add_argument("--opc-dir", type=Path, help="GBDA_Install_Prereq_x64/x86.msi (default: <workspace>/apps/KeelDeck/bin/x64/Common/opc)")
    parser.add_argument("--vc-redist", type=Path, help="vc_redist.x64.exe (default: the newest MSVC toolset's in Visual Studio)")
    parser.add_argument("--output-dir", type=Path, default=OUTPUT_DIR, help="where KeelBaseSetup_<version>.exe goes")
    parser.add_argument("--stage-only", action="store_true", help="stop after staging, checking and packing the archives")
    args = parser.parse_args()

    if args.workspace is None and not all((args.host_dir, args.kbase_bin, args.host_config, args.opc_dir)):
        parser.error("cannot find the cxxproj workspace above this script; pass --workspace")
    ws = args.workspace
    args.host_dir = args.host_dir or ws / "hosts" / "KeelHost" / "bin" / "x64" / "HostVM"
    args.module_dir = args.module_dir or args.host_dir / "modules" / "KeelBase"
    args.kbase_bin = args.kbase_bin or ws / "modules" / "KeelBase" / "bin" / "x64" / "Release"
    args.host_config = args.host_config or ws / "apps" / "KeelDeck" / "dist" / "hostvm" / "hostvm.xml"
    args.opc_dir = args.opc_dir or ws / "apps" / "KeelDeck" / "bin" / "x64" / "Common" / "opc"
    args.vc_redist = args.vc_redist or find_vc_redist()
    if args.vc_redist is None:
        parser.error("cannot find vc_redist.x64.exe in Visual Studio; pass --vc-redist")
    args.version = args.version or current_version()
    if not re.fullmatch(r"\d+\.\d+\.\d+\.\d+", args.version or "") or any(int(x) > 65535 for x in args.version.split(".")):
        parser.error("--version must be a.b.c.d with each field 0..65535")
    return args


def main():
    # Keep this script's lines in order with MSBuild's output.
    sys.stdout.reconfigure(line_buffering=True)
    args = parse_args()
    msbuild_exe = find_msbuild()
    seven_zip = find_seven_zip()
    if msbuild_exe is None or seven_zip is None:
        raise SystemExit("MSBuild and 7-Zip are required (MSBuild from Visual Studio, 7z on PATH)")
    vc_redist_version = file_version(args.vc_redist)
    print(f"KeelBaseSetup {args.version}: KeelHost {args.host_dir}, KeelBase {args.kbase_bin}, "
          f"vc_redist {vc_redist_version}")

    print("\n== 1. Uninstaller")
    originals = write_versions(args.version, vc_redist_version)
    try:
        msbuild(msbuild_exe, r"src\UnInstall")

        print("\n== 2. Stage")
        components = collect_components(args)
        check_package_definitions(components)
        check_sources(components)
        check_module_xml(args.module_dir / "module.xml")
        stage(components)

        print("\n== 3. Check")
        check_imports(components)
        check_module_loads()

        print("\n== 4. Pack")
        pack(components, seven_zip)
        if args.stage_only:
            return

        print("\n== 5. Installer")
        msbuild(msbuild_exe, "Build")
    finally:
        restore_sources(originals)

    installer = OUTPUT_DIR / "Install.exe"
    if file_version(installer) != args.version:
        raise SystemExit(f"{installer} has version {file_version(installer)}, expected {args.version}")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    target = args.output_dir / f"KeelBaseSetup_{args.version}.exe"
    shutil.copy2(installer, target)
    print(f"\n=> {target} ({target.stat().st_size // (1024 * 1024)} MiB)")


if __name__ == "__main__":
    main()
