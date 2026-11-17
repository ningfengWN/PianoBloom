# Onsets & Velocities 实验接入

这是真正调用官方预训练模型的接入，不是把基础音高检测换一个名字。
本版 **Mac 推理、iPad 采音与显示**。Mac 服务未启动时无法使用此引擎；
目前没有把 PyTorch 模型移植到 iPad 本地，也没有验证真钢琴识别准确率。

## 启动

1. Mac 安装 Python 3.10–3.12、Git（Xcode Command Line Tools 提供）。
2. 在 Terminal 执行 `bash Server/onsets_velocities/Start-Model.command`。
   首次自动建立 Python 环境、安装依赖并下载固定版本官方源码和权重，不训练模型。
3. 保持终端打开。复制终端显示的 `ws://Mac局域网IP:8765/recognize` 和连接码。
4. iPad 与 Mac 连接同一 Wi-Fi。在 App「家长设置 → 钢琴识音引擎」选择
   `Onsets & Velocities（Mac）`，填写地址、连接码，并允许本地网络和麦克风权限。
5. 选择演奏或心流，开始练琴。倒计时有声音，可在设置关闭。

基础识音仍可手动选择。新引擎连接失败、响应无效或处理严重积压会明确暂停，
**不会自动降级成基础算法**。先用演奏模式试琴，再测试心流。

## 时间与延迟

- 官方参数：16 kHz，2048 点 Hann FFT，384 点 hop，229 mel 频带（50–8000 Hz），
  power=2、80 dB 范围。使用官方网络和起音/力度解码器，MIDI 覆盖 21–108。
- 默认实验窗口 `(left=100, body=8, right=20)`，保留过去上下文，缩短未来上下文。
  最低音频等待约 0.736 秒，还要加实际推理和网络耗时。不是已经达到即时陪练质量。
- 可用 `bash Server/onsets_velocities/Start-Model.command --official-window` 对照官方
  `(100,30,100)` 窗口。官方演示说明其完整窗口约 5.5 秒；缩短窗口的准确度需要另测。
- 每个结果携带音频中的真实起音时间及已处理水位，评分不会使用网络收到消息的时刻。
  心流只对模型已经处理的音频判漏音，避免网络/模型延迟被算成孩子漏弹。
- 同一和弦跨块合并、接缝重复起音抑制、停录取消、无效结果拒绝与连接超时均有处理。

## 已知边界

O&V 输出起音和力度，不输出可靠的音符结束/踏板状态；本版不新增时值、踏板或音乐表现力评分。
声音通过本地网络发送到手动设置的 Mac，不写录音文件；连接码只用于本地配对。
不要将此测试服务直接暴露到公网。Mac 防火墙需允许该服务的本地网络连接。
校准中央 C 使用单音校准工具，不会改变模型权重或把目标曲谱当作识别结果。

## 可复现来源与授权

- 官方项目：https://github.com/andres-fr/iamusica_training
- 固定提交：`629ff11aceadf01ecc456b1c7f26a104f7e1e571`
- 权重：`assets/OnsetsAndVelocities_2023_03_04_09_53_53.289step=43500_f1=0.9675__0.9480.torch`
- 权重 SHA-256：`90901ff8c7cb15c76a4da2f4aca643a10295c834ac9e549ee16097d4bbce642d`
- 作者：Andrés Fernández Rodríguez，IAMúsica，EUSIPCO 2023。
- 预处理与解码参考官方训练库及 `andres-fr/iamusica_demo`。
- 此服务端适配代码采用 GPL-3.0-or-later，保留官方 GPL 许可证于同目录 `LICENSE`。
  原始源码、权重由启动脚本下载，未作为闭源 SDK 打包进 iPad；客户端通过独立音频协议连接。

## 测试

环境安装后：
`python test_service.py --source .cache/iamusica_training`

测试直接加载上述权重，覆盖静音推理、分块水位、分块和弦聚合、重复音、缓冲边界、
错误连接码与完整 WebSocket 音频交换。它是接入验证，不等于真钢琴准确率验收。
CI 额外使用 ByteDance 项目公开的 `resources/cut_liszt.mp3` 前 8 秒做非静音冒烟测试，
固定原仓库提交 `1ade7dcd4348add669a67c6e6282456c8c6633bd` 和音频校验值；
该片段不打包进 App，也没有用作训练数据，不从非空输出推导准确率。
