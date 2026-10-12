package com.edde746.plezy

import java.net.InetAddress
import java.net.Socket
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Forward-secret AEAD suites that current servers, GitHub included, require.
 * Android 4.4 supports AES-GCM but only enables it by default from API 20, so
 * without this a KitKat ClientHello offers only CBC suites and such servers
 * end the handshake (SSLHandshakeException).
 */
internal object ModernCipherSuites {
    private val preferred = listOf(
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
        "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
        "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256",
    )

    /** The supported preferred suites first, then whatever was already enabled. */
    fun select(supported: Array<String>, enabled: Array<String>): Array<String> {
        val available = supported.toSet()
        return (preferred.filter { it in available } + enabled).distinct().toTypedArray()
    }
}

/** Keep the provider's socket (including SNI support), enabling TLS 1.2 and AEAD suites on KitKat. */
internal class ModernTlsSocketFactory(private val delegate: SSLSocketFactory) : SSLSocketFactory() {
    private fun configure(socket: Socket): Socket {
        val ssl = socket as SSLSocket
        val enabled = ssl.supportedProtocols.filter { it == "TLSv1.2" || it == "TLSv1.3" }
        if (enabled.isEmpty()) {
            ssl.close()
            throw SSLException("TLS 1.2 is unavailable on this security provider")
        }
        ssl.enabledProtocols = enabled.toTypedArray()
        ssl.enabledCipherSuites = ModernCipherSuites.select(ssl.supportedCipherSuites, ssl.enabledCipherSuites)
        return ssl
    }

    override fun getDefaultCipherSuites(): Array<String> = delegate.defaultCipherSuites
    override fun getSupportedCipherSuites(): Array<String> = delegate.supportedCipherSuites
    override fun createSocket(): Socket = configure(delegate.createSocket())
    override fun createSocket(s: Socket, host: String, port: Int, autoClose: Boolean): Socket =
        configure(delegate.createSocket(s, host, port, autoClose))
    override fun createSocket(host: String, port: Int): Socket =
        configure(delegate.createSocket(host, port))
    override fun createSocket(host: String, port: Int, local: InetAddress, localPort: Int): Socket =
        configure(delegate.createSocket(host, port, local, localPort))
    override fun createSocket(host: InetAddress, port: Int): Socket =
        configure(delegate.createSocket(host, port))
    override fun createSocket(host: InetAddress, port: Int, local: InetAddress, localPort: Int): Socket =
        configure(delegate.createSocket(host, port, local, localPort))
}
