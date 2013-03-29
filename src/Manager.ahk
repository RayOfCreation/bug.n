/*
  bug.n -- tiling window management
  Copyright (c) 2010-2012 Joshua Fuhs, joten

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program. If not, see <http://www.gnu.org/licenses/>.

  @version 8.4.0
*/

Manager_init()
{
  Local doRestore

  Manager_setWindowBorder()
  Bar_getHeight()
  ; axes, dimensions, percentage, flipped, gapWidth
  Manager_layoutDirty := 0
  ; New/closed windows, active changed,
  Manager_windowsDirty := 0
  Manager_aMonitor := 1
  Manager_taskBarMonitor := ""
  Manager_showTaskBar := True

  doRestore := 0
  If (Config_autoSaveSession = "ask")
  {
    MsgBox, 0x4, , Would you like to restore an auto-saved session?
    IfMsgBox Yes
      doRestore := 1
  }
  Else If (Config_autoSaveSession = "auto")
  {
    doRestore := 1
  }

  SysGet, Manager_monitorCount, MonitorCount
  Loop, % Manager_monitorCount
  {
    Monitor_init(A_Index, doRestore)
  }
  Bar_initCmdGui()
  If Not Config_showTaskBar
    Monitor_toggleTaskBar()

  Manager_focus         := False
  Manager_hideShow      := False
  Bar_hideTitleWndIds   := ""
  Manager_allWndIds     := ""
  Manager_managedWndIds := ""
  Manager_initial_sync(doRestore)

  Bar_updateStatus()
  Bar_updateTitle()
  Loop, % Manager_monitorCount
  {
    View_arrange(A_Index, Monitor_#%A_Index%_aView_#1)
    Bar_updateView(A_Index, Monitor_#%A_Index%_aView_#1)
  }

  Manager_registerShellHook()
  SetTimer, Manager_maintenance_label, %Config_maintenanceInterval%
  SetTimer, Bar_loop, %Config_readinInterval%
}

; Asynchronous management of various WM properties.
; We want to make sure that we can recover the layout and windows in the event of
; unexpected problems.
; Periodically check for changes to these things and save them somewhere (not over
; user-defined files).

Manager_maintenance_label:
  Manager_maintenance()
Return

Manager_saveState()
{
  Global
  Critical
  ;Debug_logMessage("Manager_saveState", 0)

  ; @todo: Check for changes to the layout.
  ;If Manager_layoutDirty
  ;{
    ;Debug_logMessage("Saving layout state: " . Main_autoLayout, 0)
    Config_saveSession(Config_filePath, Main_autoLayout)
    Manager_layoutDirty := 0
  ;}

  ; @todo: Check for changes to windows.
  ;If Manager_windowsDirty
  ;{
    ;Debug_logMessage("Saving window state: " . Main_autoWindowState, 0)
    Manager_saveWindowState(Main_autoWindowState, Manager_monitorCount, Config_viewCount)
    Manager_windowsDirty := 0
  ;}
}

Manager_maintenance()
{
  Local tmp
  Critical
  ;Debug_logMessage("Manager_maintenance", 0)

  ; @todo: Manager_sync?

  If Not (Config_autoSaveSession = "off") And Not (Config_autoSaveSession = "False")
    Manager_saveState()
}

Manager_activateMonitor(d)
{
  Local aView, aWndHeight, aWndId, aWndWidth, aWndX, aWndY, v, wndId

  If (Manager_monitorCount > 1)
  {
    aView := Monitor_#%Manager_aMonitor%_aView_#1
    aWndId := View_getActiveWindow(Manager_aMonitor, aView)
    If aWndId
    {
      WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
      If (Monitor_get(aWndX + aWndWidth / 2, aWndY + aWndHeight / 2) = Manager_aMonitor)
        View_#%Manager_aMonitor%_#%aView%_aWndId := aWndId
    }

    Manager_aMonitor := Manager_loop(Manager_aMonitor, d, 1, Manager_monitorCount)
    v := Monitor_#%Manager_aMonitor%_aView_#1
    wndId := View_#%Manager_aMonitor%_#%v%_aWndId
    If Not (wndId And WinExist("ahk_id" wndId))
    {
      If View_#%Manager_aMonitor%_#%v%_wndIds
        wndId := SubStr(View_#%Manager_aMonitor%_#%v%_wndIds, 1, InStr(View_#%Manager_aMonitor%_#%v%_wndIds, ";")-1)
      Else
        wndId := 0
    }
    Debug_logMessage("DEBUG[1] Manager_activateMonitor: Manager_aMonitor: " Manager_aMonitor ", d: " d ", wndId: " wndId, 1)
    Manager_winActivate(wndId)
  }
}

Manager_applyRules(wndId, ByRef isManaged, ByRef m, ByRef tags, ByRef isFloating, ByRef isDecorated, ByRef hideTitle, ByRef action)
{
  Local mouseX, mouseY, wndClass, wndHeight, wndStyle, wndTitle, wndWidth, wndX, wndY
  Local rule0, rule1, rule2, rule3, rule4, rule5, rule6, rule7, rule8, rule9, rule10

  isManaged   := True
  m           := 0
  tags        := 0
  isFloating  := False
  isDecorated := False
  hideTitle   := False
  action      := ""

  WinGetClass, wndClass, ahk_id %wndId%
  WinGetTitle, wndTitle, ahk_id %wndId%
  WinGetPos, wndX, wndY, wndWidth, wndHeight, ahk_id %wndId%
  WinGet, wndStyle, Style, ahk_id %wndId%
  If wndClass And wndTitle And Not (wndX < -4999) And Not (wndY < -4999)
  {
    Loop, % Config_ruleCount
    {
      StringSplit, rule, Config_rule_#%A_index%, `;
      If RegExMatch(wndClass . ";" . wndTitle, rule1 . ";" . rule2) And (rule3 = "" Or wndStyle & rule3)
      {    ;; The last matching rule is returned.
        isManaged   := rule4
        m           := rule5
        tags        := rule6
        isFloating  := rule7
        isDecorated := rule8
        hideTitle   := rule9
        action      := rule10
      }
    }
  }
  Else
  {
    isManaged := False
    If wndTitle
      hideTitle := True
  }
}

Manager_cleanup()
{
  Local aWndId, m, ncmSize, ncm, wndIds

  WinGet, aWndId, ID, A

  Manager_resetWindowBorder()

  ;; Show borders and title bars.
  StringTrimRight, wndIds, Manager_managedWndIds, 1
  Manager_hideShow := True
  Loop, PARSE, wndIds, `;
  {
    Manager_winShow(A_LoopField)
    If Not Config_showBorder
      Manager_winSet("Style", "+0x40000", A_LoopField)
    Manager_winSet("Style", "+0xC00000", A_LoopField)
  }

  ;; Show the task bar.
  WinShow, Start ahk_class Button
  WinShow, ahk_class Shell_TrayWnd
  Manager_hideShow := False

  ;; Reset windows position and size.
  Manager_showTaskBar := True
  Loop, % Manager_monitorCount
  {
    m := A_Index
    Monitor_#%m%_showBar := False
    Monitor_getWorkArea(m)
    Loop, % Config_viewCount
    {
      View_arrange(m, A_Index)
    }
  }
  Manager_winSet("AlwaysOnTop", "On", aWndId)
  Manager_winSet("AlwaysOnTop", "Off", aWndId)

  DllCall("Shell32.dll\SHAppBarMessage", "UInt", (ABM_REMOVE := 0x1), "UInt", &Bar_appBarData)
  ;; SKAN: Crazy Scripting : Quick Launcher for Portable Apps (http://www.autohotkey.com/forum/topic22398.html)
}

Manager_closeWindow()
{
  Local aWndId, aview, c0
  WinGet, aWndId, ID, A
  WinGetClass, aWndClass, ahk_id %aWndId%
  WinGetTitle, aWndTitle, ahk_id %aWndId%
  If Not (aWndClass = "AutoHotkeyGUI" And RegExMatch(aWndTitle, "bug.n_BAR_[0-9]+"))
  {
    ;; Prior to closing, find the next window that should have focus.
    ;;   If there is no such window, choose the bar on the same monitor.
    aview := Monitor_#%Manager_aMonitor%_aView_#1
    wnds := View_#%Manager_aMonitor%_#%aview%_wndIds
    StringSplit, c, wnds, `;
    If (c0 < 3)
    {
      Manager_winActivate(0)
    }
    Else
    {
      View_activateWindow(1)
    }
    Manager_winClose(aWndId)
  }
}


;; Given a ghost window, try to find its body.
;; This is only known to work on Windows 7
Manager_findHung(ghostWnd)
{
  Local expectedH, expectedTitle, expectedW, expectedX, expectedY, wndH, wndIds, wndTitle, wndW, wndX, wndY

  WinGetTitle, expectedTitle, ahk_id %ghostWnd%
  StringReplace, expectedTitle, expectedTitle, %Config_ghostWndSubString%,
  WinGetPos, expectedX, expectedY, expectedW, expectedH, ahk_id %ghostWnd%

  SetTitleMatchMode, 2
  WinGet, wndIds, List, %expectedTitle%
  Loop, % wndIds
  {
    If (A_Index = ghostWnd)
      Continue
    WinGetPos, wndX, wndY, wndW, wndH, % "ahk_id" wndIDs%A_Index%

    If (wndX = expectedX) And (wndY = expectedY) And (wndW = expectedW) And (wndH = expectedH)
      Return wndIds%A_Index%
  }
  Return 0
}

Manager_getWindowInfo()
{
  Local text, v, aWndClass, aWndHeight, aWndId, aWndProcessName, aWndStyle, aWndTitle, aWndWidth, aWndX, aWndY

  WinGet, aWndId, ID, A
  WinGetClass, aWndClass, ahk_id %aWndId%
  WinGetTitle, aWndTitle, ahk_id %aWndId%
  WinGet, aWndProcessName, ProcessName, ahk_id %aWndId%
  WinGet, aWndStyle, Style, ahk_id %aWndId%
  WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
  text := "ID: " aWndId "`nclass:`t" aWndClass "`ntitle:`t" aWndTitle
  If InStr(Bar_hiddenWndIds, aWndId)
    text .= " (hidden)"
  text .= "`nprocess:`t" aWndProcessName "`nstyle:`t" aWndStyle "`nmetrics:`tx: " aWndX ", y: " aWndY ", width: " aWndWidth ", height: " aWndHeight "`ntags:`t" Manager_#%aWndId%_tags
  If Manager_#%aWndId%_isFloating
    text .= " (floating)"
  MsgBox, 260, bug.n: Window Information, % text "`n`nCopy text to clipboard?"
  IfMsgBox Yes
    Clipboard := text
}

Manager_getWindowList()
{
  Local text, v, aWndId, wndIds, aWndTitle

  v := Monitor_#%Manager_aMonitor%_aView_#1
  aWndId := View_#%Manager_aMonitor%_#%v%_aWndId
  WinGetTitle, aWndTitle, ahk_id %aWndId%
  text := "Active Window`n" aWndId ":`t" aWndTitle

  StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%v%_wndIds, 1
  text .= "`n`nWindow List"
  Loop, PARSE, wndIds, `;
  {
    WinGetTitle, wndTitle, ahk_id %A_LoopField%
    text .= "`n" A_LoopField ":`t" wndTitle
  }

  MsgBox, 260, bug.n: Window List, % text "`n`nCopy text to clipboard?"
  IfMsgBox Yes
    Clipboard := text
}

Manager_isGhost(wndId)
{
  Local wndClass, wndProc

  WinGet, wndProc, ProcessName, ahk_id %wndId%
  WinGetClass, wndClass, ahk_id %wndId%

  If (wndProc = "dwm.exe") And (wndClass = "Ghost")
    Return 1
  Else
    Return 0
}

;; 0 - Not hung
;; 1 - Hung
Manager_isHung(wndId)
{
  Local detect_setting, result, WM_NULL

  WM_NULL := 0
  detect_setting := A_DetectHiddenWindows
  DetectHiddenWindows, On
  SendMessage, WM_NULL, , , , ahk_id %wndId%
  result := ErrorLevel
  DetectHiddenWindows, %detect_setting%

  If result
    Return 1
  Else
    Return 0
}

Manager_lockWorkStation()
{
  Global Config_shellMsgDelay

  RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Policies\System, DisableLockWorkstation, 0
  Sleep, % Config_shellMsgDelay
  DllCall("LockWorkStation")
  Sleep, % 4 * Config_shellMsgDelay
  RegWrite, REG_DWORD, HKEY_CURRENT_USER, Software\Microsoft\Windows\CurrentVersion\Policies\System, DisableLockWorkstation, 1
}
;; Unambiguous: Re-use WIN+L as a hotkey in bug.n (http://www.autohotkey.com/community/viewtopic.php?p=500903&sid=eb3c7a119259b4015ff045ef80b94a81#p500903)

Manager_loop(index, increment, lowerBound, upperBound)
{
  index += increment
  If (index > upperBound)
    index := lowerBound
  If (index < lowerBound)
    index := upperBound
  If (upperBound = 0)
    index := 0

  Return, index
}

Manager__setWinProperties(wndId, isManaged, m, tags, isDecorated, isFloating, hideTitle, action = "")
{
  Local a

  If Not Instr(Manager_allWndIds, wndId ";")
    Manager_allWndIds .= wndId ";"

  If (isManaged)
  {
    If (action = "Close" Or action = "Maximize")
      Manager_win%action%(wndId)

    Manager_managedWndIds .= wndId ";"
    Monitor_moveWindow(m, wndId)
    Manager_#%wndId%_tags        := tags
    Manager_#%wndId%_isDecorated := isDecorated
    Manager_#%wndId%_isFloating  := isFloating

    If Not Config_showBorder
      Manager_winSet("Style", "-0x40000", wndId)
    If Not Manager_#%wndId%_isDecorated
      Manager_winSet("Style", "-0xC00000", wndId)

    a := Manager_#%wndId%_tags & (1 << (Monitor_#%m%_aView_#1 - 1))
    If a
    {
      Manager_aMonitor := m
      Manager_winActivate(wndId)
    }
    Else
    {
      Manager_hideShow := True
      Manager_winHide(wndId)
      Manager_hideShow := False
    }
  }
  If hideTitle
    Bar_hideTitleWndIds .= wndId . ";"

  Return, a
}

;; Accept a window to be added to the system for management.
;; Provide a monitor and view preference, but don't override the config.
Manager_manage(preferredMonitor, preferredView, wndId)
{
  Local a, action, c0, hideTitle, i, isDecorated, isFloating, isManaged, l, m, n, replace, search, tags, body
  Local wndControlList0, wndId0, wndIds, wndX, wndY, wndWidth, wndHeight, wndProcessName

  ; Manage any window only once.
  If InStr(Manager_managedWndIds, wndId ";")
    Return

  body := 0
  If Manager_isGhost(wndId)
  {
    Debug_logMessage("DEBUG[2] A window has given up the ghost (Ghost wndId: " . wndId . ")", 2)
    body := Manager_findHung(wndId)
    If body
    {
      isManaged := InStr(Manager_managedWndIds, body ";")
      m := Manager_#%body%_monitor
      tags := Manager_#%body%_tags
      isDecorated := Manager_#%body%_isDecorated
      isFloating := Manager_#%body%_isFloating
      hideTitle := InStr(Bar_hideTitleWndIds, body ";")
      action := ""
    }
    Else
    {
      Debug_logMessage("DEBUG[1] No body could be found for ghost wndId: " . wndId, 1)
    }
  }

  ;; Apply rules if the window is either a normal window or a ghost without a body.
  If (body = 0)
  {
    Manager_applyRules(wndId, isManaged, m, tags, isFloating, isDecorated, hideTitle, action)
    If (m = 0)
      m := preferredMonitor
    If (m < 0)
      m := 1
    If (m > Manager_monitorCount)    ;; If the specified monitor is out of scope, set it to the max. monitor.
      m := Manager_monitorCount
    If (tags = 0)
      tags := 1 << (preferredView - 1)
  }

  ; @todo: Remove this application-specific code.
  WinGet, wndProcessName, ProcessName, ahk_id %wndId%
  If (wndProcessName = "chrome.exe")
  {
    WinGet, wndControlList, ControlList, ahk_id %wndId%
    StringSplit, c, wndControlList, `n
    If (c0 <= 1)
      isManaged := False
  }

  a := Manager__setWinProperties( wndId, isManaged, m, tags, isDecorated, isFloating, hideTitle, action)

  ; Do view placement.
  If isManaged {
    Loop, % Config_viewCount
      If (Manager_#%wndId%_tags & (1 << (A_Index - 1))) {
        If (body) {
          ; Try to position near the body.
          View_ghostWindow(m, A_Index, body, wndId)
        }
        Else
          View_addWindow(m, A_Index, wndId)
      }
  }

  Return, a
}

Manager_maximizeWindow()
{
  Local aWndId, l, v

  WinGet, aWndId, ID, A
  v := Monitor_#%Manager_aMonitor%_aView_#1
  l := View_#%Manager_aMonitor%_#%v%_layout_#1
  If Not Manager_#%aWndId%_isFloating And Not (Config_layoutFunction_#%l% = "")
    View_toggleFloating()
  Manager_winSet("Top", "", aWndId)

  Manager_winMove(aWndId, Monitor_#%Manager_aMonitor%_x, Monitor_#%Manager_aMonitor%_y, Monitor_#%Manager_aMonitor%_width, Monitor_#%Manager_aMonitor%_height)
}

Manager_moveWindow()
{
  Local aWndId, l, SC_MOVE, v, WM_SYSCOMMAND

  WinGet, aWndId, ID, A
  v := Monitor_#%Manager_aMonitor%_aView_#1
  l := View_#%Manager_aMonitor%_#%v%_layout_#1
  If Not Manager_#%aWndId%_isFloating And Not (Config_layoutFunction_#%l% = "")
    View_toggleFloating()
  Manager_winSet("Top", "", aWndId)

  WM_SYSCOMMAND = 0x112
  SC_MOVE       = 0xF010
  SendMessage, WM_SYSCOMMAND, SC_MOVE, , , ahk_id %aWndId%
}

HSHELL_WINDOWCREATED := 1
;; Seems to get sent sometimes when windows are deactivated.
HSHELL_WINDOWDESTROYED := 2
HSHELL_WINDOWACTIVATED := 4
;; At least title change.
HSHELL_REDRAW := 6
;; The following two are seen when a hung window recovers.
;; lParam notes the ghost process
HSHELL_WINDOWREPLACED := 13
;; lParam notes the recovered process
;;14
;; Full-screen app activated? Root-privileged window activated?
HSHELL_RUDEAPPACTIVATED := 32772
;; When a window is signalling an application update.
WINDOW_NOTICE := 32774

/*
  Reliable messages and their meanings (note that any message may be missed if bug.n is hung):
        1 - Window shown (shown ID)
        2 - Window destroyed or hidden, same message for both (destroyed or hidden ID)
        4 - Window activated via mouse, alt+tab, or hotkey (sometimes 32772, but always one of them)
        6 - Window title change (ID of redrawn window)
       13 - Hung window recovers and replaces ghost window (ghost window ID is provided)
       14 - Hung window recovered (ID of previously hung window)
    32772 - Window activated via mouse, alt+tab, or hotkey (sometimes 4, but always one of them)
    32774 - Window is flashing due to some event, one message for each flash

  Indications of:
    New windows
      cmd/shell may be starting a new window on message 6
      Win+e indicates a new window with message 6 as long as the button
      presses are below a certain frequency.
      Message 1 may indicate a new window started from Windows Explorer.
      There doesn't seem to be a reliable way to get all application starts.
    Closed windows
      13 always indicates closed ghost window
       2 always indicates closed standard window
    Focus change
       4 or 32772 always catch this
    Window event
      6 indicates when title changes which can be used
      in the case of some applications, 32774 works for others
      Windows events can't always be caught.
*/
Manager_onShellMessage(wParam, lParam) {
  Local a, isChanged, aWndClass, aWndHeight, aWndId, aWndTitle, aWndWidth, aWndX, aWndY, m, t, wndClass, wndId, wndIds, wndPName, wndTitle, x, y

  SetFormat, Integer, hex
  lParam := lParam+0
  SetFormat, Integer, d

  Debug_logMessage("DEBUG[2] Manager_onShellMessage( wParam: " . wParam . ", lParam: " . lParam . " )", 2)

  WinGetClass, wndClass, ahk_id %lParam%
  WinGetTitle, wndTitle, ahk_id %lParam%
  WinGet, wndPName, ProcessName, ahk_id %lParam%

  WinGet, aWndId, ID, A
  WinGetClass, aWndClass, ahk_id %aWndId%
  WinGetTitle, aWndTitle, ahk_id %aWndId%
  If ((wParam = 4 Or wParam = 32772) And lParam = 0 And aWndClass = "Progman" And aWndTitle = "Program Manager")
  {
    MouseGetPos, x, y
    m := Monitor_get(x, y)
    If m
      Manager_aMonitor := m
    Bar_updateTitle()
  }

  If (wParam = HSHELL_WINDOWREPLACED)
  {    ;; This shouldn't need a redraw because the window was supposedly replaced.
    Manager_unmanage(lParam)
  }
; If (wParam = 14)
; {    ;; Window recovered from being hung. Maybe force a redraw.
; }

  ;; @todo: There are two problems with the use of Manager_hideShow:
  ;;   1) If Manager_hideShow is set when we hit this block, we won't take some actions that should eventually be taken.
  ;;      This _may_ explain why some windows never get picked up when spamming Win+e
  ;;   2) There is a race condition between the time that Manager_hideShow is checked and any other action which we are
  ;;      trying to protect against. If another process (hotkey) enters a hideShow block after Manager_hideShow has
  ;;      been checked here, bad things could happen. I've personally observed that windows may be permanently hidden.
  ;;   Look into the use of AHK synchronization primitives.
  If (wParam = 1 Or wParam = 2 Or wParam = 4 Or wParam = 6 Or wParam = 32772) And lParam And Not Manager_hideShow And Not Manager_focus
  {
    If Not wndClass And Not (wParam = 2 Or wParam = 4 Or wParam = 32772)
    {
      Sleep, %Config_shellMsgDelay%
      WinGetClass, wndClass, ahk_id %lParam%
    }

    isChanged := Manager_sync(wndIds)
    If wndIds
      isChanged := False

    If isChanged
    {
      View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
      Bar_updateView(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)
    }

    If (Manager_monitorCount > 1)
    {
      WinGet, aWndId, ID, A
      WinGetPos, aWndX, aWndY, aWndWidth, aWndHeight, ahk_id %aWndId%
      m := Monitor_get(aWndX + aWndWidth / 2, aWndY + aWndHeight / 2)
      Debug_logMessage("DEBUG[1] Manager_onShellMessage: Manager_monitorCount: " Manager_monitorCount ", Manager_aMonitor: " Manager_aMonitor ", m: " m ", aWndId: " aWndId, 1)
      If m
        Manager_aMonitor := m
    }

    If wndIds
    {    ;; If there are new (unrecognized) windows, which are hidden ...
      If (Config_onActiveHiddenWnds = "view")
      {  ;; ... change the view to show the first hidden window
        wndId := SubStr(wndIds, 1, InStr(wndIds, ";") - 1)
        Loop, % Config_viewCount
        {
          If (Manager_#%wndId%_tags & 1 << A_Index - 1)
          {
            Debug_logMessage("DEBUG[3] Switching views because " . wndId . " is considered hidden and active", 3)
            Manager_aMonitor := Manager_#%wndId%_monitor
            Monitor_activateView(A_Index)
            Break
          }
        }
      }
      Else
      {  ;; ... re-hide them
        StringTrimRight, wndIds, wndIds, 1
        StringSplit, wndId, wndIds, `;
        If (Config_onActiveHiddenWnds = "hide")
        {
          Loop, % wndId0
          {
            Manager_winHide(wndId%A_Index%)
          }
        }
        Else If (Config_onActiveHiddenWnds = "tag")
        {
          ;; ... or tag all of them for the current view.
          t := Monitor_#%Manager_aMonitor%_aView_#1
          Loop, % wndId0
          {
            wndId := wndId%A_Index%
            View_#%Manager_aMonitor%_#%t%_wndIds := wndId ";" View_#%Manager_aMonitor%_#%t%_wndIds
            View_#%Manager_aMonitor%_#%t%_aWndId := wndId
            Manager_#%wndId%_tags += 1 << t - 1
          }
          Bar_updateView(Manager_aMonitor, t)
          View_arrange(Manager_aMonitor, t)
        }
      }
    }

    Bar_updateTitle()
  }
}

Manager_registerShellHook()
{
  Gui, +LastFound
  hWnd := WinExist()
  DllCall("RegisterShellHookWindow", "UInt", hWnd)    ;; Minimum operating systems: Windows 2000 (http://msdn.microsoft.com/en-us/library/ms644989(VS.85).aspx)
  msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
  OnMessage(msgNum, "Manager_onShellMessage")
}
;; SKAN: How to Hook on to Shell to receive its messages? (http://www.autohotkey.com/forum/viewtopic.php?p=123323#123323)

Manager_resetWindowBorder()
{
  Local ncm, ncmSize

  If Config_selBorderColor
    DllCall("SetSysColors", "Int", 1, "Int*", 10, "UInt*", Manager_normBorderColor)
  If (Config_borderWidth > 0) Or (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA)
  {
    ncmSize := VarSetCapacity(ncm, 4 * (A_OSVersion = WIN_VISTA ? 11 : 10) + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), 0)
    NumPut(ncmSize, ncm, 0, "UInt")
    DllCall("SystemParametersInfo", "UInt", 0x0029, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
    If (Config_borderWidth > 0)
      NumPut(Manager_borderWidth, ncm, 4, "Int")
    If (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA)
      NumPut(Manager_borderPadding, ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
    DllCall("SystemParametersInfo", "UInt", 0x002a, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
  }
}

Manager_setViewMonitor(d)
{
  Local aView, aWndId, m, v, wndIds

  If (Manager_monitorCount > 1)
  {
    m := Manager_loop(Manager_aMonitor, d, 1, Manager_monitorCount)
    v := Monitor_#%m%_aView_#1
    aView := Monitor_#%Manager_aMonitor%_aView_#1
    If View_#%Manager_aMonitor%_#%aView%_wndIds
    {
      View_#%m%_#%v%_wndIds := View_#%Manager_aMonitor%_#%aView%_wndIds View_#%m%_#%v%_wndIds

      StringTrimRight, wndIds, View_#%Manager_aMonitor%_#%aView%_wndIds, 1
      Loop, PARSE, wndIds, `;
      {
        Loop, % Config_viewCount
        {
          StringReplace, View_#%Manager_aMonitor%_#%A_Index%_wndIds, View_#%Manager_aMonitor%_#%A_Index%_wndIds, %A_LoopField%`;,
          View_#%Manager_aMonitor%_#%A_Index%_aWndId := 0
        }

        Monitor_moveWindow(m, A_LoopField)
        Manager_#%A_LoopField%_tags := 1 << v - 1
      }
      View_arrange(Manager_aMonitor, aView)
      Loop, % Config_viewCount
      {
        Bar_updateView(Manager_aMonitor, A_Index)
      }

      Manager_aMonitor := m
      View_arrange(m, v)
      WinGet, aWndId, ID, A
      Manager_winActivate(aWndId)
      Bar_updateView(m, v)
    }
  }
}

Manager_setWindowBorder()
{
  Local ncm, ncmSize

  If Config_selBorderColor
  {
    SetFormat, Integer, hex
    Manager_normBorderColor := DllCall("GetSysColor", "Int", 10)
    SetFormat, Integer, d
    DllCall("SetSysColors", "Int", 1, "Int*", 10, "UInt*", Config_selBorderColor)
  }
  If (Config_borderWidth > 0) Or (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA)
  {
    ncmSize := VarSetCapacity(ncm, 4 * (A_OSVersion = WIN_VISTA ? 11 : 10) + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), 0)
    NumPut(ncmSize, ncm, 0, "UInt")
    DllCall("SystemParametersInfo", "UInt", 0x0029, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
    Manager_borderWidth := NumGet(ncm, 4, "Int")
    Manager_borderPadding := NumGet(ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
    If (Config_borderWidth > 0)
      NumPut(Config_borderWidth, ncm, 4, "Int")
    If (Config_borderPadding >= 0 And A_OSVersion = WIN_VISTA)
      NumPut(Config_borderPadding, ncm, 40 + 5 * (28 + 32 * (A_IsUnicode ? 2 : 1)), "Int")
    DllCall("SystemParametersInfo", "UInt", 0x002a, "UInt", ncmSize, "UInt", &ncm, "UInt", 0)
  }
}

Manager_setWindowMonitor(d)
{
  Local aWndId, v

  WinGet, aWndId, ID, A
  If (Manager_monitorCount > 1 And InStr(Manager_managedWndIds, aWndId ";"))
  {
    Loop, % Config_viewCount
    {
      StringReplace, View_#%Manager_aMonitor%_#%A_Index%_wndIds, View_#%Manager_aMonitor%_#%A_Index%_wndIds, %aWndId%`;,
      If (aWndId = View_#%Manager_aMonitor%_#%A_Index%_aWndId)
        View_#%Manager_aMonitor%_#%A_Index%_aWndId := 0
      Bar_updateView(Manager_aMonitor, A_Index)
    }
    View_arrange(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1)

    Manager_aMonitor := Manager_loop(Manager_aMonitor, d, 1, Manager_monitorCount)
    Monitor_moveWindow(Manager_aMonitor, aWndId)
    v := Monitor_#%Manager_aMonitor%_aView_#1
    Manager_#%aWndId%_tags := 1 << v - 1
    View_#%Manager_aMonitor%_#%v%_wndIds := aWndId ";" View_#%Manager_aMonitor%_#%v%_wndIds
    View_#%Manager_aMonitor%_#%v%_aWndId := aWndId
    View_arrange(Manager_aMonitor, v)
    Manager_winActivate(aWndId)
    Bar_updateView(Manager_aMonitor, v)
  }
}

Manager_sizeWindow()
{
  Local aWndId, l, SC_SIZE, v, WM_SYSCOMMAND

  WinGet, aWndId, ID, A
  v := Monitor_#%Manager_aMonitor%_aView_#1
  l := View_#%Manager_aMonitor%_#%v%_layout_#1
  If Not Manager_#%aWndId%_isFloating And Not (Config_layoutFunction_#%l% = "")
    View_toggleFloating()
  Manager_winSet("Top", "", aWndId)

  WM_SYSCOMMAND = 0x112
  SC_SIZE       = 0xF000
  SendMessage, WM_SYSCOMMAND, SC_SIZE, , , ahk_id %aWndId%
}

;; @todo: This constantly tries to re-add windows that are never going to be manageable.
;;   Manager_manage should probably ignore all windows that are already in Manager_allWndIds.
Manager_sync(ByRef wndIds = "")
{
  Local a, flag, shownWndIds, v, visibleWndIds, wndId

  Loop, % Manager_monitorCount
  {
    v := Monitor_#%A_Index%_aView_#1
    shownWndIds .= View_#%A_Index%_#%v%_wndIds
  }
  ;; Check all visible windows against the known windows
  WinGet, wndId, List, , ,
  Loop, % wndId
  {
    If Not InStr(shownWndIds, wndId%A_Index% ";")
    {
      If Not InStr(Manager_managedWndIds, wndId%A_Index% ";")
      {
        flag := Manager_manage(Manager_aMonitor, Monitor_#%Manager_aMonitor%_aView_#1, wndId%A_Index%)
        If flag
          a := flag
      }
      Else If Not Manager_isHung(wndId%A_Index%)
      {
        ;; This is a window that is already managed but was brought into focus by something.
        ;; Maybe it would be useful to do something with it.
        wndIds .= wndId%A_Index% ";"
      }
    }
    visibleWndIds := visibleWndIds wndId%A_Index% ";"
  }

  ;; @todo-future: Find out why this unmanage code exists and if it's still needed.
  ;; check, if a window, that is known to be visible, is actually not visible
  StringTrimRight, shownWndIds, shownWndIds, 1
  Loop, PARSE, shownWndIds, `;
  {
    If Not InStr(visibleWndIds, A_LoopField)
    {
      flag := Manager_unmanage(A_LoopField)
      If flag
        a := flag
    }
  }

  Return, a
}


Manager_saveWindowState(filename, nm, nv)
{
  Local allWndId, allWndIds, process, title, text, monitor, wndId, view, isManaged, isTitleHidden

  text := "; bug.n - tiling window management`n; @version " VERSION "`n`n"

  tmpfname := filename . ".tmp"
  FileDelete, %tmpfname%

  ; Dump window ID and process name. If these two don't match an existing process, we won't try
  ;   to recover that window.
  StringTrimRight, allWndIds, Manager_allWndIds, 1
  StringSplit, allWndId, allWndIds, `;
  DetectHiddenWindows, On
  Loop, % allWndId0
  {
    wndId := allWndId%A_Index%
    WinGet, process, ProcessName, ahk_id %wndId%
    ; Include title for informative reasons.
    WinGetTitle, title, ahk_id %wndId%

    ; wndId;process;Tags;Floating;Decorated;HideTitle;Managed;Title

    If ( InStr(Manager_managedWndIds, wndId . ";") > 0 )
    {
      isManaged := 1
    }
    else
    {
      isManaged := 0
    }

    If ( InStr(Bar_hideTitleWndIds, wndId . ";") > 0 )
      isTitleHidden := 1
    Else
      isTitleHidden := 0

    text .= "Window " . wndId . ";" . process . ";" . Manager_#%wndId%_monitor . ";" . Manager_#%wndId%_tags . ";" . Manager_#%wndId%_isFloating . ";" . Manager_#%wndId%_isDecorated . ";" . isTitleHidden . ";" . isManaged . ";" . title . "`n"
  }
  DetectHiddenWindows, Off

  text .= "`n"

  ;; Dump window arrangements on every view. If some views or monitors have disappeared, leave their
  ;;   corresponding windows alone.

  Loop, % nm
  {
    monitor := A_Index
    Loop, % nv
    {
      view := A_Index
      ;; Dump all view window lists
      text .= "View_#" . monitor . "_#" . view . "_wndIds=" . View_#%monitor%_#%view%_wndIds . "`n"
    }
  }

  FileAppend, %text%, %tmpfname%
  If ErrorLevel
  {
    If FileExist(tmpfname)
      FileDelete, %tmpfname%
  }
  Else
    FileMove, %tmpfname%, %filename%, 1
}

;; Restore previously saved window state.
;; If the state is completely different, this function won't do much. However, if restoring from a crash
;; or simply restarting bug.n, it should completely recover the window state.
Manager__restoreWindowState(filename)
{
  Local vidx, widx, i, j, m, v, candidate_set, view_set, excluded_view_set, view_m0, view_v0, view_list0, wnds0, items0, wndProc, view_var, isManaged, isFloating, isDecorated, hideTitle

  If Not FileExist(filename)
    Return

  widx := 1
  vidx := 1

  view_set := ""
  excluded_view_set := ""

  ;; Read all interesting things from the file.
  Loop, READ, %filename%
  {
    If (SubStr(A_LoopReadLine, 1, 5) = "View_")
    {
      i := InStr(A_LoopReadLine, "#")
      j := InStr(A_LoopReadLine, "_", false, i)
      m := SubStr(A_LoopReadLine, i + 1, j - i - 1)
      i := InStr(A_LoopReadLine, "#", false, j)
      j := InStr(A_LoopReadLine, "_", false, i)
      v := SubStr(A_LoopReadLine, i + 1, j - i - 1)

      i := InStr(A_LoopReadLine, "=", j + 1)


      If (m <= Manager_monitorCount) And ( v <= Config_viewCount )
      {
        view_list%vidx% := SubStr(A_LoopReadLine, i + 1)
        view_m%vidx% := m
        view_v%vidx% := v
        view_set := view_set . view_list%vidx%
        vidx := vidx + 1
      }
      Else
      {
        excluded_view_set := excluded_view_set . view_list%vidx%
        Debug_logMessage("View (" . m . ", " . v . ") is no longer available (" . vidx . ")", 0)
      }
    }
    Else If (SubStr(A_LoopReadLine, 1, 7) = "Window ") {
      wnds%widx% := SubStr(A_LoopReadLine, 8)
      widx := widx + 1
    }
  }

  ;Debug_logMessage("view_set: " . view_set, 1)
  ;Debug_logMessage("excluded_view_set: " . excluded_view_set, 1)

  candidate_set := ""

  ; Scan through all defined windows. Create a candidate set of windows based on whether the properties of existing windows match.
  Loop, % (widx - 1)
  {
    StringSplit, items, wnds%A_Index%, `;
    If ( items0 < 9 )
    {
      Debug_logMessage("Window '" . wnds%A_Index% . "' could not be processed due to parse error", 0)
      Continue
    }

    i := 1
    i := items%i%
    j := 2


    DetectHiddenWindows, On
    WinGet, wndProc, ProcessName, ahk_id %i%
    DetectHiddenWindows, Off
    If Not ( items%j% = wndProc )
    {
      Debug_logMessage("Window ahk_id " . i . " process '" . wndProc . "' doesn't match expected '" . items%j% . "', forgetting this window", 0)
      Continue
    }

    j := 8
    isManaged := items%j%

    ; If Managed
    If ( items%j% )
    {
      If ( InStr(view_set, i) = 0)
      {
        If ( InStr(excluded_view_set, i) )
        {
          Debug_logMessage("Window ahk_id " . i . " is being ignored because it no longer belongs to an active view", 0)
        }
        Else
        {
          Debug_logMessage("Window ahk_id " . i . " is being ignored because it doesn't exist in any views", 0)
        }
        Continue
      }
    }

    ; Set up the window.

    j := 3
    m := items%j%
    j := 4
    v := items%j%
    j := 5
    isFloating := items%j%
    j := 6
    isDecorated := items%j%
    j := 7
    hideTitle := items%j%

    Manager__setWinProperties(i, isManaged, m, v, isDecorated, isFloating, hideTitle )
    ;Manager_winHide(i)

    candidate_set := candidate_set . i . ";"
  }

  ;Debug_logMessage("candidate_set: " . candidate_set, 1)

  ; Set up all views. Must filter the window list by those from the candidate set.
  Loop, % (vidx - 1)
  {
    StringSplit, items, view_list%A_Index%, `;
    view_set := ""
    Loop, % items0 - 1
    {
      If ( InStr(candidate_set, items%A_Index% ) > 0 )
        view_set := view_set . items%A_Index% . ";"
    }
    view_var := "View_#" . view_m%A_Index% . "_#" . view_v%A_Index% . "_wndIds"
    %view_var% := view_set
  }
}



; No windows are known to the system yet.
; Try to do something smart with the initial layout.
Manager_initial_sync(doRestore)
{
  Local wndId0, wnd, wndX, wndY, wndW, wndH, x, y, m, len

  ;; Initialize lists
  ;; Note that these variables make this function non-reentrant.
  Loop, % Manager_monitorCount
  {
    Manager_initial_sync_m#%A_Index%_wndList := ""
  }

  ;; Use saved window placement settings to first determine
  ;;   which monitor/view a window should be attached to.
  If doRestore
  {
    Manager__restoreWindowState(Main_autoWindowState)
  }

  ;; Check all remaining visible windows against the known windows
  WinGet, wndId, List, , ,
  Loop, % wndId
  {
    ;; Based on some analysis here, determine which monitors and layouts would best
    ;; serve existing windows. Do not override configuration settings.

    ;; Which monitor is it on?
    wnd := wndId%A_Index%
    WinGetPos, wndX, wndY, wndW, wndH, ahk_id %wnd%

    x := wndX + wndW/2
    y := wndY + wndH/2

    m := Monitor_get(x, y)
    If m > 0
      Manager_initial_sync_m#%m%_wndList .= wndId%A_Index% ";"

  }

  Loop, % Manager_monitorCount
  {
    m := A_Index
    StringTrimRight, wndIds, Manager_initial_sync_m#%m%_wndList, 1
    StringSplit, wndId, wndIds, `;
    Loop, % wndId0
    {
      Manager_manage(m, 1, wndId%A_Index%)
    }
  }
}

Manager_toggleDecor()
{
  Local aWndId

  WinGet, aWndId, ID, A
  Manager_#%aWndId%_isDecorated := Not Manager_#%aWndId%_isDecorated
  If Manager_#%aWndId%_isDecorated
    Manager_winSet("Style", "+0xC00000", aWndId)
  Else
    Manager_winSet("Style", "-0xC00000", aWndId)
}

Manager_unmanage(wndId)
{
  Local a

  ;; Do our best to make sure that any unmanaged windows are left visible.
  Manager_winShow(wndId)
  a := Manager_#%wndId%_tags & 1 << Monitor_#%Manager_aMonitor%_aView_#1 - 1
  Loop, % Config_viewCount
  {
    If (Manager_#%wndId%_tags & 1 << A_Index - 1)
    {
      StringReplace, View_#%Manager_aMonitor%_#%A_Index%_wndIds, View_#%Manager_aMonitor%_#%A_Index%_wndIds, %wndId%`;,
      Bar_updateView(Manager_aMonitor, A_Index)
    }
  }
  Manager_#%wndId%_monitor     :=
  Manager_#%wndId%_tags        :=
  Manager_#%wndId%_isDecorated :=
  Manager_#%wndId%_isFloating  :=
  StringReplace, Bar_hideTitleWndIds, Bar_hideTitleWndIds, %wndId%`;,
  StringReplace, Manager_allWndIds, Manager_allWndIds, %wndId%`;,
  StringReplace, Manager_managedWndIds, Manager_managedWndIds, %wndId%`;, , All

  Return, a
}

Manager_winActivate(wndId)
{
  Local aWndId, wndHeight, wndWidth, wndX, wndY

  If Config_mouseFollowsFocus
  {
    If wndId
    {
      WinGetPos, wndX, wndY, wndWidth, wndHeight, ahk_id %wndId%
      DllCall("SetCursorPos", "Int", Round(wndX + wndWidth / 2), "Int", Round(wndY + wndHeight / 2))
    }
    Else
      DllCall("SetCursorPos", "Int", Round(Monitor_#%Manager_aMonitor%_x + Monitor_#%Manager_aMonitor%_width / 2), "Int", Round(Monitor_#%Manager_aMonitor%_y + Monitor_#%Manager_aMonitor%_height / 2))
  }
  If wndId And Manager_isHung(wndId)
  {
    Debug_logMessage("DEBUG[2] Manager_winActivate: Potentially hung window " . wndId, 2)
    Return 1
  }
  Else
  {
    Debug_logMessage("DEBUG[1] Activating window: " wndId, 1)
    If Not wndId
    {
      WinGet, wndId, ID, Program Manager ahk_class Progman
      Debug_logMessage("DEBUG[1] Activating Program Manager: " wndId, 1)
    }
    WinActivate, ahk_id %wndId%
    WinGet, aWndId, ID, A
    If (wndId != aWndId)
      Return 1
  }
  Bar_updateTitle()
  Return 0
}

Manager_winClose(wndId)
{
  If Manager_isHung(wndId)
  {
    Debug_logMessage("DEBUG[2] Manager_winClose: Potentially hung window " . wndId, 2)
    Return 1
  }
  Else
  {
    WinClose, ahk_id %wndId%
    Return 0
  }
}

Manager_winHide(wndId)
{
  If Manager_isHung(wndId)
  {
    Debug_logMessage("DEBUG[2] Manager_winHide: Potentially hung window " . wndId, 2)
    Return 1
  }
  Else
  {
    WinHide, ahk_id %wndId%
    Return 0
  }
}

Manager_winMaximize(wndId)
{
  If Manager_isHung(wndId)
  {
    Debug_logMessage("DEBUG[2] Manager_winMaximize: Potentially hung window " . wndId, 2)
    Return 1
  }
  Else
  {
    WinMaximize, ahk_id %wndId%
    Return 0
  }
}

Manager_winMove(wndId, x, y, width, height)
{
  If Manager_isHung(wndId)
  {
    Debug_logMessage("DEBUG[2] Manager_winMove: Potentially hung window " . wndId, 2)
    Return 1
  }
  Else
  {
    WinGet, wndMin, MinMax, ahk_id %wndId%
    If (wndMin = -1)
      WinRestore, ahk_id %wndId%
  }
  WM_ENTERSIZEMOVE = 0x0231
  WM_EXITSIZEMOVE  = 0x0232
  SendMessage, WM_ENTERSIZEMOVE, , , , ahk_id %wndId%
  If ErrorLevel
  {
    Debug_logMessage("DEBUG[2] Manager_winMove: Potentially hung window " . wndId, 1)
    Return 1
  }
  Else
  {
    WinMove, ahk_id %wndId%, , %x%, %y%, %width%, %height%
    SendMessage, WM_EXITSIZEMOVE, , , , ahk_id %wndId%
  }
}

Manager_winSet(type, value, wndId)
{
  If Manager_isHung(wndId)
  {
    Debug_logMessage("DEBUG[2] Manager_winSet: Potentially hung window " . wndId, 2)
    Return 1
  }
  Else
  {
    WinSet, %type%, %value%, ahk_id %wndId%
    Return 0
  }
}

Manager_winShow(wndId)
{
  If Manager_isHung(wndId)
  {
    Debug_logMessage("DEBUG[2] Manager_winShow: Potentially hung window " . wndId, 2)
    Return 1
  }
  Else
  {
    WinShow, ahk_id %wndId%
    Return 0
  }
}
