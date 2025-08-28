Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# do not export anything
Export-ModuleMember


# PowerShell still does have a way to autoload a completer; as a workaround, we load a very lightweight completer,
# which loads the actual completer on first invocation


$Flags = [System.Reflection.BindingFlags]"Instance, NonPublic"
$Context = $ExecutionContext.GetType().GetField("_context", $Flags).GetValue($ExecutionContext)
$NativeProp = $Context.GetType().GetProperty("NativeArgumentCompleters", $Flags)

### Set a completer for command `$CommandName` that loads another pwsh module when invoked for the first time.
### The specified module should use `Register-ArgumentCompleter` to register the actual completer when it is loaded.
function Set-SubstituteCompleter($CommandName, $CompleterModuleName) {
    $Context = $script:Context
    $NativeProp = $script:NativeProp
    Register-ArgumentCompleter -CommandName $CommandName -ScriptBlock {
        try {
            # import the actual completer to replace this one
            Import-Module -Global $CompleterModuleName -ErrorAction Stop
        } catch {
            # if loading the completer fails, fall back to the default completer and log an error
            #  (it will not be shown, but it will be available using `Get-Error`)
            throw "Failed to run the autocompleter for '$CommandName', provided by module '$CompleterModuleName': $_"
        }
        # forward it once
        $Completer = $NativeProp.GetValue($Context)[$CommandName]
        return & $Completer @Args
    }.GetNewClosure()
}


# wsl.exe completions
Set-SubstituteCompleter wsl WSLTabCompletion
# completions for git.exe, much faster than posh-git
Set-SubstituteCompleter git PSGitCompletions
# hyperfine
Set-SubstituteCompleter hyperfine D:\_\hyperfine\app\autocomplete\_hyperfine.ps1
# task
Set-SubstituteCompleter task D:\_\Task\app\completion\ps\task.ps1

Set-SubstituteCompleter delta $PSScriptRoot\CustomModules\carapace-completions\carapace.ps1
Set-SubstituteCompleter mpv $PSScriptRoot\CustomModules\carapace-completions\carapace.ps1
Set-SubstituteCompleter nvim $PSScriptRoot\CustomModules\carapace-completions\carapace.ps1
Set-SubstituteCompleter python $PSScriptRoot\CustomModules\carapace-completions\carapace.ps1
Set-SubstituteCompleter ssh $PSScriptRoot\CustomModules\carapace-completions\carapace.ps1
Set-SubstituteCompleter ssh-agent $PSScriptRoot\CustomModules\carapace-completions\carapace.ps1
Set-SubstituteCompleter ssh-keygen $PSScriptRoot\CustomModules\carapace-completions\carapace.ps1