#ifndef SIM_ESP32_SIM_HAL_H_
#define SIM_ESP32_SIM_HAL_H_

#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// FreeRTOS basic types and constants
typedef uint32_t UBaseType_t;
typedef int32_t BaseType_t;
typedef uint32_t TickType_t;
typedef void *SemaphoreHandle_t;
typedef void *QueueHandle_t;
typedef void *TaskHandle_t;
typedef void (*TaskFunction_t)(void *);

#define pdTRUE ((BaseType_t)1)
#define pdFALSE ((BaseType_t)0)
#define portMAX_DELAY ((TickType_t)0xFFFFFFFFUL)
#define configMAX_PRIORITIES 25

// Arduino Serial config constants
#define SERIAL_8N1 0x800001cUL

// ESP-IDF error and interrupt types
typedef int esp_err_t;
#define ESP_OK 0
#define ESP_FAIL -1
#define ESP_INTR_FLAG_LEVEL1 (1 << 1)
#define I2S_PIN_NO_CHANGE (-1)

// ESP-IDF I2S types
typedef enum
{
  I2S_NUM_0 = 0,
  I2S_NUM_1 = 1
} i2s_port_t;

typedef enum
{
  I2S_MODE_MASTER = (1 << 0),
  I2S_MODE_SLAVE = (1 << 1),
  I2S_MODE_TX = (1 << 2),
  I2S_MODE_RX = (1 << 3)
} i2s_mode_t;

typedef enum
{
  I2S_BITS_PER_SAMPLE_16BIT = 16,
  I2S_BITS_PER_SAMPLE_24BIT = 24,
  I2S_BITS_PER_SAMPLE_32BIT = 32
} i2s_bits_per_sample_t;

typedef enum
{
  I2S_CHANNEL_FMT_RIGHT_LEFT = 0,
  I2S_CHANNEL_FMT_ALL_RIGHT = 1,
  I2S_CHANNEL_FMT_ALL_LEFT = 2,
  I2S_CHANNEL_FMT_ONLY_RIGHT = 3,
  I2S_CHANNEL_FMT_ONLY_LEFT = 4
} i2s_channel_fmt_t;

typedef enum
{
  I2S_COMM_FORMAT_STAND_I2S = 1,
  I2S_COMM_FORMAT_STAND_MSB = 2
} i2s_comm_format_t;

typedef struct
{
  i2s_mode_t mode;
  int sample_rate;
  i2s_bits_per_sample_t bits_per_sample;
  i2s_channel_fmt_t channel_format;
  i2s_comm_format_t communication_format;
  int intr_alloc_flags;
  int dma_buf_count;
  int dma_buf_len;
  bool use_apll;
  bool tx_desc_auto_clear;
} i2s_config_t;

typedef struct
{
  int mck_io_num;
  int bck_io_num;
  int ws_io_num;
  int data_out_num;
  int data_in_num;
} i2s_pin_config_t;

// Deterministic FreeRTOS Queue implementation
struct SimQueue
{
  uint8_t *storage;
  UBaseType_t capacity;
  UBaseType_t item_size;
  UBaseType_t head;
  UBaseType_t tail;
  UBaseType_t count;
  UBaseType_t high_water_mark;
  uint32_t overflow_count;
  uint32_t total_sent;
  uint32_t total_received;
};

struct SimMutex
{
  bool locked;
};

// Deterministic HardwareSerial implementation
class HardwareSerial
{
public:
  HardwareSerial()
      : rx_buf_(nullptr),
        rx_cap_(1024),
        rx_head_(0),
        rx_tail_(0),
        rx_count_(0),
        rx_overflows_(0),
        baud_(115200),
        quiet_(true)
  {
    allocateBuffer(1024);
  }

  ~HardwareSerial()
  {
    if (rx_buf_ != nullptr)
    {
      free(rx_buf_);
      rx_buf_ = nullptr;
    }
  }

  void setRxBufferSize(size_t size)
  {
    if (size > 0)
    {
      allocateBuffer(size);
    }
  }

  void begin(uint32_t baud, uint32_t config = SERIAL_8N1, int rxPin = -1,
             int txPin = -1)
  {
    (void)config;
    (void)rxPin;
    (void)txPin;
    baud_ = baud;
  }

  int available() const { return static_cast<int>(rx_count_); }

  int read()
  {
    if (rx_count_ == 0 || rx_buf_ == nullptr)
    {
      return -1;
    }
    uint8_t b = rx_buf_[rx_head_];
    rx_head_ = (rx_head_ + 1) % rx_cap_;
    rx_count_--;
    return static_cast<int>(b);
  }

  void print(const char *s)
  {
    if (!quiet_ && s != nullptr)
    {
      fputs(s, stderr);
    }
  }

  void println(const char *s)
  {
    if (!quiet_ && s != nullptr)
    {
      fprintf(stderr, "%s\n", s);
    }
  }

  bool pushRxByte(uint8_t b)
  {
    if (rx_buf_ == nullptr || rx_count_ >= rx_cap_)
    {
      rx_overflows_++;
      return false;
    }
    rx_buf_[rx_tail_] = b;
    rx_tail_ = (rx_tail_ + 1) % rx_cap_;
    rx_count_++;
    return true;
  }

  void clearRx()
  {
    rx_head_ = 0;
    rx_tail_ = 0;
    rx_count_ = 0;
    rx_overflows_ = 0;
  }

  void setQuiet(bool q) { quiet_ = q; }
  uint32_t rxOverflows() const { return rx_overflows_; }
  uint32_t baudRate() const { return baud_; }

private:
  void allocateBuffer(size_t cap)
  {
    if (rx_buf_ != nullptr)
    {
      free(rx_buf_);
    }
    rx_cap_ = cap;
    rx_buf_ = static_cast<uint8_t *>(malloc(rx_cap_));
    rx_head_ = 0;
    rx_tail_ = 0;
    rx_count_ = 0;
  }

  uint8_t *rx_buf_;
  size_t rx_cap_;
  size_t rx_head_;
  size_t rx_tail_;
  size_t rx_count_;
  uint32_t rx_overflows_;
  uint32_t baud_;
  bool quiet_;
};

// Global simulation state for ESP32 HAL
struct Esp32SimHalState
{
  TaskFunction_t audio_task_fn;
  jmp_buf i2s_jmp_buf;
  bool i2s_yield_active;
  bool i2s_initialized;
  i2s_config_t i2s_cfg;
  i2s_pin_config_t i2s_pins;
  void (*on_i2s_write_cb)(const int16_t *samples, size_t stereo_frames);
  void (*on_midi_enqueue_cb)(uint8_t status, uint8_t d1, uint8_t d2);
  void (*on_delay_ms_cb)(uint32_t ms);
  uint64_t total_i2s_frames;
  uint32_t vtask_delay_calls;
};

inline Esp32SimHalState &sim_hal_state()
{
  static Esp32SimHalState st = {
      nullptr, {}, false, false, {}, {}, nullptr, nullptr, nullptr, 0, 0};
  return st;
}

inline HardwareSerial &sim_serial0()
{
  static HardwareSerial s0;
  return s0;
}

inline HardwareSerial &sim_serial1()
{
  static HardwareSerial s1;
  return s1;
}

#define Serial (sim_serial0())
#define Serial1 (sim_serial1())

inline void sim_step_audio_block()
{
  Esp32SimHalState &st = sim_hal_state();
  if (st.audio_task_fn != nullptr)
  {
    st.i2s_yield_active = true;
    if (setjmp(st.i2s_jmp_buf) == 0)
    {
      st.audio_task_fn(nullptr);
    }
    st.i2s_yield_active = false;
  }
}

inline void delay(uint32_t ms)
{
  Esp32SimHalState &st = sim_hal_state();
  if (st.on_delay_ms_cb != nullptr)
  {
    st.on_delay_ms_cb(ms);
  }
  else if (st.audio_task_fn != nullptr && st.i2s_cfg.sample_rate > 0 &&
           st.i2s_cfg.dma_buf_len > 0)
  {
    // Advance audio synthesis tasks proportionally during setup() delays
    uint32_t total_frames =
        (ms * static_cast<uint32_t>(st.i2s_cfg.sample_rate)) / 1000U;
    uint32_t block_len = static_cast<uint32_t>(st.i2s_cfg.dma_buf_len);
    uint32_t blocks = (total_frames + block_len - 1U) / block_len;
    for (uint32_t i = 0; i < blocks; ++i)
    {
      sim_step_audio_block();
    }
  }
}

inline void vTaskDelay(TickType_t ticks)
{
  (void)ticks;
  sim_hal_state().vtask_delay_calls++;
}

inline SemaphoreHandle_t xSemaphoreCreateMutex()
{
  SimMutex *m = static_cast<SimMutex *>(malloc(sizeof(SimMutex)));
  if (m != nullptr)
  {
    m->locked = false;
  }
  return static_cast<SemaphoreHandle_t>(m);
}

inline BaseType_t xSemaphoreTake(SemaphoreHandle_t xSemaphore,
                                 TickType_t xBlockTime)
{
  (void)xBlockTime;
  SimMutex *m = static_cast<SimMutex *>(xSemaphore);
  if (m == nullptr)
  {
    return pdFALSE;
  }
  m->locked = true;
  return pdTRUE;
}

inline BaseType_t xSemaphoreGive(SemaphoreHandle_t xSemaphore)
{
  SimMutex *m = static_cast<SimMutex *>(xSemaphore);
  if (m == nullptr)
  {
    return pdFALSE;
  }
  m->locked = false;
  return pdTRUE;
}

inline QueueHandle_t xQueueCreate(UBaseType_t uxQueueLength,
                                  UBaseType_t uxItemSize)
{
  SimQueue *q = static_cast<SimQueue *>(malloc(sizeof(SimQueue)));
  if (q == nullptr)
  {
    return nullptr;
  }
  q->storage = static_cast<uint8_t *>(malloc(uxQueueLength * uxItemSize));
  q->capacity = uxQueueLength;
  q->item_size = uxItemSize;
  q->head = 0;
  q->tail = 0;
  q->count = 0;
  q->high_water_mark = 0;
  q->overflow_count = 0;
  q->total_sent = 0;
  q->total_received = 0;
  return static_cast<QueueHandle_t>(q);
}

inline BaseType_t xQueueSend(QueueHandle_t xQueue, const void *pvItemToQueue,
                             TickType_t xTicksToWait)
{
  (void)xTicksToWait;
  SimQueue *q = static_cast<SimQueue *>(xQueue);
  if (q == nullptr || q->storage == nullptr || pvItemToQueue == nullptr)
  {
    return pdFALSE;
  }
  if (q->count >= q->capacity)
  {
    q->overflow_count++;
    return pdFALSE;
  }
  memcpy(q->storage + (q->tail * q->item_size), pvItemToQueue, q->item_size);
  q->tail = (q->tail + 1U) % q->capacity;
  q->count++;
  q->total_sent++;
  if (q->count > q->high_water_mark)
  {
    q->high_water_mark = q->count;
  }
  if (q->item_size == 3 && sim_hal_state().on_midi_enqueue_cb != nullptr)
  {
    const uint8_t *raw = static_cast<const uint8_t *>(pvItemToQueue);
    sim_hal_state().on_midi_enqueue_cb(raw[0], raw[1], raw[2]);
  }
  return pdTRUE;
}

inline BaseType_t xQueueReceive(QueueHandle_t xQueue, void *pvBuffer,
                                TickType_t xTicksToWait)
{
  (void)xTicksToWait;
  SimQueue *q = static_cast<SimQueue *>(xQueue);
  if (q == nullptr || q->storage == nullptr || pvBuffer == nullptr ||
      q->count == 0)
  {
    return pdFALSE;
  }
  memcpy(pvBuffer, q->storage + (q->head * q->item_size), q->item_size);
  q->head = (q->head + 1U) % q->capacity;
  q->count--;
  q->total_received++;
  return pdTRUE;
}

inline BaseType_t xTaskCreatePinnedToCore(TaskFunction_t pvTaskCode,
                                          const char *const pcName,
                                          const uint32_t usStackDepth,
                                          void *const pvParameters,
                                          UBaseType_t uxPriority,
                                          TaskHandle_t *const pvCreatedTask,
                                          const BaseType_t xCoreID)
{
  (void)pcName;
  (void)usStackDepth;
  (void)pvParameters;
  (void)uxPriority;
  (void)pvCreatedTask;
  (void)xCoreID;
  sim_hal_state().audio_task_fn = pvTaskCode;
  return pdTRUE;
}

inline esp_err_t i2s_driver_install(i2s_port_t i2s_num,
                                    const i2s_config_t *i2s_config,
                                    int queue_size, void *i2s_queue)
{
  (void)i2s_num;
  (void)queue_size;
  (void)i2s_queue;
  if (i2s_config == nullptr)
  {
    return ESP_FAIL;
  }
  sim_hal_state().i2s_cfg = *i2s_config;
  sim_hal_state().i2s_initialized = true;
  return ESP_OK;
}

inline esp_err_t i2s_set_pin(i2s_port_t i2s_num, const i2s_pin_config_t *pin)
{
  (void)i2s_num;
  if (pin == nullptr)
  {
    return ESP_FAIL;
  }
  sim_hal_state().i2s_pins = *pin;
  return ESP_OK;
}

inline esp_err_t i2s_zero_dma_buffer(i2s_port_t i2s_num)
{
  (void)i2s_num;
  return ESP_OK;
}

inline esp_err_t i2s_write(i2s_port_t i2s_num, const void *src, size_t size,
                           size_t *bytes_written, TickType_t ticks_to_wait)
{
  (void)i2s_num;
  (void)ticks_to_wait;
  if (src == nullptr)
  {
    return ESP_FAIL;
  }
  if (bytes_written != nullptr)
  {
    *bytes_written = size;
  }
  size_t stereo_frames = size / (2U * sizeof(int16_t));
  Esp32SimHalState &st = sim_hal_state();
  st.total_i2s_frames += stereo_frames;
  if (st.on_i2s_write_cb != nullptr)
  {
    st.on_i2s_write_cb(static_cast<const int16_t *>(src), stereo_frames);
  }
  if (st.i2s_yield_active)
  {
    longjmp(st.i2s_jmp_buf, 1);
  }
  return ESP_OK;
}

#endif // SIM_ESP32_SIM_HAL_H_
