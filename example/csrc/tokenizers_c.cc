#include "tokenizers_c.h"
#include <tokenizers_cpp.h>
#include <string>
#include <memory>
#include <vector>

#include <fstream>
#include <thread>

struct TokenizerHandle_ {
    std::unique_ptr<tokenizers::Tokenizer> tokenizer;
};

static thread_local std::string last_error;

static void SetLastError(const std::string& error) {
    last_error = error;
}

extern "C" {

TokenizersStatus TokenizerCreateFromFile(const char* model_path, TokenizerHandle* handle) {
    if (!model_path || !handle) {
        SetLastError("Invalid arguments");
        return TOKENIZERS_INVALID_ARGUMENT;
    }

    try {
        auto tokenizer_handle = new TokenizerHandle_();
        std::string blob_path(model_path);
        
        // 尝试推断tokenizer类型
        if (blob_path.find(".json") != std::string::npos) {
            // 读取文件内容
            std::ifstream fs(model_path, std::ios::in | std::ios::binary);
            if (fs.fail()) {
                SetLastError("Cannot open model file");
                delete tokenizer_handle;
                return TOKENIZERS_ERROR;
            }
            
            std::string data;
            fs.seekg(0, std::ios::end);
            size_t size = static_cast<size_t>(fs.tellg());
            fs.seekg(0, std::ios::beg);
            data.resize(size);
            fs.read(data.data(), size);
            
            tokenizer_handle->tokenizer = tokenizers::Tokenizer::FromBlobJSON(data);
        } else if (blob_path.find(".model") != std::string::npos) {
            // 读取文件内容
            std::ifstream fs(model_path, std::ios::in | std::ios::binary);
            if (fs.fail()) {
                SetLastError("Cannot open model file");
                delete tokenizer_handle;
                return TOKENIZERS_ERROR;
            }
            
            std::string data;
            fs.seekg(0, std::ios::end);
            size_t size = static_cast<size_t>(fs.tellg());
            fs.seekg(0, std::ios::beg);
            data.resize(size);
            fs.read(data.data(), size);
            
            tokenizer_handle->tokenizer = tokenizers::Tokenizer::FromBlobSentencePiece(data);
        } else {
            // 假设是RWKV World tokenizer
            tokenizer_handle->tokenizer = tokenizers::Tokenizer::FromBlobRWKVWorld(model_path);
        }
        
        if (!tokenizer_handle->tokenizer) {
            delete tokenizer_handle;
            SetLastError("Failed to load tokenizer");
            return TOKENIZERS_ERROR;
        }

        *handle = tokenizer_handle;
        return TOKENIZERS_OK;
    } catch (const std::bad_alloc&) {
        SetLastError("Out of memory");
        return TOKENIZERS_OUT_OF_MEMORY;
    } catch (const std::exception& e) {
        SetLastError(e.what());
        return TOKENIZERS_ERROR;
    }
}

TokenizersStatus TokenizerCreateFromBlob(const char* blob, size_t blob_size, TokenizerType type, TokenizerHandle* handle) {
    if (!blob || !handle || blob_size == 0) {
        SetLastError("Invalid arguments");
        return TOKENIZERS_INVALID_ARGUMENT;
    }

    try {
        auto tokenizer_handle = new TokenizerHandle_();
        std::string blob_data(blob, blob_size);
        
        switch (type) {
            case TOKENIZER_TYPE_HUGGINGFACE:
                tokenizer_handle->tokenizer = tokenizers::Tokenizer::FromBlobJSON(blob_data);
                break;
            case TOKENIZER_TYPE_SENTENCEPIECE:
                tokenizer_handle->tokenizer = tokenizers::Tokenizer::FromBlobSentencePiece(blob_data);
                break;
            case TOKENIZER_TYPE_RWKV_WORLD:
                // 注意: 这个API可能不能直接从内存blob创建
                SetLastError("RWKV World tokenizer must be loaded from file path");
                delete tokenizer_handle;
                return TOKENIZERS_ERROR;
            default:
                SetLastError("Unknown tokenizer type");
                delete tokenizer_handle;
                return TOKENIZERS_INVALID_ARGUMENT;
        }
        
        if (!tokenizer_handle->tokenizer) {
            delete tokenizer_handle;
            SetLastError("Failed to create tokenizer from blob");
            return TOKENIZERS_ERROR;
        }

        *handle = tokenizer_handle;
        return TOKENIZERS_OK;
    } catch (const std::bad_alloc&) {
        SetLastError("Out of memory");
        return TOKENIZERS_OUT_OF_MEMORY;
    } catch (const std::exception& e) {
        SetLastError(e.what());
        return TOKENIZERS_ERROR;
    }
}

void TokenizerDestroy(TokenizerHandle handle) {
    if (handle) {
        delete handle;
    }
}

TokenizersStatus TokenizerEncode(TokenizerHandle handle,
                                const char* text,
                                int32_t* tokens,
                                size_t* num_tokens,
                                size_t max_tokens) {
    if (!handle || !text || !tokens || !num_tokens) {
        SetLastError("Invalid arguments");
        return TOKENIZERS_INVALID_ARGUMENT;
    }

    try {
        std::vector<int> result = handle->tokenizer->Encode(text);
        
        if (result.size() > max_tokens) {
            SetLastError("Output buffer too small");
            return TOKENIZERS_ERROR;
        }

        *num_tokens = result.size();
        std::copy(result.begin(), result.end(), tokens);
        return TOKENIZERS_OK;
    } catch (const std::exception& e) {
        SetLastError(e.what());
        return TOKENIZERS_ERROR;
    }
}

TokenizersStatus TokenizerDecode(TokenizerHandle handle,
                                const int32_t* tokens,
                                size_t num_tokens,
                                char* text,
                                size_t* text_len) {
    if (!handle || !tokens || !text_len) {
        SetLastError("Invalid arguments");
        return TOKENIZERS_INVALID_ARGUMENT;
    }

    try {
        std::vector<int> token_vec(tokens, tokens + num_tokens);
        std::string result = handle->tokenizer->Decode(token_vec);
        
        if (text && *text_len >= result.size() + 1) {
            std::copy(result.begin(), result.end(), text);
            text[result.size()] = '\0';
        }
        *text_len = result.size() + 1;
        return TOKENIZERS_OK;
    } catch (const std::exception& e) {
        SetLastError(e.what());
        return TOKENIZERS_ERROR;
    }
}

TokenizersStatus TokenizerIdToToken(TokenizerHandle handle,
                                   int32_t id,
                                   char* token,
                                   size_t* token_len) {
    if (!handle || !token_len) {
        SetLastError("Invalid arguments");
        return TOKENIZERS_INVALID_ARGUMENT;
    }

    try {
        std::string result = handle->tokenizer->IdToToken(id);
        
        if (token && *token_len >= result.size() + 1) {
            std::copy(result.begin(), result.end(), token);
            token[result.size()] = '\0';
        }
        *token_len = result.size() + 1;
        return TOKENIZERS_OK;
    } catch (const std::exception& e) {
        SetLastError(e.what());
        return TOKENIZERS_ERROR;
    }
}

TokenizersStatus TokenizerTokenToId(TokenizerHandle handle,
                                   const char* token,
                                   int32_t* id) {
    if (!handle || !token || !id) {
        SetLastError("Invalid arguments");
        return TOKENIZERS_INVALID_ARGUMENT;
    }

    try {
        *id = handle->tokenizer->TokenToId(token);
        return TOKENIZERS_OK;
    } catch (const std::exception& e) {
        SetLastError(e.what());
        return TOKENIZERS_ERROR;
    }
}

TokenizersStatus TokenizerGetVocabSize(TokenizerHandle handle, size_t* vocab_size) {
    if (!handle || !vocab_size) {
        SetLastError("Invalid arguments");
        return TOKENIZERS_INVALID_ARGUMENT;
    }

    try {
        *vocab_size = handle->tokenizer->GetVocabSize();
        return TOKENIZERS_OK;
    } catch (const std::exception& e) {
        SetLastError(e.what());
        return TOKENIZERS_ERROR;
    }
}

const char* TokenizerGetLastError() {
    return last_error.c_str();
}

void TokenizerCreateFromFileAsync(const char* model_path, TokenizerCallback callback, void* user_data) {
    // 复制字符串参数，确保在新线程中使用时它们仍然有效
    std::string modelPathCopy(model_path ? model_path : "");
    
    std::thread([=, modelPathCopy = std::move(modelPathCopy)]() {
        TokenizerHandle handle = nullptr;
        TokenizersStatus status = TokenizerCreateFromFile(modelPathCopy.c_str(), &handle);
        
        if (callback) {
            callback(status, handle, user_data);
        }
    }).detach();
}

void TokenizerCreateFromBlobAsync(const char* blob, size_t blob_size, TokenizerType type, TokenizerCallback callback, void* user_data) {
    // 复制blob数据，确保在新线程中使用时它仍然有效
    std::string blobCopy;
    if (blob && blob_size > 0) {
        blobCopy.assign(blob, blob_size);
    }
    
    std::thread([=, blobCopy = std::move(blobCopy)]() {
        TokenizerHandle handle = nullptr;
        TokenizersStatus status = TokenizerCreateFromBlob(
            blobCopy.data(), 
            blobCopy.size(), 
            type, 
            &handle
        );
        
        if (callback) {
            callback(status, handle, user_data);
        }
    }).detach();
}

} 