package com.example.videopickerscoring

import android.net.Uri
import android.util.Log

class VideoPickerScoringSample(private val scoring: VideoPickerScoring) {
    fun analyzeFromUri(
        uri: Uri,
        context: android.content.Context,
        mode: VideoPickerScoring.VideoSceneMode = VideoPickerScoring.VideoSceneMode.PERSON,
    ) {
        val tempFile = VideoPickerScoring.copyContentUriToFile(context, uri)
        val result = scoring.analyzeVideo(tempFile.absolutePath, mode)
        if (result == null) {
            Log.e("VideoPickerScoring", "Analyze failed")
            return
        }
        Log.d("VideoPickerScoring", "mode=${mode.name.lowercase()}")
        result.mean.forEach { item ->
            Log.d("VideoPickerScoring", "mean ${item.id} score=${item.score} raw=${item.raw}")
        }
        result.worst.forEach { item ->
            Log.d("VideoPickerScoring", "worst ${item.id} score=${item.score} raw=${item.raw}")
        }
    }
}
