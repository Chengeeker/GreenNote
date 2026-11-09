package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class FeedCardDataTest {
    @Test fun explicitMetadataMergesWithoutMutatingInputsAndBadgePriorityMatchesOriginal() {
        val row=JSONObject("""{"picArr":[{"url":"http://example.test/p.jpg","width":300,"height":1000}],"imageUriList":[{"url":"https://example.test/p.jpg","hdr":1}]}""")
        val before=row.toString();val metadata=feedPictureMetadata(row,"https://example.test/p.jpg")
        assertEquals(300,feedPictureDimension(metadata,"width"));assertEquals("HDR",feedImageBadge("https://example.test/p.jpg",metadata,row,false))
        assertEquals("GIF",feedImageBadge("https://example.test/p.gif",metadata,row,true));assertEquals(before,row.toString())
        metadata.remove("hdr");assertEquals("长图",feedImageBadge("https://example.test/p.jpg",metadata,row,false))
        assertNull(feedImageBadge("https://example.test/p.jpg",JSONObject("""{"width":300,"height":600}"""),null,false))
    }
    @Test fun nestedDimensionsAndFeedHdrFlagsAreRecognized() {
        val raw=JSONObject("""{"large":{"geo":{"width":"120","height":400}}}""")
        assertEquals(120,feedPictureDimension(raw,"width"));assertEquals(400,feedPictureDimension(raw,"height"))
        assertEquals("HDR",feedImageBadge("https://example.test/image",raw,JSONObject().put("isHdr",true),false))
        assertEquals("长图",feedImageBadge("https://example.test/image",JSONObject(),null,false,120,400))
        assertEquals("长图",feedImageBadge("https://example.test/image?is_long=1",JSONObject(),null,false))
    }
    @Test fun coverSelectionDoesNotRepeatOrdinaryPicturesInDetail() {
        val row=JSONObject("""{"title":"图文动态","username":"张三","pic":"https://example.test/one.jpg,https://example.test/two.jpg"}""")
        assertEquals("https://example.test/one.jpg",feedArticleCover(row,false));assertEquals("",feedArticleCover(row,true));assertFalse(feedIsArticle(row,false))
        row.put("title","一篇文章");assertTrue(feedIsArticle(row,false));assertFalse(feedIsArticle(row,true));row.put("entityType","article");assertTrue(feedIsArticle(row,true))
    }
    @Test fun priceClassificationRejectsNonfiniteValuesAndCountFormattingKeepsOriginalBoundary() {
        fun price(value:String)=feedPrice(JSONObject().put("tsubid","6").put("tsubdata",JSONObject().put("final_price",value)))
        assertNull(price("NaN"));assertNull(price("Infinity"));assertNull(price("0"));assertEquals("12.5",price("12.50")?.formatted);assertEquals("12",price("12")?.formatted)
        assertEquals("",feedCount(0));assertEquals("10000",feedCount(10000));assertEquals("1.0w",feedCount(10001))
        val row=JSONObject("""{"title":"价格分享","pic":"https://example.test/p.jpg","tsubid":6,"tsubdata":{"final_price":100}}""")
        assertFalse(feedIsArticle(row,false))
    }
}
