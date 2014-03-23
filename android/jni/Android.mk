LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := liblittle_things_android
LOCAL_SRC_FILES := liblittle_things_android.so
include $(PREBUILT_SHARED_LIBRARY)
