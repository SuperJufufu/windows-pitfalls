' ============================================================
'  DSH launcher v2 —— token-aware, self-healing
'
'  WHY v2: DSH (0.1.7-rc.2) prints a RANDOM token on every start:
'      dsh web: http://127.0.0.1:3080/?token=<random>
'  Opening bare http://127.0.0.1:3080/ gives a BLACK PAGE
'  ("dsh web authentication required"), which users read as "it broke".
'  So the launcher must capture the token from DSH's stdout and open
'  the FULL url.
'
'  It also self-heals the "randomly hangs" failure:
'      dsh.exe dies without killing its node child
'        -> orphan node keeps :3080
'        -> next start: webserver plugin EADDRINUSE
'        -> "2 required plugins did not activate" + zombie processes
'
'  Syntax note: 0.1.7-rc.2 takes NO subcommand and NO --profile here
'  (the profile is already baked into dsh.exe). `dsh web` and
'  `dsh --profile web` both fail with "too many arguments" /
'  "select a profile only once". Plain `dsh.exe` is correct.
' ============================================================

Option Explicit

Const WAIT_SECONDS   = 180
Const SETTLE_MS      = 1200
Const LOCK_STALE_SEC = 600
Const TOKEN_WAIT_MS  = 40000

Dim WShell, FSO, exePath, workDir, port, homeUrl
Dim lockFolder, lockPath, logPath, dshLogFolder, outPath
Dim lockFile, acquired

Set WShell = CreateObject("WScript.Shell")
Set FSO    = CreateObject("Scripting.FileSystemObject")

exePath      = "C:\Users\Administrator\Desktop\dsh.exe"
workDir      = "C:\Users\Administrator\Desktop"
port         = 3080
homeUrl      = "http://127.0.0.1:3080/"
lockFolder   = WShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\DeepSeekHarness"
lockPath     = lockFolder & "\launcher.lock"
logPath      = lockFolder & "\launcher.log"
outPath      = lockFolder & "\dsh-stdout.txt"
dshLogFolder = WShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\.dsh\logs"

If Not FSO.FileExists(exePath) Then
    MsgBox "dsh.exe not found:" & vbCrLf & exePath, 16, "DSH"
    WScript.Quit 1
End If

If Not FSO.FolderExists(lockFolder) Then
    On Error Resume Next
    FSO.CreateFolder lockFolder
    On Error GoTo 0
End If

' ---- 1. already healthy? (need BOTH HTTP answer AND a live dsh.exe) ----
Dim liveDsh, tok
CountDsh liveDsh
tok = SavedToken()
If PortOpen(port) And liveDsh > 0 Then
    ReleaseStaleLock
    LogLine "Healthy: port answered and dsh.exe alive; opening saved-token URL."
    OpenUi tok
    WScript.Quit 0
End If
If PortOpen(port) And liveDsh = 0 Then
    LogLine "Port answers but no dsh.exe -> orphaned kernel; restarting."
End If

' ---- 2. serialize rapid double-clicks ----
' The lock is a file whose CONTENT is the owning PID. A lock is considered
' stale when (a) it is older than LOCK_STALE_SEC, or (b) the PID inside it is
' no longer alive. Without the PID check a launcher killed mid-start (e.g. by
' a timeout) leaves the lock behind forever and blocks every later launch with
' "Another launcher holds the lock".
Dim lockPid, lockValid
lockValid = False
If FSO.FileExists(lockPath) Then
    On Error Resume Next
    Dim oldLock, lockAge
    lockPid = 0
    Set oldLock = FSO.GetFile(lockPath)
    If Err.Number = 0 Then
        lockAge = DateDiff("s", oldLock.DateLastModified, Now)
        If lockAge > LOCK_STALE_SEC Then
            FSO.DeleteFile lockPath, True
            LogLine "Lock stale by age (" & lockAge & "s); removed."
        Else
            lockPid = CLng(ReadLockPid())
            If lockPid <= 0 Or Not PidAlive(lockPid) Then
                FSO.DeleteFile lockPath, True
                LogLine "Lock owner pid=" & lockPid & " is dead; lock removed."
            Else
                lockValid = True
            End If
        End If
    End If
    Err.Clear
    On Error GoTo 0
End If

acquired = False
On Error Resume Next
Set lockFile = FSO.CreateTextFile(lockPath, False, True)
If Err.Number = 0 Then
    lockFile.WriteLine CurrentPid()
    lockFile.Close
    acquired = True
End If
Err.Clear
On Error GoTo 0

If Not acquired Then
    LogLine "Another launcher holds the lock; waiting for port " & port & "."
    If WaitForPort(WAIT_SECONDS) Then
        OpenUi SavedToken()
        WScript.Quit 0
    End If
    WScript.Quit 2
End If

' ---- 3. PRE-CLEAN: guarantee the port is free before spawning ----
Dim preOwner, preName, preDsh
preOwner = PortOwnerPid(port)
CountDsh preDsh
If preOwner > 0 Then
    preName = NameOfPid(preOwner)
    LogLine "Pre-clean: port held by " & preName & " (pid=" & preOwner & "); clearing."
    KillPid preOwner
    WScript.Sleep SETTLE_MS
End If
If preDsh > 0 Then
    LogLine "Pre-clean: killing " & preDsh & " lingering dsh.exe."
    KillAllDsh
    WScript.Sleep SETTLE_MS
End If
If PortOwnerPid(port) > 0 Then
    LogLine "Pre-clean: port still busy."
    MsgBox "Port " & port & " is still in use by another program." & vbCrLf & _
           "DSH cannot start until it is free." & vbCrLf & vbCrLf & _
           "Launcher log: " & logPath, 48, "DSH"
    WScript.Quit 5
End If

' ---- 4. start with --no-open and capture the token URL ----
' --no-open stops DSH opening a token-less browser tab itself.
' NOTE: build the redirect with an explicit /d + cd chain. A bare
'       `cmd /c "exe" args > file` breaks when the exe path contains spaces,
'       and WShell.CurrentDirectory does NOT affect the child cmd's cwd
'       reliably — which silently produced no output file at all.
CleanupFile outPath
LogLine "Starting dsh.exe (--no-open) and capturing the token URL."
StartDsh

If WaitForPort(WAIT_SECONDS) Then
    tok = WaitForToken(TOKEN_WAIT_MS)
    SaveToken tok
    LogLine "Ready on port " & port & "."
    CleanupLock
    OpenUi tok
    WScript.Quit 0
End If

' ---- 5. one clean retry ----
LogLine "Timeout; performing one clean restart."
KillAllDsh
If PortOwnerPid(port) > 0 Then KillPid PortOwnerPid(port)
WScript.Sleep SETTLE_MS
CleanupFile outPath
StartDsh

If WaitForPort(WAIT_SECONDS) Then
    tok = WaitForToken(TOKEN_WAIT_MS)
    SaveToken tok
    LogLine "Recovered after clean restart."
    CleanupLock
    OpenUi tok
    WScript.Quit 0
End If

LogLine "Giving up: port never answered."
CleanupLock
MsgBox "DSH did not answer on port " & port & " after two attempts." & vbCrLf & vbCrLf & _
       "Launcher log: " & logPath & vbCrLf & _
       "DSH logs: " & dshLogFolder, 48, "DSH"
WScript.Quit 4


' ---------------------------------------------------------------- helpers --

' Open the UI using the freshest known token; fall back to the bare URL.
Sub OpenUi(t)
    Dim u
    If t = "" Then
        u = homeUrl
        LogLine "No token captured; opening bare URL (may show the auth notice)."
    Else
        u = homeUrl & "?token=" & t
    End If
    WShell.Run u, 1, False
End Sub

' Poll the captured stdout for the token URL.
Function WaitForToken(timeoutMs)
    Dim waited, t
    waited = 0
    Do
        t = ScanToken()
        If t <> "" Then
            WaitForToken = t
            Exit Function
        End If
        WScript.Sleep 500
        waited = waited + 500
    Loop While waited < timeoutMs
    WaitForToken = ""
End Function

Function ScanToken()
    Dim ts, line, idx, rest
    ScanToken = ""
    On Error Resume Next
    If Not FSO.FileExists(outPath) Then Exit Function
    Set ts = FSO.OpenTextFile(outPath, 1, False, -2)
    Do While Not ts.AtEndOfStream
        line = ts.ReadLine
        idx = InStr(line, "token=")
        If idx > 0 Then
            rest = Mid(line, idx + 6)
            rest = Split(rest, "&")(0)
            rest = Split(rest, " ")(0)
            rest = Split(rest, Chr(34))(0)
            If Len(rest) > 8 Then ScanToken = rest
        End If
    Loop
    ts.Close
    Err.Clear
    On Error GoTo 0
End Function

Sub SaveToken(t)
    On Error Resume Next
    Dim f
    Set f = FSO.CreateTextFile(lockFolder & "\last-token.txt", True, False)
    f.WriteLine t
    f.Close
    Err.Clear
    On Error GoTo 0
End Sub

Function SavedToken()
    Dim ts
    SavedToken = ""
    On Error Resume Next
    If FSO.FileExists(lockFolder & "\last-token.txt") Then
        Set ts = FSO.OpenTextFile(lockFolder & "\last-token.txt", 1, False, -2)
        If Not ts.AtEndOfStream Then SavedToken = Trim(ts.ReadLine)
        ts.Close
    End If
    Err.Clear
    On Error GoTo 0
End Function

Sub CleanupFile(p)
    On Error Resume Next
    If FSO.FileExists(p) Then FSO.DeleteFile p, True
    Err.Clear
    On Error GoTo 0
End Sub

Function PortOpen(p)
    Dim req
    PortOpen = False
    On Error Resume Next
    Set req = CreateObject("WinHttp.WinHttpRequest.5.1")
    If Err.Number = 0 Then
        req.SetProxy 1
        req.SetTimeouts 500, 750, 1500, 1500
        req.Open "GET", "http://127.0.0.1:" & p & "/", False
        req.Send
        If Err.Number = 0 Then
            If req.Status >= 100 Then PortOpen = True
        End If
    End If
    Err.Clear
    On Error GoTo 0
End Function

Function WaitForPort(timeoutSeconds)
    Dim t0
    t0 = Timer
    Do
        If PortOpen(port) Then
            WaitForPort = True
            Exit Function
        End If
        If Elapsed(t0) >= timeoutSeconds Then Exit Do
        WScript.Sleep 1000
    Loop
    WaitForPort = False
End Function

Function Elapsed(t0)
    Dim t
    t = Timer
    If t < t0 Then t = t + 86400
    Elapsed = t - t0
End Function

Function Wmi()
    On Error Resume Next
    Dim s
    Set s = GetObject("winmgmts:\\.\root\cimv2")
    If Err.Number <> 0 Then
        Err.Clear
        Set Wmi = Nothing
        Exit Function
    End If
    Set Wmi = s
End Function

Sub CountDsh(ByRef n)
    Dim svc, q, p
    n = 0
    Set svc = Wmi()
    If svc Is Nothing Then Exit Sub
    On Error Resume Next
    Set q = svc.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='dsh.exe'")
    If Err.Number <> 0 Then
        Err.Clear
        Exit Sub
    End If
    For Each p In q
        n = n + 1
    Next
    Err.Clear
    On Error GoTo 0
End Sub

Sub KillAllDsh()
    Dim svc, q, p
    Set svc = Wmi()
    If svc Is Nothing Then Exit Sub
    On Error Resume Next
    Set q = svc.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='dsh.exe'")
    For Each p In q
        p.Terminate()
    Next
    Err.Clear
    On Error GoTo 0
End Sub

Function NameOfPid(pidValue)
    Dim svc, q, p
    NameOfPid = ""
    Set svc = Wmi()
    If svc Is Nothing Then Exit Function
    On Error Resume Next
    Set q = svc.ExecQuery("SELECT Name FROM Win32_Process WHERE ProcessId=" & pidValue)
    For Each p In q
        NameOfPid = CStr(p.Name)
    Next
    Err.Clear
    On Error GoTo 0
End Function

Sub KillPid(pidValue)
    Dim svc, q, p
    Set svc = Wmi()
    If svc Is Nothing Then Exit Sub
    On Error Resume Next
    Set q = svc.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE ProcessId=" & pidValue)
    For Each p In q
        p.Terminate()
    Next
    Err.Clear
    On Error GoTo 0
End Sub

' PID listening on the port, or 0.
' NOTE: use CLng, not CInt — netstat PIDs exceed Integer's 32767 limit and
' CInt raises, which (under On Error Resume Next) silently yields 0 and
' disables the whole pre-clean path.
Function PortOwnerPid(p)
    Dim sh, fso2, tmp, ts, line, tokens, k, last, needle
    PortOwnerPid = 0
    On Error Resume Next
    needle = ":" & p
    Set sh = CreateObject("WScript.Shell")
    Set fso2 = CreateObject("Scripting.FileSystemObject")
    tmp = sh.ExpandEnvironmentStrings("%TEMP%") & "\dsh_port_owner.txt"
    sh.Run "cmd /c netstat -ano -p TCP | findstr LISTENING | findstr " & needle & " > """ & tmp & """", 0, True
    If fso2.FileExists(tmp) Then
        Set ts = fso2.OpenTextFile(tmp, 1)
        Do While Not ts.AtEndOfStream
            line = Trim(ts.ReadLine)
            If InStr(line, needle & " ") > 0 And InStr(line, "LISTENING") > 0 Then
                tokens = Split(line, " ")
                last = ""
                For k = 0 To UBound(tokens)
                    If Trim(tokens(k)) <> "" Then last = Trim(tokens(k))
                Next
                If IsNumeric(last) Then
                    If CLng(last) > 0 Then
                        PortOwnerPid = CLng(last)
                        Exit Do
                    End If
                End If
            End If
        Loop
        ts.Close
        fso2.DeleteFile tmp, True
    End If
    Err.Clear
    On Error GoTo 0
End Function

Sub ReleaseStaleLock()
    On Error Resume Next
    If FSO.FileExists(lockPath) Then FSO.DeleteFile lockPath, True
    Err.Clear
    On Error GoTo 0
End Sub

' ---- lock helpers (PID-based so a dead owner can never wedge the launcher) ----

' Launch DSH with --no-open, redirecting all output to outPath.
' /d sets cmd's own working directory explicitly — more reliable than
' relying on WScript.Shell.CurrentDirectory to propagate to the child.
Sub StartDsh()
    Dim cmd
    cmd = "cmd /d /c cd /d """ & workDir & """ && """ & exePath & """ --no-open > """ & outPath & """ 2>&1"
    WShell.Run cmd, 0, False
End Sub

Function CurrentPid()
    Dim svc, q, p
    CurrentPid = 0
    Set svc = Wmi()
    If svc Is Nothing Then Exit Function
    On Error Resume Next
    Set q = svc.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='cscript.exe' OR Name='wscript.exe'")
    Dim best
    best = 0
    For Each p In q
        ' our own PID is the largest among our (usually single) host processes
        If p.ProcessId > best Then best = p.ProcessId
    Next
    CurrentPid = best
    Err.Clear
    On Error GoTo 0
End Function

Function ReadLockPid()
    Dim ts, v
    ReadLockPid = 0
    On Error Resume Next
    If FSO.FileExists(lockPath) Then
        Set ts = FSO.OpenTextFile(lockPath, 1, False, -2)
        If Not ts.AtEndOfStream Then v = Trim(ts.ReadLine)
        ts.Close
        If IsNumeric(v) Then ReadLockPid = CLng(v)
    End If
    Err.Clear
    On Error GoTo 0
End Function

Function PidAlive(pidValue)
    Dim svc, q, p, found
    PidAlive = False
    found = False
    Set svc = Wmi()
    If svc Is Nothing Then
        ' cannot verify -> assume alive, safer than stealing a live lock
        PidAlive = True
        Exit Function
    End If
    On Error Resume Next
    Set q = svc.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE ProcessId=" & pidValue)
    For Each p In q
        found = True
    Next
    PidAlive = found
    Err.Clear
    On Error GoTo 0
End Function

Sub CleanupLock()
    ReleaseStaleLock
End Sub

Sub LogLine(message)
    Dim f
    On Error Resume Next
    Set f = FSO.OpenTextFile(logPath, 8, True, -1)
    If Err.Number = 0 Then
        f.WriteLine CStr(Now) & vbTab & message
        f.Close
    End If
    Err.Clear
    On Error GoTo 0
End Sub
