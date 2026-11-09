package com.green.note.content

internal data class PublishForm(
    val type: String,
    val message: String,
    val title: String = "",
    val pictures: List<String> = emptyList(),
    val category: String = "",
    val price: String = "",
    val productLink: String = "",
    val businessSeller: Boolean = false,
    val multipleVote: Boolean = false,
    val voteOptions: List<String> = listOf("", ""),
    val voteDays: Int = 7,
    val voteLimit: Int = 1,
    val cover: String = "",
    val topic: String = "",
    val productId: String = "",
    val location: String = "",
    val extraTitle: String = "",
    val voteId: String = "",
) {
    fun validationError(): String? = when {
        type !in setOf("feed", "article", "picture", "ershou", "vote") -> "不支持的发布类型"
        pictures.size > 9 -> "最多选择9张图片"
        type == "article" && (title.isBlank() || message.isBlank() && pictures.isEmpty()) -> "请填写标题和正文或图片"
        type == "picture" && (pictures.isEmpty() || category.isBlank()) -> "请选择图片和分类"
        type == "ershou" && (title.isBlank() || message.isBlank() || pictures.isEmpty() || (price.toDoubleOrNull() ?: 0.0) <= 0.0 || price.toDoubleOrNull()?.isFinite() != true) -> "请填写标题、描述、图片及有效价格"
        type == "ershou" && productLink.isNotEmpty() && !validWebUrl(productLink) -> "请输入有效的商品链接"
        type == "vote" && (title.isBlank() || voteOptions.size < 2 || voteOptions.any(String::isBlank)) -> "请填写标题和至少两个选项"
        type == "vote" && voteOptions.map(String::trim).distinct().size != voteOptions.size -> "投票选项不能重复"
        type == "vote" && (voteDays !in 1..365 || voteLimit !in 1..voteOptions.size) -> "投票期限或最多选择项数无效"
        type == "feed" && message.isBlank() && pictures.isEmpty() -> "请填写内容或选择图片"
        else -> null
    }

    fun body(nowSeconds: Long): Map<String, String> {
        check(validationError() == null) { validationError().orEmpty() }
        return buildMap {
            put("message", if (type == "vote") title.trim() else message.trim().ifEmpty { "分享图片" })
            put("type", type); put("pic", pictures.joinToString(","))
            if (topic.isNotEmpty()) put("tag", topic)
            if (productId.isNotEmpty()) { put("product_id", productId); if (type != "feed") { put("targetType", "product_phone"); put("targetId", productId) } }
            if (location.isNotEmpty()) put("location", location)
            if (extraTitle.isNotEmpty()) put("extra_title", extraTitle)
            if (voteId.isNotEmpty()) put("vote_id", voteId)
            when (type) {
                "article" -> { put("extra_title", title.trim()); put("message_title", title.trim()); if (cover.isNotEmpty()) put("message_cover", cover) }
                "picture" -> put("tag", category)
                "ershou" -> { put("extra_title", title.trim()); put("ershou_price", price); put("ershou_link", productLink); put("ershou_deal_type", if (businessSeller) "1" else "0") }
                "vote" -> {
                    put("extra_title", title.trim()); put("vote_type", if (multipleVote) "1" else "0"); put("vote_message", message.trim())
                    put("vote_end_time", "${nowSeconds + voteDays.toLong() * 86400}")
                    put("vote_max_select_num", if (multipleVote) "$voteLimit" else "1"); put("vote_min_select_num", "1")
                    voteOptions.forEachIndexed { index, option -> put("vote_option[$index]", option.trim()) }
                }
            }
        }
    }
}
