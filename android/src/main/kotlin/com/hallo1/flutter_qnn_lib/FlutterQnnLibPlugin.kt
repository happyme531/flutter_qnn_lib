package com.hallo1.flutter_qnn_lib

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.BufferedReader
import java.io.InputStreamReader

/** FlutterQnnLibPlugin */
class FlutterQnnLibPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var context: Context

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_qnn_lib/app_context")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getNativeLibraryDir" -> {
        result.success(context.applicationInfo.nativeLibraryDir)
      }
      "getAppLogs" -> {
        try {
          // 获取应用包名
          val packageName = context.packageName
          // 执行logcat命令，过滤指定应用的日志
          val process = Runtime.getRuntime().exec("logcat -d -v threadtime *:V | grep $packageName")
          val bufferedReader = BufferedReader(InputStreamReader(process.inputStream))
          val log = StringBuilder()
          var line: String?
          
          while (bufferedReader.readLine().also { line = it } != null) {
            log.append(line)
            log.append('\n')
          }
          
          result.success(log.toString())
        } catch (e: Exception) {
          result.error("LOG_ERROR", "获取日志失败: ${e.message}", null)
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
} 