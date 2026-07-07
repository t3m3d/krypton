// Windows fs smoke for direct Win32 file I/O marshalling.

import "k:fs"

just run {
    print("cwd=" + fsCwd())
    print("exists=" + fsFileExists("README.md"))
    print("binary=" + fsLooksBinary("README.md"))
    print("hex=" + fsHexDump("README.md", "8"))
}