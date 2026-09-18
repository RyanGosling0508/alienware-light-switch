$ProgressPreference='SilentlyContinue'
$ErrorActionPreference='Stop'
$root=$LogRoot
New-Item -ItemType Directory -Path $root -Force | Out-Null
$logPath=Join-Path $root 'last-run.log'
$history=Join-Path $root 'history.log'
$mutex=New-Object Threading.Mutex($false,'Local\AlienwareLightSwitch')
$locked=$false
$exe=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Alienware\Alienware Command Center\AWCC\AWCC.exe'
function Log([string]$Message){
 $line=('{0:o} {1}' -f (Get-Date),$Message)
 $line | Add-Content -LiteralPath $logPath -Encoding UTF8
 $line | Add-Content -LiteralPath $history -Encoding UTF8
 Write-Output $line
}
function Get-AwccWindow {
 $processes=@(Get-Process AWCC -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.Path -eq $exe})
 if($processes.Count -eq 1){return [Windows.Automation.AutomationElement]::FromHandle($processes[0].MainWindowHandle)}
 if($processes.Count -gt 1){throw 'Multiple AWCC windows found. Close duplicate windows and retry.'}
 return $null
}
function Find-Id([string]$Id) {
 $window=Get-AwccWindow
 if(-not $window){return $null}
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
 if(-not (Get-AwccWindow)){Start-Process -FilePath $exe | Out-Null}
 # Restore a previously minimized AWCC window so its controls are available.
 $existingWindow=Get-AwccWindow
 if($existingWindow){
  $windowPattern=$null
  if($existingWindow.TryGetCurrentPattern([Windows.Automation.WindowPattern]::Pattern,[ref]$windowPattern)){
   if($windowPattern.Current.WindowVisualState -eq [Windows.Automation.WindowVisualState]::Minimized){
    $windowPattern.SetWindowVisualState([Windows.Automation.WindowVisualState]::Normal)
   }
  }
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
 # Minimize only after confirming the lighting state. Keep errors visible.
 try {
  $awccWindow=Get-AwccWindow
  if(-not $awccWindow){throw 'AWCC window is no longer available.'}
  $windowPattern=[Windows.Automation.WindowPattern]$awccWindow.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern)
  if(-not $windowPattern.Current.CanMinimize){throw 'AWCC does not expose minimize support.'}
  $windowPattern.SetWindowVisualState([Windows.Automation.WindowVisualState]::Minimized)
  $minimizeDeadline=(Get-Date).AddSeconds(3)
  do {
   Start-Sleep -Milliseconds 100
   $minimized=$windowPattern.Current.WindowVisualState -eq [Windows.Automation.WindowVisualState]::Minimized
  } while(-not $minimized -and (Get-Date) -lt $minimizeDeadline)
  if(-not $minimized){throw 'AWCC did not report a minimized window.'}
  Log 'AWCC_MINIMIZED_VERIFIED'
 } catch {
  Log ('WINDOW_WARNING Lighting changed, but AWCC could not be minimized: '+$_.Exception.Message)
 }
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
