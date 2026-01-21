package com.example.videopickerscoring

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import java.io.File
import java.io.FileOutputStream

class VideoPickerScoring {
    data class Item(val id: String, val score: Float, val raw: Float)
    data class Aggregate(val mean: List<Item>, val worst: List<Item>)

    external fun analyzeVideo(filePath: String): Aggregate?

    fun weightedScore(aggregate: Aggregate): Float? {
        val weights = mapOf(
            "sharpness" to 0.25f,
            "exposure" to 0.25f,
            "motion_blur" to 0.2f,
            "noise" to 0.15f,
            "person_blur" to 0.15f,
        )
        val scoreById = aggregate.mean.associate { it.id to it.score }
        var weightedSum = 0.0f
        var weightSum = 0.0f
        weights.forEach { (id, weight) ->
            val score = scoreById[id]
            if (score != null) {
                weightedSum += score * weight
                weightSum += weight
            }
        }
        if (weightSum <= 0.0f) {
            return null
        }
        return weightedSum / weightSum
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
