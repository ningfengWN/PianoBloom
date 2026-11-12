# PianoBloom · 琴芽

独立的 iPhone / iPad 钢琴单音练习 App。麦克风听琴，音符跟随演奏高亮。

## 第一版功能

- **中央 C 校准**：弹 C4 保持约一秒，稳定后自动保存基准；校准失败或取消不会覆盖旧值。
- **跟谱练习**：中央 C 音阶、欢乐颂、小星星；弹对前进，弹错停留，自动滚动到当前音符。
- **自由识音**：显示音名、唱名、频率、音分与 C4–C5 键盘示意。麦克风识别范围约 C3–C6。
- **重复音判断**：结合稳定音高、静音与击键音量上升，避免持续音重复计数。
- **练习记录**：保存最近 30 次完整练习的音符准确率、错音数、用时。
- **麦克风设置**：权限拒绝时可进入系统设置；可调灵敏度；来电、切后台或更换输入设备时暂停。
- **设备适配**：iOS 16+，iPhone / iPad，横竖屏、安全区、可滚动布局。
- **隐私**：音频只在本机实时处理，不保存、不上传；无需账号和联网。

## 在 Mac 上安装运行

```bash
git clone https://github.com/ningfengWN/PianoBloom.git
cd PianoBloom
open PianoBloom.xcodeproj
```

1. 在 Xcode 顶部选择 **PianoBloom** Scheme。
2. 点左侧工程 → TARGETS → PianoBloom → Signing & Capabilities。
3. 勾选 Automatically manage signing，选择自己的 **Team**。如提示 Bundle ID 被占用，改为自己的唯一名称，例如 `com.yourname.pianobloom`。
4. 用数据线连接并信任 iPhone / iPad；若系统要求，在设备上开启开发者模式。
5. 选择该真机，点击 ▶。第一次弹出麦克风权限时选择允许。

此仓库不包含个人开发团队、签名证书或描述文件。GitHub 构建产物是模拟器 App，**不能直接安装到 iPhone**。真机需由你的 Apple 开发账号签名，或后续通过 TestFlight 分发。

## 第一次使用

1. 设备放在钢琴旁约 30–80 厘米，安静环境，关闭踏板。
2. 点「校准中央 C」，弹中央 C（C4）保持约一秒。也可以直接使用标准音高开始。
3. 校准成功后先松键，待余音变小。
4. 选择练习曲，逐个弹出高亮音符；完成后查看结果。
5. 重复音若卡住，松键等余音变小再弹；噪声误触发时在设置中降低灵敏度。

## 范围和限制

这是单音入门练习版，不支持双手和弦、踏板混音、导入曲谱、自动翻页和节奏评分。谱面显示音符顺序，间距不代表演奏时值。键盘示意范围 C4–C5，范围外音符仍可显示音名。

麦克风识别会受琴音、距离、背景声和混响影响。音量突变只能近似判断再次击键；无法保证所有钢琴及所有重复音都准确。中央 C 校准只修正整体音高偏移，不能替代调律。

准确率 = 正确音数 ÷（正确音数 + 识别为错音的次数）。这是本次练习的识别反馈，不是专业演奏评分。

## 开发与验证

源码分为 `PitchCore.swift`（音高与练习逻辑）、`Microphone.swift`（收音）、`PracticeModel.swift`（状态与存储）、`PianoBloomApp.swift`（界面）。无第三方运行时依赖。

```bash
bash scripts/test-core.sh
xcodebuild -project PianoBloom.xcodeproj -scheme PianoBloom \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions 会运行生产核心代码的合成 PCM 测试，覆盖多个音区、采样率、泛音、偏调、静音与噪声；同时验证持续音、重复音、中央 C 校准和练习进度，并构建模拟器与未签名真机版本、保存模拟器首屏截图。

合成信号测试与编译不等于真钢琴测试。发布前需按 [真机验收清单](DEVICE_TESTING.md) 验证实际钢琴和麦克风表现。
