// Show how various units add up to a year.

just run {
    let secPerMin = 60
    let minPerHour = 60
    let hourPerDay = 24
    let dayPerYear = 365

    let secPerHour = secPerMin * minPerHour
    let secPerDay  = secPerHour * hourPerDay
    let secPerYear = secPerDay * dayPerYear

    kp("Time unit breakdown")
    kp("===================")
    kp("seconds per minute: " + secPerMin)
    kp("seconds per hour:   " + secPerHour)
    kp("seconds per day:    " + secPerDay)
    kp("seconds per year:   " + secPerYear)
    kp("")

    kp("Comparisons:")
    kp("  1 day  = " + (secPerDay  / secPerMin) + " minutes")
    kp("  1 year = " + (secPerYear / secPerHour) + " hours")
    kp("  1 year = " + (secPerYear / secPerDay)  + " days")
    kp("")

    let yearsAlive = 30
    let totalSec = yearsAlive * secPerYear
    kp("If you've been alive for " + yearsAlive + " years, you've experienced:")
    kp("  " + totalSec + " seconds")
    kp("  " + (totalSec / secPerHour) + " hours")
}
