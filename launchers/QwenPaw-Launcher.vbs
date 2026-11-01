' ============================================================
'  QwenPaw-Launcher.vbs  --  double-click entry for the QwenPaw service
'  (http://127.0.0.1:8088 : the OpenClaw backend that N.E.K.O. talks to)
'
'  It only launches open-qwenpaw.ps1 hidden.  That script does the real work:
'    1) if QwenPaw already answers on 8088 -> just open the browser
'       (no second server, no duplicate process);
'    2) otherwise start `qwenpaw app` hidden and WAIT until it really answers;
'    3) log one line per run to launchers\qwenpaw-launcher.log.
'
'  Why a VBS shim: it starts PowerShell with no console window, so a
'  double-click does not flash a black box on screen.  ASCII-only on purpose
'  (WScript reads .vbs as ANSI; Chinese text in a UTF-8 file turns to mojibake).
'
'  Note: N.E.K.O. needs this service running to use its "OpenClaw" switch.
' ============================================================

Option Explicit

Dim WShell, FSO, dir, ps1, extra, i, a

dir = "C:\Users\Administrator\Desktop\launchers"
ps1 = dir & "\open-qwenpaw.ps1"

Set WShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

If Not FSO.FileExists(ps1) Then
    MsgBox "launcher missing:" & vbCrLf & ps1, 16, "QwenPaw"
    WScript.Quit 1
End If

WShell.CurrentDirectory = dir

' 0 = hidden window, False = do not wait (the script waits on the port itself)
extra = ""
For i = 0 To WScript.Arguments.Count - 1
    a = LCase(WScript.Arguments(i))
    If a = "/nobrowser" Or a = "-nobrowser" Or a = "--no-browser" Then
        extra = " -NoBrowser"
    End If
Next

WShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """" & extra, 0, False

WScript.Quit 0
