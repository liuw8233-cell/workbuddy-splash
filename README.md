# WorkBuddy Splash Launcher

给 **WorkBuddy** 加一段全屏启动动画：双击图标 → 动画播完 → 无缝进入主界面。

顺序永远固定，**先动画，后程序**。开机再快也是动画先走完，程序在后台悄悄加载好、等在那儿。

> 纯 Windows 脚本实现，不需要 Python / Node，不依赖任何第三方库。

---

## 效果

| 时间 | 发生什么 |
|---|---|
| 0.0s | 动画窗口全屏铺开并**强制置顶**（`SetWindowPos HWND_TOPMOST`） |
| 2.6s | 动画进入中段，此时才在**后台**拉起 WorkBuddy |
| ~5.7s | 进度条走到 100% |
| ~6.7s | 页面把 `document.title` 改成 `WB_READY`，动画淡出收场 |
| +0.3s | 关闭动画窗口 → 把 WorkBuddy 窗口提到最前 |

切换时机不是写死等几秒。页面播完主动发信号（改窗口标题），启动器轮询标题 + 检测主窗口句柄，**两个条件都满足**才收场 —— 快机器慢机器都准。

---

## 快速开始

1. 把整个目录拷到任意位置（例如 `D:\tools\WorkBuddySplash\`）
2. 双击 **`启动 WorkBuddy.bat`**
3. 想从桌面启动：右键 bat → 发送到 → 桌面快捷方式

开机自启：把快捷方式丢进 `Win+R` → `shell:startup` 打开的启动文件夹。

---

## 换电脑 / 拷给别人

**整个文件夹直接复制就能用，不用改任何路径。**

启动器会自动探测，按顺序逐条验证，命中即止：

**浏览器**（优先 Edge，Win10/11 出厂自带，几乎不会失手）

```
注册表 App Paths\msedge.exe | chrome.exe  (HKLM / WOW6432 / HKCU)
→ 常见安装目录
```

**WorkBuddy**

| # | 手段 |
|---|---|
| 1 | 运行中进程的 `.Path` |
| 2 | `App Paths\WorkBuddy.exe` |
| 3 | 卸载表 `InstallLocation` / `DisplayIcon` |
| 4 | 开始菜单 + 桌面 `.lnk`（解析快捷方式目标） |
| 5 | 常见目录（`%LOCALAPPDATA%\Programs` 等 ×3 层） |
| 6 | 按盘符浅扫，深度 3，4.5s 预算 |
| 7 | 仍找不到 → 弹窗手动选一次，**自动写进 `config.ini`** |

到新机器上不放心，先跑自检（只打印结果，不播动画）：

```
双击 _detect.bat
```

```
配置文件 : D:\tools\WorkBuddySplash\config.ini
浏览器   : C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
WorkBuddy: D:\ai\agenttools\workbuddy\WorkBuddy.exe
```

---

## 手动配置

`config.ini` 全是可选项，留空即自动探测：

```ini
# 有空格也不用加引号
AppPath=
BrowserPath=
```

里面的路径在别的机器上失效会自动跳过、回落探测，所以这个文件可以跟着项目一起拷。

---

## 目录结构

```
index.html                动画页面（双击可单看，F11 全屏）
assets\miku-splash.mp4    动画视频
assets\poster.jpg         视频加载前的静态帧
launcher.ps1              主逻辑：探测 + 时序 + 收场
config.ini                可选手动配置
启动 WorkBuddy.bat        双击入口
_detect.bat               自检（只打印探测结果）
使用说明.txt              中文说明书
```

---

## 换动画 / 调时序

换动画：覆盖 `assets\miku-splash.mp4` 和 `assets\poster.jpg`（文件名不变）即可。

调时序：

| 位置 | 参数 | 默认 | 作用 |
|---|---|---|---|
| `launcher.ps1` | `-AppStartDelayMs` | 2600 | 动画开始后多久才启动程序 |
| `launcher.ps1` | `-DeepScanMs` | 4500 | 深扫时间预算 |
| `launcher.ps1` | `-MaxWaitMs` | 30000 | 等主窗口的上限 |
| `index.html` | `MIN_DURATION` | 5200 | 进度条基础时长 |
| `index.html` | `FINISH_LEAD` | 5400 | 开始收尾的时间点（与上一项差 200 左右最顺） |

播放中按 `ESC` 可跳过动画。

---

## 已知行为

- 动画窗口强制置顶，后台启动的程序不会抢镜头
- WorkBuddy 已经开着时**不会**重启，播完直接把窗口提到最前
- 只对**最小化**的窗口做还原，不会把你的最大化窗口还原成小窗
- 动画用独立浏览器配置（`%TEMP%\WB_Splash_Profile`），不碰你日常浏览器的会话

---

## 踩过的坑（改动记录）

这些是实现时真金白银踩出来的，改代码前值得先看一眼：

1. **中文路径必须百分号编码**
   `--app=file:///D:/社交/微信/...` 这种没编码的中文 URL，Chrome 会把 `--app` 参数整个忽略，退化成普通「新标签页」。必须用 `([System.Uri]$path).AbsoluteUri` 生成编码后的 URL。

2. **ps1 含中文必须存 UTF-8 带 BOM**
   PowerShell 5.1 默认按 ANSI 读无 BOM 文件，中文全乱码。bat 保持纯 ASCII。

3. **`$MyInvocation.MyCommand.Definition` 不可靠**
   交互式会话里它返回的是整个会话脚本内容，路径直接炸。改成 `$PSScriptRoot` → `$PSCommandPath` → `Get-Location` 三级回退。

4. **无条件 `ShowWindow(SW_RESTORE)` 会毁掉最大化窗口**
   它会把你最大化的 WorkBuddy 还原成小窗。先 `IsIconic` 判断，只对最小化的窗口做还原。

---

## 系统要求

Windows 10 / 11 · PowerShell 5.1（系统自带）· Edge 或 Chrome 任一（系统基本都自带）

---

## License

MIT
