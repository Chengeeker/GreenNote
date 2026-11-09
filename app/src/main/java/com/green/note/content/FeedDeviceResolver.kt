package com.green.note.content

/** Feed author device links share the account-scoped, bounded device lookup. */
internal object FeedDeviceResolver {
    suspend fun resolve(api:ContentApi,device:String):String? =
        resolveContentDeviceProduct(api,device)?.text("id","productId")?.takeIf(String::isNotEmpty)
}
