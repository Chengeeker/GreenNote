package com.green.note.content

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DigitalLibraryDataTest {
    @Test fun tabletBrandRoutesRetainServerQueriesAndDoNotMutateInput() {
        val row=JSONObject().put("id","123").put("url","/page?url=%2Fproduct%2FseriesList%3Fcategory_id%3D1000%26id%3D123")
        val original=row.toString();assertTrue(digitalTabletBrand(row).text("url").contains("category_id%3D1001"));assertEquals(original,row.toString())
        assertTrue(digitalTabletBrand(JSONObject().put("id","123")).text("url").contains("category_id%3D1001"))
        assertEquals("",digitalTabletBrand(JSONObject()).text("url"))
    }
    @Test fun rankingDefaultsToPhoneWhileBrandHonorsMarkedTab() {
        val root=JSONObject("""{"data":[{"entityTemplate":"sortSelectCard","entities":[{"title":"平板榜","url":"pad"},{"title":"手机榜","url":"phone"}]}]}""")
        assertEquals(1,digitalTabs(root,false).second)
        val brand=JSONObject("""{"data":[{"entityTemplate":"iconTabLinkGridCard","selectedTab":1,"entities":[{"title":"第一系列","url":"one","isSelected":true},{"title":"第二系列","url":"two"}]}]}""")
        assertEquals(0,digitalTabs(brand,true).second)
    }
    @Test fun groupedProductsRespectInterveningCardsAndDoNotMutateInput() {
        fun product(id:String)=JSONObject().put("entityType","product").put("id",id).put("_composeGroupProducts",true).put("_composeCardContext","brand")
        val rows=listOf(product("1"),product("2"),JSONObject().put("entityType","card"),product("3"));val before=rows.map{it.toString()}
        val result=normalizeSpecializedCards(rows)
        assertTrue(result[0].optBoolean("_composeGroupStart"));assertFalse(result[0].optBoolean("_composeGroupEnd"))
        assertFalse(result[1].optBoolean("_composeGroupStart"));assertTrue(result[1].optBoolean("_composeGroupEnd"))
        assertTrue(result[3].optBoolean("_composeGroupStart"));assertTrue(result[3].optBoolean("_composeGroupEnd"));assertEquals(before,rows.map{it.toString()})
    }
}
