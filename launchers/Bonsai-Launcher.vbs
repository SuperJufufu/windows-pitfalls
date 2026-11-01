' ============================================================
'  Bonsai-2 launcher  --  PrismML patched build, port 8010
'  - starts the patched PrismML llama-server hidden
'  - waits for the port, then opens the built-in web UI
'
'  WHY 8010 AND NOT 8090
'  --------------------
'  There used to be TWO Bonsai servers on this machine:
'    8010  PrismML patched build  (--spec-type draft-mtp, CUDA 12.8)
'    8090  Bonsai-demo standard build
'  Both loaded the SAME 7 GB model with -ngl 99, and on a 16 GB
'  GPU only one fits. Worse, the 8010 script has a VRAM guard
'  (refuses to start below 12000 MiB free) while the 8090 script
'  has none -- so starting 8090 would SILENTLY lock out 8010,
'  which is the server SillyTavern's 8020 bridge talks to.
'
'  Unified on 8010: it is the patched build (MTP speculative
'  decoding, ~1.8-2x faster decode) and the chat stack already
'  depends on it. The Bonsai-demo 8090 server is now unused.
' ============================================================

Option Explicit

Dim WShell, FSO, baseDir, ps1, url, port, i

url     = "http://127.0.0.1:8010/"
port    = 8010
baseDir = "C:\Users\Administrator\Documents\Codex\2026-09-26\ni\outputs"
ps1     = baseDir & "\start-bonsai-prism-mtp.ps1"

Set WShell = CreateObject("WScript.Shell")
Set FSO    = CreateObject("Scripting.FileSystemObject")

If Not FSO.FolderExists(baseDir) Then
    MsgBox "PrismML Bonsai folder not found:" & vbCrLf & baseDir, 16, "Bonsai"
    WScript.Quit 1
End If
If Not FSO.FileExists(ps1) Then
    MsgBox "Launcher script not found:" & vbCrLf & ps1, 16, "Bonsai"
    WScript.Quit 1
End If

' ---- already running? just open the UI ----
If PortOpen(port) Then
    WShell.Run url, 1, False
    WScript.Quit 0
End If

' ---- launch hidden (0 = no window) ----
WShell.CurrentDirectory = baseDir
WShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """", 0, False

' ---- wait for the port (model loads in ~15s; allow up to 5 min) ----
For i = 1 To 200
    WScript.Sleep 1500
    If PortOpen(port) Then
        WShell.Run url, 1, False
        WScript.Quit 0
    End If
Next

MsgBox "Bonsai Prism llama-server did not start within 5 minutes." & vbCrLf & vbCrLf & _
       "Common cause: not enough free GPU memory." & vbCrLf & _
       "The Prism script refuses to start unless >= 12000 MiB VRAM is free." & vbCrLf & _
       "Stop ComfyUI / the image studio's audit model first, then retry." & vbCrLf & vbCrLf & _
       "To stop an existing Bonsai: use the desktop shortcut" & vbCrLf & _
       "'Stop Bonsai Prism service'.", 48, "Bonsai"


Function PortOpen(p)
    Dim h, ok
    ok = False
    On Error Resume Next
    Set h = CreateObject("MSXML2.XMLHTTP")
    h.Open "GET", "http://127.0.0.1:" & p & "/health", False
    h.Send
    If Err.Number = 0 Then ok = True
    Err.Clear
    On Error GoTo 0
    PortOpen = ok
End Function
