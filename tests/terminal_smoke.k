// Windows terminal setup smoke. Verifies the direct Win32 handle path compiles
// and runs without routing through C or the legacy toHandle(-11) crash path.

import "k:terminal"

just run {
    termEnableVT100()
    print("terminal ok")
}