package com.edde746.plezy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XgimiApkVerifierTest {
  @Test
  fun refusesEqualVersionsAndDowngrades() {
    assertTrue(XgimiApkVerifier.isNewerBuild(1155, 1154))
    assertFalse(XgimiApkVerifier.isNewerBuild(1154, 1154))
    assertFalse(XgimiApkVerifier.isNewerBuild(1153, 1154))
  }

  @Test
  fun acceptsOnlyAnUpdateCarryingTheInstalledCertificate() {
    val installed = listOf("aa")
    assertTrue(XgimiApkVerifier.sharesSigner(installed, listOf("aa")))
    // A rotated key still lists the original certificate in its history.
    assertTrue(XgimiApkVerifier.sharesSigner(installed, listOf("aa", "bb")))
    assertFalse(XgimiApkVerifier.sharesSigner(installed, listOf("bb")))
    assertFalse(XgimiApkVerifier.sharesSigner(emptyList(), listOf("aa")))
  }

  @Test
  fun digestsCertificatesAsLowercaseSha256() {
    assertEquals(
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      XgimiApkVerifier.digest(ByteArray(0)),
    )
  }
}
