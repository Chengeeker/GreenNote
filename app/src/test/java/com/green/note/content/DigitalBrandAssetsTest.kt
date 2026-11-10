package com.green.note.content

import android.app.Application
import android.graphics.BitmapFactory
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.green.note.settings.AppPreferences
import com.green.note.ui.GreenNoteTheme
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], application = Application::class, qualifiers = "w360dp-h800dp-mdpi")
class DigitalBrandAssetsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val temp = TemporaryFolder()

    @Test fun phoneAndTabletStartWithTheRealBrandImagesAndRoutesWhileOffline() {
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject =
                throw IOException("offline")
        }
        var opened = ""
        compose.setContent {
            GreenNoteTheme(AppPreferences()) {
                DigitalLibraryScreen(api, onProduct = {}, onBrand = { _, route -> opened = route }, onLogin = {})
            }
        }
        // An empty or failed logo adds a second copy of the brand's title inside the tile.
        compose.onAllNodesWithText("小米", useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithText("小米").performClick()
        compose.runOnIdle {
            assertTrue(opened.contains("id%3D1016%26category_id%3D1000"))
        }
        compose.onNodeWithText("平板").performClick()
        compose.onAllNodesWithText("华为", useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithText("华为").performClick()
        compose.runOnIdle {
            assertTrue(opened.contains("id%3D1002%26category_id%3D1001"))
        }
    }

    @Test fun changedLogoIsValidatedPersistedAndNeverReplacedByStaleOrFailedData() = runBlocking {
        val context = compose.activity.applicationContext
        val directory = temp.newFolder()
        val base = "https://image.coolapk.com/product_logo/"
        val invalid = "${base}2026/1109/10/invalid.png"
        val newer = "${base}2026/1109/11/new.png"
        val newest = "${base}2026/1110/10/newest.png"
        val oldStarted = CompletableDeferred<Unit>()
        val finishOld = CompletableDeferred<Unit>()
        val requested = mutableListOf<String>()
        lateinit var picture: ByteArray
        val assets = DigitalBrandAssets(context, directory) { url ->
            synchronized(requested) { requested.add(url) }
            when (url) {
                invalid -> byteArrayOf(1, 2, 3)
                newer -> { oldStarted.complete(Unit); finishOld.await(); picture }
                newest -> picture
                else -> error("Unexpected image request")
            }
        }
        assets.warm()
        val stock = assets.rows("1000").first { it.text("id") == "1016" }.text("logo")
        picture = context.resources.openRawResource(assets.drawable("1016")).use { it.readBytes() }
        assets.refresh("1016", stock)
        assets.refresh("1016", "https://image.coolapk.com.example/product_logo/fake.png")
        assets.refresh("../escape", newest)
        assertTrue(requested.isEmpty())
        assets.refresh("1016", invalid)
        assertNull(assets.savedBytes("1016"))
        val pending = async { assets.refresh("1016", newer) }
        oldStarted.await()
        assets.refresh("1016", newest)
        val saved = requireNotNull(assets.savedBytes("1016"))
        finishOld.complete(Unit)
        pending.await()
        assertSame(saved, assets.savedBytes("1016"))
        assertNotNull(BitmapFactory.decodeByteArray(saved, 0, saved.size))
        val restarted = DigitalBrandAssets(context, directory) { error("Already available locally") }
        assertArrayEquals(saved, restarted.savedBytes("1016"))
        restarted.refresh("1016", stock)
        restarted.refresh("1016", newer)
        restarted.refresh("1016", newest)
    }
}
