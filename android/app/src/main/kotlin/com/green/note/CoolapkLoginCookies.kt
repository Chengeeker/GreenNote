package com.green.note

import android.webkit.CookieManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Fixed official origins only; never expose a general-purpose cookie reader. */
class CoolapkLoginCookies {
    private val hosts = listOf("account.coolapk.com", "www.coolapk.com", "api.coolapk.com", "api2.coolapk.com")

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            val manager = CookieManager.getInstance()
            when (call.method) {
                "read" -> {
                    val values = linkedMapOf<String, String>()
                    for (host in hosts) {
                        for (part in manager.getCookie("https://$host/").orEmpty().split(';')) {
                            val index = part.indexOf('=')
                            if (index > 0) values[part.substring(0, index).trim()] = part.substring(index + 1).trim()
                        }
                    }
                    result.success(values.entries.joinToString("; ") { "${it.key}=${it.value}" })
                }
                "clear" -> {
                    val names = mutableSetOf("uid", "username", "token", "SESSID", "validate", "forward")
                    for (host in hosts) {
                        for (path in listOf("/", "/auth/loginByCoolApk")) {
                            manager.getCookie("https://$host$path").orEmpty().split(';').forEach {
                                val name = it.substringBefore('=').trim()
                                if (Regex("[A-Za-z0-9_-]{1,128}").matches(name)) names.add(name)
                            }
                        }
                    }
                    val removals = hosts.flatMap { host -> names.flatMap { name ->
                        listOf("/", "/auth", "/auth/").flatMap { path ->
                            listOf("", "; Domain=.coolapk.com", "; Domain=$host").map { domain ->
                                "https://$host/" to "$name=; Path=$path$domain; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; HttpOnly"
                            }
                        }
                    } }
                    var remaining = removals.size
                    for ((url, cookie) in removals) {
                        manager.setCookie(url, cookie) {
                            remaining--
                            if (remaining == 0) {
                                manager.flush()
                                result.success(null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("LOGIN_COOKIES", "Cannot access login session", null)
        }
    }
}
