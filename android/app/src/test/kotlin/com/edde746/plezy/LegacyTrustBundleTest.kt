package com.edde746.plezy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

class LegacyTrustBundleTest {
    @Test fun bundleContainsOfficialGenerationYChainLinks() {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream("ca/legacy-roots.pem"))
        val certificates = stream.use {
            CertificateFactory.getInstance("X.509").generateCertificates(it)
                .filterIsInstance<X509Certificate>()
        }
        assertEquals(9, certificates.size)

        val rootX1 = certificates.firstOrNull { it.subjectX500Principal.name.contains("CN=ISRG Root X1") }
        val rootYr = certificates.firstOrNull { it.subjectX500Principal.name.contains("CN=Root YR") }
        val rootYe = certificates.firstOrNull { it.subjectX500Principal.name.contains("CN=Root YE") }
        assertNotNull(rootX1)
        assertNotNull(rootYr)
        assertNotNull(rootYe)
        assertEquals("CN=ISRG Root X1,O=Internet Security Research Group,C=US", rootYr!!.issuerX500Principal.name)
        assertEquals("CN=ISRG Root X2,O=Internet Security Research Group,C=US", rootYe!!.issuerX500Principal.name)

        // Proves the bundled RSA bridge is genuinely signed by our existing X1 anchor.
        rootYr.verify(rootX1!!.publicKey)
        certificates.forEach { it.checkValidity() }
    }

    /**
     * GitHub serves github.com and api.github.com from Sectigo's Public Server
     * Authentication hierarchy as well as Let's Encrypt. Android 4.4 predates
     * those roots, so the updater bundles them (with their USERTrust cross-signers).
     */
    @Test fun bundleTrustsGitHubsSectigoHierarchy() {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream("ca/legacy-roots.pem"))
        val bySha256 = stream.use {
            CertificateFactory.getInstance("X.509").generateCertificates(it)
                .filterIsInstance<X509Certificate>()
        }.associateBy { certificate ->
            java.security.MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
                .joinToString("") { "%02X".format(it) }
        }
        val expected = mapOf(
            "7BB647A62AEEAC88BF257AA522D01FFEA395E0AB45C73F93F65654EC38F25A06" to "CN=Sectigo Public Server Authentication Root R46",
            "C90F26F0FB1B4018B22227519B5CA2B53E2CA5B3BE5CF18EFE1BEF47380C5383" to "CN=Sectigo Public Server Authentication Root E46",
            "E793C9B02FD8AA13E21C31228ACCB08119643B749C898964B1746D46C3D4CBD2" to "CN=USERTrust RSA Certification Authority",
            "4FF460D54B9C86DABFBCFC5712E0400D2BED3FBC4D4FBDAA86E06ADCD2A9AD7A" to "CN=USERTrust ECC Certification Authority",
        )
        for ((fingerprint, name) in expected) {
            val certificate = bySha256[fingerprint]
            assertNotNull("$name is missing from the bundle", certificate)
            assertEquals(true, certificate!!.subjectX500Principal.name.startsWith(name))
            certificate.checkValidity()
        }
    }
}
