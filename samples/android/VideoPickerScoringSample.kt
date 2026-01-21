package com.example.videopickerscoring

import android.net.Uri
import android.util.Log

class VideoPickerScoringSample(private val scoring: VideoPickerScoring) {
    fun analyzeFromUri(uri: Uri, context: android.content.Context) {
        val tempFile = VideoPickerScoring.copyContentUriToFile(context, uri)
        val result = scoring.analyzeVideo(tempFile.absolutePath)
        if (result == null) {
            Log.e("VideoPickerScoring", "Analyze failed")
            return
        }
        result.mean.forEach { item ->
            Log.d("VideoPickerScoring", "mean ${item.id} score=${item.score} raw=${item.raw}")
        }
        result.worst.forEach { item ->
            Log.d("VideoPickerScoring", "worst ${item.id} score=${item.score} raw=${item.raw}")
        }
    }
}
