#ifndef QNN_SAMPLE_APP_C_H
#define QNN_SAMPLE_APP_C_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// 定义状态码，和 C++ 中 sample_app::StatusCode 保持一致
typedef enum {
    QNN_STATUS_SUCCESS = 0,
    QNN_STATUS_FAILURE,
    QNN_STATUS_FAILURE_INPUT_LIST_EXHAUSTED,
    QNN_STATUS_FAILURE_SYSTEM_ERROR,
    QNN_STATUS_FAILURE_SYSTEM_COMMUNICATION_ERROR,
    QNN_STATUS_FEATURE_UNSUPPORTED
} QnnStatus;

// 定义输出数据类型
typedef enum {
    QNN_OUTPUT_DATA_TYPE_FLOAT_ONLY = 0,
    QNN_OUTPUT_DATA_TYPE_NATIVE_ONLY,
    QNN_OUTPUT_DATA_TYPE_FLOAT_AND_NATIVE,
    QNN_OUTPUT_DATA_TYPE_INVALID
} QnnOutputDataType;

// 定义输入数据类型
typedef enum {
    QNN_INPUT_DATA_TYPE_FLOAT = 0,
    QNN_INPUT_DATA_TYPE_NATIVE,
    QNN_INPUT_DATA_TYPE_INVALID
} QnnInputDataType;

// 定义HTP精度模式
typedef enum {
    QNN_HTP_PRECISION_MODE_FLOAT32 = 0,
    QNN_HTP_PRECISION_MODE_FLOAT16 = 1,
    QNN_HTP_PRECISION_MODE_DEFAULT = 0x7FFFFFFF
} QnnHtpPrecisionMode;

// 定义HTP后端配置结构体
typedef struct {
    int optimizationLevel;      // 优化级别(0-3)，3为最佳性能
    QnnHtpPrecisionMode precisionMode;  // 精度模式
} QnnBackendHtpConfig;

// 不透明指针类型，用户只能通过接口操作
typedef struct QnnSampleApp QnnSampleApp;

/* 
 * 创建 QnnSampleApp 对象。
 * 参数 backendPath 和 modelPath 为后端库及模型库文件路径，
 * outputDataType 与 inputDataType 为数据类型枚举值。
 * dataDir 为应用数据目录路径，用于切换工作目录。
 * htpConfig 为HTP后端特定配置，如果不是HTP后端则忽略。
 * 如果创建失败返回 NULL。
 */
QnnSampleApp* qnn_sample_app_create(const char* backendPath, 
                                    const char* modelPath, 
                                    QnnOutputDataType outputDataType, 
                                    QnnInputDataType inputDataType, 
                                    const char* dataDir
                                   );

/* 释放 QnnSampleApp 对象 */
void qnn_sample_app_destroy(QnnSampleApp* app);

/* 以下接口分别包装了 C++ 对象的方法，返回的状态码与 C++ 中保持一致 */
QnnStatus qnn_sample_app_initialize(QnnSampleApp* app);
QnnStatus qnn_sample_app_initialize_profiling(QnnSampleApp* app);
QnnStatus qnn_sample_app_create_context(QnnSampleApp* app);
QnnStatus qnn_sample_app_compose_graphs(QnnSampleApp* app);
QnnStatus qnn_sample_app_finalize_graphs(QnnSampleApp* app);
QnnStatus qnn_sample_app_execute_graphs(QnnSampleApp* app);
QnnStatus qnn_sample_app_register_op_packages(QnnSampleApp* app);
QnnStatus qnn_sample_app_create_from_binary(QnnSampleApp* app);
QnnStatus qnn_sample_app_save_binary(QnnSampleApp* app, const char* outputPath, const char* binaryName);
QnnStatus qnn_sample_app_free_context(QnnSampleApp* app);
QnnStatus qnn_sample_app_terminate_backend(QnnSampleApp* app);
QnnStatus qnn_sample_app_free_graphs(QnnSampleApp* app);

/*
 * 获取后端生成的版本号字符串。
 * 返回的字符串由内部动态分配，调用者需要使用 free() 释放。
 */
const char* qnn_sample_app_get_backend_build_id(QnnSampleApp* app);

QnnStatus qnn_sample_app_is_device_property_supported(QnnSampleApp* app);
QnnStatus qnn_sample_app_create_device(QnnSampleApp* app);
QnnStatus qnn_sample_app_free_device(QnnSampleApp* app);

/*
 * 加载浮点数输入张量。
 * 参数 inputs 为指向各输入数组的指针数组，sizes 为各数组元素的个数，numInputs 为输入个数，graphIdx 为图索引。
 */
QnnStatus qnn_sample_app_load_float_inputs(QnnSampleApp* app,
                                           const float** inputs,
                                           const size_t* sizes,
                                           size_t numInputs,
                                           int graphIdx);

/*
 * 获取浮点数输出张量。
 * 参数 outputs 是一个输出指针，函数内部会分配内存保存各个输出数据（调用者需要对每个输出以及 outputs 数组调用 free() 释放）。
 * out_sizes 返回各输出张量的元素个数，numOutputs 返回输出张量数量。
 */
QnnStatus qnn_sample_app_get_float_outputs(QnnSampleApp* app,
                                           float*** outputs,
                                           size_t** out_sizes,
                                           size_t* numOutputs,
                                           int graphIdx);

/*
 * 获取HTP架构版本号
 * 参数 backendPath 为后端库路径
 * 返回HTP架构版本号，如果发生错误则返回-1
 */
int qnn_get_htp_arch_version(const char* backendPath);




// 定义异步回调函数类型
typedef void (*QnnAsyncCallback)(QnnStatus status, void* userData);

// 结果回调，用于带返回数据的异步函数
typedef void (*QnnFloatOutputCallback)(QnnStatus status, float** outputs, size_t* sizes, size_t numOutputs, void* userData);
typedef void (*QnnStringCallback)(QnnStatus status, const char* result, void* userData);
typedef void (*QnnArchVersionCallback)(int version, void* userData);

// 异步函数声明
void qnn_sample_app_create_async(const char* backendPath, 
                              const char* modelPath, 
                              QnnOutputDataType outputDataType, 
                              QnnInputDataType inputDataType, 
                              const char* dataDir,
                              void (*callback)(QnnSampleApp* app, void* userData),
                              void* userData);

void qnn_sample_app_destroy_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_initialize_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_initialize_profiling_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_create_context_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_compose_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_finalize_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_execute_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_register_op_packages_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_create_from_binary_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_save_binary_async(QnnSampleApp* app, const char* outputPath, const char* binaryName, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_free_context_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_terminate_backend_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_free_graphs_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_get_backend_build_id_async(QnnSampleApp* app, QnnStringCallback callback, void* userData);
void qnn_sample_app_is_device_property_supported_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_create_device_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_free_device_async(QnnSampleApp* app, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_load_float_inputs_async(QnnSampleApp* app, const float** inputs, const size_t* sizes, size_t numInputs, int graphIdx, QnnAsyncCallback callback, void* userData);
void qnn_sample_app_get_float_outputs_async(QnnSampleApp* app, int graphIdx, QnnFloatOutputCallback callback, void* userData);
void qnn_get_htp_arch_version_async(const char* backendPath, QnnArchVersionCallback callback, void* userData);

#ifdef __cplusplus
}
#endif

#endif // QNN_SAMPLE_APP_C_H