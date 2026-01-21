package com.example.videopickerscoring

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

class VideoPickerScoring {
    enum class VideoSceneMode {
        PERSON,
        LANDSCAPE,
    }

    data class Item(val id: String, val score: Float, val raw: Float)
    data class Aggregate(val mean: List<Item>, val worst: List<Item>)

    external fun analyzeVideo(filePath: String): Aggregate?

    fun analyzeVideo(filePath: String, mode: VideoSceneMode): Aggregate? {
        return analyzeVideo(filePath)
    }

    companion object {
        init {
            System.loadLibrary("vp_scoring_jni")
        }

        fun copyContentUriToFile(context: Context, uri: Uri, destFileName: String = "vp_temp_video") : File {
            val resolver: ContentResolver = context.contentResolver
            val tempFile = File.createTempFile(destFileName, ".mp4", context.cacheDir)
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            return tempFile
        }
    }
}
