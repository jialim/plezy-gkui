package com.edde746.plezy

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Keeps the last crash on disk so the Status screen can show it after the app
 * restarts. Only exception classes and code locations are stored: messages can
 * carry stream URLs or Plex tokens.
 */
internal object CrashLog {
    private const val FILE_NAME = "last-crash.txt"
    private const val MAX_CAUSES = 3
    private const val FRAMES_PER_CAUSE = 6

    fun install(context: Context) {
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                record(appContext, "Crash on ${thread.name}", error)
            } catch (_: Throwable) {
                // Never let crash logging replace the original crash.
            }
            previous?.uncaughtException(thread, error)
        }
    }

    fun record(context: Context, label: String, error: Throwable) {
        File(context.filesDir, FILE_NAME).writeText(format(label, error, System.currentTimeMillis()))
    }

    fun read(context: Context): String? =
        File(context.filesDir, FILE_NAME).takeIf { it.isFile }?.readText()?.takeIf { it.isNotBlank() }

    fun format(label: String, error: Throwable, timeMs: Long): String {
        val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date(timeMs))
        val lines = mutableListOf("$time  $label")
        var current: Throwable? = error
        val seen = mutableListOf<Throwable>()
        while (current != null && seen.size < MAX_CAUSES && seen.none { it === current }) {
            seen.add(current)
            lines.add((if (seen.size == 1) "" else "caused by ") + current.javaClass.name)
            current.stackTrace.take(FRAMES_PER_CAUSE).forEach { lines.add("  at ${location(it)}") }
            current = current.cause
        }
        return lines.joinToString("\n")
    }

    /** `Class.method:line` for the frame that threw, without the package prefix. */
    fun location(error: Throwable): String =
        error.stackTrace.firstOrNull()?.let(::location) ?: "unknown location"

    private fun location(frame: StackTraceElement): String =
        "${frame.className.substringAfterLast('.')}.${frame.methodName}:${frame.lineNumber}"
}
