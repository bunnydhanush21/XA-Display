#include "XASeal.h"

#include <CommonCrypto/CommonCryptor.h>

/* The oneshot GCM entry points ship in libsystem but are omitted from the Swift overlay. */
extern CCCryptorStatus CCCryptorGCMOneshotEncrypt(
    CCAlgorithm algorithm,
    const void *key,
    size_t keyLength,
    const void *iv,
    size_t ivLength,
    const void *aData,
    size_t aDataLength,
    const void *dataIn,
    size_t dataInLength,
    void *cipherOut,
    void *tagOut,
    size_t tagLength);

extern CCCryptorStatus CCCryptorGCMOneshotDecrypt(
    CCAlgorithm algorithm,
    const void *key,
    size_t keyLength,
    const void *iv,
    size_t ivLength,
    const void *aData,
    size_t aDataLength,
    const void *dataIn,
    size_t dataInLength,
    void *dataOut,
    const void *tag,
    size_t tagLength);

int xa_gcm_encrypt(
    const uint8_t *key,
    size_t keyLength,
    const uint8_t *nonce,
    size_t nonceLength,
    const uint8_t *aad,
    size_t aadLength,
    const uint8_t *input,
    size_t inputLength,
    uint8_t *output,
    uint8_t *tag,
    size_t tagLength,
    int encrypt)
{
    CCCryptorStatus status;
    if (encrypt) {
        status = CCCryptorGCMOneshotEncrypt(
            kCCAlgorithmAES, key, keyLength, nonce, nonceLength, aad, aadLength, input, inputLength, output, tag, tagLength);
    } else {
        status = CCCryptorGCMOneshotDecrypt(
            kCCAlgorithmAES, key, keyLength, nonce, nonceLength, aad, aadLength, input, inputLength, output, tag, tagLength);
    }
    return status == kCCSuccess ? 0 : (int)status;
}
