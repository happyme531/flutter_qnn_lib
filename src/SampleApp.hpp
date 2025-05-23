//==============================================================================
//
//  Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
//  All rights reserved.
//  Confidential and Proprietary - Qualcomm Technologies, Inc.
//
//==============================================================================

#pragma once

#include "QnnInterface.h"
#include "QnnWrapperUtils.hpp"
#include "System/QnnSystemInterface.h"

namespace qnn {
namespace tools {
namespace sample_app {

// Graph Related Function Handle Types
typedef qnn_wrapper_api::ModelError_t (*ComposeGraphsFnHandleType_t)(
    Qnn_BackendHandle_t,
    QNN_INTERFACE_VER_TYPE,
    Qnn_ContextHandle_t,
    const qnn_wrapper_api::GraphConfigInfo_t **,
    const uint32_t,
    qnn_wrapper_api::GraphInfo_t ***,
    uint32_t *,
    bool,
    QnnLog_Callback_t,
    QnnLog_Level_t);
typedef qnn_wrapper_api::ModelError_t (*FreeGraphInfoFnHandleType_t)(
    qnn_wrapper_api::GraphInfo_t ***, uint32_t);

typedef struct QnnFunctionPointers {
  ComposeGraphsFnHandleType_t composeGraphsFnHandle;
  FreeGraphInfoFnHandleType_t freeGraphInfoFnHandle;
  QNN_INTERFACE_VER_TYPE qnnInterface;
  QNN_SYSTEM_INTERFACE_VER_TYPE qnnSystemInterface;
} QnnFunctionPointers;

}  // namespace sample_app
}  // namespace tools
}  // namespace qnn
