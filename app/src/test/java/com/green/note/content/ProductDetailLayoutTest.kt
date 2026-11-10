package com.green.note.content

import android.app.Application
import android.content.ComponentName
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.core.app.ApplicationProvider
import com.green.note.settings.AppPreferences
import com.green.note.ui.GreenNoteTheme
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import org.junit.rules.TestRule
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.junit.runner.RunWith

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "zh-rCN-w360dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ProductDetailLayoutTest {
    private val compose = createAndroidComposeRule<ComponentActivity>()
    private val register = TestRule { base, _ -> object : org.junit.runners.model.Statement() {
        override fun evaluate() {
            val context = ApplicationProvider.getApplicationContext<Application>()
            shadowOf(context.packageManager).addActivityIfNotPresent(ComponentName(context, ComponentActivity::class.java))
            base.evaluate()
        }
    } }
    @get:Rule val rules: TestRule = RuleChain.outerRule(register).around(compose)

    @Test fun watchUsesOfficialHeaderGeometryAndOnlyItsOwnRatingDimensions() {
        val product = JSONObject("""{
            "id":"2488","title":"OPPO Watch Free","category_id":1005,"is_can_compare":0,
            "release_time":"2021年09月26日","tagArr":["全场景睡眠监测","血氧监测"],
            "hot_num_txt":"680","feed_comment_num_txt":"4792","follow_num_txt":"1774",
            "owner_star_total_count":0,"star_total_count":256,"v4_rating_total_count":27,"rating_average_score":"8.0",
            "rating_item_info":[
                {"id":"v4_score_item_1","name":"续航","average_score":"8.6"},
                {"id":"v4_score_item_2","name":"屏幕","average_score":"8.0"},
                {"id":"v4_score_item_3","name":"外观质感","average_score":"7.7"},
                {"id":"v4_score_item_4","name":"系统","average_score":"6.5"},
                {"id":"v4_score_item_5","name":"性价比","average_score":"7.6"}
            ]
        }""")
        val tabs = listOf("参数" to "main", "讨论" to "feed", "点评" to "rating", "图文" to "article", "问答" to "answer", "交易" to "trade")
        product.put("tabList", JSONArray(tabs.map { (label, type) ->
            JSONObject().put("title", label).put("url", "/product/feedList?type=$type&id=2488")
        }))
        val post = JSONObject("""{"entityType":"feed","id":"1","uid":"2","username":"Oneton","user_level":4,
            "device_title":"小米13 Pro","message":"#OPPOWatchFree# 有人试过实时动态更新吗？"}""")
        val api = object : ContentApi {
            override suspend fun request(path: String, method: String, query: Map<String, String>, body: Map<String, String>?): JSONObject {
                return JSONObject().put("data", if (path == "/v6/product/detail") product else JSONArray(listOf(post)))
            }
        }
        compose.setContent {
            GreenNoteTheme(AppPreferences(themeMode = 2)) {
                NativeEntityDetailScreen(api, "product", "2488", {}, { _, _, _ -> })
            }
        }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Oneton", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        fun label(text: String): Rect = compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val toolbarBottom = compose.onNodeWithContentDescription("返回", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.center.y + 26
        assertEquals(102f, label("OPPO Watch Free").left, 1f)
        assertEquals(28f, label("酷安评分").left, 1f)
        assertEquals(117f, label("酷安评分").top - toolbarBottom, 3f)
        assertEquals(284f, label("2021-09-26 上市").center.y - toolbarBottom, 3f)
        assertEquals(93f, label("讨论").center.x, 2f)
        assertEquals(379f, label("全部讨论").center.y - toolbarBottom, 4f)
        assertEquals(62f, label("Oneton").left, 2f)
        assertEquals(422f, label("Oneton").center.y - toolbarBottom, 5f)
        assertEquals(listOf("续航" to 8.6f, "屏幕" to 8f, "外观质感" to 7.7f, "系统" to 6.5f, "性价比" to 7.6f),
            productDimensionScores(product))
        compose.onNodeWithText("680热度  4792讨论", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("1774关注", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("256用户点评 27详细点评", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("Lv.4").assertDoesNotExist()
        compose.onNodeWithText("影像").assertDoesNotExist()
        compose.onNodeWithText("性能").assertDoesNotExist()
        compose.onNodeWithText("对比").assertDoesNotExist()
        compose.onNodeWithText("购买").assertDoesNotExist()
        compose.onNodeWithText("最新").performClick().assertIsSelected()
        compose.onNodeWithText("OPPO Watch Free").assertIsDisplayed()
    }
}
