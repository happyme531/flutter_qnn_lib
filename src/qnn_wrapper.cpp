#include "qnn_wrapper.h"
#include "HTP/QnnHtpDevice.h"
#include "QnnSampleApp.hpp"
#include <cstring>
#include <cstdlib>
#include <new>
#include <thread>
#include <vector>
#include <string>
#include <stdexcept>
#include <unistd.h>
#include <android/log.h>
#include <errno.h>
#include <dirent.h>

#include "Logger.hpp"

using namespace qnn::tools;

// 定义Android日志宏，如果未定义
#ifndef ANDROID_LOG_INFO
#define ANDROID_LOG_INFO 4
#endif
#ifndef ANDROID_LOG_ERROR
#define ANDROID_LOG_ERROR 6
#endif

// 定义不透明结构体，内部保存 C++ 对象实例指针
struct QnnSampleApp {
    qnn::tools::sample_app::QnnSampleApp* instance;
};

extern "C" {

QnnSampleApp* qnn_sample_app_create(const char* backendPath, const char* modelPath, QnnOutputDataType outputDataType, QnnInputDataType inputDataType, const char* dataDir) {
    if (!qnn::log::initializeLogging()) {
        __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "ERROR: Unable to initialize logging!\n");
        return nullptr;
    }

    qnn::log::setLogLevel(QNN_LOG_LEVEL_DEBUG);
    // 使用Android日志API记录当前路径
    char* currentPath = getcwd(nullptr, 0);
    __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "初始路径: %s", currentPath);
    free(currentPath);
    
    // 如果提供了Hexagon库目录路径，则尝试切换到该目录
    if (dataDir != nullptr && dataDir[0] != '\0') {
        if (chdir(dataDir) == 0) {
            currentPath = getcwd(nullptr, 0);
            __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "已切换到Hexagon库目录: %s", currentPath);
            
            // 列出目录中的文件
            DIR* dir = opendir(dataDir);
            if (dir != nullptr) {
                struct dirent* entry;
                __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "目录内容:");
                while ((entry = readdir(dir)) != nullptr) {
                    __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "- %s", entry->d_name);
                }
                closedir(dir);
            }
            
            free(currentPath);
        } else {
            __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "切换目录失败: %s", strerror(errno));
        }
    }
    
    QnnSampleApp* appWrapper = new(std::nothrow) QnnSampleApp;
    if (!appWrapper) {
        return nullptr;
    }
    try {
        // 使用 C++ 对象构造函数创建实例
        appWrapper->instance = new qnn::tools::sample_app::QnnSampleApp(backendPath, modelPath,
            static_cast<iotensor::OutputDataType>(outputDataType),
            static_cast<iotensor::InputDataType>(inputDataType));
    } catch (const std::exception&) {
        delete appWrapper;
        __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "创建QNN实例失败");
        return nullptr;
    }
    __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "创建QNN实例成功");
    return appWrapper;
}

void qnn_sample_app_destroy(QnnSampleApp* app) {
    if (app) {
        try {
            delete app->instance;
        } catch (...) {
            // 忽略异常
        }
        delete app;
    }
}

QnnStatus qnn_sample_app_initialize(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->initialize());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_initialize_profiling(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->initializeProfiling());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_create_context(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->createContext());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_compose_graphs(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->composeGraphs());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_finalize_graphs(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->finalizeGraphs());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_execute_graphs(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->executeGraphs());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_register_op_packages(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->registerOpPackages());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_create_from_binary(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->createFromBinary());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_save_binary(QnnSampleApp* app, const char* outputPath, const char* binaryName) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->saveBinary(outputPath, binaryName));
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_free_context(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->freeContext());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_terminate_backend(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->terminateBackend());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_free_graphs(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->freeGraphs());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

const char* qnn_sample_app_get_backend_build_id(QnnSampleApp* app) {
    if (!app || !app->instance) return nullptr;
    try {
        std::string id = app->instance->getBackendBuildId();
        // 复制一份字符串返回，由调用者负责释放
        char* cstr = (char*)std::malloc(id.size() + 1);
        if (cstr) {
            std::strcpy(cstr, id.c_str());
        }
        return cstr;
    } catch (...) {
        return nullptr;
    }
}

QnnStatus qnn_sample_app_is_device_property_supported(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->isDevicePropertySupported());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_create_device(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->createDevice());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_free_device(QnnSampleApp* app) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        return static_cast<QnnStatus>(app->instance->freeDevice());
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_load_float_inputs(QnnSampleApp* app,
                                           const float** inputs,
                                           const size_t* sizes,
                                           size_t numInputs,
                                           int graphIdx) {
    if (!app || !app->instance) return QNN_STATUS_FAILURE;
    try {
        std::vector<std::vector<float>> inputData(numInputs);
        for (size_t i = 0; i < numInputs; ++i) {
            inputData[i] = std::vector<float>(inputs[i], inputs[i] + sizes[i]);
        }
        return static_cast<QnnStatus>(app->instance->loadFloatInputs(inputData, graphIdx));
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

QnnStatus qnn_sample_app_get_float_outputs(QnnSampleApp* app,
                                           float*** outputs,
                                           size_t** out_sizes,
                                           size_t* numOutputs,
                                           int graphIdx) {
    if (!app || !app->instance || !outputs || !out_sizes || !numOutputs) return QNN_STATUS_FAILURE;
    try {
        std::vector<std::vector<float>> outputData;
        QnnStatus status = static_cast<QnnStatus>(app->instance->getFloatOutputs(outputData, graphIdx));
        if (status != QNN_STATUS_SUCCESS) {
            return status;
        }
        *numOutputs = outputData.size();
        // 分配内存保存各输出数据指针
        float** outs = (float**)std::malloc(sizeof(float*) * (*numOutputs));
        size_t* sizes_array = (size_t*)std::malloc(sizeof(size_t) * (*numOutputs));
        if (!outs || !sizes_array) {
            if (outs) std::free(outs);
            if (sizes_array) std::free(sizes_array);
            return QNN_STATUS_FAILURE;
        }
        for (size_t i = 0; i < *numOutputs; ++i) {
            sizes_array[i] = outputData[i].size();
            outs[i] = (float*)std::malloc(sizeof(float) * outputData[i].size());
            if (!outs[i]) {
                for (size_t j = 0; j < i; ++j) {
                    std::free(outs[j]);
                }
                std::free(outs);
                std::free(sizes_array);
                return QNN_STATUS_FAILURE;
            }
            std::copy(outputData[i].begin(), outputData[i].end(), outs[i]);
        }
        *outputs = outs;
        *out_sizes = sizes_array;
        return QNN_STATUS_SUCCESS;
    } catch (...) {
        return QNN_STATUS_FAILURE;
    }
}

int qnn_get_htp_arch_version(const char* backendPath) {
    if (!backendPath) {
        __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "后端路径为空");
        return -1;
    }

    try {
        auto platformInfo = sample_app::QnnSampleApp::getPlatformInfo(backendPath);
        if (platformInfo.v1.numHwDevices == 0 || 
            !platformInfo.v1.hwDevices || 
            !platformInfo.v1.hwDevices[0].v1.deviceInfoExtension) {
            __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "无法获取HTP架构版本：设备信息不完整");
            return -1;
        }
        auto archVersion = platformInfo.v1.hwDevices[0].v1.deviceInfoExtension->onChipDevice.arch;
        __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "HTP架构版本: %d", archVersion);
        return archVersion;
    } catch (const std::exception& e) {
        __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "发生异常: %s", e.what());
        return -1;
    } catch (...) {
        __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "发生未知异常");
        return -1;
    }
}


// 异步函数实现
void qnn_sample_app_create_async(const char* backendPath, 
                             const char* modelPath, 
                             QnnOutputDataType outputDataType, 
                             QnnInputDataType inputDataType, 
                             const char* dataDir,
                             void (*callback)(QnnSampleApp* app, void* userData),
                             void* userData) {
    // 复制字符串参数，确保在新线程中使用时它们仍然有效
    std::string backendPathCopy(backendPath ? backendPath : "");
    std::string modelPathCopy(modelPath ? modelPath : "");
    std::string dataDirCopy(dataDir ? dataDir : "");

    __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "开始异步创建QNN实例");
    __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "后端路径: %s", backendPathCopy.c_str());
    __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "模型路径: %s", modelPathCopy.c_str());
    __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "数据目录: %s", dataDirCopy.c_str());

    std::thread([=, backendPathCopy = std::move(backendPathCopy), 
                   modelPathCopy = std::move(modelPathCopy),
                   dataDirCopy = std::move(dataDirCopy)]() {
        __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "异步线程启动");
        QnnSampleApp* app = nullptr;

        try {
            app = qnn_sample_app_create(
                backendPathCopy.c_str(),
                modelPathCopy.c_str(),
                outputDataType,
                inputDataType,
                dataDirCopy.c_str()
            );
            
            __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "QNN实例创建%s", app ? "成功" : "失败");
            
            if (callback) {
                __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "准备调用回调函数");
                callback(app, userData);
                __android_log_print(ANDROID_LOG_INFO, "QnnWrapper", "回调函数调用完成");
            } else {
                __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "回调函数为空");
            }
        } catch (const std::exception& e) {
            __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "创建QNN实例时发生异常: %s", e.what());
            if (callback) {
                callback(nullptr, userData);
            }
        } catch (...) {
            __android_log_print(ANDROID_LOG_ERROR, "QnnWrapper", "创建QNN实例时发生未知异常");
            if (callback) {
                callback(nullptr, userData);
            }
        }
    }).detach();
}

void qnn_sample_app_destroy_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        qnn_sample_app_destroy(app);
        if (callback) {
            callback(QNN_STATUS_SUCCESS, userData);
        }
    }).detach();
}

void qnn_sample_app_initialize_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_initialize(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_initialize_profiling_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_initialize_profiling(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_create_context_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_create_context(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_compose_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_compose_graphs(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_finalize_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_finalize_graphs(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_execute_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_execute_graphs(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_register_op_packages_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_register_op_packages(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_create_from_binary_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_create_from_binary(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_save_binary_async(QnnSampleApp* app, const char* outputPath, const char* binaryName, QnnAsyncCallback callback, void* userData) {
    // 复制路径字符串，因为它们在线程执行时必须有效
    std::string outputPathCopy(outputPath ? outputPath : "");
    std::string binaryNameCopy(binaryName ? binaryName : "");
    
    std::thread([=, outputPathCopy = std::move(outputPathCopy), binaryNameCopy = std::move(binaryNameCopy)]() {
        QnnStatus status = qnn_sample_app_save_binary(app, outputPathCopy.c_str(), binaryNameCopy.c_str());
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_free_context_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_free_context(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_terminate_backend_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_terminate_backend(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_free_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_free_graphs(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_get_backend_build_id_async(QnnSampleApp* app, QnnStringCallback callback, void* userData) {
    std::thread([=]() {
        const char* buildId = qnn_sample_app_get_backend_build_id(app);
        if (callback) {
            callback(buildId ? QNN_STATUS_SUCCESS : QNN_STATUS_FAILURE, buildId, userData);
        }
    }).detach();
}

void qnn_sample_app_is_device_property_supported_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_is_device_property_supported(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_create_device_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_create_device(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_free_device_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_free_device(app);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_load_float_inputs_async(QnnSampleApp* app, const float** inputs, const size_t* sizes, size_t numInputs, int graphIdx, QnnAsyncCallback callback, void* userData) {
    std::thread([=]() {
        QnnStatus status = qnn_sample_app_load_float_inputs(app, inputs, sizes, numInputs, graphIdx);
        if (callback) {
            callback(status, userData);
        }
    }).detach();
}

void qnn_sample_app_get_float_outputs_async(QnnSampleApp* app, int graphIdx, QnnFloatOutputCallback callback, void* userData) {
    std::thread([=]() {
        float** outputs = nullptr;
        size_t* sizes = nullptr;
        size_t numOutputs = 0;
        
        QnnStatus status = qnn_sample_app_get_float_outputs(app, &outputs, &sizes, &numOutputs, graphIdx);
        
        if (callback) {
            callback(status, outputs, sizes, numOutputs, userData);
        }
        // for (size_t i = 0; i < numOutputs; ++i) {
        //     free(outputs[i]);
        // }
        // free(outputs);
        // free(sizes);
    }).detach();
}

void qnn_get_htp_arch_version_async(const char* backendPath, QnnArchVersionCallback callback, void* userData) {
    std::string backendPathCopy(backendPath ? backendPath : "");
    
    std::thread([=, backendPathCopy = std::move(backendPathCopy)]() {
        int version = qnn_get_htp_arch_version(backendPathCopy.c_str());
        if (callback) {
            callback(version, userData);
        }
    }).detach();
}

} // extern "C"