# 第三方开源组件声明（THIRD PARTY NOTICES）

本仓库基于 [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)（AGPL-3.0）二次开发，
并包含或依赖以下第三方开源组件。所有商标、平台内容版权归其各自所有者。

## 内置（vendored / 内嵌）组件

### 1. GetX（lib/get）

- 来源：https://github.com/jonataslaw/getx
- 许可证：MIT License
- 说明：仓库以源码副本（vendored fork）形式内置，并做了少量定制（见 lib/get/README.md）。
- Copyright (c) 2019-2021 GetX authors

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### 2. CryptoJS（lib/core/scripts/douyu_sign.dart）

- 来源：https://github.com/brix/crypto-js
- 许可证：MIT License（Copyright 2009-2013 Jeff Mott）
- 说明：以压缩版 JS 内嵌，用于斗鱼等平台签名计算。

### 3. TARS 协议实现（lib/pkg/tars）

- 协议来源：腾讯 TARS（https://github.com/Tencent/Tars，BSD-3-Clause）
- 说明：本仓库内置的是 TARS 协议的 Dart 移植实现，原始移植出处与许可证**待核实**；
  如涉及版权问题请联系处理。

### 4. 抖音 a_bogus / x-bogus 签名算法（lib/core/scripts/douyin_sign.dart）

- 说明：算法来自社区公开的逆向分析成果，仅用于个人学习与交流，
  原始出处**待核实**，详见文件内注释。

## 依赖的原生组件（随发行物分发）

| 组件 | 来源 | 许可证 |
| --- | --- | --- |
| media-kit（Dart） | https://github.com/media-kit/media-kit | MIT |
| libmpv（视频内核） | https://github.com/mpv-player/mpv | GPL-2.0-or-later / ISC |
| FFmpeg | https://ffmpeg.org | LGPL-2.1（使用 ffmpeg_kit_extended 的 lgpl 构建） |
| IJKPlayer | https://github.com/bilibili/ijkplayer | LGPL-2.1 |
| QuickJS（dart_quickjs） | https://bellard.org/quickjs | MIT |
| Remix Icon（图标） | https://remixicon.com | Apache-2.0 |
| Judou Sans（字体） | https://github.com/JudouEco/JudouSans | SIL OFL 1.1 |

## 字体许可风险提示

- `assets/PingFangSC.ttf` 为 **Apple 专有系统字体**，仅随系统分发，
  内置到安装包再分发**可能违反 Apple 的字体使用条款**，建议替换为可再分发开源字体（如思源黑体，OFL）。
- `assets/icons/CustomIcons.ttf` 图标字体来源未注明，若包含 FontAwesome / Remix Icon 字形，
  需分别遵守其许可证。

## Dart / Flutter 依赖

其余 Dart 与 Flutter 依赖的许可证列表，以构建产物中的
`assets/flutter_assets/NOTICES.Z`（Flutter 自动生成）为准。

## 其他说明

- 各直播平台的表情、Logo 等资源版权归对应平台所有，仅作展示用途。
- 若您认为本声明遗漏了某个组件的出处或许可证，欢迎提交 Issue 或 Pull Request 补充。
