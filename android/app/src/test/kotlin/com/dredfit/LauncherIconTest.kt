//
//  The launcher icon the manifest names. Android only — iOS's is named by the
//  build setting ASSETCATALOG_COMPILER_APPICON_NAME. The app once installed with the system's
//  default icon because the manifest named none, and no build or test
//  failed; a name that resolves to nothing fails the build instead.
//

package com.dredfit

import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.test.Test
import kotlin.test.assertEquals

class LauncherIconTest {

    private val android = "http://schemas.android.com/apk/res/android"

    @Test
    fun theAppNamesItsAdaptiveIcon() {
        val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        val doc = factory.newDocumentBuilder().parse(File("src/main/AndroidManifest.xml"))
        val application = doc.getElementsByTagName("application").item(0) as Element
        assertEquals("@mipmap/ic_launcher", application.getAttributeNS(android, "icon"))
        assertEquals("@mipmap/ic_launcher", application.getAttributeNS(android, "roundIcon"),
                     "the round one is the same adaptive icon, masked by the launcher")
    }
}
