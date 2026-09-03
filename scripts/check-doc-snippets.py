#!/usr/bin/env python3
"""Compile the JavaScript snippets in the fullstack wiki chapters.

Documentation examples rot silently: nobody runs them, and the subset is strict
enough that an untested snippet is usually wrong in some small way an author
will then copy. This compiles every server-side snippet through the real
`js2elpian`, so a chapter that drifts from the language fails a check rather
than misleading a reader.

Client-side snippets are skipped: they use `el`/`print` from the GUI SDK, which
is not standalone-compilable, and pretending otherwise would mean either a fake
prelude (testing the fake) or skipping the check silently. This says which.

Usage: scripts/check-doc-snippets.py [--compiler PATH]
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAPTERS = [
    "18-fullstack",
    "19-server-functions",
    "20-proxy-and-egress",
    "21-hosting",
    "22-packaging",
]
# A snippet mentioning any of these needs the server SDK in scope.
SERVER_MARKERS = ("kvSet", "kvGet", "kvList", "kvDelete", "ui(", "ctxUser",
                  "ctxHasRole", "revalidate(", "secret(", "callFunction")
# A snippet mentioning any of these is client-side and cannot be compiled alone.
CLIENT_MARKERS = ("callServer", "serverComponent", "serverRender", "el(",
                  "print(", "action(")


def main() -> int:
    compiler = os.path.join(ROOT, "rust/target/debug/elpian-compile")
    if "--compiler" in sys.argv:
        compiler = sys.argv[sys.argv.index("--compiler") + 1]
    if not os.path.exists(compiler):
        print(f"compiler not found at {compiler}\n"
              f"build it: cd rust && cargo build -p js2elpian --bin elpian-compile")
        return 2

    sdk = open(os.path.join(ROOT, "guest-sdk/js/elpian-server.js")).read()
    compiled = skipped = 0
    failures = []

    with tempfile.TemporaryDirectory() as work:
        for chapter in CHAPTERS:
            path = os.path.join(ROOT, "wiki", f"{chapter}.md")
            text = open(path).read()
            blocks = re.findall(r"```(?:js|javascript)\n(.*?)```", text, re.S)
            for i, block in enumerate(blocks):
                if any(m in block for m in SERVER_MARKERS):
                    source = sdk + "\n" + block
                elif any(m in block for m in CLIENT_MARKERS):
                    skipped += 1
                    continue
                else:
                    source = block
                js = os.path.join(work, f"{chapter}-{i}.js")
                open(js, "w").write(source)
                result = subprocess.run(
                    [compiler, "bytecode", js, js + ".bc"],
                    capture_output=True,
                )
                compiled += 1
                if result.returncode != 0:
                    failures.append((chapter, i, result.stderr.decode().strip(), block))

    for chapter, i, error, block in failures:
        print(f"\nFAIL {chapter}.md, JavaScript block {i + 1}:\n  {error}")
        print("  " + "\n  ".join(block.strip().splitlines()[:10]))

    print(f"\n{compiled} snippet(s) compiled, {skipped} client-side skipped, "
          f"{len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
