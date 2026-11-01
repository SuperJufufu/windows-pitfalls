' ============================================================
'  Local AI Services Dashboard - launcher (lazy edition)
'  - double-click to run
'  - starts the dashboard backend hidden
'  - opens the panel in the browser
' ============================================================

Option Explicit

Dim WShell, FSO, scriptPath, port, i

port       = 7799
scriptPath = "C:\Users\Administrator\AppData\Local\hermes\scripts\ai_dashboard.py"

Set WShell = CreateObject("WScript.Shell")
Set FSO    = CreateObject("Scripting.FileSystemObject")

If Not FSO.FileExists(scriptPath) Then
    MsgBox "Dashboard script not found:" & vbCrLf & scriptPath, 16, "AI Panel"
    WScript.Quit 1
End If

' ---- already running? ----
If PortOpen(port) Then
    WShell.Run "http://127.0.0.1:" & port, 1, False
    WScript.Quit 0
End If

' ---- find a python with no PYTHONPATH pollution ----
On Error Resume Next
WShell.Environment("PROCESS")("PYTHONPATH") = ""
WShell.Environment("PROCESS")("PYTHONHOME") = ""
WShell.Environment("PROCESS")("VIRTUAL_ENV") = ""
On Error GoTo 0

' Prefer the Hermes venv python (guaranteed to exist on this machine)
Dim py
py = "C:\Users\Administrator\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe"
If Not FSO.FileExists(py) Then py = "python.exe"

WShell.Run """" & py & """ """ & scriptPath & """", 0, False

For i = 1 To 40
    WScript.Sleep 500
    If PortOpen(port) Then
        WShell.Run "http://127.0.0.1:" & port, 1, False
        WScript.Quit 0
    End If
Next

MsgBox "Dashboard did not start on port " & port & ".", 48, "AI Panel"


Function PortOpen(p)
    Dim h, ok
    ok = False
    On Error Resume Next
    Set h = CreateObject("MSXML2.XMLHTTP")
    h.Open "GET", "http://127.0.0.1:" & p & "/api/status", False
    h.Send
    If Err.Number = 0 Then ok = True
    Err.Clear
    On Error GoTo 0
    PortOpen = ok
End Function
