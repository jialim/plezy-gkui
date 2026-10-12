package com.edde746.plezy

import org.junit.Assert.*
import org.junit.Test
import java.net.InetAddress
import java.net.Socket
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

class ModernTlsSocketFactoryTest {
    /** Reproduce a provider that supports TLS 1.2 but enables only TLS 1.0. No network I/O. */
    private class LegacyDefaults : SSLSocketFactory() {
        val delegate = SSLContext.getInstance("TLS").apply { init(null, null, null) }.socketFactory
        var last: Socket? = null
        private fun legacy(): Socket = (delegate.createSocket() as SSLSocket).apply {
            enabledProtocols = arrayOf("TLSv1")
            // KitKat enables only CBC suites by default, although it supports GCM.
            enabledCipherSuites = supportedCipherSuites.filter { it.endsWith("_CBC_SHA") }.toTypedArray()
            last = this
        }
        override fun getDefaultCipherSuites() = delegate.defaultCipherSuites
        override fun getSupportedCipherSuites() = delegate.supportedCipherSuites
        override fun createSocket() = legacy()
        override fun createSocket(s: Socket, host: String, port: Int, close: Boolean) = legacy()
        override fun createSocket(host: String, port: Int) = legacy()
        override fun createSocket(host: String, port: Int, local: InetAddress, localPort: Int) = legacy()
        override fun createSocket(host: InetAddress, port: Int) = legacy()
        override fun createSocket(host: InetAddress, port: Int, local: InetAddress, localPort: Int) = legacy()
    }

    @Test fun everySocketOverloadEnablesModernTlsAndPreservesProviderSocket() {
        val provider = LegacyDefaults()
        val factory = ModernTlsSocketFactory(provider)
        val address = InetAddress.getByAddress(byteArrayOf(127, 0, 0, 1))
        val creators: List<() -> Socket> = listOf(
            { factory.createSocket() },
            { Socket().use { factory.createSocket(it, "unused.test", 443, true) } },
            { factory.createSocket("unused.test", 443) },
            { factory.createSocket("unused.test", 443, address, 0) },
            { factory.createSocket(address, 443) },
            { factory.createSocket(address, 443, address, 0) },
        )
        for (create in creators) {
            (create() as SSLSocket).use { socket ->
                assertSame(provider.last, socket)
                assertTrue(socket.enabledProtocols.contains("TLSv1.2"))
                assertTrue(socket.enabledProtocols.all { it == "TLSv1.2" || it == "TLSv1.3" })
                assertEquals("TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", socket.enabledCipherSuites.first())
                assertTrue(socket.enabledCipherSuites.contains("TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"))
                // The provider's own suites stay available as a fallback.
                assertTrue(socket.enabledCipherSuites.any { it.endsWith("_CBC_SHA") })
            }
        }
        assertArrayEquals(provider.defaultCipherSuites, factory.defaultCipherSuites)
    }

    @Test fun unsupportedPreferredSuitesAreNeverEnabled() {
        val selected = ModernCipherSuites.select(
            supported = arrayOf("TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", "TLS_RSA_WITH_AES_128_CBC_SHA"),
            enabled = arrayOf("TLS_RSA_WITH_AES_128_CBC_SHA"),
        )
        assertArrayEquals(
            arrayOf("TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", "TLS_RSA_WITH_AES_128_CBC_SHA"),
            selected,
        )
    }
}
