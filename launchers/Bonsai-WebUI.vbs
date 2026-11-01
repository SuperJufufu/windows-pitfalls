' ============================================================
'  Bonsai Web UI launcher  (Open WebUI on :9090)
'
'  ChatGPT-style interface in front of the local Bonsai 27B
'  (which itself runs on :8010 via the PrismML llama-server).
'
'  - double-click, no console window
'  - if :9090 already answers, just opens the browser
'  - otherwise starts open-webui hidden, waits, then opens it
' ============================================================

Option Explicit

Const WAIT_SECONDS = 180
Const SETTLE_MS    = 1500

Dim WShell, FSO, port, homeUrl, exePath, workDir
Dim logFolder, logPath

Set WShell = CreateObject("WScript.Shell")
Set FSO    = CreateObject("Scripting.FileSystemObject")

port     = 9090
homeUrl  = "http://127.0.0.1:9090/"
exePath  = "C:\Users\Administrator\.local\Bonsai-Prism\OpenWebUI\.venv\Scripts\open-webui.exe"
workDir  = "C:\Users\Administrator\.local\Bonsai-Prism\OpenWebUI"
logFolder = WShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\BonsaiWebUI"
logPath  = logFolder & "\launcher.log"

If Not FSO.FileExists(exePath) Then
    MsgBox "open-webui.exe not found:" & vbCrLf & exePath & vbCrLf & vbCrLf & _
           "The Bonsai demo's Open WebUI venv is missing." & vbCrLf & _
           "Reinstall with: uv pip install "".[webui]""", 16, "Bonsai Web UI"
    WScript.Quit 1
End If

If Not FSO.FolderExists(logFolder) Then
    On Error Resume Next
    FSO.CreateFolder logFolder
    On Error GoTo 0
End If

' ---- already serving? ----
If PortOpen(port) Then
    LogLine "Port " & port & " already answered; opening browser."
    WShell.Run homeUrl, 1, False
    WScript.Quit 0
End If

' ---- start hidden and wait ----
' CRITICAL: clear PYTHONPATH / PYTHONHOME / VIRTUAL_ENV before launching.
' If this VBS is started from a shell that has an active venv (e.g. Hermes'
' own), the child open-webui inherits that venv and dies with
'   ModuleNotFoundError: No module named 'pydantic_core._pydantic_core'
' because it resolves packages from the wrong site-packages.
LogLine "Starting open-webui on port " & port & "."
Dim launch
launch = "cmd /d /c set ""PYTHONPATH="" && set ""PYTHONHOME="" && set ""VIRTUAL_ENV="" && " & _
         "cd /d """ & workDir & """ && """ & exePath & """ serve --host 127.0.0.1 --port " & port & _
         " > """ & logFolder & "\webui-out.txt"" 2>&1"
WShell.Run launch, 0, False

If WaitForPort(WAIT_SECONDS) Then
    LogLine "Ready on port " & port & "."
    WShell.Run homeUrl, 1, False
    WScript.Quit 0
End If

LogLine "Timeout after " & WAIT_SECONDS & "s."
MsgBox "The Bonsai Web UI did not answer on port " & port & " within " & _
       WAIT_SECONDS & " seconds." & vbCrLf & vbCrLf & _
       "Launcher log: " & logPath & vbCrLf & _
       "Server output: " & logFolder & "\webui-out.txt", 48, "Bonsai Web UI"
WScript.Quit 4


' ---------------------------------------------------------------- helpers --

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
