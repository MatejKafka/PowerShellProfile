using namespace Microsoft.PowerShell

Set-StrictMode -Version Latest
Export-ModuleMember # don't export anything

Set-PSReadLineKeyHandler -Key Shift+UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key Shift+DownArrow -Function HistorySearchForward
# bypass custom Enter handling below
Set-PSReadLineKeyHandler -Key Alt+Enter -Function AcceptLine

Set-PSReadLineOption -HistorySearchCursorMovesToEnd
# disable default history handler, which filters "sensitive" commands from being written to the history file
#  (see https://github.com/PowerShell/PSReadLine/issues/3243)
Set-PSReadLineOption -AddToHistoryHandler $null

# enable fish-like autocompletion
Set-PSReadLineOption -PredictionSource History

# set which part of prompt is highlighted in red for invalid input
Set-PSReadLineOption -PromptText "> "
# inform PSReadLine that our prompt has 2 lines
Set-PSReadLineOption -ExtraPromptLineCount 1

# increase history file size
Set-PSReadLineOption -MaximumHistoryCount 100000

Set-PSReadLineOption -Colors @{
    InlinePrediction = "#555555"
    Selection = $PSStyle.Reverse
}

# auto-correct casing of commands before executing any command
Set-PSReadLineKeyHandler -Chord Enter {
    $Ast = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$Ast, [ref]$null, [ref]$null, [ref]$null)

    # defined in functions.psm1
    FixCommandCasing $Ast | % {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($_.Extent.StartOffset, $_.Extent.EndOffset - $_.Extent.StartOffset, $_.Replacement)
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::ValidateAndAcceptLine()
}

# if at the beginning of a line, add Tab (4 spaces), otherwise open autocomplete dropdown
Set-PSReadLineKeyHandler -Key "Tab" -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    $lineStartI = $line.LastIndexOf("`n", [Math]::max(0, $cursor - 1)) + 1
    if ($line.Substring($lineStartI, $cursor - $lineStartI).Trim() -eq "") {
        [PSConsoleReadLine]::Insert("    ")
    } else {
        [PSConsoleReadLine]::MenuComplete($key, $arg)
    }
}

# if at the beginning of a line, remove all indentation
Set-PSReadLineKeyHandler -Key "Shift+Tab" -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    # $selectionStart = $null
    # $selectionLength = $null
    # [PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $lineStartI = $line.LastIndexOf("`n", [Math]::max(0, $cursor - 1)) + 1
    for ($i = $lineStartI; $i -lt $line.length -and [char]::IsWhiteSpace($line[$i]); $i++) {}
    $whitespaceEndI = $i

    if ($line.Substring($lineStartI, $cursor - $lineStartI).Trim() -eq "") {
        $deleteStartI = [math]::Max($lineStartI, $whitespaceEndI - 4)
        [PSConsoleReadLine]::Delete($deleteStartI, $whitespaceEndI - $deleteStartI)
    } else {
        [PSConsoleReadLine]::TabCompletePrevious($key, $arg)
    }
}


Set-PSReadLineKeyHandler -Key "End" -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length) {
        [PSConsoleReadLine]::EndOfLine($key, $arg)
    } else {
        [PSConsoleReadLine]::AcceptSuggestion($key, $arg)
    }
}


Set-PSReadLineKeyHandler -Key RightArrow `
             -BriefDescription ForwardCharAndAcceptNextSuggestionWord `
             -LongDescription "Move cursor one character to the right in the current editing line and accept the next word in suggestion when it's at the end of current editing line" `
             -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length) {
        [PSConsoleReadLine]::ForwardChar($key, $arg)
    } else {
        [PSConsoleReadLine]::AcceptNextSuggestionWord($key, $arg)
    }
}

# Wrap the current whitespace-delimited token in quotes.
Set-PSReadLineKeyHandler -Key 'Ctrl+"' -ScriptBlock {
    $line, $cursor = $null
    [PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    $whitespaceChars = [char[]]@(" ", "`n", "`t")
    $startI = $line.LastIndexOfAny($whitespaceChars, $cursor - 1) + 1

    $endI = $cursor -eq $line.Length ? -1 : $line.IndexOfAny($whitespaceChars, $cursor)
    if ($endI -eq -1) {
        $endI = $line.Length
    }

    [PSConsoleReadLine]::Replace($startI, $endI - $startI, '"' + $line.Substring($startI, $endI - $startI) + '"')
    [PSConsoleReadLine]::SetCursorPosition($cursor + 1)
}

# Sometimes you want to get a property of invoke a member on what you've entered so far
# but you need parens to do that.  This binding will help by putting parens around the current selection,
# or if nothing is selected, the whole line.
Set-PSReadLineKeyHandler -Key 'Alt+(' `
             -BriefDescription ParenthesizeSelection `
             -LongDescription "Put parenthesis around the selection or entire line and move the cursor to after the closing parenthesis" `
             -ScriptBlock {
    param($key, $arg)

    $selectionStart = $null
    $selectionLength = $null
    [PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

    $line = $null
    $cursor = $null
    [PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($selectionStart -ne -1) {
        [PSConsoleReadLine]::Replace($selectionStart, $selectionLength, '(' + $line.SubString($selectionStart, $selectionLength) + ')')
        [PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    } else {
        [PSConsoleReadLine]::Replace(0, $line.Length, '(' + $line + ')')
        [PSConsoleReadLine]::EndOfLine()
    }
}

Set-PSReadLineKeyHandler -Key Alt+r `
             -BriefDescription NativeArgs `
             -LongDescription "Convert a native Win32 cmdline string to something that PowerShell correctly passes as args to a native binary." `
             -ScriptBlock {
    $InputStr = $null
    [PSConsoleReadLine]::GetBufferState([ref]$InputStr, [ref]$null)
    # not correct, but it's pretty useful when I'm manually changing some args and split them up in separate lines
    $InputStr = $InputStr -replace "`n", " "
    # CommandLineToArgv is defined in functions.psm1
    $CmdStr = CommandLineToArgv $InputStr | % {"'$_'"} | Join-String -Separator " "
    [PSConsoleReadLine]::Replace(0, $InputStr.Length, "& $CmdStr")
}

Set-PSReadLineKeyHandler -Key Ctrl+Alt+r `
             -BriefDescription NativeArgsArray `
             -LongDescription "Convert a native Win32 cmdline string to an argv array literal." `
             -ScriptBlock {
    $InputStr = $null
    [PSConsoleReadLine]::GetBufferState([ref]$InputStr, [ref]$null)
    # not correct, but it's pretty useful when I'm manually changing some args and split them up in separate lines
    $InputStr = $InputStr -replace "`n", " "
    # CommandLineToArgv is defined in functions.psm1
    $CmdStr = CommandLineToArgv $InputStr | % {"'$_'"} | Join-String -Separator ", "
    [PSConsoleReadLine]::Replace(0, $InputStr.Length, $CmdStr)
}