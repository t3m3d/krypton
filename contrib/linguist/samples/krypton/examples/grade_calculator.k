// Grade calculator
// Demonstrates: const, match, ternary, for-in, compound assignment

func letterGrade(score) {
    let grade = ""
    match score / 10 {
        10 { grade = "A+" }
        9  { grade = "A" }
        8  { grade = "B" }
        7  { grade = "C" }
        6  { grade = "D" }
        else { grade = "F" }
    }
    emit grade
}

func passFail(score) {
    emit score >= 60 ? "PASS" : "FAIL"
}

just run {
    const title = "Grade Calculator"
    const separator = repeat("=", len(title))
    kp(title)
    kp(separator)

    const scores = "95,87,73,62,45,100,58,81,69,91"
    let passCount = 0
    let failCount = 0
    let totalScore = 0

    for score in scores {
        const grade = letterGrade(score)
        const status = passFail(score)
        kp("  Score " + padLeft(score, 3, " ") + " -> " + padRight(grade, 3, " ") + " [" + status + "]")
        totalScore += score
        if status == "PASS" {
            passCount += 1
        } else {
            failCount += 1
        }
    }

    kp(separator)
    const count = length(scores)
    const avg = totalScore / count
    kp("Students:  " + count)
    kp("Average:   " + avg)
    kp("Passed:    " + passCount)
    kp("Failed:    " + failCount)
    kp("Pass rate: " + passCount * 100 / count + "%")
    emit "ok"
}
