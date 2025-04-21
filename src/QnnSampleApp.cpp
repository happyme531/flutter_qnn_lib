//==============================================================================
//
//  Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
//  All rights reserved.
//  Confidential and Proprietary - Qualcomm Technologies, Inc.
//
//==============================================================================

#include <cstddef>
#include <cstdint>
#include <inttypes.h>

#include <cstring>

#include "DataUtil.hpp"
#include "DynamicLoadUtil.hpp"
#include "HTP/QnnHtpPerfInfrastructure.h"
#include "Logger.hpp"
#include "PAL/DynamicLoading.hpp"
#include "QnnCommon.h"
#include "QnnDevice.h"
#include "QnnGraph.h"
#include "QnnSampleApp.hpp"
#include "QnnSampleAppUtils.hpp"
#include "QnnTypeMacros.hpp"
#include "QnnTypes.h"
#include "QnnWrapperUtils.hpp"

#include "QnnLog.h"

#include "QNN/HTP/QnnHtpDevice.h"
#include "QNN/HTP/QnnHtpGraph.h"

#include "QNN/GPU/QnnGpuBackend.h"

#include <filesystem>

using namespace qnn;
using namespace qnn::tools;

static constexpr bool USE_CUSTOM_PARAMS = true;

sample_app::QnnSampleApp::QnnSampleApp(
    QnnFunctionPointers qnnFunctionPointers, std::string opPackagePaths,
    void *backendLibraryHandle, bool debug,
    iotensor::OutputDataType outputDataType,
    iotensor::InputDataType inputDataType,
    sample_app::ProfilingLevel profilingLevel, std::string cachedBinaryPath)
    : m_qnnFunctionPointers(qnnFunctionPointers),
      m_cachedBinaryPath(cachedBinaryPath), m_debug(debug),
      m_outputDataType(outputDataType), m_inputDataType(inputDataType),
      m_profilingLevel(profilingLevel),
      m_backendLibraryHandle(backendLibraryHandle),
      m_isBackendInitialized(false), m_isContextCreated(false) {
  split(m_opPackagePaths, opPackagePaths, ',');
  return;
}

sample_app::QnnSampleApp::QnnSampleApp(const std::string &backendPath,
                                       const std::string &modelPath,
                                       iotensor::OutputDataType outputDataType,
                                       iotensor::InputDataType inputDataType,
                                       const BackendConfig &backendCfg)
    : m_outputDataType(outputDataType), m_inputDataType(inputDataType),
      m_profilingLevel(ProfilingLevel::OFF), // 默认关闭性能分析
      m_isBackendInitialized(false), m_isContextCreated(false), m_debug(false),
      m_backendCfg(backendCfg) // 初始化后端配置
{
  // 确定是否为二进制模型文件
  m_isBinaryModel = (modelPath.length() >= 4) &&
                    (modelPath.rfind(".bin") == (modelPath.length() - 4));

  // 动态加载 backend 和 model 库
  auto dynStatus = dynamicloadutil::getQnnFunctionPointers(
      backendPath, modelPath, &m_qnnFunctionPointers, &m_ownedBackendHandle,
      !m_isBinaryModel, &m_ownedModelHandle);

  if (m_isBinaryModel) {
    // 二进制模型需要System接口
    // 获取backendPath所在文件夹
    std::string backendDir =
        std::filesystem::path(backendPath).parent_path().string();
    dynamicloadutil::getQnnSystemFunctionPointers(
        backendDir + "/libQnnSystem.so", &m_qnnFunctionPointers);
    m_cachedBinaryPath = modelPath;
  }

  if (dynStatus != dynamicloadutil::StatusCode::SUCCESS) {
    QNN_ERROR("初始化QNN函数指针失败");
    throw std::runtime_error("Failed to initialize QNN function pointers");
  }

  // 设置backend句柄
  m_backendLibraryHandle = m_ownedBackendHandle;


    if (backendPath.find("Gpu") != std::string::npos) {
    // 配置GPU后端
    QnnGpuBackend_CustomConfig_t gpuTuningEnableConfig;
    QnnGpuBackend_CustomConfig_t gpuTuningPerformanceCacheConfig;
    QnnGpuBackend_CustomConfig_t gpuTuningInvalidatePerformanceCacheConfig;

    // enable tuning mode
    gpuTuningEnableConfig.option                                = QNN_GPU_BACKEND_CONFIG_OPTION_ENABLE_TUNING_MODE;
    gpuTuningEnableConfig.enableTuningMode                      = true;

    // set performanceCache directory
    gpuTuningPerformanceCacheConfig.option                      = QNN_GPU_BACKEND_CONFIG_OPTION_PERFORMANCE_CACHE_DIR;
    gpuTuningPerformanceCacheConfig.performanceCacheDir         = ".";

    // invalidate performanceCache
    gpuTuningInvalidatePerformanceCacheConfig.option                      = QNN_GPU_BACKEND_CONFIG_OPTION_INVALIDATE_PERFORMANCE_CACHE;
    gpuTuningInvalidatePerformanceCacheConfig.invalidatePerformanceCache  = true;

    QnnBackend_Config_t *pBackendConfig_tuningEnable = new QnnBackend_Config_t();
    pBackendConfig_tuningEnable->option = QNN_BACKEND_CONFIG_OPTION_CUSTOM;
    pBackendConfig_tuningEnable->customConfig = &gpuTuningEnableConfig;

    QnnBackend_Config_t *pBackendConfig_performanceCache = new QnnBackend_Config_t();
    pBackendConfig_performanceCache->option = QNN_BACKEND_CONFIG_OPTION_CUSTOM;
    pBackendConfig_performanceCache->customConfig = &gpuTuningPerformanceCacheConfig;

    QnnBackend_Config_t *pBackendConfig_invalidatePerformanceCache = new QnnBackend_Config_t();
    pBackendConfig_invalidatePerformanceCache->option = QNN_BACKEND_CONFIG_OPTION_CUSTOM;
    pBackendConfig_invalidatePerformanceCache->customConfig = &gpuTuningInvalidatePerformanceCacheConfig;

    QnnBackend_Config_t **pBackendConfig = new QnnBackend_Config_t *[4];
    pBackendConfig[0] = pBackendConfig_tuningEnable;
    pBackendConfig[1] = pBackendConfig_performanceCache;
    // pBackendConfig[2] = pBackendConfig_invalidatePerformanceCache;
    pBackendConfig[2] = nullptr;
    pBackendConfig[3] = nullptr;

    if (USE_CUSTOM_PARAMS) {
      // m_backendConfig = pBackendConfig;

      // auto result = m_qnnFunctionPointers.qnnInterface.backendSetConfig(
      //     m_backendHandle, (const QnnBackend_Config_t **)pBackendConfig);
      // if (result != QNN_SUCCESS) {
      //   QNN_ERROR("设置后端配置失败: %d", result);
      // } else {
      //   QNN_INFO("设置后端配置成功");
      // }
    }
  }

  // 初始化后端
  if (initializeBackend() != StatusCode::SUCCESS) {
    QNN_ERROR("后端初始化失败");
    throw std::runtime_error("Failed to initialize backend");
  }

  // 注册Op包（二进制模型可能不需要，但为安全起见保留）
  if (StatusCode::SUCCESS != registerOpPackages()) {
    QNN_ERROR("注册Op包失败");
    throw std::runtime_error("Failed to register op packages");
  }

  // 根据模型类型选择初始化路径
  if (m_isBinaryModel) {
    // 二进制模型路径：直接从二进制加载
    if (createFromBinary() != StatusCode::SUCCESS) {
      QNN_ERROR("从二进制文件创建模型失败");
      throw std::runtime_error("Failed to create model from binary");
    }
  } else {
    // 非二进制模型路径：常规初始化
    if (createContext() != StatusCode::SUCCESS) {
      QNN_ERROR("创建上下文失败");
      throw std::runtime_error("Failed to create context");
    }
    if (composeGraphs() != StatusCode::SUCCESS) {
      QNN_ERROR("组合图失败");
      throw std::runtime_error("Failed to compose graphs");
    }

    // 配置一下HTP后端
    if (backendPath.find("Htp") != std::string::npos) {
      // 配置图
      QnnHtpGraph_CustomConfig_t *configGraphVtcm =
          new QnnHtpGraph_CustomConfig_t();
      configGraphVtcm->option = QNN_HTP_GRAPH_CONFIG_OPTION_VTCM_SIZE;
      configGraphVtcm->vtcmSizeInMB = QNN_HTP_GRAPH_CONFIG_OPTION_MAX;

      QnnGraph_Config_t *devConfigGraphVtcm = new QnnGraph_Config_t();
      devConfigGraphVtcm->option = QNN_GRAPH_CONFIG_OPTION_CUSTOM;
      devConfigGraphVtcm->customConfig = configGraphVtcm;

      QnnHtpGraph_CustomConfig_t *configGraphPrecision =
          new QnnHtpGraph_CustomConfig_t();
      configGraphPrecision->option = QNN_HTP_GRAPH_CONFIG_OPTION_PRECISION;
      configGraphPrecision->precision =
          (Qnn_Precision_t)m_backendCfg.htpConfig.precisionMode;

      QnnGraph_Config_t *devConfigGraphPrecision = new QnnGraph_Config_t();
      devConfigGraphPrecision->option = QNN_GRAPH_CONFIG_OPTION_CUSTOM;
      devConfigGraphPrecision->customConfig = configGraphPrecision;

      // 添加图优化级别配置 (O=3)
      QnnHtpGraph_CustomConfig_t *configGraphOpt =
          new QnnHtpGraph_CustomConfig_t();
      configGraphOpt->option = QNN_HTP_GRAPH_CONFIG_OPTION_OPTIMIZATION;
      configGraphOpt->optimizationOption.type =
          QNN_HTP_GRAPH_OPTIMIZATION_TYPE_FINALIZE_OPTIMIZATION_FLAG;
      configGraphOpt->optimizationOption.floatValue =
          (float)m_backendCfg.htpConfig.optimizationLevel; // O=3最佳性能

      QnnGraph_Config_t *devConfigGraphOpt = new QnnGraph_Config_t();
      devConfigGraphOpt->option = QNN_GRAPH_CONFIG_OPTION_CUSTOM;
      devConfigGraphOpt->customConfig = configGraphOpt;

      // 添加HVX线程数配置
      QnnHtpGraph_CustomConfig_t *configGraphHvx =
          new QnnHtpGraph_CustomConfig_t();
      configGraphHvx->option = QNN_HTP_GRAPH_CONFIG_OPTION_NUM_HVX_THREADS;
      configGraphHvx->numHvxThreads = UINT64_MAX; // 设置为最大线程！！！！

      QnnGraph_Config_t *devConfigGraphHvx = new QnnGraph_Config_t();
      devConfigGraphHvx->option = QNN_GRAPH_CONFIG_OPTION_CUSTOM;
      devConfigGraphHvx->customConfig = configGraphHvx;

      // 添加DLBC优化配置
      QnnHtpGraph_CustomConfig_t *configGraphDlbc =
          new QnnHtpGraph_CustomConfig_t();
      configGraphDlbc->option = QNN_HTP_GRAPH_CONFIG_OPTION_OPTIMIZATION;
      configGraphDlbc->optimizationOption.type =
          QNN_HTP_GRAPH_OPTIMIZATION_TYPE_ENABLE_DLBC;
      configGraphDlbc->optimizationOption.floatValue = 1.0f; // 启用DLBC

      QnnGraph_Config_t *devConfigGraphDlbc = new QnnGraph_Config_t();
      devConfigGraphDlbc->option = QNN_GRAPH_CONFIG_OPTION_CUSTOM;
      devConfigGraphDlbc->customConfig = configGraphDlbc;

      // QnnHtpGraph_CustomConfig_t *configGraphDlbcWeights =
      //     new QnnHtpGraph_CustomConfig_t();
      // configGraphDlbcWeights->option =
      //     QNN_HTP_GRAPH_CONFIG_OPTION_OPTIMIZATION;
      // configGraphDlbcWeights->optimizationOption.type =
      //     QNN_HTP_GRAPH_OPTIMIZATION_TYPE_ENABLE_DLBC_WEIGHTS;
      // configGraphDlbcWeights->optimizationOption.floatValue =
      //     1.0f; // 启用权重DLBC优化

      // QnnGraph_Config_t *devConfigGraphDlbcWeights =
      //     new QnnGraph_Config_t();
      // devConfigGraphDlbcWeights->option = QNN_GRAPH_CONFIG_OPTION_CUSTOM;
      // devConfigGraphDlbcWeights->customConfig = configGraphDlbcWeights;

      QnnGraph_Config_t **pGraphConfig =
          new QnnGraph_Config_t *[7]; // 增加数组大小以容纳新配置
      pGraphConfig[0] = devConfigGraphVtcm;
      pGraphConfig[1] = devConfigGraphPrecision;
      pGraphConfig[2] = devConfigGraphOpt;  // 新增优化级别
      pGraphConfig[3] = devConfigGraphHvx;  // 新增HVX线程
      pGraphConfig[4] = devConfigGraphDlbc; // 新增DLBC优化
      // pGraphConfig[5] = devConfigGraphDlbcWeights; // 新增DLBC权重优化  //
      // 好像设备上不支持
      pGraphConfig[5] = nullptr;
      pGraphConfig[6] = nullptr;

      if (USE_CUSTOM_PARAMS) {
        auto result = m_qnnFunctionPointers.qnnInterface.graphSetConfig(
            m_graphsInfo[0]->graph, (const QnnGraph_Config_t **)pGraphConfig);
        if (result != QNN_SUCCESS) {
          QNN_ERROR("设置图配置失败: %d", result);
        } else {
          QNN_INFO("设置图配置成功");
        }
      }
    }

    if (finalizeGraphs() != StatusCode::SUCCESS) {
      QNN_ERROR("完成图初始化失败");
      throw std::runtime_error("Failed to finalize graphs");
    }
  }

  // 配置一下HTP后端
  if (backendPath.find("Htp") != std::string::npos) {
    // 获取平台信息
    const QnnDevice_PlatformInfo_t *platformInfo;
    Qnn_ErrorHandle_t err =
        m_qnnFunctionPointers.qnnInterface.deviceGetPlatformInfo(nullptr,
                                                                 &platformInfo);

    // 使用new分配SoC配置
    QnnHtpDevice_CustomConfig_t *configSoc = new QnnHtpDevice_CustomConfig_t();
    configSoc->option = QNN_HTP_DEVICE_CONFIG_OPTION_SOC;
    configSoc->socModel = platformInfo->v1.hwDevices[0]
                              .v1.deviceInfoExtension->onChipDevice.socModel;

    QnnDevice_Config_t *devConfigSoc = new QnnDevice_Config_t();
    devConfigSoc->option = QNN_DEVICE_CONFIG_OPTION_CUSTOM;
    devConfigSoc->customConfig = configSoc;

    // 使用new分配架构配置
    QnnHtpDevice_CustomConfig_t *configArch = new QnnHtpDevice_CustomConfig_t();
    configArch->option = QNN_HTP_DEVICE_CONFIG_OPTION_ARCH;
    configArch->arch.arch =
        platformInfo->v1.hwDevices[0].v1.deviceInfoExtension->onChipDevice.arch;
    configArch->arch.deviceId = 0; // 默认设备ID为0

    QnnDevice_Config_t *devConfigArch = new QnnDevice_Config_t();
    devConfigArch->option = QNN_DEVICE_CONFIG_OPTION_CUSTOM;
    devConfigArch->customConfig = configArch;

    // 使用new分配指针数组
    QnnDevice_Config_t **pDeviceConfig = new QnnDevice_Config_t *[3];
    pDeviceConfig[0] = devConfigSoc;
    pDeviceConfig[1] = devConfigArch;
    pDeviceConfig[2] = nullptr; // 以nullptr结束的数组
    if (USE_CUSTOM_PARAMS) {
      m_deviceConfig = pDeviceConfig;

      auto result = m_qnnFunctionPointers.qnnInterface.backendSetConfig(
          m_backendHandle, (const QnnBackend_Config_t **)m_backendConfig);
      if (result != QNN_SUCCESS) {
        QNN_ERROR("设置后端配置失败: %d", result);
      } else {
        QNN_INFO("设置后端配置成功");
      }
    }

    // 配置性能基础设施 (Performance Infrastructure)
    Qnn_DeviceHandle_t deviceHandle = nullptr;
    Qnn_ErrorHandle_t perfResult =
        m_qnnFunctionPointers.qnnInterface.deviceCreate(
            m_logHandle, (const QnnDevice_Config_t **)m_deviceConfig,
            &deviceHandle);
    if (perfResult == QNN_SUCCESS && deviceHandle != nullptr) {
      QnnDevice_Infrastructure_t deviceInfra = nullptr;
      perfResult = m_qnnFunctionPointers.qnnInterface.deviceGetInfrastructure(
          &deviceInfra);

      if (perfResult == QNN_SUCCESS && deviceInfra != nullptr) {
        QnnHtpDevice_Infrastructure_t *htpInfra =
            static_cast<QnnHtpDevice_Infrastructure_t *>(deviceInfra);
        QnnHtpDevice_PerfInfrastructure_t perfInfra = htpInfra->perfInfra;
        uint32_t powerConfigId = 0;

        // 创建电源配置ID
        perfResult = perfInfra.createPowerConfigId(0, 0, &powerConfigId);

        if (perfResult == QNN_SUCCESS) {
          QNN_INFO("创建电源配置ID成功: %d", powerConfigId);

          // 配置DCVS V3高性能Burst模式
          QnnHtpPerfInfrastructure_PowerConfig_t *dcvsConfig =
              new QnnHtpPerfInfrastructure_PowerConfig_t();
          memset(dcvsConfig, 0, sizeof(QnnHtpPerfInfrastructure_PowerConfig_t));
          dcvsConfig->option =
              QNN_HTP_PERF_INFRASTRUCTURE_POWER_CONFIGOPTION_DCVS_V3;
          dcvsConfig->dcvsV3Config.contextId = powerConfigId;
          dcvsConfig->dcvsV3Config.setBusParams = 1;
          dcvsConfig->dcvsV3Config.busVoltageCornerMin =
              DCVS_VOLTAGE_VCORNER_TURBO;
          dcvsConfig->dcvsV3Config.busVoltageCornerTarget =
              DCVS_VOLTAGE_VCORNER_TURBO;
          dcvsConfig->dcvsV3Config.busVoltageCornerMax =
              DCVS_VOLTAGE_VCORNER_TURBO;
          dcvsConfig->dcvsV3Config.setCoreParams = 1;
          dcvsConfig->dcvsV3Config.coreVoltageCornerMin =
              DCVS_VOLTAGE_VCORNER_TURBO;
          dcvsConfig->dcvsV3Config.coreVoltageCornerTarget =
              DCVS_VOLTAGE_VCORNER_TURBO;
          dcvsConfig->dcvsV3Config.coreVoltageCornerMax =
              DCVS_VOLTAGE_VCORNER_TURBO;
          dcvsConfig->dcvsV3Config.setSleepLatency = 1;
          dcvsConfig->dcvsV3Config.sleepLatency = 40; // Burst模式建议值
          dcvsConfig->dcvsV3Config.setDcvsEnable = 1;
          dcvsConfig->dcvsV3Config.dcvsEnable = 0; // 禁用DCVS以锁定高频
          dcvsConfig->dcvsV3Config.powerMode =
              QNN_HTP_PERF_INFRASTRUCTURE_POWERMODE_PERFORMANCE_MODE;

          // 配置HMX (如果SoC支持)
          QnnHtpPerfInfrastructure_PowerConfig_t *hmxConfig =
              new QnnHtpPerfInfrastructure_PowerConfig_t();
          memset(hmxConfig, 0, sizeof(QnnHtpPerfInfrastructure_PowerConfig_t));
          hmxConfig->option =
              QNN_HTP_PERF_INFRASTRUCTURE_POWER_CONFIGOPTION_HMX_V2;
          hmxConfig->hmxV2Config.hmxPickDefault = 0;
          hmxConfig->hmxV2Config.hmxPerfMode =
              QNN_HTP_PERF_INFRASTRUCTURE_CLK_PERF_HIGH;
          hmxConfig->hmxV2Config.hmxVoltageCornerMin = DCVS_EXP_VCORNER_TUR;
          hmxConfig->hmxV2Config.hmxVoltageCornerTarget = DCVS_EXP_VCORNER_TUR;
          hmxConfig->hmxV2Config.hmxVoltageCornerMax = DCVS_EXP_VCORNER_TUR;

          // 配置RPC Control Latency
          QnnHtpPerfInfrastructure_PowerConfig_t *rpcLatencyConfig =
              new QnnHtpPerfInfrastructure_PowerConfig_t();
          memset(rpcLatencyConfig, 0,
                 sizeof(QnnHtpPerfInfrastructure_PowerConfig_t));
          rpcLatencyConfig->option =
              QNN_HTP_PERF_INFRASTRUCTURE_POWER_CONFIGOPTION_RPC_CONTROL_LATENCY;
          rpcLatencyConfig->rpcControlLatencyConfig = 100; // 建议值100us

          // 配置RPC Polling Time
          QnnHtpPerfInfrastructure_PowerConfig_t *rpcPollingConfig =
              new QnnHtpPerfInfrastructure_PowerConfig_t();
          memset(rpcPollingConfig, 0,
                 sizeof(QnnHtpPerfInfrastructure_PowerConfig_t));
          rpcPollingConfig->option =
              QNN_HTP_PERF_INFRASTRUCTURE_POWER_CONFIGOPTION_RPC_POLLING_TIME;
          rpcPollingConfig->rpcPollingTimeConfig = 1000;

          // 创建电源配置数组
          const QnnHtpPerfInfrastructure_PowerConfig_t **powerConfigs =
              new const QnnHtpPerfInfrastructure_PowerConfig_t *[5];
          powerConfigs[0] = dcvsConfig;
          powerConfigs[1] = hmxConfig;
          powerConfigs[2] = rpcLatencyConfig;
          powerConfigs[3] = rpcPollingConfig;
          powerConfigs[4] = nullptr;

          // 应用电源配置
          if (USE_CUSTOM_PARAMS) {
            perfResult = perfInfra.setPowerConfig(powerConfigId, powerConfigs);
            if (perfResult == QNN_SUCCESS) {
              QNN_INFO("应用电源配置成功");
            } else {
              QNN_ERROR("应用电源配置失败: %d", perfResult);
            }
          }
        }
      }
    }
  }
}

sample_app::QnnSampleApp::~QnnSampleApp() {

  m_ioTensor.tearDownInputAndOutputTensors(
    m_storedInputs, m_storedOutputs,
    (*m_graphsInfo)[0].numInputTensors,
    (*m_graphsInfo)[0].numOutputTensors);
  m_storedInputs = nullptr;
  m_storedOutputs = nullptr;
  m_currentGraphIndex = -1;

  // Free Profiling object if it was created
  if (nullptr != m_profileBackendHandle) {
    QNN_DEBUG("Freeing backend profile object.");
    if (QNN_PROFILE_NO_ERROR != m_qnnFunctionPointers.qnnInterface.profileFree(
                                    m_profileBackendHandle)) {
      QNN_ERROR("Could not free backend profile handle.");
    }
  }
  // Free context if not already done
  if (m_isContextCreated) {
    QNN_DEBUG("Freeing context");
    if (QNN_CONTEXT_NO_ERROR !=
        m_qnnFunctionPointers.qnnInterface.contextFree(m_context, nullptr)) {
      QNN_ERROR("Could not free context");
    }
  }
  m_isContextCreated = false;
  // Terminate backend
  if (m_isBackendInitialized &&
      nullptr != m_qnnFunctionPointers.qnnInterface.backendFree) {
    QNN_DEBUG("Freeing backend");
    if (QNN_BACKEND_NO_ERROR !=
        m_qnnFunctionPointers.qnnInterface.backendFree(m_backendHandle)) {
      QNN_ERROR("Could not free backend");
    }
  }
  m_isBackendInitialized = false;
  // Terminate logging in the backend
  if (nullptr != m_qnnFunctionPointers.qnnInterface.logFree &&
      nullptr != m_logHandle) {
    if (QNN_SUCCESS !=
        m_qnnFunctionPointers.qnnInterface.logFree(m_logHandle)) {
      QNN_WARN("Unable to terminate logging in the backend.");
    }
  }

  // 关闭动态库句柄
  if (m_ownedModelHandle) {
    pal::dynamicloading::dlClose(m_ownedModelHandle);
    m_ownedModelHandle = nullptr;
  }
  if (m_ownedBackendHandle) {
    pal::dynamicloading::dlClose(m_ownedBackendHandle);
    m_ownedBackendHandle = nullptr;
  }
}

std::string sample_app::QnnSampleApp::getBackendBuildId() {
  char *backendBuildId{nullptr};
  if (QNN_SUCCESS != m_qnnFunctionPointers.qnnInterface.backendGetBuildId(
                         (const char **)&backendBuildId)) {
    QNN_ERROR("Unable to get build Id from the backend.");
  }
  return (backendBuildId == nullptr ? std::string("")
                                    : std::string(backendBuildId));
}

sample_app::StatusCode sample_app::QnnSampleApp::initializeProfiling() {
  if (ProfilingLevel::OFF != m_profilingLevel) {
    QNN_INFO("Profiling turned on; level = %d", m_profilingLevel);
    if (ProfilingLevel::BASIC == m_profilingLevel) {
      QNN_INFO("Basic profiling requested. Creating Qnn Profile object.");
      if (QNN_PROFILE_NO_ERROR !=
          m_qnnFunctionPointers.qnnInterface.profileCreate(
              m_backendHandle, QNN_PROFILE_LEVEL_BASIC,
              &m_profileBackendHandle)) {
        QNN_WARN("Unable to create profile handle in the backend.");
        return StatusCode::FAILURE;
      }
    } else if (ProfilingLevel::DETAILED == m_profilingLevel) {
      QNN_INFO("Detailed profiling requested. Creating Qnn Profile object.");
      if (QNN_PROFILE_NO_ERROR !=
          m_qnnFunctionPointers.qnnInterface.profileCreate(
              m_backendHandle, QNN_PROFILE_LEVEL_DETAILED,
              &m_profileBackendHandle)) {
        QNN_ERROR("Unable to create profile handle in the backend.");
        return StatusCode::FAILURE;
      }
    }
  }
  return StatusCode::SUCCESS;
}

// Simple method to report error from app to lib.
int32_t sample_app::QnnSampleApp::reportError(const std::string &err) {
  QNN_ERROR("%s", err.c_str());
  return EXIT_FAILURE;
}

// Initialize a QnnBackend.
sample_app::StatusCode sample_app::QnnSampleApp::initializeBackend() {
  auto qnnStatus = m_qnnFunctionPointers.qnnInterface.backendCreate(
      m_logHandle, (const QnnBackend_Config_t **)m_backendConfig,
      &m_backendHandle);
  if (QNN_BACKEND_NO_ERROR != qnnStatus) {
    QNN_ERROR("Could not initialize backend due to error = %d", qnnStatus);
    return StatusCode::FAILURE;
  }
  QNN_INFO("Initialize Backend Returned Status = %d", qnnStatus);
  m_isBackendInitialized = true;
  return StatusCode::SUCCESS;
}

// Terminate the backend after done.
sample_app::StatusCode sample_app::QnnSampleApp::terminateBackend() {
  if ((m_isBackendInitialized &&
       nullptr != m_qnnFunctionPointers.qnnInterface.backendFree) &&
      QNN_BACKEND_NO_ERROR !=
          m_qnnFunctionPointers.qnnInterface.backendFree(m_backendHandle)) {
    QNN_ERROR("Could not terminate backend");
    return StatusCode::FAILURE;
  }
  m_isBackendInitialized = false;
  return StatusCode::SUCCESS;
}

// Register op packages and interface providers supplied during
// object creation. If there are multiple op packages, register
// them sequentially in the order provided.
sample_app::StatusCode sample_app::QnnSampleApp::registerOpPackages() {
  const size_t pathIdx = 0;
  const size_t interfaceProviderIdx = 1;
  for (auto const &opPackagePath : m_opPackagePaths) {
    std::vector<std::string> opPackage;
    split(opPackage, opPackagePath, ':');
    QNN_DEBUG("opPackagePath: %s", opPackagePath.c_str());
    const char *target = nullptr;
    const size_t targetIdx = 2;
    if (opPackage.size() != 2 && opPackage.size() != 3) {
      QNN_ERROR("Malformed opPackageString provided: %s",
                opPackagePath.c_str());
      return StatusCode::FAILURE;
    }
    if (opPackage.size() == 3) {
      target = (char *)opPackage[targetIdx].c_str();
    }
    if (nullptr ==
        m_qnnFunctionPointers.qnnInterface.backendRegisterOpPackage) {
      QNN_ERROR("backendRegisterOpPackageFnHandle is nullptr.");
      return StatusCode::FAILURE;
    }
    if (QNN_BACKEND_NO_ERROR !=
        m_qnnFunctionPointers.qnnInterface.backendRegisterOpPackage(
            m_backendHandle, (char *)opPackage[pathIdx].c_str(),
            (char *)opPackage[interfaceProviderIdx].c_str(), target)) {
      QNN_ERROR("Could not register Op Package: %s and interface provider: %s",
                opPackage[pathIdx].c_str(),
                opPackage[interfaceProviderIdx].c_str());
      return StatusCode::FAILURE;
    }
    QNN_INFO("Registered Op Package: %s and interface provider: %s",
             opPackage[pathIdx].c_str(),
             opPackage[interfaceProviderIdx].c_str());
  }
  return StatusCode::SUCCESS;
}

// Create a Context in a backend.
sample_app::StatusCode sample_app::QnnSampleApp::createContext() {
  if (QNN_CONTEXT_NO_ERROR != m_qnnFunctionPointers.qnnInterface.contextCreate(
                                  m_backendHandle, m_deviceHandle,
                                  (const QnnContext_Config_t **)m_contextConfig,
                                  &m_context)) {
    QNN_ERROR("Could not create context");
    return StatusCode::FAILURE;
  }
  m_isContextCreated = true;
  return StatusCode::SUCCESS;
}

// Free context after done.
sample_app::StatusCode sample_app::QnnSampleApp::freeContext() {
  if (QNN_CONTEXT_NO_ERROR != m_qnnFunctionPointers.qnnInterface.contextFree(
                                  m_context, m_profileBackendHandle)) {
    QNN_ERROR("Could not free context");
    return StatusCode::FAILURE;
  }
  m_isContextCreated = false;
  return StatusCode::SUCCESS;
}

// Calls composeGraph function in QNN's model.so.
// composeGraphs is supposed to populate graph related
// information in m_graphsInfo and m_graphsCount.
// m_debug is the option supplied to composeGraphs to
// say that all intermediate tensors including output tensors
// are expected to be read by the app.
sample_app::StatusCode sample_app::QnnSampleApp::composeGraphs() {
  auto returnStatus = StatusCode::SUCCESS;
  if (qnn_wrapper_api::ModelError_t::MODEL_NO_ERROR !=
      m_qnnFunctionPointers.composeGraphsFnHandle(
          m_backendHandle, m_qnnFunctionPointers.qnnInterface, m_context,
          (const qnn_wrapper_api::GraphConfigInfo_t **)m_graphConfigsInfo,
          m_graphConfigsInfoCount, &m_graphsInfo, &m_graphsCount, m_debug,
          log::getLogCallback(), log::getLogLevel())) {
    QNN_ERROR("Failed in composeGraphs()");
    returnStatus = StatusCode::FAILURE;
  }
  return returnStatus;
}

sample_app::StatusCode sample_app::QnnSampleApp::finalizeGraphs() {
  for (size_t graphIdx = 0; graphIdx < m_graphsCount; graphIdx++) {
    if (QNN_GRAPH_NO_ERROR !=
        m_qnnFunctionPointers.qnnInterface.graphFinalize(
            (*m_graphsInfo)[graphIdx].graph, m_profileBackendHandle, nullptr)) {
      return StatusCode::FAILURE;
    }
  }
  if (ProfilingLevel::OFF != m_profilingLevel) {
    extractBackendProfilingInfo(m_profileBackendHandle);
  }
  auto returnStatus = StatusCode::SUCCESS;
  return returnStatus;
}

sample_app::StatusCode sample_app::QnnSampleApp::createFromBinary() {
  if (m_cachedBinaryPath.empty()) {
    QNN_ERROR("No name provided to read binary file from.");
    return StatusCode::FAILURE;
  }
  if (nullptr == m_qnnFunctionPointers.qnnSystemInterface.systemContextCreate ||
      nullptr ==
          m_qnnFunctionPointers.qnnSystemInterface.systemContextGetBinaryInfo ||
      nullptr == m_qnnFunctionPointers.qnnSystemInterface.systemContextFree) {
    QNN_ERROR("QNN System function pointers are not populated.");
    return StatusCode::FAILURE;
  }
  uint64_t bufferSize{0};
  std::shared_ptr<uint8_t> buffer{nullptr};
  // read serialized binary into a byte buffer
  tools::datautil::StatusCode status{tools::datautil::StatusCode::SUCCESS};
  std::tie(status, bufferSize) =
      tools::datautil::getFileSize(m_cachedBinaryPath);
  if (0 == bufferSize) {
    QNN_ERROR("Received path to an empty file. Nothing to deserialize.");
    return StatusCode::FAILURE;
  }
  buffer = std::shared_ptr<uint8_t>(new uint8_t[bufferSize],
                                    std::default_delete<uint8_t[]>());
  if (!buffer) {
    QNN_ERROR("Failed to allocate memory.");
    return StatusCode::FAILURE;
  }

  status = tools::datautil::readBinaryFromFile(
      m_cachedBinaryPath, reinterpret_cast<uint8_t *>(buffer.get()),
      bufferSize);
  if (status != tools::datautil::StatusCode::SUCCESS) {
    QNN_ERROR("Failed to read binary data.");
    return StatusCode::FAILURE;
  }

  // inspect binary info
  auto returnStatus = StatusCode::SUCCESS;
  QnnSystemContext_Handle_t sysCtxHandle{nullptr};
  if (QNN_SUCCESS !=
      m_qnnFunctionPointers.qnnSystemInterface.systemContextCreate(
          &sysCtxHandle)) {
    QNN_ERROR("Could not create system handle.");
    returnStatus = StatusCode::FAILURE;
  }
  const QnnSystemContext_BinaryInfo_t *binaryInfo{nullptr};
  Qnn_ContextBinarySize_t binaryInfoSize{0};
  if (StatusCode::SUCCESS == returnStatus &&
      QNN_SUCCESS !=
          m_qnnFunctionPointers.qnnSystemInterface.systemContextGetBinaryInfo(
              sysCtxHandle, static_cast<void *>(buffer.get()), bufferSize,
              &binaryInfo, &binaryInfoSize)) {
    QNN_ERROR("Failed to get context binary info");
    returnStatus = StatusCode::FAILURE;
  }

  // fill GraphInfo_t based on binary info
  if (StatusCode::SUCCESS == returnStatus &&
      !copyMetadataToGraphsInfo(binaryInfo, m_graphsInfo, m_graphsCount)) {
    QNN_ERROR("Failed to copy metadata.");
    returnStatus = StatusCode::FAILURE;
  }
  m_qnnFunctionPointers.qnnSystemInterface.systemContextFree(sysCtxHandle);
  sysCtxHandle = nullptr;

  if (StatusCode::SUCCESS == returnStatus &&
      nullptr == m_qnnFunctionPointers.qnnInterface.contextCreateFromBinary) {
    QNN_ERROR("contextCreateFromBinaryFnHandle is nullptr.");
    returnStatus = StatusCode::FAILURE;
  }
  if (StatusCode::SUCCESS == returnStatus &&
      m_qnnFunctionPointers.qnnInterface.contextCreateFromBinary(
          m_backendHandle, m_deviceHandle,
          (const QnnContext_Config_t **)m_contextConfig,
          static_cast<void *>(buffer.get()), bufferSize, &m_context,
          m_profileBackendHandle)) {
    QNN_ERROR("Could not create context from binary.");
    returnStatus = StatusCode::FAILURE;
  }
  if (ProfilingLevel::OFF != m_profilingLevel) {
    extractBackendProfilingInfo(m_profileBackendHandle);
  }
  m_isContextCreated = true;
  if (StatusCode::SUCCESS == returnStatus) {
    for (size_t graphIdx = 0; graphIdx < m_graphsCount; graphIdx++) {
      if (nullptr == m_qnnFunctionPointers.qnnInterface.graphRetrieve) {
        QNN_ERROR("graphRetrieveFnHandle is nullptr.");
        returnStatus = StatusCode::FAILURE;
        break;
      }
      if (QNN_SUCCESS != m_qnnFunctionPointers.qnnInterface.graphRetrieve(
                             m_context, (*m_graphsInfo)[graphIdx].graphName,
                             &((*m_graphsInfo)[graphIdx].graph))) {
        QNN_ERROR("Unable to retrieve graph handle for graph Idx: %d",
                  graphIdx);
        returnStatus = StatusCode::FAILURE;
      }
    }
  }
  if (StatusCode::SUCCESS != returnStatus) {
    QNN_DEBUG("Cleaning up graph Info structures.");
    qnn_wrapper_api::freeGraphsInfo(&m_graphsInfo, m_graphsCount);
  }
  return returnStatus;
}

sample_app::StatusCode
sample_app::QnnSampleApp::saveBinary(std::string outputPath,
                                     std::string saveBinaryName) {
  if (saveBinaryName.empty()) {
    QNN_ERROR("No name provided to save binary file.");
    return StatusCode::FAILURE;
  }
  if (nullptr == m_qnnFunctionPointers.qnnInterface.contextGetBinarySize ||
      nullptr == m_qnnFunctionPointers.qnnInterface.contextGetBinary) {
    QNN_ERROR(
        "contextGetBinarySizeFnHandle or contextGetBinaryFnHandle is nullptr.");
    return StatusCode::FAILURE;
  }
  uint64_t requiredBufferSize{0};
  if (QNN_CONTEXT_NO_ERROR !=
      m_qnnFunctionPointers.qnnInterface.contextGetBinarySize(
          m_context, &requiredBufferSize)) {
    QNN_ERROR("Could not get the required binary size.");
    return StatusCode::FAILURE;
  }
  std::unique_ptr<uint8_t[]> saveBuffer(new uint8_t[requiredBufferSize]);
  if (nullptr == saveBuffer) {
    QNN_ERROR("Could not allocate buffer to save binary.");
    return StatusCode::FAILURE;
  }
  uint64_t writtenBufferSize{0};
  if (QNN_CONTEXT_NO_ERROR !=
      m_qnnFunctionPointers.qnnInterface.contextGetBinary(
          m_context, reinterpret_cast<void *>(saveBuffer.get()),
          requiredBufferSize, &writtenBufferSize)) {
    QNN_ERROR("Could not get binary.");
    return StatusCode::FAILURE;
  }
  if (requiredBufferSize < writtenBufferSize) {
    QNN_ERROR("Illegal written buffer size [%d] bytes. Cannot exceed allocated "
              "memory of [%d] bytes",
              writtenBufferSize, requiredBufferSize);
    return StatusCode::FAILURE;
  }

  auto dataUtilStatus = tools::datautil::writeBinaryToFile(
      outputPath, saveBinaryName + ".bin", (uint8_t *)saveBuffer.get(),
      writtenBufferSize);
  if (tools::datautil::StatusCode::SUCCESS != dataUtilStatus) {
    QNN_ERROR("Error while writing binary to file.");
    return StatusCode::FAILURE;
  }

  return StatusCode::SUCCESS;
}

sample_app::StatusCode sample_app::QnnSampleApp::extractBackendProfilingInfo(
    Qnn_ProfileHandle_t profileHandle) {
  if (nullptr == m_profileBackendHandle) {
    QNN_ERROR("Backend Profile handle is nullptr; may not be initialized.");
    return StatusCode::FAILURE;
  }
  const QnnProfile_EventId_t *profileEvents{nullptr};
  uint32_t numEvents{0};
  if (QNN_PROFILE_NO_ERROR !=
      m_qnnFunctionPointers.qnnInterface.profileGetEvents(
          profileHandle, &profileEvents, &numEvents)) {
    QNN_ERROR("Failure in profile get events.");
    return StatusCode::FAILURE;
  }
  QNN_DEBUG("ProfileEvents: [%p], numEvents: [%d]", profileEvents, numEvents);
  for (size_t event = 0; event < numEvents; event++) {
    extractProfilingEvent(*(profileEvents + event));
    extractProfilingSubEvents(*(profileEvents + event));
  }
  return StatusCode::SUCCESS;
}

sample_app::StatusCode sample_app::QnnSampleApp::extractProfilingSubEvents(
    QnnProfile_EventId_t profileEventId) {
  const QnnProfile_EventId_t *profileSubEvents{nullptr};
  uint32_t numSubEvents{0};
  if (QNN_PROFILE_NO_ERROR !=
      m_qnnFunctionPointers.qnnInterface.profileGetSubEvents(
          profileEventId, &profileSubEvents, &numSubEvents)) {
    QNN_ERROR("Failure in profile get sub events.");
    return StatusCode::FAILURE;
  }
  QNN_DEBUG("ProfileSubEvents: [%p], numSubEvents: [%d]", profileSubEvents,
            numSubEvents);
  for (size_t subEvent = 0; subEvent < numSubEvents; subEvent++) {
    extractProfilingEvent(*(profileSubEvents + subEvent));
    extractProfilingSubEvents(*(profileSubEvents + subEvent));
  }
  return StatusCode::SUCCESS;
}

sample_app::StatusCode sample_app::QnnSampleApp::extractProfilingEvent(
    QnnProfile_EventId_t profileEventId) {
  QnnProfile_EventData_t eventData;
  if (QNN_PROFILE_NO_ERROR !=
      m_qnnFunctionPointers.qnnInterface.profileGetEventData(profileEventId,
                                                             &eventData)) {
    QNN_ERROR("Failure in profile get event type.");
    return StatusCode::FAILURE;
  }
  QNN_DEBUG("Printing Event Info - Event Type: [%d], Event Value: [%" PRIu64
            "], Event Identifier: [%s], Event Unit: [%d]",
            eventData.type, eventData.value, eventData.identifier,
            eventData.unit);
  return StatusCode::SUCCESS;
}

sample_app::StatusCode
sample_app::QnnSampleApp::verifyFailReturnStatus(Qnn_ErrorHandle_t errCode) {
  auto returnStatus = sample_app::StatusCode::FAILURE;
  switch (errCode) {
  case QNN_COMMON_ERROR_SYSTEM_COMMUNICATION:
    returnStatus = sample_app::StatusCode::FAILURE_SYSTEM_COMMUNICATION_ERROR;
    break;
  case QNN_COMMON_ERROR_SYSTEM:
    returnStatus = sample_app::StatusCode::FAILURE_SYSTEM_ERROR;
    break;
  case QNN_COMMON_ERROR_NOT_SUPPORTED:
    returnStatus = sample_app::StatusCode::QNN_FEATURE_UNSUPPORTED;
    break;
  default:
    break;
  }
  return returnStatus;
}

sample_app::StatusCode sample_app::QnnSampleApp::isDevicePropertySupported() {
  if (nullptr != m_qnnFunctionPointers.qnnInterface.propertyHasCapability) {
    auto qnnStatus = m_qnnFunctionPointers.qnnInterface.propertyHasCapability(
        QNN_PROPERTY_GROUP_DEVICE);
    if (QNN_PROPERTY_NOT_SUPPORTED == qnnStatus) {
      QNN_WARN("Device property is not supported");
    }
    if (QNN_PROPERTY_ERROR_UNKNOWN_KEY == qnnStatus) {
      QNN_ERROR("Device property is not known to backend");
      return StatusCode::FAILURE;
    }
  }
  return StatusCode::SUCCESS;
}

sample_app::StatusCode sample_app::QnnSampleApp::createDevice() {
  if (nullptr != m_qnnFunctionPointers.qnnInterface.deviceCreate) {
    auto qnnStatus = m_qnnFunctionPointers.qnnInterface.deviceCreate(
        m_logHandle, (const QnnDevice_Config_t **)m_deviceConfig,
        &m_deviceHandle);
    if (QNN_SUCCESS != qnnStatus &&
        QNN_DEVICE_ERROR_UNSUPPORTED_FEATURE != qnnStatus) {
      QNN_ERROR("Failed to create device");
      return verifyFailReturnStatus(qnnStatus);
    }
  }
  return StatusCode::SUCCESS;
}

sample_app::StatusCode sample_app::QnnSampleApp::freeDevice() {
  if (nullptr != m_qnnFunctionPointers.qnnInterface.deviceFree) {
    auto qnnStatus =
        m_qnnFunctionPointers.qnnInterface.deviceFree(m_deviceHandle);
    if (QNN_SUCCESS != qnnStatus &&
        QNN_DEVICE_ERROR_UNSUPPORTED_FEATURE != qnnStatus) {
      QNN_ERROR("Failed to free device");
      return verifyFailReturnStatus(qnnStatus);
    }
  }
  return StatusCode::SUCCESS;
}

// executeGraphs() that is currently used by qnn-sample-app's main.cpp.
// This function runs all the graphs present in model.so by reading
// inputs from input_list based files and writes output to .raw files.
sample_app::StatusCode sample_app::QnnSampleApp::executeGraphs() {
  // 目前仅支持单图模式，添加断言保证只有一张图
  if (m_graphsCount != 1) {
    QNN_ERROR("Only single graph is supported in executeGraphs for now.");
    return StatusCode::FAILURE;
  }

  m_currentGraphIndex = 0;

  // 检查持久化张量的初始化状态
  if (m_currentGraphIndex != 0 || m_storedInputs == nullptr ||
      m_storedOutputs == nullptr) {
    QNN_ERROR(
        "Persistent tensors are not properly initialized for graph index 0. "
        "m_currentGraphIndex: %d, m_storedInputs: %p, m_storedOutputs: %p",
        m_currentGraphIndex, m_storedInputs, m_storedOutputs);
    return StatusCode::FAILURE;
  }

  auto returnStatus = StatusCode::SUCCESS;
  QNN_DEBUG("Starting execution for graph index 0");

  // 不再使用循环执行多次推理，只执行一次
  Qnn_ErrorHandle_t executeStatus =
      m_qnnFunctionPointers.qnnInterface.graphExecute(
          (*m_graphsInfo)[0].graph, m_storedInputs,
          (*m_graphsInfo)[0].numInputTensors, m_storedOutputs,
          (*m_graphsInfo)[0].numOutputTensors, m_profileBackendHandle, nullptr);
  if (QNN_GRAPH_NO_ERROR != executeStatus) {
    QNN_ERROR("Execution of graph failed");
    returnStatus = StatusCode::FAILURE;
  }

  // 注意：保持持久化张量和图信息，不释放以便后续获取输出数据
  return returnStatus;
}

// 修改 loadFloatInputs：不再内部初始化持久化张量，要求在调用前已完成初始化
sample_app::StatusCode sample_app::QnnSampleApp::loadFloatInputs(
    const std::vector<std::vector<float>> &inputData, int graphIdx) {
  if (static_cast<size_t>(graphIdx) >= m_graphsCount) {
    QNN_ERROR("Invalid graph index %d for loading float inputs.", graphIdx);
    return StatusCode::FAILURE;
  }

  QNN_INFO("numInputTensors: %d", (*m_graphsInfo)[graphIdx].numInputTensors);
  QNN_INFO("numOutputTensors: %d", (*m_graphsInfo)[graphIdx].numOutputTensors);
  QNN_INFO("graphName: %s", (*m_graphsInfo)[graphIdx].graphName);

  // 如果持久化张量未初始化或者图索引不匹配，则进行初始化
  if (m_storedInputs == nullptr || m_storedOutputs == nullptr ||
      m_currentGraphIndex != graphIdx) {
    QNN_INFO(
        "Persistent tensors not initialized for graphIdx: %d, initializing...",
        graphIdx);
    if (iotensor::StatusCode::SUCCESS !=
        m_ioTensor.setupInputAndOutputTensors(&m_storedInputs, &m_storedOutputs,
                                              (*m_graphsInfo)[graphIdx])) {
      QNN_ERROR("Error in setting up Input and output Tensors for graphIdx: %d",
                graphIdx);
      return StatusCode::FAILURE;
    }
  }
  QNN_INFO("m_storedInputs: %p", m_storedInputs);
  QNN_INFO("m_storedOutputs: %p", m_storedOutputs);

  uint32_t numInputs = (*m_graphsInfo)[graphIdx].numInputTensors;
  if (inputData.size() < numInputs) {
    QNN_ERROR("Provided input data count (%zu) is less than required input "
              "tensors (%d).",
              inputData.size(), numInputs);
    return StatusCode::FAILURE;
  }

  QNN_DEBUG("Loading float inputs for graphIdx: %d", graphIdx);
  for (uint32_t i = 0; i < numInputs; i++) {
    // 将 float 数据复制到持久化输入张量
    if (m_ioTensor.copyFromFloatToNative(
            const_cast<float *>(inputData[i].data()), &m_storedInputs[i]) !=
        iotensor::StatusCode::SUCCESS) {
      QNN_ERROR("Failed to copy float data to input tensor %d", i);
      return StatusCode::FAILURE;
    }
    // Debug：打印张量维度和部分数据
    std::vector<size_t> dims;
    if (m_ioTensor.fillDims(dims, QNN_TENSOR_GET_DIMENSIONS(m_storedInputs[i]),
                            QNN_TENSOR_GET_RANK(m_storedInputs[i])) ==
        iotensor::StatusCode::SUCCESS) {
      size_t numElements = datautil::calculateElementCount(dims);
      std::string dimsStr;
      for (size_t d : dims) {
        dimsStr += std::to_string(d) + " ";
      }
      QNN_DEBUG("Input tensor %d dimensions: %s", i, dimsStr.c_str());
      std::string sampleStr;
      for (size_t j = 0; j < std::min(numElements, (size_t)5); j++) {
        sampleStr += std::to_string(inputData[i][j]) + " ";
      }
      QNN_DEBUG("Input tensor %d first 5 elements: %s", i, sampleStr.c_str());
    } else {
      QNN_WARN("Could not retrieve dimensions for input tensor %d", i);
    }
  }

  QNN_INFO("All float inputs loaded for graphIdx: %d", graphIdx);
  return StatusCode::SUCCESS;
}

// 修改 getFloatOutputs：不再做懒初始化，而是直接使用持久化张量
sample_app::StatusCode sample_app::QnnSampleApp::getFloatOutputs(
    std::vector<std::vector<float>> &outputData, int graphIdx) {
  if (static_cast<size_t>(graphIdx) >= m_graphsCount) {
    QNN_ERROR("Invalid graph index %d for getting float outputs.", graphIdx);
    return StatusCode::FAILURE;
  }

  if (m_storedInputs == nullptr || m_storedOutputs == nullptr ||
      m_currentGraphIndex != graphIdx) {
    QNN_ERROR("Persistent tensors are not initialized for graphIdx: %d",
              graphIdx);
    return StatusCode::FAILURE;
  }

  uint32_t numOutputs = (*m_graphsInfo)[graphIdx].numOutputTensors;
  outputData.clear();
  outputData.resize(numOutputs);

  QNN_DEBUG("Retrieving float outputs for graphIdx: %d", graphIdx);
  for (uint32_t i = 0; i < numOutputs; i++) {
    float *floatBuffer = nullptr;
    if (m_ioTensor.convertToFloat(&floatBuffer, &m_storedOutputs[i]) !=
        iotensor::StatusCode::SUCCESS) {
      QNN_ERROR("Failed to convert output tensor %d to float", i);
      return StatusCode::FAILURE;
    }

    // 获取输出张量的维度信息，计算元素总数
    std::vector<size_t> dims;
    if (m_ioTensor.fillDims(dims, QNN_TENSOR_GET_DIMENSIONS(m_storedOutputs[i]),
                            QNN_TENSOR_GET_RANK(m_storedOutputs[i])) !=
        iotensor::StatusCode::SUCCESS) {
      QNN_ERROR("Failed to get dimensions for output tensor %d", i);
      return StatusCode::FAILURE;
    }
    size_t numElements = datautil::calculateElementCount(dims);

    std::string dimsStr;
    for (size_t d : dims) {
      dimsStr += std::to_string(d) + " ";
    }
    QNN_DEBUG("Output tensor %d dimensions: %s", i, dimsStr.c_str());

    std::string sampleStr;
    for (size_t j = 0; j < std::min(numElements, (size_t)5); j++) {
      sampleStr += std::to_string(floatBuffer[j]) + " ";
    }
    QNN_DEBUG("Output tensor %d first 5 elements: %s", i, sampleStr.c_str());

    std::vector<float> tensorData(floatBuffer, floatBuffer + numElements);
    outputData[i] = tensorData;
    free(floatBuffer); // 假设 convertToFloat 分配的内存需要释放
  }

  QNN_INFO("Float outputs retrieved for graphIdx: %d", graphIdx);

  // // 新增：释放持久化输入/输出张量，供后续重新初始化使用
  // m_ioTensor.tearDownInputAndOutputTensors(
  //     m_storedInputs, m_storedOutputs,
  //     (*m_graphsInfo)[graphIdx].numInputTensors,
  //     (*m_graphsInfo)[graphIdx].numOutputTensors);
  // m_storedInputs = nullptr;
  // m_storedOutputs = nullptr;
  // m_currentGraphIndex = -1;

  return StatusCode::SUCCESS;
}

// 添加缺失的initialize()方法实现
sample_app::StatusCode sample_app::QnnSampleApp::initialize() {
  throw std::runtime_error("initialize is deprecated!!!");
  // initialize是一个顶层接口，它组合了整个初始化流程
  auto returnStatus = StatusCode::SUCCESS;

  // 首先初始化后端
  returnStatus = initializeBackend();
  if (StatusCode::SUCCESS != returnStatus) {
    QNN_ERROR("Failed to initialize backend");
    return returnStatus;
  }

  // 注册Op包
  returnStatus = registerOpPackages();
  if (StatusCode::SUCCESS != returnStatus) {
    QNN_ERROR("Failed to register op packages");
    return returnStatus;
  }

  // 检查设备属性支持
  returnStatus = isDevicePropertySupported();
  if (StatusCode::SUCCESS != returnStatus) {
    QNN_ERROR("Device property is not supported");
    return returnStatus;
  }

  // 创建设备
  returnStatus = createDevice();
  if (StatusCode::SUCCESS != returnStatus) {
    QNN_ERROR("Failed to create device");
    return returnStatus;
  }

  // 如果是二进制模型，走从二进制创建的流程
  if (m_isBinaryModel) {
    returnStatus = createFromBinary();
    if (StatusCode::SUCCESS != returnStatus) {
      QNN_ERROR("Failed to create from binary");
      return returnStatus;
    }
  } else {
    // 创建上下文
    returnStatus = createContext();
    if (StatusCode::SUCCESS != returnStatus) {
      QNN_ERROR("Failed to create context");
      return returnStatus;
    }

    // 组合图
    returnStatus = composeGraphs();
    if (StatusCode::SUCCESS != returnStatus) {
      QNN_ERROR("Failed to compose graphs");
      return returnStatus;
    }

    // 完成图初始化
    returnStatus = finalizeGraphs();
    if (StatusCode::SUCCESS != returnStatus) {
      QNN_ERROR("Failed to finalize graphs");
      return returnStatus;
    }
  }

  return returnStatus;
}

// 添加缺失的freeGraphs()方法实现
// TODO: 之后删了
sample_app::StatusCode sample_app::QnnSampleApp::freeGraphs() {
  auto returnStatus = StatusCode::SUCCESS;

  // 释放图信息
  if (m_graphsInfo != nullptr) {
    qnn_wrapper_api::freeGraphsInfo(&m_graphsInfo, m_graphsCount);
    m_graphsInfo = nullptr;
    m_graphsCount = 0;
  }

  m_currentGraphIndex = -1;

  return returnStatus;
}

QnnDevice_PlatformInfo_t
sample_app::QnnSampleApp::getPlatformInfo(const std::string &backendPath) {
  // 加载function pointers
  QnnFunctionPointers qnnFunctionPointers;
  Qnn_BackendHandle_t backendHandle;
  void *modelHandle;
  auto dynStatus = dynamicloadutil::getQnnFunctionPointers(
      backendPath, "", &qnnFunctionPointers, &backendHandle, true,
      &modelHandle);
  std::string backendDir =
      std::filesystem::path(backendPath).parent_path().string();
  dynamicloadutil::getQnnSystemFunctionPointers(backendDir + "/libQnnSystem.so",
                                                &qnnFunctionPointers);
  // 调用qnnInterface.getPlatformInfo
  const QnnDevice_PlatformInfo_t *platformInfo;
  Qnn_ErrorHandle_t err =
      qnnFunctionPointers.qnnInterface.deviceGetPlatformInfo(nullptr,
                                                             &platformInfo);
  if (err != QNN_SUCCESS) {
    QNN_ERROR("Failed to get platform info");
    throw std::runtime_error("Failed to get platform info");
  }
  auto numDevices = platformInfo->v1.numHwDevices;
  QNN_INFO("numDevices: %d", numDevices);
  auto devices = platformInfo->v1.hwDevices;
  for (uint32_t i = 0; i < numDevices; i++) {
    QNN_INFO("Device %d: id = %d, type = %d, numCores = %d", i,
             devices[i].v1.deviceId, devices[i].v1.deviceType,
             devices[i].v1.numCores);
    auto cores = devices[i].v1.cores;
    for (uint32_t j = 0; j < devices[i].v1.numCores; j++) {
      QNN_INFO("Core %d: id = %d, type = %d, numThreads = %d", j,
               cores[j].v1.coreId, cores[j].v1.coreType);
    }
    if (devices[i].v1.deviceInfoExtension != nullptr) {
      QnnHtpDevice_DeviceInfoExtension_t *deviceInfoExtension =
          (QnnHtpDevice_DeviceInfoExtension_t *)devices[i]
              .v1.deviceInfoExtension;
      QNN_INFO("> deviceType: %d", deviceInfoExtension->devType);
      QNN_INFO("> arch: %d", deviceInfoExtension->onChipDevice.arch);
      // typedef enum {
      //   QNN_HTP_DEVICE_ARCH_NONE    = 0,
      //   QNN_HTP_DEVICE_ARCH_V68     = 68,
      //   QNN_HTP_DEVICE_ARCH_V69     = 69,
      //   QNN_HTP_DEVICE_ARCH_V73     = 73,
      //   QNN_HTP_DEVICE_ARCH_V75     = 75,
      //   QNN_HTP_DEVICE_ARCH_V79     = 79,
      //   QNN_HTP_DEVICE_ARCH_V81     = 81,
      //   QNN_HTP_DEVICE_ARCH_UNKNOWN = 0x7fffffff
      // } QnnHtpDevice_Arch_t;
      QNN_INFO("> socModel: %d", deviceInfoExtension->onChipDevice.socModel);
      QNN_INFO("> dlbcSupport: %d",
               deviceInfoExtension->onChipDevice.dlbcSupport);
      QNN_INFO("> signedPdSupport: %d",
               deviceInfoExtension->onChipDevice.signedPdSupport);
      QNN_INFO("> vtcmSize: %d", deviceInfoExtension->onChipDevice.vtcmSize);
    }
  }
  return *platformInfo;
}