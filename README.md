# 芯乐——多维交互电子乐器

基于高云 FPGA 的触摸与压力交互实时音频合成工程。

## 硬件与功能

- Tang Mega 60K / GW5AT-60 系列 FPGA，配合 NEO Dock。
- TTP229 十六键电容触摸，四路 FSR402 压力输入。
- FSR1：音量；FSR2：Tremolo 音量颤动；FSR3：音高弯曲；FSR4：Echo 回声。
- 32 声部合成、DDS、独立 ADSR 包络、正弦波与三角波音色。
- PCM5102A 标准 I²S 输出，保留 PT8211 输出链路；SSD1306 OLED 状态显示。

## 工程结构

```text
audio_hw_440hz/
  audio_hw_440hz.gprj   Gowin IDE 工程
  src/                 RTL、PLL IP 与波形表
  constraint/          引脚与时序约束
  tb/                  各模块及多声部仿真 testbench
  sim/                 Echo 仿真
  python/              音频/复音验证脚本
  output/              原工程输出图片
archive/
  parts/               原始压缩包的二进制分卷
  manifest.json        大小及 SHA-256 校验值
  restore_archive.py   合并并校验，恢复完整原始 ZIP
```

## 打开工程

1. 在 Gowin IDE 中打开 `audio_hw_440hz/audio_hw_440hz.gprj`。
2. 原工程指定器件为 `GW5AT-LV60PG484AC1/I0`（GW5AT-60B）；下载前核对实际开发板与引脚约束。
3. 保留 `src/sine_1024.mem` 和 PLL 文件的相对路径，在工程目录运行综合、布局布线与下载。
4. Python 验证脚本依赖 NumPy、Matplotlib，输入使用工程提供的 PCM 文本数据。

## 恢复完整提交资料

GitHub 可直接浏览的目录提供源码、约束、仿真、验证脚本、PCM 数据和输出图片。原 ZIP 包含的编译结果、中间文件及工具缓存则完整保存在 `archive/parts/`，没有从原始备份中删除。

下载或克隆本仓库后运行：

```bash
python archive/restore_archive.py
```

脚本校验每个分卷及合并后的 SHA-256，生成 `archive/final_project.zip`。解压即可恢复用户提交的完整工程，包括原 `impl/` 下的下载文件和布局布线结果。

原始文件：`final_project(1).zip`；大小：56531673 字节。

SHA-256：`dce4b0f794a66db57fd7957af71ab91738fc2f6fb3eb67578522f7841824f26a`
