# Changelog

All notable changes to **PulseAwake** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/lang/zh-CN/).

## [1.1.0] - 2026-11-18

### Added
- 新增 **“阻止合盖休眠（需管理员授权）”** 模式，支持未连接外接显示器时合上 MacBook 盖子继续后台运行。
- 直读 IOKit `IOPMrootDomain` 的 `SleepDisabled` 内核状态，与系统实际 `pmset` 配置实时同步。
- 新增 **退出安全确认护栏**：当“阻止合盖休眠”仍开启时点击退出，自动弹窗提示一键恢复正常合盖休眠，防止装包发热与亏电。

## [1.0.0] - 2026-11-18

### Added
- 智能空闲监测与非阻塞 `1px` 微脉冲保活引擎，仅在系统真实空闲达到阈值且未按住鼠标按键时触发，防止桌面 IM 自动切为“离开”。
- 基于 IOKit 独立管理“阻止系统休眠”（`NoIdleSleepAssertion`）与“阻止屏幕休眠”（`NoDisplaySleepAssertion`）。
- 辅助功能权限（`AXIsProcessTrusted`）实时检测、菜单栏警告态提示与一键跳转系统授权引导。
- 基于 `SMAppService.mainApp` 的原生开机自动启动开关（无需外部 LaunchAgent plist）。
- 纯 CoreGraphics 矢量渲染的“脉冲心跳”全分辨率应用图标（`AppIcon.icns`）与心电脉冲菜单栏状态图标。
- 支持 `arm64 + x86_64` 双架构 Universal Binary 编译及附带 `SHA256SUMS.txt` 的 Release 打包脚本。
