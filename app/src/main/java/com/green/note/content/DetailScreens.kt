package com.green.note.content

import com.green.note.ui.ReviewText as Text

import com.green.note.ui.rememberReviewScrollState
import com.green.note.ui.tapClickable as clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

private data class FeedDetailSnapshot(val feed: JSONObject, val parts: List<ArticlePart>)

private suspend fun loadFeedDetail(api: ContentApi, id: String, seed: JSONObject?, challenge: com.green.note.network.CaptchaRequired? = null): FeedDetailSnapshot {
    val owner = api.imageCacheScope()
    val response = if (challenge == null) api.request("/v6/feed/detail", query = mapOf("id" to id)) else api.verifyFeedDetail(id, challenge)
    val detail = response.optJSONObject("data") ?: error("动态详情为空")
    val result = withContext(Dispatchers.Default) {
        check(detail.length() > 0) { "动态详情为空" }
        val merged = mergeFeedDetail(seed, detail)
        FeedDetailSnapshot(merged, articleParts(merged))
    }
    check(owner == api.imageCacheScope()) { "账号已变更，请重新打开动态" }
    return result
}

@Composable
internal fun FeedDetailScreen(api: ContentApi, id: String, session: ContentSession,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit,
    onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit, onLogin: () -> Unit, initialReplyId: String = "", onBack: () -> Unit = {}, questionId: String = "", initialFeed: JSONObject? = null) {
    val reactions = remember(api, id) { ReplyReactionStore() }
    CompositionLocalProvider(LocalReplyReactions provides reactions) {
        FeedDetailContent(api, id, session, onOpen, onUser, onLink, onGallery, onLike, onMore, onLogin, initialReplyId, onBack, questionId, initialFeed)
    }
}

@Composable
private fun FeedDetailContent(api: ContentApi, id: String, session: ContentSession,
    onOpen: (JSONObject) -> Unit, onUser: (String) -> Unit, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit,
    onLike: (JSONObject) -> Unit, onMore: (JSONObject) -> Unit, onLogin: () -> Unit, initialReplyId: String, onBack: () -> Unit, questionId: String, initialFeed: JSONObject?) {
    val seed = initialFeed?.takeIf { it.text("id", "entityId") == id }
    var feed by remember(id, seed) { mutableStateOf(seed) }
    var parsedParts by remember(id, seed) { mutableStateOf(emptyList<ArticlePart>()) }
    val trade = remember(feed) { feed?.let(::secondhandInfo) }
    val parts = if (trade == null) parsedParts else emptyList()
    var failure by remember(id) { mutableStateOf<String?>(null) }
    var challenge by remember(id) { mutableStateOf<com.green.note.network.CaptchaRequired?>(null) }
    var requestedVerification by remember(id) { mutableStateOf<com.green.note.network.CaptchaRequired?>(null) }
    var attempt by remember(id) { mutableIntStateOf(0) }
    var ordering by rememberSaveable(id) { mutableIntStateOf(0) }
    var replyTo by remember { mutableStateOf<JSONObject?>(null) }
    var replyToDelete by remember { mutableStateOf<JSONObject?>(null) }
    var targetReply by remember(initialReplyId) { mutableStateOf<JSONObject?>(null) }
    var targetFailure by remember(initialReplyId) { mutableStateOf<String?>(null) }
    val draft = remember(id) { ReplyDraft() }
    var menu by remember { mutableStateOf(false) }; var delete by remember { mutableStateOf(false) }; var working by remember { mutableStateOf(false) }; var following by remember(id, seed) { mutableStateOf(seed?.let(api::isUserFollowed) ?: false) }
    val scope = rememberCoroutineScope(); val context = androidx.compose.ui.platform.LocalContext.current
    val toast = remember { com.green.note.ui.AppToastState() }
    val deviceRecovery = LocalCommentDeviceRecovery.current
    val importing = deviceRecovery?.importing == true
    val importRevision = deviceRecovery?.revision ?: 0L
    val owner = api.imageCacheScope()
    val replyLists = remember(api, id) { CommentListOwner(owner, importRevision) }
        .listsFor(owner, importRevision, importing, deviceRecovery?.preserveOwner == true)
    val removedReplies = remember(replyLists) { mutableStateListOf<String>() }
    val replies = replyLists[ordering]
    val hotReplies = replyLists[1]
    val requestedOrdering = ordering
    val requestedAuthorOnly = ordering == 3
    val authorUid = feed?.let(::replyAuthor)?.uid.orEmpty()
    val replySource = Triple(attempt to importRevision, requestedOrdering, authorUid.takeIf { requestedAuthorOnly }.orEmpty())
    val hotSource = Triple(attempt to importRevision, 1, "")
    val previewFeed = feed
    val restricted = replies.accessRestricted && replies.rows.isEmpty()
    val emptyHotPage = hotReplies.appliedSource == hotSource && !hotReplies.busy &&
        hotReplies.error == null && hotReplies.rows.isEmpty() && !hotReplies.more
    val checkingHot = restricted && ordering in listOf(0, 2) && hotReplies.rows.isEmpty() &&
        !emptyHotPage && hotReplies.error == null
    val embedded = remember(previewFeed, id, requestedAuthorOnly) {
        previewFeed?.let { embeddedReplies(it, id, requestedAuthorOnly) }.orEmpty()
    }
    val needsRecentFallback = embedded.isEmpty() && (ordering == 1 && emptyHotPage ||
        restricted && !requestedAuthorOnly && !checkingHot && hotReplies.rows.isEmpty())
    val recentIds = if (needsRecentFallback) recentReplyIds(previewFeed) else emptyList()
    val recentPreview by key(replyLists, recentIds, attempt, importRevision) {
        produceState<List<JSONObject>?>(null, importing) {
            if (!importing && value == null && recentIds.isNotEmpty()) value = loadRecentReplyPreview(api, recentIds, id)
        }
    }
    val loadingRecent = recentIds.isNotEmpty() && recentPreview == null
    val hotPreview = restricted && ordering in listOf(0, 2) && hotReplies.rows.isNotEmpty()
    val fallbackReplies = when {
        hotPreview -> hotReplies.rows
        restricted || ordering == 1 && emptyHotPage -> embedded.ifEmpty { recentPreview.orEmpty() }
        else -> emptyList()
    }.filterNot { replyId(it) in removedReplies }
    LaunchedEffect(replies, replySource, importing) {
        if (!importing && requestedOrdering != 1) {
            replies.bind(replySource) { page, first, last ->
                check(!requestedAuthorOnly || authorUid.isNotEmpty()) { "暂时无法确认原帖作者" }
                loadContentReplies(api, feed, id, requestedOrdering, requestedAuthorOnly, page, first, last)
            }
        }
    }
    LaunchedEffect(hotReplies, hotSource, importing) {
        if (importing) return@LaunchedEffect
        // Keep one hot request alive across a switch between the selected list and its preview.
        snapshotFlow {
            val selected = replyLists[ordering]
            ordering == 1 || ordering in listOf(0, 2) && selected.accessRestricted && selected.rows.isEmpty()
        }.first { it }
        hotReplies.bind(hotSource) { page, first, last ->
            loadContentReplies(api, null, id, 1, false, page, first, last)
        }
    }
    LaunchedEffect(id, seed) {
        if (seed != null && trade == null) {
            val preview = withContext(Dispatchers.Default) { articleParts(seed) }
            if (feed === seed) parsedParts = preview
        }
    }
    LaunchedEffect(api, id, attempt, seed, importRevision) {
        if (importing) return@LaunchedEffect
        val verification = requestedVerification
        requestedVerification = null
        challenge = null
        failure = null
        try {
            val (next, body) = loadFeedDetail(api, id, feed ?: seed, verification)
            parsedParts = body; feed = next; following = api.isUserFollowed(next)
        }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { challenge = error as? com.green.note.network.CaptchaRequired; failure = error.message }
    }
    fun retryDetail() { requestedVerification = challenge; attempt++ }
    val inlineFailure = failure?.takeIf { feed != null && challenge == null && !isContentAccessError(it) }
    LaunchedEffect(initialReplyId, attempt, importRevision) {
        if (initialReplyId.isEmpty() || importing) return@LaunchedEffect
        try {
            val root = api.request("/v6/feed/replyDetail", query = mapOf("id" to initialReplyId)); val row = root.optJSONObject("data") ?: root
            check(replyMatchesFeed(row, id)) { "评论不属于当前帖子" }
            check(replyId(row) == initialReplyId && visibleReply(row)) { "评论已删除或暂不可访问" }
            targetReply = normalizeReply(row, id); targetFailure = null
        } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { targetFailure = "目标评论加载失败：${error.message}" }
    }
    val scroll = androidx.compose.foundation.lazy.rememberLazyListState()
    val commentsIndex = if (parts.isEmpty()) 1 else parts.size + 2
    val articleImages = remember(parts) { parts.filter { it.type == "image" }.map { it.url } }
    val articleIndices = remember(parts) { articleImageIndices(parts) }
    val articleLead = remember(feed, parts.isNotEmpty()) { feed?.let { row ->
        JSONObject(row, row.keys().asSequence().toList().toTypedArray())
            .put("_composeArticlePartsExternal", true).put("_composeArticleHeaderOnly", parts.isNotEmpty())
    } }
    val articleTail = remember(feed, parts.isNotEmpty()) { if (parts.isNotEmpty()) feed?.let { row ->
        JSONObject(row, row.keys().asSequence().toList().toTypedArray()).put("_composeArticleTailOnly", true)
    } else null }
    @Composable fun CommentsHeader() {
        Spacer(Modifier.height(if (trade != null) 10.dp else 7.75.dp))
        if (trade == null) { HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .25f)); Spacer(Modifier.height(7.75.dp)) }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            val count = feed?.text("replynum", "replyNum")?.takeIf { it.isNotEmpty() && it != "0" }
                ?: replies.rows.ifEmpty { fallbackReplies }.size
            Text(if (trade != null) "共${count}回复" else "共 $count 回复", fontSize = if (trade != null) 14.sp else 15.5.sp,
                fontWeight = if (trade != null) FontWeight.Normal else FontWeight.Bold)
            androidx.compose.foundation.text.selection.DisableSelection {
              Row(Modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest.copy(alpha = .5f), androidx.compose.foundation.shape.RoundedCornerShape(16.dp)).padding(2.5.dp)) {
                listOf("默认" to 0, "最新" to 2, "热门" to 1, "楼主" to 3).forEach { (label, value) -> Text(label, Modifier.semantics { selected = ordering == value }.background(if (ordering == value) MaterialTheme.colorScheme.surface else androidx.compose.ui.graphics.Color.Transparent, androidx.compose.foundation.shape.RoundedCornerShape(14.dp)).clickable(enabled = !importing) { if (ordering == value) scope.launch { replies.load(true) } else ordering = value }.padding(horizontal = 9.dp, vertical = 4.dp), fontSize = 12.sp, color = if (ordering == value) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) }
              }
            }
        }
    }
    com.green.note.ui.GlassBackdropHost(content = {
    val scheme = MaterialTheme.colorScheme
    val background = if (trade == null) com.green.note.ui.LocalScaffoldColor.current
        else if (scheme.surface.red + scheme.surface.green + scheme.surface.blue < 1.5f) androidx.compose.ui.graphics.Color(0xFF1C1C1C) else scheme.surface
    Column(Modifier.fillMaxSize().background(background)) {
        ContentToolbarRow(Modifier.fillMaxWidth().height(52.dp).contentToolbarBorder(), verticalAlignment = Alignment.CenterVertically) {
            ContentIcon("arrow_back", "返回", onBack, Modifier.width(56.dp))
            val row = feed; val author = row?.text("uid").orEmpty(); val info = row?.optJSONObject("userInfo") ?: row
            Row(Modifier.weight(1f).clickable(enabled = author.isNotEmpty()) { onUser(author) }, verticalAlignment = Alignment.CenterVertically) {
                ContentAvatar(api, row?.text("userAvatar", "avatar").orEmpty(), row?.text("username").orEmpty(), 38.dp) { if (author.isNotEmpty()) onUser(author) }
                Spacer(Modifier.width(8.dp)); Column(Modifier.weight(1f)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(row?.text("username").orEmpty().ifEmpty { "酷安用户" }, Modifier.weight(1f, fill = false), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, fontSize = 14.5.sp, fontWeight = FontWeight.Bold); info?.text("level", "user_level")?.takeIf(String::isNotEmpty)?.let { Spacer(Modifier.width(4.dp)); Text("(${if (it.startsWith("Lv.", true)) it else "Lv.$it"})", fontSize = 11.sp, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.SemiBold) } }; Spacer(Modifier.height(1.dp)); Text(listOf(relativeTime(row?.text("dateline").orEmpty()), row?.text("device_title", "device_name", "device").orEmpty().takeIf(String::isNotEmpty)?.let { "📱 $it" }.orEmpty()).filter(String::isNotEmpty).joinToString(" "), fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }
            }
            if (questionId.isNotEmpty()) ContentIcon("help_outline", "查看问题", { onOpen(JSONObject().put("entityType", "question").put("id", questionId)) })
            if (author.isNotEmpty() && !(session.authenticated && author == session.uid)) com.green.note.ui.ReviewOutlinedButton(enabled = !working, modifier = Modifier.height(30.dp), shape = androidx.compose.foundation.shape.RoundedCornerShape(15.dp), contentPadding = PaddingValues(horizontal = 14.dp), border = androidx.compose.foundation.BorderStroke(if (following) .8.dp else 1.2.dp, if (following) MaterialTheme.colorScheme.outlineVariant else MaterialTheme.colorScheme.primary), onClick = { if (!session.authenticated && !session.anonymous) toast.showSnackbar(session.loginRequiredMessage) else scope.launch { working = true; try { following = api.followUser(JSONObject(row.toString()).put("uid", author), following); toast.showSnackbar(if (following) "已关注" else "已取消关注") } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败") } finally { working = false } } }) { Text(if (following) "已关注" else "关注", fontSize = if (following) 12.sp else 12.5.sp, fontWeight = if (following) FontWeight.Normal else FontWeight.Bold, color = if (following) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary) }
            Box { ContentIcon("more_vert_rounded", "更多", { menu = true }); com.green.note.ui.ReviewPopupMenu(menu, { menu = false }) {
                if (session.authenticated && author == session.uid) com.green.note.ui.ReviewPopupMenuItem(text = { Text("删除动态") }, leadingIcon = { com.green.note.ui.MaterialGlyph("delete_outline_rounded", size = 20.dp) }, onClick = { menu = false; delete = true })
                com.green.note.ui.ReviewPopupMenuItem(text = { Text("复制文本") }, leadingIcon = { com.green.note.ui.MaterialGlyph("copy_rounded", size = 20.dp) }, onClick = { menu = false; val text = android.text.Html.fromHtml(row?.text("message").orEmpty(), android.text.Html.FROM_HTML_MODE_COMPACT).toString().trim(); if (text.isNotEmpty()) { (context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(android.content.ClipData.newPlainText("动态", text)); toast.showSnackbar("已复制动态内容") } })
                com.green.note.ui.ReviewPopupMenuItem(text = { Text("查看主页") }, leadingIcon = { com.green.note.ui.MaterialGlyph("person_outline_rounded", size = 20.dp) }, onClick = { menu = false; if (author.isNotEmpty()) onUser(author) })
            } }; Spacer(Modifier.width(4.dp))
        }
        ContentList(api, replies, { replyTo = it }, onUser, onLink, onGallery, onLike, onMore, Modifier.weight(1f),
                scroll = scroll, selectable = true, contentPadding = PaddingValues(bottom = 84.dp), initialBodyAnchor = initialReplyId.isNotEmpty() && (targetReply != null || targetFailure != null),
                bodyAnchorIndex = commentsIndex + 1,
                lazyItemCount = commentsIndex,
                refreshAction = { attempt++ }, endText = if (emptyHotPage && fallbackReplies.isNotEmpty()) "已显示原帖附带的部分评论" else "已经到底了", loadInitially = false, commentErrors = true,
                emptyContent = {
                    if (ordering == 1 && emptyHotPage && (loadingRecent || feed == null ||
                            (feed?.text("replynum", "replyNum")?.toIntOrNull() ?: 0) > 0)) {
                        Box(Modifier.fillMaxWidth().padding(vertical = 20.dp), contentAlignment = Alignment.Center) {
                            Text(if (loadingRecent) "正在补读原帖附带评论" else "暂无热门评论",
                                color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp)
                        }
                    } else FeedRepliesEmpty(ordering == 3, trade != null)
                },
                fallbackRows = fallbackReplies,
                accessErrorContent = { hasRows, retry ->
                    CommentRecoveryNotice(replies, hasRows, onRetry = retry,
                        onVerify = { scope.launch { replies.verify(api) } }, message = when {
                            hotPreview -> "当前排序暂不可用，已显示热门评论"
                            hasRows -> "已显示部分评论，完整列表暂不可用"
                            checkingHot -> "正在加载热门评论"
                            loadingRecent -> "正在补读原帖附带评论"
                            else -> "暂时无法加载评论"
                        })
                },
                itemContent = { row -> if (row.text("id") != targetReply?.text("id")) ReplyRow(api, row, onUser, onLink, onGallery, authorUid = feed?.text("uid").orEmpty(), onFilterAuthor = { ordering = 3 }, onReplyRequest = { replyTo = it }, onDeleteRequest = { replyToDelete = it }) },
                lazyContent = {
                    if (parts.isNotEmpty()) {
                        items(parts.size, key = { "article:$it" }, contentType = { parts[it].type }) { index ->
                            ArticleBlock(api, feed!!, parts[index], articleImages, articleIndices[index], onLink, onGallery, Modifier.padding(horizontal = 14.dp))
                        }
                        item(key = "article:tail") { FeedRow(api, articleTail!!, true, onOpen, onUser, onLink, onGallery, onLike, onMore) }
                    }
                    item(key = "feed:comments") { CommentsHeader() }
                },
                beforeRows = if (initialReplyId.isNotEmpty() || inlineFailure != null) ({
                    inlineFailure?.let { message -> Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("原帖加载失败：$message")
                        com.green.note.ui.ReviewTextButton(onClick = ::retryDetail) { Text("重新加载原帖") }
                    } }
                    if (initialReplyId.isNotEmpty()) {
                    Surface(color = MaterialTheme.colorScheme.surfaceContainerLow) { Column {
                        Text("目标评论", Modifier.padding(horizontal = 16.dp, vertical = 12.dp), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                        targetReply?.let { ReplyRow(api, it, onUser, onLink, onGallery, authorUid = feed?.text("uid").orEmpty(), onFilterAuthor = { ordering = 3 }, onReplyRequest = { replyTo = it }, onDeleteRequest = { replyToDelete = it }) } ?: com.green.note.ui.ReviewTextButton(onClick = { attempt++ }) { Text(targetFailure ?: "正在加载目标评论…") }
                    } }
                    }
                }) else null) {
                val row = feed
                val bodyFailure = failure
                when {
                    row == null -> Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(when {
                            bodyFailure == null -> "正在加载原帖…"
                            challenge != null || isContentAccessError(bodyFailure) -> "原帖暂不可用"
                            else -> bodyFailure
                        })
                        if (bodyFailure != null) com.green.note.ui.ReviewTextButton(onClick = ::retryDetail) {
                            Text(if (challenge == null) "重新加载原帖" else "完成验证并重试")
                        }
                    }
                    trade != null -> SecondhandDetailBody(api, row, trade, onLink, onGallery)
                    else -> FeedRow(api, articleLead ?: row, true, onOpen, onUser, onLink, onGallery, onLike, onMore)
                }
            }
    }
    }, overlay = {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
            feed?.let { row -> FeedDetailToolbar(api, row, session, onLogin, { replyTo = JSONObject() },
                { scroll.requestScrollToItem(commentsIndex) }, xianyu = trade?.destination) }
        }
    })
    replyTo?.let { reply -> ReplyComposer(api, id, reply.text("id"), draft, onDismiss = { replyTo = null }, onSent = { replyTo = null; attempt++ }, actionScope = scope) }
    replyToDelete?.let { reply -> com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { replyToDelete = null }, title = { Text("删除这条评论？") },
        dismissButton = { com.green.note.ui.ReviewTextButton(onClick = { replyToDelete = null }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(onClick = {
            replyToDelete = null
            scope.launch { try {
                api.request("/v6/feed/deleteReply", "POST", query = mapOf("id" to replyId(reply)))
                removedReplies.add(replyId(reply))
                replyLists.forEach { it.remove(reply) }
                attempt++
            }
                catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "操作失败") } }
        }) { Text("删除") } }) }
    if (delete) com.green.note.ui.ReviewAlertDialog(appDialog = true, onDismissRequest = { if (!working) delete = false }, title = { Text("删除这条动态？") }, text = { Text("此操作会直接请求酷安删除动态。") }, dismissButton = { com.green.note.ui.ReviewTextButton(enabled = !working, onClick = { delete = false }) { Text("取消") } }, confirmButton = { com.green.note.ui.ReviewButton(enabled = !working, onClick = { working = true; scope.launch { try { api.request("/v6/feed/deleteFeed", "POST", body = mapOf("id" to id)); delete = false; onBack() } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) { toast.showSnackbar(failure.message ?: "删除失败") } finally { working = false } } }) { Text("删除") } })
}

@Composable
internal fun FeedRepliesEmpty(authorOnly: Boolean, secondhand: Boolean) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = if (secondhand) 76.dp else 16.dp, bottom = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        if (!secondhand) {
            com.green.note.ui.MaterialGlyph("chat_bubble_outline_rounded", size = 40.dp, color = muted.copy(alpha = .35f))
            Spacer(Modifier.height(10.dp))
        }
        Text(if (authorOnly) "该动态下暂无楼主回复" else "还没有回复哦，快来回复一下吧~",
            Modifier.fillMaxWidth(), textAlign = TextAlign.Center, fontSize = 13.sp, color = muted.copy(alpha = .7f))
    }
}

internal fun mergeFeedDetail(seed: JSONObject?, detail: JSONObject): JSONObject {
    val result = if (seed == null) JSONObject() else JSONObject(seed, seed.keys().asSequence().toList().toTypedArray())
    val previewFields = setOf("message", "title", "description", "pic", "message_cover", "picArr", "message_raw_output", "messageRawOutput", "ershou_info") + embeddedReplyFields
    detail.keys().forEach { key ->
        val value = detail.get(key)
        val empty = value == JSONObject.NULL || (value is String && value.isBlank()) || (value is JSONArray && value.length() == 0) ||
            (value is JSONObject && value.length() == 0)
        if (!empty || key !in previewFields || !result.has(key)) result.put(key, value)
    }
    val rawKeys = listOf("message_raw_output", "messageRawOutput")
    val detailRaw = rawKeys.firstNotNullOfOrNull { key ->
        detail.opt(key).takeIf { (it is JSONArray && it.length() > 0) || (it is String && it.isNotBlank() && it.trim() != "[]") }
    }
    val freshMessage = detail.text("message")
    if (detailRaw != null || freshMessage.isNotEmpty() && freshMessage != seed?.text("message")) {
        rawKeys.forEach(result::remove)
        if (detailRaw != null) result.put(rawKeys.first(), detailRaw)
    }
    val freshTrade = EntityDetails.objectValue(detail.opt("ershou_info"))
    val previewTrade = EntityDetails.objectValue(seed?.opt("ershou_info"))
    if (freshTrade.length() > 0 && previewTrade.length() > 0) {
        val merged = JSONObject(previewTrade.toString())
        freshTrade.keys().forEach { key -> merged.put(key, freshTrade.get(key)) }
        result.put("ershou_info", merged)
    }
    return result
}

@Composable
internal fun EntityDetailScreen(api: ContentApi, type: String, id: String, onLink: (String) -> Unit, onGallery: (List<String>, Int, JSONObject?) -> Unit) {
    var detail by remember(id) { mutableStateOf<JSONObject?>(null) }
    var error by remember(id) { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    LaunchedEffect(id, revision) {
        error = null
        try { detail = api.request(if (type == "apk") "/v6/apk/detail" else "/v6/product/detail", query = mapOf("id" to id)).optJSONObject("data") ?: kotlin.error("详情为空") }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (failure: Exception) { error = failure.message }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberReviewScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        detail?.let { row ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                ContentImage(api, row.text("logo", "icon", "pic"), null, Modifier.size(72.dp))
                Spacer(Modifier.width(16.dp)); Column { Text(row.text("title"), fontSize = 22.sp, fontWeight = FontWeight.Bold); Text(row.text("versionName", "price"), fontSize = 14.sp) }
            }
            ContentRichText(row.text("description", "introduce", "intro"), onLink = onLink)
            val screenshots = row.optJSONArray("screenshots")?.let { array -> (0 until array.length()).map { array.optString(it) } } ?: emptyList()
            FeedImages(api, screenshots) { urls, index -> onGallery(urls, index, null) }
        } ?: if (error != null) { Text(error!!); com.green.note.ui.ReviewTextButton(onClick = { revision++ }) { Text("重试") } } else com.green.note.ui.ReviewCircularProgress()
    }
}

