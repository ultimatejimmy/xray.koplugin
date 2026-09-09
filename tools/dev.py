#!/usr/bin/env python3
"""Isolated test execution and runtime file management for tools/dev.sh."""

import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
DEV = ROOT / ".dev"
PROFILE = DEV / "profile"
PLUGIN = PROFILE / "plugins" / "xray.koplugin"
MANIFEST = DEV / "synced-plugin-files.json"


def sample_book():
    book = DEV / "books" / "sample.epub"
    if book.exists():
        return book
    book.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(book, "w") as epub:
        epub.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        epub.writestr("META-INF/container.xml", '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''')
        epub.writestr("book.opf", '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">xray-local-development</dc:identifier><dc:title>X-Ray Development Sample</dc:title>
<dc:creator>Local development fixture</dc:creator><dc:language>en</dc:language>
<meta property="dcterms:modified">2026-09-08T00:00:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="chapter"/></spine></package>''')
        epub.writestr("nav.xhtml", '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">The Observatory</a></li></ol></nav></body></html>''')
        paragraphs = "\n".join(
            f"<p>Mira and Rowan walked toward the old observatory. At marker {i}, "
            "Mira stopped to study the map while Rowan carried the telescope. "
            "The village lay three miles beyond the river. They hoped to meet "
            "Professor Vale before sunset.</p>" for i in range(1, 31)
        )
        epub.writestr("chapter.xhtml", '''<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>The Observatory</title></head><body><h1>The Observatory</h1>'''
            + paragraphs + "</body></html>")
    return book


def plugin_destination(relative):
    destination = PLUGIN / relative
    if not destination.resolve().is_relative_to(PLUGIN.resolve()):
        raise RuntimeError(f"Unsafe plugin destination: {relative}")
    if destination.is_symlink() or any(p.is_symlink() for p in destination.parents):
        raise RuntimeError(f"Refusing to sync through a symlink: {destination}")
    return destination


def sync():
    PLUGIN.mkdir(parents=True, exist_ok=True)
    files = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "xray.koplugin/"],
        cwd=ROOT,
    ).decode().split("\0")
    current = set()
    for filename in filter(None, files):
        source = ROOT / filename
        if not source.is_file():
            continue
        if source.is_symlink():
            raise RuntimeError(f"Refusing to copy plugin source symlink: {source}")
        relative = source.relative_to(ROOT / "xray.koplugin").as_posix()
        destination = plugin_destination(relative)
        current.add(relative)
        if relative == "xray_config.lua" and destination.exists():
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    previous = set(json.loads(MANIFEST.read_text())) if MANIFEST.exists() else set()
    for relative in previous - current - {"xray_config.lua"}:
        destination = plugin_destination(relative)
        if destination.is_file():
            destination.unlink()
    MANIFEST.write_text(json.dumps(sorted(current), indent=2) + "\n")
    sample_book()
    print(f"Synced {len(current)} source files to {PLUGIN}", flush=True)
    return 0


def check(selected=None):
    if selected:
        spec = (ROOT / selected).resolve()
        if not spec.is_relative_to(ROOT) or not spec.is_file() or spec.suffix != ".lua":
            raise RuntimeError("Specify an existing Lua spec inside this checkout.")
        specs = [spec.relative_to(ROOT)]
    else:
        specs = [p.relative_to(ROOT) for p in sorted((ROOT / "spec").glob("*_spec.lua"))]
    if not specs:
        raise RuntimeError("No test specs found.")

    runs = DEV / "test-runs"
    runs.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="run-", dir=runs))
    print(f"Test artifacts: {work}", flush=True)
    shutil.copytree(ROOT / "xray.koplugin", work / "xray.koplugin")
    shutil.copytree(ROOT / "spec", work / "spec")
    shutil.copytree(ROOT / "tools", work / "tools", ignore=shutil.ignore_patterns("__pycache__"))
    if selected and not (work / specs[0]).exists():
        (work / specs[0]).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / specs[0], work / specs[0])
    temporary = work / "tmp"
    temporary.mkdir()
    # Upstream specs contain fixed /tmp paths. Relocate only the disposable test
    # copies so their cleanup cannot touch another KOReader instance or test run.
    test_sources = set((work / "spec").rglob("*.lua")) | {work / p for p in specs}
    for path in test_sources:
        path.write_text(path.read_text().replace("/tmp/", temporary.as_posix() + "/"))
    env = os.environ.copy()
    env["TMPDIR"] = str(temporary)
    env["LUA_PATH"] = "./?.lua;./?/init.lua;./xray.koplugin/?.lua;" + env.get("LUA_PATH", ";;")
    failed = False

    def execute(arguments):
        nonlocal failed
        print("\n$ " + " ".join(map(str, arguments)), flush=True)
        result = subprocess.run(list(map(str, arguments)), cwd=work, env=env)
        failed = failed or result.returncode != 0

    for directory in sorted({p.parent for p in (work / "xray.koplugin").rglob("*.lua")}):
        execute([sys.executable, work / "tools/check_syntax.py", directory])
    execute([sys.executable, work / "tools/check_translations.py"])
    execute([sys.executable, work / "tools/test_dev.py"])
    # One process per spec prevents leaked mocks or monkey patches between files.
    for spec in specs:
        execute([DEV / "rocks/bin/busted", "--lua=luajit", "--helper=tools/dev_test_helper.lua", "--no-auto-insulate", spec])
    print(f"\n{'FAILED' if failed else 'PASSED'}: checks and {len(specs)} spec files. Artifacts: {work}", flush=True)
    return int(failed)


def run(book=None):
    target = Path(book).expanduser().resolve() if book else sample_book()
    if not target.is_file():
        raise RuntimeError(f"Book does not exist: {target}")
    candidates = list((DEV / "koreader").glob("koreader-emulator-*/koreader/luajit"))
    if len(candidates) != 1:
        raise RuntimeError("Expected one built emulator. Run tools/dev.sh setup first.")
    sync()
    runtime = candidates[0].parent
    # Give the SDL process a macOS app identity (Dock, app switching, and UI
    # inspection), while keeping the native build and data in their own folders.
    bundle = DEV / "X-Ray Reader.app" / "Contents"
    executable = bundle / "MacOS" / "luajit"
    executable.parent.mkdir(parents=True, exist_ok=True)
    if not executable.exists() or executable.stat().st_mtime_ns != candidates[0].stat().st_mtime_ns:
        shutil.copy2(candidates[0], executable)
    libraries = bundle / "MacOS" / "libs"
    if not libraries.exists():
        libraries.symlink_to(runtime / "libs", target_is_directory=True)
    (bundle / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleName": "X-Ray Reader",
        "CFBundleDisplayName": "X-Ray Reader",
        "CFBundleIdentifier": "rocks.koreader.xray-dev",
        "CFBundleExecutable": "launch",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "NSHighResolutionCapable": True,
        "NSPrincipalClass": "NSApplication",
    }))
    launcher = bundle / "MacOS" / "launch"
    launcher.write_text("#!/bin/sh\nexec " + shlex.quote(str(ROOT / "tools/dev.sh")) + ' run "$@"\n')
    launcher.chmod(0o755)
    env = os.environ.copy()
    env.update(KO_HOME=str(PROFILE), EMULATE_READER_W="600", EMULATE_READER_H="800", EMULATE_READER_DPI="167")
    # Project-local test libraries must not shadow KOReader's bundled libraries.
    env.pop("LUA_PATH", None)
    env.pop("LUA_CPATH", None)
    print(f"Opening {target}\nDevelopment profile: {PROFILE}", flush=True)
    os.chdir(runtime)
    os.execve(str(executable), [str(executable), "reader.lua", "-d", str(target)], env)


if __name__ == "__main__":
    try:
        command = sys.argv[1]
        arguments = sys.argv[2:]
        sys.exit({"sync": sync, "check": check, "run": run}[command](*arguments))
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"dev: {error}", file=sys.stderr)
        sys.exit(1)
