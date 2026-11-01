' ============================================================
'  Octop-Launcher.vbs  --  double-click entry for the Octop service
'  (http://127.0.0.1:8089 : TencentCloud Octop self-hosted AI assistant)
'
'  It only launches open-octop.ps1 hidden.  That script does the real work:
'    1) if Octop already answers on 8089 -> just open the browser
'       (no second server, no duplicate process);
'    2) if ~/.octop is missing -> tell the user to run `octop init` first;
'    3) otherwise start `octop run` hidden and WAIT until it really answers;
'    4) log one line per run to launchers\octop-launcher.log.
'
'  Why a VBS shim: it starts PowerShell with no console window, so a
'  double-click does not flash a black box on screen.  ASCII-only on purpose
'  (WScript reads .vbs as ANSI; Chinese text in a UTF-8 file turns to mojibake).
' ============================================================

Option Explicit

Dim WShell, FSO, dir, ps1, extra, i, a

dir = "C:\Users\Administrator\Desktop\launchers"
ps1 = dir & "\open-octop.ps1"

Set WShell = CreateObject("WScript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

If Not FSO.FileExists(ps1) Then
    MsgBox "launcher missing:" & vbCrLf & ps1, 16, "Octop"
    WScript.Quit 1
End If

WShell.CurrentDirectory = dir

' 0 = hidden window, False = do not wait (the script waits on the port itself)
' 1 = normal window is NOT used here; but for the "not initialized" message we
'     want the user to SEE it, so open-octop.ps1 shows its own console output.
extra = ""
For i = 0 To WScript.Arguments.Count - 1
    a = LCase(WScript.Arguments(i))
    If a = "/nobrowser" Or a = "-nobrowser" Or a = "--no-browser" Then
        extra = " -NoBrowser"
    End If
Next

WShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """" & extra, 0, False

WScript.Quit 0
