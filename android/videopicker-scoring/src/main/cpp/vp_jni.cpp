#include <jni.h>
#include <string>
#include <vector>

#include "vp_analyzer.h"

static jobject buildAggregate(JNIEnv* env, const VpAggregateResult& result) {
  jclass scoringClass = env->FindClass("com/example/videopickerscoring/VideoPickerScoring");
  jclass itemClass = env->FindClass("com/example/videopickerscoring/VideoPickerScoring$Item");
  jclass aggregateClass = env->FindClass("com/example/videopickerscoring/VideoPickerScoring$Aggregate");

  jmethodID itemCtor = env->GetMethodID(itemClass, "<init>", "(Ljava/lang/String;FF)V");
  jmethodID aggregateCtor = env->GetMethodID(aggregateClass, "<init>", "(Ljava/util/List;Ljava/util/List;)V");

  jclass arrayListClass = env->FindClass("java/util/ArrayList");
  jmethodID arrayListCtor = env->GetMethodID(arrayListClass, "<init>", "()V");
  jmethodID arrayListAdd = env->GetMethodID(arrayListClass, "add", "(Ljava/lang/Object;)Z");

  jobject meanList = env->NewObject(arrayListClass, arrayListCtor);
  jobject worstList = env->NewObject(arrayListClass, arrayListCtor);

  for (int i = 0; i < result.item_count; ++i) {
    const VpItemResult& meanItem = result.mean[i];
    jstring meanId = env->NewStringUTF(meanItem.id_str);
    jobject meanObj = env->NewObject(itemClass, itemCtor, meanId, meanItem.score, meanItem.raw);
    env->CallBooleanMethod(meanList, arrayListAdd, meanObj);
    env->DeleteLocalRef(meanId);
    env->DeleteLocalRef(meanObj);

    const VpItemResult& worstItem = result.worst[i];
    jstring worstId = env->NewStringUTF(worstItem.id_str);
    jobject worstObj = env->NewObject(itemClass, itemCtor, worstId, worstItem.score, worstItem.raw);
    env->CallBooleanMethod(worstList, arrayListAdd, worstObj);
    env->DeleteLocalRef(worstId);
    env->DeleteLocalRef(worstObj);
  }

  jobject aggregate = env->NewObject(aggregateClass, aggregateCtor, meanList, worstList);
  env->DeleteLocalRef(meanList);
  env->DeleteLocalRef(worstList);
  return aggregate;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_example_videopickerscoring_VideoPickerScoring_analyzeVideo(JNIEnv* env, jobject /*thiz*/, jstring filePath) {
  if (!filePath) {
    return nullptr;
  }

  const char* path = env->GetStringUTFChars(filePath, nullptr);
  if (!path) {
    return nullptr;
  }

  VpConfig config;
  vp_default_config(&config);
  VpAnalyzer* analyzer = vp_create(&config);
  if (!analyzer) {
    env->ReleaseStringUTFChars(filePath, path);
    return nullptr;
  }

  VpAggregateResult result{};
  int rc = vp_analyze_video_file(analyzer, path, &result);
  vp_destroy(analyzer);
  env->ReleaseStringUTFChars(filePath, path);

  if (rc != VP_OK) {
    return nullptr;
  }

  return buildAggregate(env, result);
}
