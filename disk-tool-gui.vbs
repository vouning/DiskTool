' Disk Tool GUI launcher - starts PowerShell hidden, no console window lingers.
' Double-click this file or run:  wscript.exe "disk-tool-gui.vbs"
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps = scriptDir & "\disk-tool-gui.ps1"
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps & """", 0, False