' ============================================================
'  ComfyUI Launcher (lazy edition)
'  - double-click to run
'  - starts the server hidden (no console window)
'  - opens the browser when ready
'  - if already running, just opens the browser
' ============================================================

Option Explicit

Dim WShell, FSO, baseDir, pyExe, args, url, port, i
Dim env

url     = "http://127.0.0.1:8188"
port    = 8188
baseDir = "C:\ComfyUI_windows_portable\ComfyUI_Windows_portable"

Set WShell = CreateObject("WScript.Shell")
Set FSO    = CreateObject("Scripting.FileSystemObject")

If Not FSO.FolderExists(baseDir) Then
    MsgBox "ComfyUI folder not found:" & vbCrLf & baseDir, 16, "ComfyUI"
    WScript.Quit 1
End If

pyExe = baseDir & "\python_standalone\python.exe"
If Not FSO.FileExists(pyExe) Then
    MsgBox "python.exe not found:" & vbCrLf & pyExe, 16, "ComfyUI"
    WScript.Quit 1
End If

' ---- already running? ----
If PortOpen(port) Then
    WShell.Run url, 1, False
    WScript.Quit 0
End If

' ---- clear the leaked Hermes venv vars for this process tree ----
' Launching through the shell inherits the user environment; blank the three
' vars that break the standalone python (they point at the Hermes venv).
On Error Resume Next
WShell.Environment("PROCESS")("PYTHONPATH") = ""
WShell.Environment("PROCESS")("PYTHONHOME") = ""
WShell.Environment("PROCESS")("VIRTUAL_ENV") = ""
WShell.Environment("PROCESS")("PYTHONNOUSERSITE") = "1"
' HuggingFace downloads: the bundled python cannot reach huggingface.co
' (aiohttp connect fails while plain urllib works), so route them through
' the mirror. Without this, WD14-Tagger / Florence2 / QwenVL model
' downloads all die with "Cannot connect to host huggingface.co:443".
WShell.Environment("PROCESS")("HF_ENDPOINT") = "https://hf-mirror.com"
On Error GoTo 0

' ---- start the server hidden, no cmd wrapper ----
' --output-directory sends generated images to a folder on the Desktop
' NOTE: keep the folder name ASCII-only — a CN name gets mangled by the
' console codepage when passed through WScript.Shell.Run.
args = "-s ""ComfyUI\main.py"" --listen 127.0.0.1 --port " & port & _
       " --disable-xformers --use-pytorch-cross-attention" & _
       " --output-directory ""C:\Users\Administrator\Desktop\ComfyUI-Output"""

WShell.CurrentDirectory = baseDir
WShell.Run """" & pyExe & """ " & args, 0, False

' ---- wait for the port (up to ~3 min), then open the browser ----
For i = 1 To 120
    WScript.Sleep 1500
    If PortOpen(port) Then
        WShell.Run url, 1, False
        WScript.Quit 0
    End If
Next

MsgBox "ComfyUI did not answer on port " & port & " within 3 minutes." & vbCrLf & _
       "It may still be loading models - try the browser again shortly.", _
       48, "ComfyUI"


Function PortOpen(p)
    Dim h, ok
    ok = False
    On Error Resume Next
    Set h = CreateObject("MSXML2.XMLHTTP")
    h.Open "GET", "http://127.0.0.1:" & p & "/", False
    h.Send
    If Err.Number = 0 Then ok = True
    Err.Clear
    On Error GoTo 0
    PortOpen = ok
End Function
