// Test count function (comma-separated item counting)

func check(name, expected, actual) {
    if expected == actual {
        kp("[PASS] " + name)
    } else {
        kp("[FAIL] " + name + " expected=" + expected + " actual=" + actual)
    }
}

just run {
    kp("Count Function Tests")
    kp("====================")

    check("three items", "3", "" + count("a,b,c"))
    check("five items", "5", "" + count("1,2,3,4,5"))
    check("single item", "1", "" + count("only"))
    check("two items", "2", "" + count("first,second"))
    check("ten items", "10", "" + count("a,b,c,d,e,f,g,h,i,j"))

    // Count with numbers
    check("numbers", "4", "" + count("10,20,30,40"))

    // Count with longer strings
    check("long strings", "3", "" + count("hello,world,krypton"))

    emit "ok"
}
