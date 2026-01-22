#include <jni.h>
extern "C" JNIEXPORT jobject JNICALL
Java_com_example_videopickerscoring_VideoPickerScoring_analyzeVideo(JNIEnv* env, jobject /*thiz*/, jstring filePath) {
  (void)env;
  (void)filePath;
  return nullptr;
}
