package com.example.robi

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.robi/image_utils"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "convertNv21ToJpeg") {
                try {
                    val bytes = call.argument<ByteArray>("bytes")
                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")
                    val rotation = call.argument<Int>("rotation") ?: 0

                    if (bytes != null && width != null && height != null) {
                        val yuvImage = YuvImage(bytes, ImageFormat.NV21, width, height, null)
                        val out = ByteArrayOutputStream()
                        yuvImage.compressToJpeg(Rect(0, 0, width, height), 70, out)
                        val jpegBytes = out.toByteArray()

                        if (rotation != 0) {
                            val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                            val matrix = Matrix()
                            matrix.postRotate(rotation.toFloat())
                            val rotatedBitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                            val rotatedOut = ByteArrayOutputStream()
                            rotatedBitmap.compress(Bitmap.CompressFormat.JPEG, 70, rotatedOut)
                            result.success(rotatedOut.toByteArray())
                            bitmap.recycle()
                            rotatedBitmap.recycle()
                        } else {
                            result.success(jpegBytes)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing bytes, width, or height", null)
                    }
                } catch (e: Exception) {
                    result.error("CONVERSION_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
