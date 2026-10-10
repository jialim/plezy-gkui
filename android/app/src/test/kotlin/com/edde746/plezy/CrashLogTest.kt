package com.edde746.plezy

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CrashLogTest {
    @Test
    fun keepsExceptionClassesAndLocationsButNoMessages() {
        val error = RuntimeException(
            "https://plex.example/library/parts/1?X-Plex-Token=secret",
            IllegalStateException("token=secret"),
        )
        val text = CrashLog.format("Crash on main", error, 0L)

        assertTrue(text.contains("Crash on main"))
        assertTrue(text.contains("java.lang.RuntimeException"))
        assertTrue(text.contains("caused by java.lang.IllegalStateException"))
        assertTrue(text.contains("  at CrashLogTest.keepsExceptionClassesAndLocationsButNoMessages:"))
        assertFalse(text.contains("secret"))
        assertFalse(text.contains("plex.example"))
    }

    @Test
    fun locationNamesTheThrowingFrame() {
        val location = CrashLog.location(IllegalStateException())
        assertTrue(location.startsWith("CrashLogTest.locationNamesTheThrowingFrame:"))
    }
}
