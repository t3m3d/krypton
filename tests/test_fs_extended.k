// Test the 2.1 fs gap builtins (mkdir, copy, rename, delete, rmdir,
// cwd, tempdir, homedir) — these landed to close the most common
// Python `os` / `shutil` use cases.
import "k:fs"

just run {
    let tmp = fsTempDir()
    let dir = tmp + "_krfs_test"

    // mkdir + verify
    fsMkdir(dir)
    if fsIsDir(dir) != "1" { kp("FAIL: mkdir"); exit("1") }

    // write a file, copy, rename, delete
    writeFile(dir + "/a.txt", "alpha")
    if fsCopy(dir + "/a.txt", dir + "/b.txt", "1") != "1" { kp("FAIL: copy"); exit("1") }
    if fsRename(dir + "/b.txt", dir + "/c.txt") != "1" { kp("FAIL: rename"); exit("1") }
    if fsFileExists(dir + "/c.txt") != "1" { kp("FAIL: exists after rename"); exit("1") }
    if fsDelete(dir + "/a.txt") != "1" { kp("FAIL: delete a"); exit("1") }
    if fsDelete(dir + "/c.txt") != "1" { kp("FAIL: delete c"); exit("1") }
    if fsRmdir(dir) != "1" { kp("FAIL: rmdir"); exit("1") }

    // env-aware paths return non-empty
    if len(fsCwd())     == 0 { kp("FAIL: cwd empty");  exit("1") }
    if len(fsTempDir()) == 0 { kp("FAIL: temp empty"); exit("1") }
    if len(fsHomeDir()) == 0 { kp("FAIL: home empty"); exit("1") }

    kp("ok")
}
