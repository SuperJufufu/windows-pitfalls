# windows-pitfalls — battle-tested fixes for Windows problems nobody documents

**Scripts and notes from actually fixing the boring, badly-documented Windows problems:** every desktop shortcut icon turning blank (icon cache), 40+ autostart entries, `.bat` files mangled by the OEM codepage, `.vbs` launchers broken by Chinese paths, and services that silently re-create themselves after you delete them.

Everything here was written to fix a real problem on a real machine — no pseudo-code, no untested snippets.

`windows` `windows-11` `powershell` `vbs` `icon-cache` `autostart` `launcher` `oem-codepage` `troubleshooting` `sysadmin`

---

## 中文说明

> 我在一台 Windows 11 机器上被这些破事反复咬过：桌面快捷方式集体变白、开机启动项几十个、批处理里的中文全变乱码、`.vbs` 启动器被中文路径搞崩……这份仓库就是逐个咬回去的过程。

## 目录

```
launchers/     VBS 启动器（无黑窗启动 + 探活 + 自带浏览器打开，失败自愈）
  DSH-Launcher.vbs           起服务、从 stdout 抓随机 token、健康检查后再开浏览器
  Bonsai-*.vbs / ComfyUI-Launcher.vbs / QwenPaw-Launcher.vbs / SDXL-*.vbs
  icons/                     每个快捷方式的 .ico（含从单尺寸拼多尺寸的方法）
scripts/system/
  autostart-apps.ps1/.bat    开机自启清单：导出/对账/精简
  make-bonsai-icons.ps1      用 PNG/ICO 生成一整套快捷方式图标
  fix-icon-label.ps1/.bat    修"快捷方式名字被截断/图标错位"
  rebuild-icons.bat          重建图标缓存（IconCache.db + explorer 重启）
  dsh-upgrade-*.ps1          就地升级脚本（备份 → 替换 → 校验）
  valorant-latency-optimize.ps1   网卡省电项/驱动/优先级/虚拟网卡
  va-opt-admin.ps1 / rtl-driver-install.ps1
scripts/security/
  purge-miner.ps1/.bat       挖矿病毒应急处置（杀进程 → 删伪装服务 → 封 C2 → 清理启动项）
  rebuild-icons-reference.ps1
docs/
  README-桌面图标变白-修复经验.md   全白图标的完整根因链与修复顺序
  开机自启清理报告-20261003.md      49 项逐项裁决 → 保留 7 项，含还原脚本设计
```

## 几个反直觉的坑（都在 `docs/` 里有完整过程）

1. **桌面图标变白 ≠ 图标缓存坏了**。只删 `IconCache.db` 往往不够：`explorer` 会重建一部分，剩下的仍指向已失效的 `.ico`。正确顺序是「先修 .lnk 的 IconLocation → 再清缓存 → 再重启 explorer」。
2. **`.bat` 里不能写中文**。cmd 用 OEM 代码页（GBK）解析 UTF-8，中文会把命令拆碎成「'xxx' 不是内部或外部命令」。中文说明写进 `.ps1` / README，`.bat` 保持纯 ASCII。
3. **`.vbs` 启动器里中文路径会让 `.lnk` 参数乱码**。路径统一走英文目录，或用 `WScript.Shell` 拿 `SpecialFolders`。
4. **移动桌面文件前先 grep 启动器**。`dsh.exe` 被挪走后，`DSH.lnk → DSH-Launcher.vbs` 里写死的 `Desktop\dsh.exe` 直接报 not found —— 这种硬编码引用是桌面整理的最大雷区。
5. **启动项 ≠ 只有「启动应用」列表**。还有 HKCU/HKLM Run、9 个服务、计划任务、24 条残留标记；只清列表等于没清。
6. **杀软/驱动类自启删了会「自己回来」**（WPS 更新任务、机场客户端、Realtek 音频服务），需要幂等的复核脚本而不是一次性清理。

## 用法

脚本里都写死了我这台机器的路径（`C:\Users\Administrator\...`）。**抄思路，不要直接跑**——先把路径改成你自己的，或改成 `$PSScriptRoot`。
破坏性操作（删启动项、删服务、杀进程）都是先备份再动手，脚本注释里标了备份位置。

## 免责

`scripts/security/purge-miner.*` 是应急脚本，按当时那台机器上挖矿木马的形态写的。样本不同就可能误杀，跑之前先读一遍要删的名单。
