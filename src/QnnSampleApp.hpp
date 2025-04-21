//==============================================================================
//
//  Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
//  All rights reserved.
//  Confidential and Proprietary - Qualcomm Technologies, Inc.
//
//==============================================================================
#pragma once

#include <memory>
#include <queue>

#include "IOTensor.hpp"
#include "QnnDevice.h"
#include "SampleApp.hpp"

namespace qnn {
namespace tools {
namespace sample_app {

enum class StatusCode {
  SUCCESS,
  FAILURE,
  FAILURE_INPUT_LIST_EXHAUSTED,
  FAILURE_SYSTEM_ERROR,
  FAILURE_SYSTEM_COMMUNICATION_ERROR,
  QNN_FEATURE_UNSUPPORTED
};

// 图优化配置结构体
union BackendConfig {
  struct HtpConfig {
    // 优化级别 (0-3)，3为最佳性能但可能增加编译时间
    int optimizationLevel = 2;
    // 优先使用的精度模式
    enum class PrecisionMode {
      FLOAT32 = 0,
      FLOAT16 = 1,
      DEFAULT = 0x7FFFFFFF
    } precisionMode = PrecisionMode::FLOAT16;
  } htpConfig;
  
  // 显式默认构造函数
  BackendConfig() : htpConfig() {}
};

class QnnSampleApp {
 public:
  QnnSampleApp(QnnFunctionPointers qnnFunctionPointers,
               std::string opPackagePaths,
               void *backendHandle,
               bool debug                              = false,
               iotensor::OutputDataType outputDataType = iotensor::OutputDataType::FLOAT_ONLY,
               iotensor::InputDataType inputDataType   = iotensor::InputDataType::FLOAT,
               ProfilingLevel profilingLevel           = ProfilingLevel::OFF,
               std::string cachedBinaryPath            = "");

  QnnSampleApp(const std::string& backendPath, 
               const std::string& modelPath,
               iotensor::OutputDataType outputDataType = iotensor::OutputDataType::FLOAT_ONLY,
               iotensor::InputDataType inputDataType = iotensor::InputDataType::FLOAT,
               const BackendConfig& backendCfg = BackendConfig());

  // @brief Print a message to STDERR then return a nonzero
  //  exit status.
  int32_t reportError(const std::string &err);

  StatusCode initialize();

  StatusCode initializeBackend();

  StatusCode createContext();

  StatusCode composeGraphs();

  StatusCode finalizeGraphs();

  StatusCode executeGraphs();

  StatusCode registerOpPackages();

  StatusCode createFromBinary();

  StatusCode saveBinary(std::string outputPath, std::string saveBinaryName);

  StatusCode freeContext();

  StatusCode terminateBackend();

  StatusCode freeGraphs();

  Qnn_ContextHandle_t getContext();

  StatusCode initializeProfiling();

  std::string getBackendBuildId();

  StatusCode isDevicePropertySupported();

  StatusCode createDevice();

  StatusCode freeDevice();

  StatusCode verifyFailReturnStatus(Qnn_ErrorHandle_t errCode);

  bool isBinaryModel() const { return m_isBinaryModel; }

  // 新增接口：加载 float 输入数据
  StatusCode loadFloatInputs(const std::vector<std::vector<float>>& inputData, int graphIdx = 0);

  // 新增接口：获取 float 输出数据
  StatusCode getFloatOutputs(std::vector<std::vector<float>>& outputData, int graphIdx = 0);

  static QnnDevice_PlatformInfo_t getPlatformInfo(const std::string& backendPath);


  virtual ~QnnSampleApp();

 private:
  StatusCode extractBackendProfilingInfo(Qnn_ProfileHandle_t profileHandle);

  StatusCode extractProfilingSubEvents(QnnProfile_EventId_t profileEventId);

  StatusCode extractProfilingEvent(QnnProfile_EventId_t profileEventId);

  QnnFunctionPointers m_qnnFunctionPointers;
  std::vector<std::string> m_opPackagePaths;
  std::string m_cachedBinaryPath;
  QnnBackend_Config_t **m_backendConfig = nullptr;
  QnnDevice_Config_t **m_deviceConfig = nullptr;
  Qnn_ContextHandle_t m_context         = nullptr;
  QnnContext_Config_t **m_contextConfig = nullptr;
  bool m_debug;
  iotensor::OutputDataType m_outputDataType;
  iotensor::InputDataType m_inputDataType;
  ProfilingLevel m_profilingLevel;
  qnn_wrapper_api::GraphInfo_t **m_graphsInfo;
  uint32_t m_graphsCount;
  void *m_backendLibraryHandle;
  iotensor::IOTensor m_ioTensor;
  bool m_isBackendInitialized;
  bool m_isContextCreated;
  Qnn_ProfileHandle_t m_profileBackendHandle              = nullptr;
  qnn_wrapper_api::GraphConfigInfo_t **m_graphConfigsInfo = nullptr;
  uint32_t m_graphConfigsInfoCount;
  Qnn_LogHandle_t m_logHandle         = nullptr;
  Qnn_BackendHandle_t m_backendHandle = nullptr;
  Qnn_DeviceHandle_t m_deviceHandle   = nullptr;

  // 新增：用于存储持久化的输入/输出张量，避免重复创建
  int m_currentGraphIndex = -1; // 当前保存张量对应的图索引
  Qnn_Tensor_t* m_storedInputs = nullptr;
  Qnn_Tensor_t* m_storedOutputs = nullptr;

  // 新增：存储动态库句柄，以便在析构函数中关闭
  void* m_ownedBackendHandle = nullptr;
  void* m_ownedModelHandle = nullptr;
  bool m_isBinaryModel = false;
  
  // 后端配置
  BackendConfig m_backendCfg;
};
}  // namespace sample_app
}  // namespace tools
}  // namespace qnn
