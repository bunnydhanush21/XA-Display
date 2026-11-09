#ifndef XASEAL_H
#define XASEAL_H

#include <stddef.h>
#include <stdint.h>

/// Calls CommonCrypto AES-GCM. encrypt is 1 to seal and 0 to open. Returns 0 on success.
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
    int encrypt);

#endif
