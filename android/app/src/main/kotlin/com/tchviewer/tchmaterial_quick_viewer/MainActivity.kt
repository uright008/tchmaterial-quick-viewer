package com.tchviewer.tchmaterial_quick_viewer

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 「用系统程序打开」的处理端。
 *
 * Android 从 API 24 起禁止把 `file://` URI 通过 Intent 交给其它应用
 * （`FileUriExposedException`）。正确做法是用 FileProvider 换成一个带临时授权的
 * `content://` URI，再交给 `ACTION_VIEW`。
 *
 * 这里刻意没有用现成的插件：`open_filex` 会在合并 manifest 时把
 * `READ_MEDIA_VIDEO` / `READ_MEDIA_AUDIO` 塞进来 —— 一个教材阅读器去申请读取
 * 用户的视频和音频库没有必要。自己实现只要几十行，而且权限为零。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "tchmaterial_quick_viewer/file_actions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWith" -> {
                        val path = call.argument<String>("path")
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        if (path.isNullOrEmpty()) {
                            result.error("bad_args", "path 为空", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(openWith(path, mimeType))
                        } catch (e: PathNotSharedException) {
                            // 路径不在 tch_file_paths.xml 声明范围内。
                            // 这是配置问题，必须和「设备上没有能打开它的应用」
                            // 区分开 —— 否则只会看到一个笼统的失败，无从排查。
                            result.error("path_not_shared", e.message, null)
                        } catch (e: Exception) {
                            result.error("open_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 路径不在 FileProvider 已声明的根目录里。 */
    private class PathNotSharedException(message: String) : Exception(message)

    /** 返回 true 表示已经有应用接手；false 表示设备上没有能打开它的应用。 */
    private fun openWith(path: String, mimeType: String): Boolean {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("文件不存在：$path")
        }

        // FLAG_GRANT_READ_URI_PERMISSION 是必须的：接收方默认无权读取本应用的
        // content:// URI，少了这个标志对方会直接报 SecurityException。
        val uri: Uri = try {
            FileProvider.getUriForFile(this, "$packageName.tchfileprovider", file)
        } catch (e: IllegalArgumentException) {
            // 典型信息：Failed to find configured root that contains /...
            // 说明 res/xml/tch_file_paths.xml 没覆盖这个目录 —— 上传前请对照
            // CacheStore 的落盘位置。
            throw PathNotSharedException(
                "文件所在目录未在 FileProvider 中声明：${file.parent}（${e.message}）",
            )
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            // 交给调用方提示「没有找到可打开的程序」，而不是崩掉。
            false
        }
    }
}
