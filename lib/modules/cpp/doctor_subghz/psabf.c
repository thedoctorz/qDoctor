#include "psabf.h"

#if defined(_WIN32) && !defined(__MINGW32__)
#include "../hardnested/pthread_shim.h"
#else
#include <pthread.h>
#endif
#include <stdatomic.h>
#include <string.h>

#ifdef __APPLE__
#include <dispatch/dispatch.h>
#include <unistd.h>
#endif

#define TEA_DELTA   0x9E3779B9U
#define TEA_ROUNDS  32
#define PSA_BF_CHUNK 65536U

#define PSA_BF1_CONST_U4 0x0E0F5C41U
#define PSA_BF1_CONST_U5 0x0F5C4123U

static const uint32_t PSA_BF1_KEY_SCHEDULE[4] = {
    0x4A434915U,
    0xD6743C2BU,
    0x1F29D308U,
    0xE6B79A64U,
};

static const uint32_t PSA_BF2_KEY_SCHEDULE[4] = {
    0x4039C240U,
    0xEDA92CABU,
    0x4306C02AU,
    0x02192A04U,
};

typedef struct {
    uint32_t s0[TEA_ROUNDS];
    uint32_t s1[TEA_ROUNDS];
} PsaTeaSchedule;

static void psa_tea_build_schedule(const uint32_t* key, PsaTeaSchedule* out) {
    for(int i = 0; i < TEA_ROUNDS; i++) {
        uint32_t sum0 = (uint32_t)((uint64_t)i * TEA_DELTA);
        uint32_t sum1 = (uint32_t)((uint64_t)(i + 1) * TEA_DELTA);
        out->s0[i] = key[sum0 & 3] + sum0;
        out->s1[i] = key[(sum1 >> 11) & 3] + sum1;
    }
}

static inline void
    psa_tea_encrypt_with_schedule(uint32_t* v0, uint32_t* v1, const PsaTeaSchedule* sched) {
    uint32_t a = *v0;
    uint32_t b = *v1;
    for(int i = 0; i < TEA_ROUNDS; i++) {
        a += (sched->s0[i] ^ (((b >> 5) ^ (b << 4)) + b));
        b += (sched->s1[i] ^ (((a >> 5) ^ (a << 4)) + a));
    }
    *v0 = a;
    *v1 = b;
}

static inline void psa_tea_encrypt(uint32_t* v0, uint32_t* v1, const uint32_t* key) {
    uint32_t sum = 0;
    for(int i = 0; i < TEA_ROUNDS; i++) {
        uint32_t k_idx1 = sum & 3;
        uint32_t temp = key[k_idx1] + sum;
        sum = sum + TEA_DELTA;
        *v0 = *v0 + (temp ^ (((*v1 >> 5) ^ (*v1 << 4)) + *v1));
        uint32_t k_idx2 = (sum >> 11) & 3;
        temp = key[k_idx2] + sum;
        *v1 = *v1 + (temp ^ (((*v0 >> 5) ^ (*v0 << 4)) + *v0));
    }
}

static inline void psa_tea_decrypt(uint32_t* v0, uint32_t* v1, const uint32_t* key) {
    uint32_t a = *v0;
    uint32_t b = *v1;
    const uint32_t k[4] = {key[0], key[1], key[2], key[3]};
    uint32_t sum = TEA_DELTA * TEA_ROUNDS;
    for(int i = 0; i < TEA_ROUNDS; i++) {
        uint32_t temp = k[(sum >> 11) & 3] + sum;
        sum = sum - TEA_DELTA;
        b = b - (temp ^ (((a >> 5) ^ (a << 4)) + a));
        temp = k[sum & 3] + sum;
        a = a - (temp ^ (((b >> 5) ^ (b << 4)) + b));
    }
    *v0 = a;
    *v1 = b;
}

static uint8_t psa_tea_crc(uint32_t v0, uint32_t v1) {
    uint32_t crc = ((v0 >> 24) & 0xFF) + ((v0 >> 16) & 0xFF) + ((v0 >> 8) & 0xFF) + (v0 & 0xFF);
    crc += ((v1 >> 24) & 0xFF) + ((v1 >> 16) & 0xFF) + ((v1 >> 8) & 0xFF);
    return (uint8_t)(crc & 0xFF);
}

static uint16_t psa_crc16_bf2(uint32_t dec_v0, uint32_t dec_v1) {
    uint8_t bytes[6] = {
        (uint8_t)((dec_v0 >> 24) & 0xFF),
        (uint8_t)((dec_v0 >> 8) & 0xFF),
        (uint8_t)((dec_v0 >> 16) & 0xFF),
        (uint8_t)(dec_v0 & 0xFF),
        (uint8_t)((dec_v1 >> 24) & 0xFF),
        (uint8_t)((dec_v1 >> 16) & 0xFF),
    };
    uint16_t crc = 0;
    for(int i = 0; i < 6; i++) {
        crc = crc ^ ((uint16_t)bytes[i] << 8);
        for(int j = 0; j < 8; j++) {
            if(crc & 0x8000) {
                crc = (uint16_t)((crc << 1) ^ 0x8005);
            } else {
                crc = (uint16_t)(crc << 1);
            }
        }
    }
    return crc;
}

void psa_bf_setup_cipher(
    uint32_t key1_low,
    uint32_t key1_high,
    uint16_t key2_low,
    uint32_t* w0,
    uint32_t* w1) {
    uint8_t buffer[10];
    for(int i = 0; i < 8; i++) {
        int shift = i * 8;
        uint8_t byte_val;
        if(shift < 32) {
            byte_val = (uint8_t)((key1_low >> shift) & 0xFF);
        } else {
            byte_val = (uint8_t)((key1_high >> (shift - 32)) & 0xFF);
        }
        buffer[7 - i] = byte_val;
    }
    buffer[9] = (uint8_t)(key2_low & 0xFF);
    buffer[8] = (uint8_t)((key2_low >> 8) & 0xFF);
    *w0 = ((uint32_t)buffer[3] << 16) | ((uint32_t)buffer[2] << 24) | ((uint32_t)buffer[4] << 8) |
          (uint32_t)buffer[5];
    *w1 = ((uint32_t)buffer[7] << 16) | ((uint32_t)buffer[6] << 24) | ((uint32_t)buffer[8] << 8) |
          (uint32_t)buffer[9];
}

void psa_bf_fill_result(uint32_t v0, uint32_t v1, PsaBfResult* out) {
    uint8_t buffer[10];
    buffer[2] = (uint8_t)((v0 >> 24) & 0xFF);
    buffer[3] = (uint8_t)((v0 >> 16) & 0xFF);
    buffer[4] = (uint8_t)((v0 >> 8) & 0xFF);
    buffer[5] = (uint8_t)(v0 & 0xFF);
    buffer[6] = (uint8_t)((v1 >> 24) & 0xFF);
    buffer[7] = (uint8_t)((v1 >> 16) & 0xFF);
    buffer[8] = (uint8_t)((v1 >> 8) & 0xFF);
    buffer[9] = (uint8_t)(v1 & 0xFF);
    out->button = (buffer[5] >> 4) & 0xF;
    out->serial = ((uint32_t)buffer[3] << 8) | ((uint32_t)buffer[2] << 16) | (uint32_t)buffer[4];
    out->counter = ((uint32_t)buffer[7] << 8) | ((uint32_t)buffer[6] << 16) | (uint32_t)buffer[8] |
                    (((uint32_t)buffer[5] & 0xF) << 24);
    out->crc = (uint16_t)buffer[9];
    out->seed = out->serial;
    out->type = PSA_BF_TYPE_TEA;
}

void psa_bf_encode_mode36(
    uint32_t serial,
    uint8_t button,
    uint32_t counter,
    uint16_t crc,
    uint32_t* key1_high,
    uint32_t* key1_low,
    uint16_t* key2_low) {
    uint32_t v0 = ((serial & 0xFFFFFF) << 8) | ((uint32_t)(button & 0xF) << 4) |
                  ((counter >> 24) & 0xF);
    uint32_t v1 = ((counter & 0xFFFFFF) << 8) | (crc & 0xFF);
    uint8_t tea_crc = psa_tea_crc(v0, v1);
    v1 = (v1 & 0xFFFFFF00U) | tea_crc;

    uint32_t bf_counter = PSA_BF_BF1_START | (serial & 0xFFFFFF);
    uint32_t wk2 = PSA_BF1_CONST_U4;
    uint32_t wk3 = bf_counter;
    psa_tea_encrypt(&wk2, &wk3, PSA_BF1_KEY_SCHEDULE);
    uint32_t wk0 = (bf_counter << 8) | 0x0E;
    uint32_t wk1 = PSA_BF1_CONST_U5;
    psa_tea_encrypt(&wk0, &wk1, PSA_BF1_KEY_SCHEDULE);
    uint32_t working_key[4] = {wk0, wk1, wk2, wk3};
    psa_tea_encrypt(&v0, &v1, working_key);

    uint8_t buffer[10] = {0};
    buffer[2] = (uint8_t)((v0 >> 24) & 0xFF);
    buffer[3] = (uint8_t)((v0 >> 16) & 0xFF);
    buffer[4] = (uint8_t)((v0 >> 8) & 0xFF);
    buffer[5] = (uint8_t)(v0 & 0xFF);
    buffer[6] = (uint8_t)((v1 >> 24) & 0xFF);
    buffer[7] = (uint8_t)((v1 >> 16) & 0xFF);
    buffer[8] = (uint8_t)((v1 >> 8) & 0xFF);
    buffer[9] = (uint8_t)(v1 & 0xFF);
    buffer[0] = (uint8_t)(buffer[2] ^ buffer[6]);
    buffer[1] = (uint8_t)(buffer[3] ^ buffer[7]);

    *key1_high = ((uint32_t)buffer[0] << 24) | ((uint32_t)buffer[1] << 16) |
                  ((uint32_t)buffer[2] << 8) | (uint32_t)buffer[3];
    *key1_low = ((uint32_t)buffer[4] << 24) | ((uint32_t)buffer[5] << 16) |
                 ((uint32_t)buffer[6] << 8) | (uint32_t)buffer[7];
    *key2_low = (uint16_t)(((uint16_t)buffer[8] << 8) | (uint16_t)buffer[9]);
}

typedef struct {
    uint32_t w0;
    uint32_t w1;
    PsaTeaSchedule sched;
    _Atomic int found;
    _Atomic uint32_t progress;
    volatile int* cancel;
    void (*progress_cb)(uint32_t done, uint32_t total, void* ctx);
    void* ctx;
    uint32_t total;
    uint32_t found_v0;
    uint32_t found_v1;
    pthread_mutex_t result_lock;
} PsaBfSearch;

static int psa_bf_cancelled(const PsaBfSearch* s) {
    return (s->cancel && *s->cancel) || atomic_load_explicit(&s->found, memory_order_relaxed);
}

static void psa_bf_report_progress(PsaBfSearch* s, uint32_t add) {
    uint32_t done = atomic_fetch_add_explicit(&s->progress, add, memory_order_relaxed) + add;
    if(s->progress_cb && ((done & 0x3FFFFU) == 0 || done >= s->total)) {
        uint32_t report = done > s->total ? s->total : done;
        s->progress_cb(report, s->total, s->ctx);
    }
}

static int psa_bf1_try(PsaBfSearch* s, uint32_t counter, uint32_t* v0, uint32_t* v1) {
    uint32_t wk2 = PSA_BF1_CONST_U4;
    uint32_t wk3 = counter;
    psa_tea_encrypt_with_schedule(&wk2, &wk3, &s->sched);
    uint32_t wk0 = (counter << 8) | 0x0E;
    uint32_t wk1 = PSA_BF1_CONST_U5;
    psa_tea_encrypt_with_schedule(&wk0, &wk1, &s->sched);
    uint32_t working_key[4] = {wk0, wk1, wk2, wk3};
    uint32_t dec_v0 = s->w0;
    uint32_t dec_v1 = s->w1;
    psa_tea_decrypt(&dec_v0, &dec_v1, working_key);
    if((counter & 0xFFFFFFU) != (dec_v0 >> 8)) {
        return 0;
    }
    if(psa_tea_crc(dec_v0, dec_v1) != (dec_v1 & 0xFF)) {
        return 0;
    }
    *v0 = dec_v0;
    *v1 = dec_v1;
    return 1;
}

static int psa_bf2_try(PsaBfSearch* s, uint32_t counter, uint32_t* v0, uint32_t* v1) {
    uint32_t working_key[4] = {
        PSA_BF2_KEY_SCHEDULE[0] ^ counter,
        PSA_BF2_KEY_SCHEDULE[1] ^ counter,
        PSA_BF2_KEY_SCHEDULE[2] ^ counter,
        PSA_BF2_KEY_SCHEDULE[3] ^ counter,
    };
    uint32_t dec_v0 = s->w0;
    uint32_t dec_v1 = s->w1;
    psa_tea_decrypt(&dec_v0, &dec_v1, working_key);
    if((counter & 0xFFFFFFU) != (dec_v0 >> 8)) {
        return 0;
    }
    if(psa_crc16_bf2(dec_v0, dec_v1) != (uint16_t)(dec_v1 & 0xFFFF)) {
        return 0;
    }
    *v0 = dec_v0;
    *v1 = dec_v1;
    return 1;
}

static void psa_bf_mark_found(PsaBfSearch* s, uint32_t v0, uint32_t v1) {
    if(atomic_load_explicit(&s->found, memory_order_relaxed)) {
        return;
    }
    pthread_mutex_lock(&s->result_lock);
    if(!atomic_load_explicit(&s->found, memory_order_relaxed)) {
        s->found_v0 = v0;
        s->found_v1 = v1;
        atomic_store_explicit(&s->found, 1, memory_order_release);
    }
    pthread_mutex_unlock(&s->result_lock);
}

static void psa_bf_range_bf1(PsaBfSearch* s, uint32_t start, uint32_t end) {
    uint32_t v0 = 0;
    uint32_t v1 = 0;
    for(uint32_t counter = start; counter < end; counter++) {
        if((counter & (PSA_BF_CHUNK - 1U)) == 0 && psa_bf_cancelled(s)) {
            return;
        }
        if(psa_bf1_try(s, counter, &v0, &v1)) {
            psa_bf_mark_found(s, v0, v1);
            return;
        }
    }
}

static void psa_bf_range_bf2(PsaBfSearch* s, uint32_t start, uint32_t end) {
    uint32_t v0 = 0;
    uint32_t v1 = 0;
    for(uint32_t counter = start; counter < end; counter++) {
        if((counter & (PSA_BF_CHUNK - 1U)) == 0 && psa_bf_cancelled(s)) {
            return;
        }
        if(psa_bf2_try(s, counter, &v0, &v1)) {
            psa_bf_mark_found(s, v0, v1);
            return;
        }
    }
}

#ifdef __APPLE__
static void psa_bf_parallel(
    PsaBfSearch* s,
    uint32_t range_start,
    uint32_t range_end,
    void (*body)(PsaBfSearch*, uint32_t, uint32_t)) {
    uint32_t span = range_end - range_start;
    uint32_t nchunks = (span + PSA_BF_CHUNK - 1U) / PSA_BF_CHUNK;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_apply(nchunks, q, ^(size_t i) {
        if(psa_bf_cancelled(s)) {
            return;
        }
        uint32_t start = range_start + (uint32_t)i * PSA_BF_CHUNK;
        uint32_t end = start + PSA_BF_CHUNK;
        if(end > range_end) {
            end = range_end;
        }
        body(s, start, end);
        psa_bf_report_progress(s, end - start);
    });
}
#else
static void psa_bf_parallel(
    PsaBfSearch* s,
    uint32_t range_start,
    uint32_t range_end,
    void (*body)(PsaBfSearch*, uint32_t, uint32_t)) {
    body(s, range_start, range_end);
    psa_bf_report_progress(s, range_end - range_start);
}
#endif

int psa_bf_recover_cpu(
    const PsaBfRequest* req,
    PsaBfResult* out,
    const PsaBfOptions* opts) {
    if(!req || !out) {
        return 0;
    }
    memset(out, 0, sizeof(*out));

    PsaBfSearch s;
    memset(&s, 0, sizeof(s));
    psa_bf_setup_cipher(req->key1_low, req->key1_high, req->key2_low, &s.w0, &s.w1);
    psa_tea_build_schedule(PSA_BF1_KEY_SCHEDULE, &s.sched);
    atomic_init(&s.found, 0);
    atomic_init(&s.progress, 0);
    s.cancel = opts ? opts->cancel : NULL;
    s.progress_cb = opts ? opts->progress : NULL;
    s.ctx = opts ? opts->ctx : NULL;
    s.total = (PSA_BF_BF1_END - PSA_BF_BF1_START) + (PSA_BF_BF2_END - PSA_BF_BF2_START);
    pthread_mutex_init(&s.result_lock, NULL);

    psa_bf_parallel(&s, PSA_BF_BF1_START, PSA_BF_BF1_END, psa_bf_range_bf1);
    if(!atomic_load(&s.found) && !(s.cancel && *s.cancel)) {
        psa_bf_parallel(&s, PSA_BF_BF2_START, PSA_BF_BF2_END, psa_bf_range_bf2);
    }
    out->states_tried = atomic_load(&s.progress);
    int found = atomic_load(&s.found);
    int cancelled = s.cancel && *s.cancel;
    pthread_mutex_destroy(&s.result_lock);
    if(found) {
        psa_bf_fill_result(s.found_v0, s.found_v1, out);
        return 1;
    }
    if(cancelled) {
        return -1;
    }
    return 0;
}
