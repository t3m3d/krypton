// Temperature converter
// Convert between Celsius, Fahrenheit, and Kelvin

func celsiusToFahrenheit(c) {
    emit (c * 9) / 5 + 32
}

func fahrenheitToCelsius(f) {
    emit ((f - 32) * 5) / 9
}

func celsiusToKelvin(c) {
    emit c + 273
}

func kelvinToCelsius(k) {
    emit k - 273
}

func fahrenheitToKelvin(f) {
    emit celsiusToKelvin(fahrenheitToCelsius(f))
}

func kelvinToFahrenheit(k) {
    emit celsiusToFahrenheit(kelvinToCelsius(k))
}

just run {
    kp("Temperature Converter")
    kp("=====================")
    kp("")

    // Common temperatures
    kp("Common temperatures:")
    kp("  Water freezing: 0C = " + celsiusToFahrenheit(0) + "F = " + celsiusToKelvin(0) + "K")
    kp("  Room temp:      20C = " + celsiusToFahrenheit(20) + "F = " + celsiusToKelvin(20) + "K")
    kp("  Body temp:      37C = " + celsiusToFahrenheit(37) + "F = " + celsiusToKelvin(37) + "K")
    kp("  Water boiling:  100C = " + celsiusToFahrenheit(100) + "F = " + celsiusToKelvin(100) + "K")
    kp("")

    // Conversion table
    kp("Celsius to Fahrenheit table:")
    let c = 0 - 40
    while c <= 100 {
        let f = celsiusToFahrenheit(c)
        let label = "" + c
        while len(label) < 6 {
            label = " " + label
        }
        kp("  " + label + " C = " + f + " F")
        c = c + 10
    }
    emit "ok"
}
