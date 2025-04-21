#ifndef TOKENIZERS_C_H_
#define TOKENIZERS_C_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

// 错误码定义
typedef enum {
    TOKENIZERS_OK = 0,
    TOKENIZERS_ERROR = 1,
    TOKENIZERS_INVALID_ARGUMENT = 2,
    TOKENIZERS_OUT_OF_MEMORY = 3
} TokenizersStatus;

typedef enum {
    TOKENIZER_TYPE_HUGGINGFACE = 0,
    TOKENIZER_TYPE_SENTENCEPIECE = 1,
    TOKENIZER_TYPE_RWKV_WORLD = 2
} TokenizerType;

// Tokenizer句柄
typedef struct TokenizerHandle_* TokenizerHandle;

// 异步回调函数类型定义
typedef void (*TokenizerCallback)(TokenizersStatus status, TokenizerHandle handle, void* user_data);

// 创建tokenizer
TokenizersStatus TokenizerCreateFromFile(const char* model_path, TokenizerHandle* handle);
TokenizersStatus TokenizerCreateFromBlob(const char* blob, size_t blob_size, TokenizerType type, TokenizerHandle* handle);

// 异步创建tokenizer
void TokenizerCreateFromFileAsync(const char* model_path, TokenizerCallback callback, void* user_data);
void TokenizerCreateFromBlobAsync(const char* blob, size_t blob_size, TokenizerType type, TokenizerCallback callback, void* user_data);

// 销毁tokenizer
void TokenizerDestroy(TokenizerHandle handle);

// encode接口
TokenizersStatus TokenizerEncode(TokenizerHandle handle, 
                                const char* text,
                                int32_t* tokens,
                                size_t* num_tokens,
                                size_t max_tokens);

// decode接口
TokenizersStatus TokenizerDecode(TokenizerHandle handle,
                                const int32_t* tokens,
                                size_t num_tokens, 
                                char* text,
                                size_t* text_len);

TokenizersStatus TokenizerIdToToken(TokenizerHandle handle,
                                   int32_t id,
                                   char* token,
                                   size_t* token_len);

TokenizersStatus TokenizerTokenToId(TokenizerHandle handle,
                                   const char* token,
                                   int32_t* id);

TokenizersStatus TokenizerGetVocabSize(TokenizerHandle handle, size_t* vocab_size);

// 获取最后一次错误信息
const char* TokenizerGetLastError();

#ifdef __cplusplus
}
#endif

#endif  // TOKENIZERS_C_H_ 