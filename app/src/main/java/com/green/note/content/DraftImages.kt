package com.green.note.content

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File

internal fun uploadSampleSize(width: Int, height: Int): Int {
    require(width > 0 && height > 0) { "图片格式无效" }
    var sample = 1
    while (maxOf(width, height) / sample > 2048) sample *= 2
    return sample
}

// Must run on IO: preserve the original upload sizing and EXIF orientation rules.
fun prepareUploadPng(file: File): ByteArray {
    require(file.isFile && file.length() in 1..16L * 1024 * 1024) { "图片内容为空或超过16 MB" }
    val bytes = file.readBytes()
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    val options = BitmapFactory.Options().apply { inSampleSize = uploadSampleSize(bounds.outWidth, bounds.outHeight) }
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: error("图片格式无效")
    var oriented: Bitmap? = null
    try {
        val matrix = Matrix()
        val orientation = try { ExifInterface(bytes.inputStream()).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1) } catch (_: Exception) { 1 }
        when (orientation) {
            2 -> matrix.setScale(-1f, 1f)
            3 -> matrix.setRotate(180f)
            4 -> matrix.setScale(1f, -1f)
            5 -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
            6 -> matrix.setRotate(90f)
            7 -> { matrix.setRotate(270f); matrix.postScale(-1f, 1f) }
            8 -> matrix.setRotate(270f)
        }
        oriented = if (matrix.isIdentity) bitmap else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        val output = ByteArrayOutputStream()
        check(oriented.compress(Bitmap.CompressFormat.PNG, 100, output)) { "图片转换失败" }
        check(output.size() <= 16 * 1024 * 1024) { "图片不能超过16 MB" }
        return output.toByteArray()
    } finally {
        if (oriented !== bitmap) oriented?.recycle()
        bitmap.recycle()
    }
}
