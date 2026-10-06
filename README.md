# iScreen Menu
**Screen and Light Controller：灯光、双屏联动与 Mac 辅助控制，集中在菜单栏。**

最初是为 Studio Display 补上 iScreenBar 熄屏同步，现在加入亮度联动、环境光规则、自动色温与内屏管理。非官方独立项目，与 BenQ、Apple 无隶属关系。最新版源码继续在这个原仓库以 MIT 许可证公开。

## 界面与功能

详见 [截图使用指南](docs/UI-GUIDE.zh-CN.md) · [完整功能清单](docs/FEATURES.zh-CN.md)。

| 模块 | 功能 |
| --- | --- |
| 快捷控制 | 灯光、自动感光、入座检测、视频模式、亮度跟随、熄屏同步、自动色温、双屏亮度、防止休眠 |
| 灯光调节 | 亮度与 2700–6500K 色温，支持物理操作后的状态回读 |
| 亮度联动 | 保留当前亮度差，实现 MacBook ↔ Studio Display → iScreenBar 联动 |
| 环境光标定 | 使用 Studio Display 传感器，分别保存明亮关灯、昏暗开灯阈值 |
| 自动色温 | 按时间变化，白天偏冷、夜间偏暖；不是测量环境色温 |
| 内屏管理 | 内屏开关、0°/90°/270° 旋转、5 秒确认回退、外屏断开恢复 |
| Studio Display 按钮 | 黑色遮罩，保持窗口布局；**不关闭背光，不等同于硬件节电** |
| 预设 | 保存灯光模式、按前台应用切换模式；独立保存旋转预设 |

图标黄色表示灯亮，灰色表示灯灭，红色提示异常；悬停显示亮度和色温。App 不占 Dock 位置。

## 安装

已测试：Apple Silicon MacBook Pro、macOS 26、Studio Display、BenQ iScreenBar（USB VID 0x04A5 / PID 0x2501）。其他系统和设备尚未全面验证。

先安装 Xcode Command Line Tools，然后运行：

```bash
xcode-select --install
git clone https://github.com/rogerbush007-a11y/iScreenBar-StudioDisplay-Sync.git
cd iScreenBar-StudioDisplay-Sync
./scripts/install.sh
```

脚本本机编译、临时签名，安装到 `~/Applications/iScreen Menu.app`，创建用户级 LaunchAgent，登录后自动运行。安装无需管理员密码；防止休眠的强制层另需管理员授权。

日常灯控直接通过 USB HID 执行，不依赖官方 App。建议避免两个软件同时自动写入灯光设置。相机自动视频模式和灯体硬件记忆尚未完全对齐，不宣称完整替代官方所有功能。

## 使用规则

- 亮度跟随与灯体自动感光互斥，关闭跟随后保留当前亮度。
- 环境光采用近 10 秒中位数。明亮关灯约 30 秒，达到昏暗开灯点约 30 秒；环境关灯后的渐进回开约 45 秒。带回差与持续时间判断，不是越过数值就立即切换。
- 旋转预设开启：连接 Studio Display 时应用保存角度。关闭：回到 0°，重新连接也请求保持 0°。
- 外屏断开请求强制恢复内屏。一般显示配置操作避开锁屏/唤醒切换，断开恢复是例外。
- 防止休眠使用 caffeinate 和管理员授权的 pmset disablesleep，关闭或退出后尝试释放。请实际验证本机合盖、锁屏与恢复行为。

## 验证与限制

```bash
./scripts/check.sh
tail -f ~/Library/Logs/iScreenBarStudioSync.log
launchctl print gui/$(id -u)/local.qiu.iScreenBarStudioSync
```

2026-10-05 的“关闭内屏后拔掉外屏恢复”已由使用者实际确认；2026-10-06 的旋转预设关闭回 0°已构建部署，仍待新一轮插拔验收。构建通过、系统状态回读不代表面板确实发光。

显示控制依赖 macOS 私有 SkyLight / MonitorPanel / DisplayServices 接口，系统升级后需要复测。USB 报文针对特定灯型，其他 ScreenBar 型号不保证兼容。虚拟分屏实验不属于当前正式功能。

## 卸载与开发

```bash
./scripts/uninstall.sh
# 仅构建，不安装：
./scripts/build.sh
```

卸载将 App 和 LaunchAgent 移至废纸篓，保留日志。构建产物位于 `build/iScreen Menu.app`。目前为本机临时签名，无 Developer ID 公证或自动更新。

源码无网络请求、分析或云端依赖。参见 [安全说明](SECURITY.md)、[商标声明](NOTICE.md)、[MIT 许可证](LICENSE)。
