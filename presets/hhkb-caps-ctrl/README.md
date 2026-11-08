# hhkb-caps-ctrl — Toshy 预设（Caps↔左Ctrl 完整对调 + Ctrl+Space 交给输入法）

给 10+ 年 macOS / HHKB 习惯的人准备的一键预设：把 Toshy 配成你熟悉的键位工作流。
全平台通用（KDE / GNOME / Xfce / Hyprland / wlroots 系……只要官方 Toshy 支持的桌面都适用），tmux 或终端同样可用。

> 为什么需要它：Toshy 默认会用 "SPOTL" 模块把 Ctrl+Space 收走（改写成桌面布局切换键，比如 KDE 的 Meta+Alt+L），
> 所以输入法的 Ctrl+Space 触发键打不过去；默认的对调模式（role swap）也不是字面交换——按住 Caps 在 GUI 里输的是 Super 不是 Ctrl。本预设全部修正。

## 改成之后是什么样子

| 按键 | 行为 |
|------|------|
| Caps | 真 Left Ctrl（所有应用，包括终端） |
| 物理左 Ctrl | CapsLock 切换键 |
| Caps + Space | 切换输入法（fcitx5/ibus） |
| Cmd 位（Windows 键盘的 **Alt**） | macOS 的 Cmd：Alt+C=复制、Alt+Q=关窗口 |
|Cmd+Space 位（**Alt+Space**）| 应用启动器（KRunner 等，Toshy 原有行为保留）|
| Win 键位 | macOS 的 Option/Alt |

## 全新机器 3 步走

1. 按官方方式安装 Toshy（区别于本预设，正常装即可）：
   ```bash
   curl -fsSL https://toshy-config.s3.us-east-1.amazonaws.com/install_master.sh | bash
   ```
   装完重登录一次会话（或重启），托盘图标出现即就绪。
2. 应用本预设（二选一）：
   ```bash
   # 免 clone：
   curl -fsSL https://raw.githubusercontent.com/lovelock/Toshy/preset/hhkb-caps-ctrl/presets/hhkb-caps-ctrl/apply.sh | bash
   # 或 clone 后运行：
   git clone https://github.com/lovelock/Toshy && bash Toshy/presets/hhkb-caps-ctrl/apply.sh
   ```
3. 验证：
   - 文本框里按 **Caps+C** = 复制；**Caps+Space** = 切换输入法
   - 终端里 **Caps+C** 发送 SIGINT / tmux 前缀用 Caps
   - 按一下**物理左 Ctrl** —— 大写指示灯应切换
   - Fcitx5 用户：托盘输入法图标应随 Caps+Space 切换

## 幂等与升级

- 脚本可**反复运行**：已打过补丁的配置自动跳过（含"手工改过没带标记"的识别），重复运行零副作用
- **Toshy 升级后请重跑一次**：升级可能重生成配置文件里的 modmap/keymap 区域，重跑脚本即可恢复（所有插入都有 `### PRESET: hhkb-caps-ctrl ... ###` 标记，可 grep 定位）
- 若上游未来改掉了脚本依赖的锚文本（如 SPOTL 的 `setup_spotlight_input_keymaps(` 结构），脚本会**响亮报错退出并保持原文件不动**，不会盲改

## 主要参数 / 环境变量

| 项 | 说明 |
|----|------|
| `--dry-run` | 只显示将要做的动作，不写任何文件 |
| `--no-fcitx5` | 跳过 fcitx5 触发键修正（GNOME/ibus 用户无需理会） |
| `--skip-restart` | 不重启 toshy-config 服务（自行重启或重登会话） |
| `TOSH_PREFS_DB` / `TOSH_FCITX_CONFIG` | 覆盖偏好库 / fcitx5 配置路径（测试用）|
| `TOSHY_PYTHON` | 覆盖所用的 python（默认优先 Toshy 自带 venv）|

## 它具体改了什么

1. `~/.config/toshy/toshy_config.py`：
   - 插入 modmap **"Cond modmap - User - Caps<->LCtrl full swap"**：`Caps↔LeftCtrl` 字面交换（kbtype 限定 Apple/Windows，避开远程/VM）
   - 插入 keymap **"User: Ctrl+Space for IME passthrough"**：Ctrl+Space 原样透传（注册顺序在 SPOTL 之前，否则会被吞）
2. Toshy 偏好库：`capslock_mode = caps_is_caps`（否则 caps 机制会和交换 modmap 打架）
3. （仅当检测到 fcitx5）把 `~/.config/fcitx5/config` 的 `TriggerKeys[0]` 修成 `Control+space`，旧值备份为 `config.bak-hhkb-*`
4. 每次真正写配置前自动备份为 `toshy_config.py.bak-hhkb-时间戳`

## 回滚

- 配置文件：恢复最新的 `~/.config/toshy/toshy_config.py.bak-hhkb-*` 即可
- fcitx5：恢复 `~/.config/fcitx5/config.bak-hhkb-*`
- 改完后重启：`systemctl --user restart toshy-config.service`

## 维护/开发

- 锚点与插入块的唯一权威文本在本仓库 `docs/superpowers/specs/2026-11-08-hhkb-caps-ctrl-design.md`
- 场景测试：`bash presets/hhkb-caps-ctrl/tests/run.sh`（对临时副本运行，绝不碰真实配置）
