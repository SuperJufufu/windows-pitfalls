# 桌面图标变白(.lnk 变空白纸) 修复经验

整理日期: 2026-10-03
适用: Windows 11, 桌面快捷方式(.lnk)全部变成"白纸+小箭头", 但文件夹 / .exe / .png 图标正常。

---

## 一句话结论

真因是 **桌面文件夹被打上了 Low 完整性标签 (Low Mandatory Level)**。
**不是 IconCache 损坏。** Windows 不会解析 Low 完整性文件夹里 .lnk 的图标。

## 典型症状(用来对号入座)

- 桌面所有 .lnk 变白纸, 文件夹 / .exe / .png 正常
- 公共桌面(Public Desktop)里的快捷方式图标正常
- 同一个 .lnk 复制到普通文件夹, 图标立刻正常
- 删图标缓存、重启 explorer、重启电脑都没用

## 快速诊断(10 秒)

    icacls "C:\Users\Administrator\Desktop"

输出里如果有这一行, 就是它:

    Mandatory Label\Low Mandatory Level:(OI)(CI)(NW)

常伴随的 ACE: CodexSandboxUsers、S-1-4-1039366120-933337351 (agent 沙箱用户)。

## 修复

方式 A (推荐): 双击桌面根目录的 `fix-icon-label.bat`
  - 会自动 UAC 提权, 可反复运行, 内部调用 fix-icon-label.ps1
  - 把 Desktop 和 Favorites 的标签 Low -> Medium

方式 B (手动, 管理员权限):

    icacls "C:\Users\Administrator\Desktop" /setintegritylevel (OI)(CI)Medium

修复后图标立即恢复, 不需要重启, 不需要动缓存。
(2026-10-01 实测: 桌面 25 个 .lnk, 修复前 25 个全白, 修复后 0 个空白。)

## 为什么确定是它(可复现实验)

| 操作 | 结果 |
|---|---|
| 同一个 Chrome.lnk 复制到普通文件夹 | 真实图标 (2081 B) |
| 同一个文件留在桌面 | 空白 (614 B) |
| 把普通文件夹人为打上 Low 标签, 放同一个文件 | 复现空白 |
| 标签改回 Medium | 立刻恢复真实图标 |

唯一变量 = 文件夹完整性标签。

## 走过的弯路(都无效, 别再做)

1. 删除 / 重建 IconCache (iconcache_*.db) —— 无效, 还会清出"黄文件夹"新故障
2. 清 Bags / BagMRU —— 无效
3. 重启 explorer —— 无效
4. 重启电脑 —— 无效。Low 标签是文件系统上的持久属性, 重启不会清
5. 怀疑 imageres/shell32 图标资源、.lnk 关联、desktop.ini、ACL 读权限 —— 逐一验证, 全部无关

教训: 症状"只有 .lnk 白、其他正常"本身就是线索, 说明不是全局缓存问题。
第一步应该先对比"同一个文件在别的文件夹是否正常", 再决定查缓存还是查文件夹属性。

## 会复发 —— 原因和预防

### 复发源已定位 (2026-10-04 查明, 不再是猜测)

真凶是 DSH 自带的 Windows 沙箱后端 **`@deepseek-ai/dsh-sandbox-windows-acl`**
(代码在 `C:\Users\Administrator\.dsh\kernels\<版本>\node_modules\@deepseek-ai\dsh-sandbox-windows-acl`)。

机制(摘自该包 README.zh.md):

1. 沙箱把**工作区根目录**(= DSH 进程的 `process.cwd()`)当作授权根, 在该目录上一次性写入
   能力 SID 允许 ACE + 对 world SID 的 `FILE_DELETE_CHILD` 拒绝 + **可继承的 Low 完整性标签**。
2. 这三样都带 `(OI)(CI)` 继承, 所以**整棵工作区树**都会被染成 Low。
3. README 明确写着它们**按设计常驻、绝不撤销**:
   > "工作区 ACE、拒绝项与标签按设计常驻(复用缓存, 绝不撤销)"
   > "常驻 Low 标签的生命期长于 DSH"
   即: 沙箱退出、DSH 重启、电脑重启都**不会**清掉这个标签。

**而当前 DSH 的工作目录就是 `C:\Users\Administrator\Desktop`** —— 所以工作区根 = 桌面,
每一次以 `workspace-write` 模式跑的会话都会把 Low 标签重新盖到桌面上, 并继承到全部子目录
(本次实测: 桌面全树 14464 项**全部** Low)。

这也解释了文档早先记的"删缓存/重启都无效"以及"公共桌面正常"(公共桌面不是工作区)。

### 预防(按有效性排序)

1. **不要用桌面当工作目录。** 把 DSH 的工作目录换到独立文件夹, 例如
   `C:\Users\Administrator\dsh-workspace`, 让常驻 Low 标签落在那里而不是桌面。
   做法: 改启动 dsh 的快捷方式的"起始位置", 或 `cd` 到该目录后再启动。
   这是**唯一治本**的办法。
2. **把文件策略保持在 `danger-full-access`。** 该模式下不挂载 ACL 沙箱, 不产生标签。
   只要不用 `workspace-write` / `read-only`, 标签就不会被重新写。
3. 复发时: 双击桌面根目录的 `fix-icon-label.bat`(会自动提权), 或直接跑
   `icacls "C:\Users\Administrator\Desktop" /setintegritylevel (OI)(CI)Medium`。
   (实测**不提权也能成功**。)
4. 注意该包 README 的一句话: "工作区若等于或包含临时根目录, 会在任何授权前被拒绝" ——
   与本次无关, 但配置工作区时别把它设到 `%TEMP%` 下面。

### 手动清理残留在该平台行不通

README 另一条限制: 手工 `icacls` **无法**回收这些常驻 ACE/拒绝项
(`ERROR_NONE_MAPPED`, 1332), 必须通过该模块回收。但 Low **标签**用
`/setintegritylevel (OI)(CI)Medium` 是可以直接改掉的 —— 本次已验证有效。

## 2026-10-03 复发与修复记录

- 症状: 桌面 26 个 .lnk 全部空白纸 (图标索引 0), 公共桌面 / .exe / .png 正常。
- 诊断: `icacls` 确认 Desktop 为 Low; 受控实验(测试文件夹 -> 打 Low -> .lnk 索引 0 -> 改回 Medium -> 索引 50)确认因果。
  - **踩坑警告**: `SHGetFileInfo` 在**同一进程内**有图标缓存。复测必须**每个文件开新进程**,
    否则会拿到假阴性(先测正常再测 Low, 两者都返回 50, 会误判成"改标签无效、理论与文档不符")。
- 修复: `icacls "C:\Users\Administrator\Desktop" /setintegritylevel (OI)(CI)Medium`
  —— 本次**未提权即成功**(Administrator 对该文件夹有继承的完全控制), 不必非得管理员。
- 验证: 两个桌面 36 个 .lnk, 图标索引为 0 的: **0 个**。
  逐文件独立进程比对图标像素哈希, 空白页参照哈希 `7DF60F88BDFD` 无一命中。
- 取证: `桌面\04-文档报告\桌面图标修复后-20261003.png`
- 残留: Desktop 上仍有沙箱 ACE (`CodexSandboxUsers:(OI)(CI)(RX)`、
  `S-1-4-1039366120-933337351:(OI)(CI)(W,D,DC)`、`Everyone:(CI)(DENY)(DC)`,
  子目录继承为 `Everyone:(I)(CI)(DENY)(DC)`)。
  实测新建/删除仍正常(删除走子对象自身 DACL, 不依赖父目录 DELETE_CHILD), 故未清理。
  若日后要清: `icacls "C:\Users\Administrator\Desktop" /remove:d Everyone` 等, 建议先备份 ACL。

## 2026-10-04 第二次复发(Games 目录)与修复记录

- 触发: 用户报告 `桌面\Games` 里的图标也变白。
- 诊断: Desktop **根目录又变回 Low**(这次是根上的显式 ACE, 非继承),
  且 `(OI)(CI)` 继承把**整棵桌面树 14464 项全部**染成 Low —— Games 只是其中一个子目录。
  桌面根 27 个 .lnk + Games 29 个 .lnk 图标索引全为 0(空白)。
- 修复: `icacls "C:\Users\Administrator\Desktop" /setintegritylevel (OI)(CI)Medium`
  —— 根目录一改, 继承自动传播, 无需逐项处理。
- 验证: 桌面全树 **14465 项全部 Medium, 0 项 Low**。
  全树 **97 个 .lnk + 26 个 .url, 图标索引为 0 的: 0 个**。
- 取证: `桌面\04-文档报告\Games图标修复后-20261004.png`
- **性能提示**: 用 `icacls` 逐项递归扫全树极慢(>2 分钟)。改用 C#
  `GetNamedSecurityInfo(LABEL_SECURITY_INFORMATION)` + `GetAce` + `GetSidSubAuthority`
  读完整性级别, 14000+ 项只需数秒。探测脚本见本文末附录。

### 附带发现: 一个真正的坏图标引用(与标签无关)

`桌面\Games\冰汽时代.url` 的 `IconFile` 指向
`C:\Program Files (x86)\Steam\steam\games\ff63d3a47b367f7c434e391d1bce02c9d717e4b7.ico`,
而该文件**已被 Steam 删除**(appid 323190 已卸载, 不会重建)。这是独立故障。

- 已从 Steam 库缓存图 `appcache\librarycache\323190\library_600x900.jpg` 生成
  **10 尺寸多尺寸 ICO**(256/128/96/64/48/40/32/24/20/16, PNG 压缩), 存放于
  `桌面\Games\icons\Frostpunk-323190.ico`, 并把它指给该 .url。
- 原 .url 已备份: `桌面\04-文档报告\iconfix-backup\冰汽时代.url.bak-20261004-023034`
- **踩坑警告(重要)**: `.url` 的 `IconFile=` 是**按系统 ANSI(GBK/936)读取**的。
  PowerShell 7 的 `[System.Text.Encoding]::Default` 其实是 **UTF-8**, 用它写回会让
  含中文的路径变成乱码 → 图标依旧不显示(本次第一版就踩了这个坑)。
  正确做法: 用 `[System.Text.Encoding]::GetEncoding(936)` 写, 或者
  **图标路径干脆用纯 ASCII**, 更省事。

## 其他注意

- 删东西时说清楚: 删的是快捷方式, 不是密钥文件。
- 重建 .lnk 前先备份原 Target / Args / Icon, 并确认图标文件真实存在。
- ICO 文件要含多尺寸 (256/128/96/64/48/40/32/24/20/16), 单尺寸 ICO 在桌面 32/48px 下会显示空白
  —— 这是另一种"空白图标"原因, 与本文的标签问题不同, 注意区分。

## 相关文件

- 桌面\fix-icon-label.bat / fix-icon-label.ps1  修复脚本(把 Low 改回 Medium)
- 桌面\04-文档报告\check-integrity.ps1  快速体检: 打印桌面树完整性级别分布(**秒级**)
- 桌面\Games\icons\Frostpunk-323190.ico  为坏图标引用补的多尺寸 ICO
- 桌面\04-文档报告\iconfix-backup\  改动前的备份
- 桌面\04-文档报告\给Hermes的桌面交接报告-20261001.md  第八节有完整实验过程和排除清单
- 桌面\04-文档报告\桌面图标修复后-20261001.png  第一次修复取证
- 桌面\04-文档报告\桌面图标修复后-20261003.png  第二次修复取证(桌面)
- 桌面\04-文档报告\Games图标修复后-20261004.png  第三次修复取证(Games)

## 附: 完整性体检脚本 (check-integrity.ps1)

逐项 `icacls` 扫全树要 2 分钟以上; 下面是秒级版本(直接读 SACL)。

```powershell
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Integ {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern uint GetNamedSecurityInfo(string n,int t,uint i,IntPtr o,IntPtr g,IntPtr d,out IntPtr sacl,out IntPtr sd);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetAce(IntPtr acl,uint idx,out IntPtr ace);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr h);
  [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr sid,int n);
  public static int Level(string path){
    IntPtr sacl, sd;
    if(GetNamedSecurityInfo(path,1,0x10,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,out sacl,out sd)!=0) return -2;
    try{
      if(sacl==IntPtr.Zero) return -1;
      if(Marshal.ReadInt16(sacl,4)<=0) return -1;
      IntPtr ace; if(!GetAce(sacl,0,out ace)) return -2;
      return Marshal.ReadInt32(GetSidSubAuthority(new IntPtr(ace.ToInt64()+8),0));
    } finally { LocalFree(sd); }
  }
  public static string Name(int l)=> l==-1?"无标签":l==-2?"读取失败":l==0x1000?"Low":l==0x2000?"Medium":"0x"+l.ToString("X");
}
'@
$root = 'C:\Users\Administrator\Desktop'
$stat = @{}
$stat[[Integ]::Name([Integ]::Level($root))] = 1
Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $n = [Integ]::Name([Integ]::Level($_.FullName))
  if(-not $stat.ContainsKey($n)){ $stat[$n] = 0 }
  $stat[$n]++
}
$stat.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0,-10} {1}" -f $_.Key, $_.Value }
# Low 的项数 > 0 就是复发: icacls "$root" /setintegritylevel (OI)(CI)Medium
```
