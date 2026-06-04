# Buddy 硬件基础信息

本文件用于沉淀当前项目的开发板基础配置，避免重复检索。固件默认 profile 是 `Waveshare ESP32-S3-LCD-1.54`，旧的 `Waveshare ESP32-C6-LCD-1.47` 仍可通过编译宏保留。

## 1) 默认开发板信息

- 板型：`Waveshare ESP32-S3-LCD-1.54`
- 主控：`ESP32-S3R8`
- 无线：`2.4GHz Wi-Fi` + `BLE 5`
- 存储：`16MB Flash` + `8MB PSRAM`
- 屏幕：`1.54" TFT`，`240x240`，驱动 `ST7789`
- 其他：板载 `PLUS`、`PWR`、`BOOT`、`RESET`、`Micro SD`、`QMI8658`、音频 Codec/功放、双麦克风、电池接口

## 2) 默认 S3 profile 引脚（板载固定）

- `MOSI = GPIO39`
- `SCLK = GPIO38`
- `CS   = GPIO21`
- `DC   = GPIO45`
- `RST  = GPIO40`
- `BL   = GPIO46`（背光）
- `BTN  = GPIO4`（板载 `PLUS` 键，`INPUT_PULLUP`）
- `BAT_EN = GPIO2`（电池供电保持，高电平）
- `PWR  = GPIO5`（板载 `PWR` 键，运行中长按关机）
- 默认 `LCD_ROT = 2`，整体显示相对原厂示例旋转 180 度

> 说明：这些是板载屏幕连接，通常不建议改动。

## 3) 旧 C6 profile 引脚

如需临时回到旧开发板，编译时增加：

```bash
--build-property compiler.cpp.extra_flags=-DBUDDY_BOARD_ESP32_C6_LCD_1_47
```

旧 C6 profile 参数：

- 板型：`Waveshare ESP32-C6-LCD-1.47`
- 屏幕：`172x320`，`ST7789`
- `MOSI = GPIO6`
- `SCLK = GPIO7`
- `CS   = GPIO14`
- `DC   = GPIO15`
- `RST  = GPIO21`
- `BL   = GPIO22`
- `BTN  = GPIO9`（板载 `BOOT` 键）

## 4) Arduino 环境要点

### 必装库

- `Adafruit GFX Library`
- `Adafruit ST7735 and ST7789 Library`
- `Adafruit BusIO`

### 开发板设置建议

- 开发板：`ESP32S3 Dev Module`
- `USB CDC On Boot = Enabled`（若串口异常可优先检查）
- `CPU Frequency = 240MHz`
- `Flash Size = 16MB`
- `PSRAM = QSPI PSRAM`
- `Partition Scheme = Huge APP (3MB No OTA/1MB SPIFFS)`

### 上传模式提示

若出现无法进入下载：

1. 按住 `BOOT`
2. 点按 `RESET`
3. 松开 `BOOT`
4. 再执行上传

## 5) 屏幕点亮关键点（本项目已踩坑）

使用 Adafruit ST7789 时，要显式绑定 SPI 引脚：

```cpp
SPI.begin(38, -1, 39, 21);
tft.init(240, 240);
tft.invertDisplay(true);
```

背光极性可能因板子/代码不同而不同，可用开关参数快速切换：

```cpp
constexpr bool BACKLIGHT_ACTIVE_HIGH = true; // 不亮可改 false
digitalWrite(TFT_BL, BACKLIGHT_ACTIVE_HIGH ? HIGH : LOW);
```

如果使用电池供电，S3 1.54 需要尽早把 `BAT_EN` 拉高：

```cpp
pinMode(2, OUTPUT);
digitalWrite(2, HIGH);
```

Buddy 的电池供电策略：

- 3.7V 锂电池接板载电池座。
- 关机状态下长按 `PWR` 开机，硬件会临时拉起供电。
- 固件启动后立即拉高 `BAT_EN/GPIO2` 锁住供电。
- 运行中长按 `PWR/GPIO5` 约 1.5 秒，固件拉低 `BAT_EN/GPIO2` 关机。
- 短按 `PWR` 不做唤醒；屏幕息屏后仍由 BLE 状态或 `PLUS` 业务键唤醒。
- USB 供电时拉低 `BAT_EN` 不一定会断电，因为 USB 仍在供电。

## 6) 最小自检顺序（推荐每次新工程先跑）

1. 初始化串口 `Serial.begin(115200)`
2. 打开背光 GPIO
3. `SPI.begin(...)` 绑定屏幕引脚
4. `tft.init(240, 240)`
5. 连续刷 `红/绿/蓝` 三色确认显示链路正常
6. 再进入业务 UI

## 7) 参考资料（下次可直接打开）

- Waveshare 文档: <https://docs.waveshare.com/ESP32-S3-Touch-LCD-1.54>
- Waveshare 产品页: <https://www.waveshare.com/esp32-s3-lcd-1.54.htm>
- Waveshare 示例仓库: <https://github.com/waveshareteam/ESP32-S3-Touch-LCD-1.54>

---

最后更新：2026-06-04
