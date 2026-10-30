# 有落品牌与 App 图标

## 已选方向：亮系统蓝

![有落 App 图标亮蓝方案](yolo-ledger-app-icon-concept-v2-system-blue.png)

用户于 2026-10-28 选择亮系统蓝方案作为当前图标方向。背景以 `#0A84FF` 为设计基准，接近 Xcode 与 Apple 系统蓝的明亮观感；橙色圆点与象牙色承接页保持不变。该配色也作为当前应用内部主色试用。

- 文件：`yolo-ledger-app-icon-concept-v2-system-blue.png`
- 尺寸：1254 × 1254 px
- Alpha：无
- SHA-256：`51e87d2d8de6f499b2c9190a0a0165b2c3c9f6e38660ec2c4980753fa07ae24c`
- 状态：已生成 1024 × 1024 iOS master 与 16–1024 px macOS 图标资源，并接入两个 Xcode App Target

这是一枚无文字的独立标志，不使用猫、爪印、票据锯齿、货币符号、计算器、图表，也不沿用此前黄粉描边的参考风格。系统负责为 iOS 与 macOS App 图标应用最终蒙版，因此源图保持不透明方形画布，不预先绘制外层圆角。

旧图标草案及其他预览图片已按用户要求移除，仓库只保留当前选中的亮系统蓝 icon。Xcode 资源位于 `apps/xcode/Resources/Assets.xcassets/AppIcon.appiconset/`；iOS 使用不透明 1024 × 1024 master，macOS 使用由同一源图缩放生成的标准尺寸。

## 生成说明

使用内置图像生成工具创建。最终提示的核心要求是：为“有落 / YoloLedger”设计无文字、可缩放的原生 App 图标；以一个下降的记录点和连续承接页表达“每一笔，都有落点”；使用亮系统蓝、象牙白和克制的橙色；保持强轮廓和负空间；排除猫、爪印、票据、货币符号、计算器、图表、旧 UI 元素及外部产品风格。
