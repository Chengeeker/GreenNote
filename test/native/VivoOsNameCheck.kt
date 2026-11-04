package com.green.note

fun main() {
    check(vivoOsName("OriginOS 7", "Funtouch", "17.0") == "OriginOS 7.0")
    check(vivoOsName("OriginOS 7.1", "Funtouch", "17.0") == "OriginOS 7.1")
    check(vivoOsName("Funtouch OS 15", "Funtouch", "15.0") == "Funtouch OS 15.0")
    check(vivoOsName("", "Funtouch", "15.0") == "Funtouch OS 15.0")
    check(vivoOsName("PD2502C_A_17.1", "OriginOS", "7.0") == "OriginOS 7.0")
    check(vivoOsName("PD2502C_A_17.1", "", "") == null)
    check(vivoOsName("Android 17", "", "") == null)
    check(vivoOsName("", "", "PD2502C_A_17.1") == null)
    println("Vivo OS name: 8 checks passed")
}
