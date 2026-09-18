$ProgressPreference='SilentlyContinue'
$ErrorActionPreference='Stop'
$root=$LogRoot
New-Item -ItemType Directory -Path $root -Force | Out-Null
$logPath=Join-Path $root 'last-run.log'
$history=Join-Path $root 'history.log'
$mutex=New-Object Threading.Mutex($false,'Local\AlienwareLightSwitch')
$locked=$false
$ownedPid=$null
$ownedStart=$null
$userTookOver=$false
$inputAtLaunch=0
$exe=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Alienware\Alienware Command Center\AWCC\AWCC.exe'
function Log([string]$Message){
 $line=('{0:o} {1}' -f (Get-Date),$Message)
 $line | Add-Content -LiteralPath $logPath -Encoding UTF8
 $line | Add-Content -LiteralPath $history -Encoding UTF8
 [Console]::WriteLine($line)
}
function Get-AwccWindow {
 $processes=@(Get-Process AWCC -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.Path -eq $exe})
 if($processes.Count -eq 1){return [Windows.Automation.AutomationElement]::FromHandle($processes[0].MainWindowHandle)}
 if($processes.Count -gt 1){throw 'Multiple AWCC windows found. Close duplicate windows and retry.'}
 return $null
}
function Protect-WindowOwnership($Window) {
 if(-not $ownedPid -or -not $Window){return}
 if($Window.Current.ProcessId -ne $ownedPid){return}
 $handle=[IntPtr]$Window.Current.NativeWindowHandle
 if([AwccWindowActivity]::GetForegroundWindow() -eq $handle -and [AwccWindowActivity]::LastInput() -ne $inputAtLaunch){
  if(-not $script:userTookOver){Log 'AWCC_USER_TAKEOVER Keeping the window available.'}
  $script:userTookOver=$true
 }
 if(-not $script:userTookOver){
  $pattern=$null
  if($Window.TryGetCurrentPattern([Windows.Automation.WindowPattern]::Pattern,[ref]$pattern) -and $pattern.Current.CanMinimize){
   if($pattern.Current.WindowVisualState -ne [Windows.Automation.WindowVisualState]::Minimized){
    $pattern.SetWindowVisualState([Windows.Automation.WindowVisualState]::Minimized)
   }
  }
 }
}
function Finish-OwnedWindow {
 if(-not $ownedPid){Log 'AWCC_EXISTING_WINDOW_PRESERVED';return}
 $window=Get-AwccWindow
 Protect-WindowOwnership $window
 if($script:userTookOver){Log 'AWCC_CLOSE_SKIPPED User took over the window.';return}
 $process=Get-Process -Id $ownedPid -ErrorAction SilentlyContinue
 if(-not $process){Log 'AWCC_OWNED_PROCESS_ALREADY_EXITED';return}
 if($process.Path -ne $exe -or $process.StartTime.Ticks -ne $ownedStart){Log 'AWCC_CLOSE_SKIPPED Ownership could not be confirmed.';return}
 if(-not $window -or $window.Current.ProcessId -ne $ownedPid){Log 'AWCC_CLOSE_SKIPPED Window ownership changed.';return}
 $visual=[Windows.Automation.WindowPattern]$window.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern)
 if($visual.Current.WindowVisualState -eq [Windows.Automation.WindowVisualState]::Minimized){Log 'AWCC_OWNED_BACKGROUND_VERIFIED'}
 if(-not $process.CloseMainWindow()){Log 'WINDOW_WARNING Could not request a normal AWCC close.';return}
 $deadline=(Get-Date).AddSeconds(5)
 do {
  Start-Sleep -Milliseconds 100
  $process.Refresh()
  if($process.HasExited -or $process.MainWindowHandle -eq 0){Log 'AWCC_OWNED_WINDOW_CLOSED_VERIFIED';return}
 } while((Get-Date) -lt $deadline)
 Log 'WINDOW_WARNING AWCC did not close promptly. It was not forcibly terminated.'
}
function Find-Id([string]$Id) {
 $window=Get-AwccWindow
 if(-not $window){return $null}
 Protect-WindowOwnership $window
 $condition=New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,$Id)
 $matches=$window.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)
 if($matches.Count -gt 1){throw ('Ambiguous AWCC control: '+$Id)}
 if($matches.Count -eq 1){return $matches[0]}
 return $null
}
function Wait-Id([string]$Id,[int]$Timeout=15) {
 $until=(Get-Date).AddSeconds($Timeout)
 do {
  $element=Find-Id $Id
  if($element -and $element.Current.IsEnabled){return $element}
  Start-Sleep -Milliseconds 250
 } while((Get-Date) -lt $until)
 throw ('AWCC control unavailable: '+$Id)
}
function Select-Control($Element){
 ([Windows.Automation.SelectionItemPattern]$Element.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)).Select()
}
function Read-Lighting {
 $light=Wait-Id 'FX_GlobalBrightness_RadioButton_RadioButton1'
 $dark=Wait-Id 'FX_GlobalBrightness_RadioButton_RadioButton2'
 $dim=Wait-Id 'FX_GlobalBrightness_RadioButton_RadioButton3'
 if(([Windows.Automation.SelectionItemPattern]$dark.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)).Current.IsSelected){return 'Off'}
 if(([Windows.Automation.SelectionItemPattern]$light.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)).Current.IsSelected){return 'On'}
 if(([Windows.Automation.SelectionItemPattern]$dim.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)).Current.IsSelected){return 'Dim'}
 throw 'AWCC did not expose a selected lighting mode.'
}
try {
 $locked=$mutex.WaitOne(0)
 if(-not $locked){throw 'Another lighting change is already running. Please wait and try again.'}
 Add-Type -AssemblyName UIAutomationClient
 Add-Type -AssemblyName UIAutomationTypes
 '' | Set-Content -LiteralPath $logPath -Encoding UTF8
 Log ('START requested='+$Mode+' PID='+$PID)
 if(-not (Test-Path -LiteralPath $exe)){throw 'Alienware Command Center is not installed at the expected location.'}
 Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AwccWindowActivity {
 [StructLayout(LayoutKind.Sequential)] struct InputInfo { public uint Size; public uint Time; }
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref InputInfo info);
 public static uint LastInput(){var info=new InputInfo();info.Size=(uint)Marshal.SizeOf(info);return GetLastInputInfo(ref info)?info.Time:0;}
}
"@
 $alreadyRunning=@(Get-Process AWCC -ErrorAction SilentlyContinue | Where-Object Path -eq $exe)
 if($alreadyRunning.Count -eq 0){
  $inputAtLaunch=[AwccWindowActivity]::LastInput()
  $launched=Start-Process -FilePath $exe -WindowStyle Minimized -RedirectStandardOutput (Join-Path $root 'awcc-stdout.log') -RedirectStandardError (Join-Path $root 'awcc-stderr.log') -PassThru
  $ownedPid=$launched.Id
  $ownedStart=$launched.StartTime.Ticks
  Log ('AWCC_OWNED_LAUNCH pid='+$ownedPid)
 } elseif(-not (Get-AwccWindow)){
  # Do not claim an existing background instance as our own.
  Start-Process -FilePath $exe -WindowStyle Minimized -RedirectStandardOutput (Join-Path $root 'awcc-stdout.log') -RedirectStandardError (Join-Path $root 'awcc-stderr.log') | Out-Null
  Log 'AWCC_EXISTING_PROCESS Reusing without ownership.'
 } else {
  Log 'AWCC_EXISTING_WINDOW Reusing without restoring, minimizing, or closing.'
 }
 $library=Wait-Id 'GAME' 60
 if(-not (Find-Id 'GameLibrary_SystemDefaultView_TextBlock_TextBlock14')) {
 Select-Control (Wait-Id 'DASHBOARD')
 $null=Wait-Id 'Core_Grid_TextBlock_DashboardTitle'
 Select-Control (Wait-Id 'GAME')
 $grid=Wait-Id 'GameLibrary_GLModuleView_CustomAutomationPropertyGridView_gridView'
 $condition=New-Object Windows.Automation.AndCondition(
  (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::ListItem)),
  (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'System Default')))
 $defaults=$grid.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)
 if($defaults.Count -ne 1){throw 'Cannot uniquely identify the System Default profile. No lighting change made.'}
 ([Windows.Automation.InvokePattern]$defaults[0].GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)).Invoke()
 $null=Wait-Id 'GameLibrary_SystemDefaultView_TextBlock_TextBlock14'
 }
 $before=Read-Lighting
 if($Mode -eq 'Toggle'){$Mode=if($before -eq 'Off'){'On'}else{'Off'}}
 Log ('AWCC before='+$before+' target='+$Mode)
 $targetId=if($Mode -eq 'Off'){'FX_GlobalBrightness_RadioButton_RadioButton2'}else{'FX_GlobalBrightness_RadioButton_RadioButton1'}
 Select-Control (Wait-Id $targetId)
 $until=(Get-Date).AddSeconds(10)
 do {
  Start-Sleep -Milliseconds 250
  $after=Read-Lighting
  if($after -eq $Mode){break}
 } while((Get-Date) -lt $until)
 if($after -ne $Mode){throw ('AWCC verification failed: '+$after)}
 Start-Sleep -Milliseconds 800
 if((Read-Lighting) -ne $Mode){throw 'AWCC lighting selection reverted.'}
 Log ('AWCC_SELECTION_VERIFIED before='+$before+' after='+$after)
 Finish-OwnedWindow
} catch {
 Log ('FAILED '+($_ | Out-String))
 if(-not $Quiet){
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show(('Cannot change AWCC lighting. Details: '+$logPath),'Alienware Lights') | Out-Null
 }
 exit 1
} finally {
 if($locked){$mutex.ReleaseMutex()}
 $mutex.Dispose()
}
