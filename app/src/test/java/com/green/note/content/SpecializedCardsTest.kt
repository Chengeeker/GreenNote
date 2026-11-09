package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SpecializedCardsTest {
    @Test fun systemMergingRetainsOriginalRowsAndDoesNotMutateInput() {
        val main=JSONObject("""{"id":"one","entityTemplate":"iconListCard","title":"系统区","_composeCardContext":"system","entities":[{"id":"system"}]}""")
        val grid=JSONObject("""{"entityTemplate":"iconMiniGridCard","entities":[{"id":"feature"}]}""")
        val tail=JSONObject("""{"id":"tail","title":"其他卡片"}""")
        val before=listOf(main,grid,tail).map{it.toString()}
        val result=normalizeSpecializedCards(listOf(main,grid,tail))
        assertEquals(2,result.size);assertEquals("system_zone_card",result[0].text("entityType"))
        assertEquals("system",cardChildren(result[0].getJSONObject("mainCard")).single().text("id"))
        assertEquals("feature",cardChildren(result[0].getJSONObject("featureCard")).single().text("id"))
        assertEquals("tail",result[1].text("id"));assertEquals(before,listOf(main,grid,tail).map{it.toString()})
        result[0].getJSONObject("featureCard").put("title","changed output")
        assertEquals(before,listOf(main,grid,tail).map{it.toString()})
    }
    @Test fun carouselMergesOnlyAdjacentDigitalQuickLinks() {
        fun rows(context:String)=listOf(JSONObject().put("entityTemplate","imageCarouselCard").put("_composeCardContext",context),JSONObject("""{"entityTemplate":"iconMiniLinkGridCard","entities":[{"id":"link"}]}"""))
        assertEquals(2,normalizeSpecializedCards(rows("api")).size)
        val merged=normalizeSpecializedCards(rows("digital_channel"));assertEquals(1,merged.size)
        assertEquals("link",merged.single().getJSONArray("quickLinks").getJSONObject(0).text("id"))
    }
    @Test fun bannerRatiosPreserveTemplateSpecificRules() {
        assertEquals(4.5f,bannerAspectRatio("https://example.test/banner.jpg"),0f)
        assertEquals(3.338f,bannerAspectRatio("https://example.test/banner@1200x600.jpg"),.0001f)
        assertEquals(2f,bannerAspectRatio("https://example.test/banner@1200x600.jpg",false),0f)
        assertEquals(4.5f,bannerAspectRatio("https://example.test/banner@1200x0.jpg"),0f)
        assertEquals("1.2万",digitalHot("12000"));assertEquals("1万",digitalHot("10000"));assertEquals("3.5万",digitalHot("3.5万"))
    }
    @Test fun imageMetadataOverridesUrlButInvalidDimensionsStayBounded() {
        val row=JSONObject("""{"picArr":[{"url":"https://example.test/a@400x200.jpg","width":300,"height":1200}],"imageUriList":[{"url":"https://example.test/a@400x200.jpg","geo":{"width":500}}]}""")
        assertEquals(.35f,discoveryPictureRatio(row,"https://example.test/a@400x200.jpg"),0f)
        assertEquals(2f,discoveryPictureRatio(JSONObject(),"https://example.test/a@600x100.jpg"),0f)
        assertEquals(.5f,discoveryPictureRatio(JSONObject(),"https://example.test/a@600x0.jpg"),0f)
        assertEquals("11.5\n10:30",homeCalendarTime("2026年11月5日10:30"))
        assertEquals("即将发布",homeCalendarTime("即将发布"))
        assertEquals(4.5f,configuredCardRatio(JSONObject("""{"extraDataArr":{"dimensionRatio":"1080:0"}}""")),0f)
    }
    @Test fun rankingProductMergeAndVoteKeepSourceImmutableAndServerIdentity() {
        val row=JSONObject("""{"id":"ranking-item","note":"original","extra_entities":[{"id":"goods-id","title":"Product"}],"goodsListInfo":{"item_id":"server-vote-id","is_vote":0,"vote_num":9},"isVote":1,"vote_num":500}""")
        val original=row.toString();val product=rankingProduct(row)
        assertEquals("goods-id",product.text("id"));assertEquals("original",product.text("note"))
        assertEquals(false to 9L,rankingVote(row))
        val updated=rankingApplyVote(row)
        assertEquals(true to 10L,rankingVote(updated));assertEquals("ranking-item",updated.text("id"))
        assertEquals("server-vote-id",updated.getJSONObject("goodsListInfo").text("item_id"))
        assertEquals(original,row.toString())
        assertEquals(false to 9L,rankingVote(rankingApplyVote(updated)))
    }
    @Test fun rankingVoteCountsNeverUnderflowAndBuyLinksAreExternalWebOnly() {
        val selected=JSONObject("""{"isVote":1,"vote_num":0}""")
        assertEquals(false to 0L,rankingVote(rankingApplyVote(selected)))
        listOf("javascript:alert(1)","file:///data/x","https://user:password@example.com/path","intent://somewhere").forEach { assertEquals("",rankingBuyUrl(JSONObject().put("url",it))) }
        val url="https://example.com/item?id=123";assertEquals(url,rankingBuyUrl(JSONObject().put("goods_buy_url",url)))
    }
}
